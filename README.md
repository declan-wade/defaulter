# Defaulter

A macOS Tahoe utility for managing which app opens which file type — the thing
Windows 7 put in *Control Panel → Default Programs*, which macOS never really
shipped an equivalent for.

Four panes:

| Pane | What it does |
| --- | --- |
| **By Extension** | Every file extension on the system, its current app, and a picker to change it. |
| **By App** | Every installed app, everything it currently opens, and everything it *could* open. |
| **URL Schemes** | Default browser, mail client, and every other `scheme://` handler. |
| **History** | Every change made here, with one-click revert. |

## Build

```bash
./build.sh --install
```

Builds `build/Defaulter.app` and copies it to `/Applications`. Drop `--install`
to build in place. Requires Xcode's command line tools; no Xcode project needed.
Deployment target is macOS 15.

## Why this is harder than it looks

macOS does not associate an app with an *extension*. It associates an app with a
**Uniform Type Identifier**, and one extension can map to several UTIs at once.

On the machine this was developed against, **165 of 1,125 extensions were
"split"** — their UTIs pointed at different apps:

```
.aiff  →  io.iina.aiff        → IINA
          public.aiff-audio   → Music
.aac   →  io.iina.aac         → IINA
          public.aac-audio    → Books
```

This is why "I changed the default and it didn't work" happens: Finder's *Change
All…* sets one UTI, and files tagged with the other keep opening elsewhere.

Defaulter handles this directly:

- Split extensions are flagged with a warning triangle in the list, and the
  detail pane explains exactly which identifier points where.
- Choosing an app sets **every** UTI behind the extension in one action, so the
  split is actually repaired rather than half-fixed.
- A **Split only** filter lets you find every broken association at once.

There is a second trap in the "By App" direction. Apps declare what they can
open in two different ways, and modern code tends to only read the first:

- `CFBundleDocumentTypes → LSItemContentTypes` (modern, UTI-based)
- `CFBundleTypeExtensions` (legacy, raw extension strings)

VS Code on this machine declares **1 modern UTI and 153 legacy extensions**.
Reading only the modern key would have shown almost nothing for it. Defaulter
reads both, plus `UTExportedTypeDeclarations` / `UTImportedTypeDeclarations` for
types an app defines itself.

## Safety

Launch Services has no undo. So every write goes through one coordinator that
captures the previous handler *before* changing anything, and appends it to a log
at `~/Library/Application Support/Defaulter/history.json`.

- Changes made in one action are grouped, so reverting a split extension
  restores all of its UTIs together.
- If a type had no handler before, the entry is marked "Nothing to restore"
  rather than pretending it can be undone.
- A change that only partly applies reports which identifiers macOS refused,
  instead of claiming success.
- The log is written atomically, is capped at 2,000 entries, and a corrupt log
  is discarded rather than crashing the app.

Clearing the history does **not** change any association — it only discards the
ability to revert from here.

## Layout

```
Sources/DefaulterKit/     # No UI. Usable on its own.
  Models.swift            # AppRecord, TypeRecord, SchemeRecord
  Catalog.swift           # Scans installed apps, builds the type index
  SeedExtensions.swift    # ~300 common extensions so the list is never sparse
  Associations.swift      # Reads/writes Launch Services; split detection
  History.swift           # Append-only change log and revert
  Manager.swift           # The only path that writes; records before-state
Sources/Defaulter/        # SwiftUI app
```

`DefaulterKit` has no dependency on the UI, so the same logic can back a CLI.

## API notes

Writes use `NSWorkspace.setDefaultApplication`, falling back to
`LSSetDefaultRoleHandlerForContentType` when the modern call fails — the two
disagree on a handful of system-declared types. Reads go through `NSWorkspace`,
which reflects the live Launch Services database.

Cold start scans ~274 apps in about 0.5s; re-reading every current default takes
about 0.15s and runs after each change, since changing one UTI can shift what
other extensions resolve to.

## Verification

### Logic tests

18 checks cover catalog building, extension/UTI resolution, split detection,
legacy declaration parsing, and the history store including reload and
corruption handling:

```bash
swiftc -o /tmp/verify Tests/main.swift Sources/DefaulterKit/*.swift -swift-version 5 && /tmp/verify
```

### Headless UI smoke test

There is no accessibility permission in this environment, so the UI cannot be
driven by clicking. Instead the app carries scripted hooks that are completely
inert unless `DEFAULTER_UITEST=1` is set:

```bash
DEFAULTER_UITEST=1 ./build/Defaulter.app/Contents/MacOS/Defaulter
```

It focuses each search field, types, selects rows, toggles the split filter and
cycles all four panes, logging each step through `NSLog`. `DEFAULTER_UITEST_SCENARIO`
narrows it to `search` or `panes` to isolate which interaction breaks something.

This exists because two crashes were only reachable by interacting with the UI,
and both were found by this harness rather than by reading the code.

### Two crashes this found and fixed

**1. Clicking the search box killed the app.**
`No Observable object of type AppModel found`. The model was passed through
`@Environment`, but SwiftUI hoists `searchable` and toolbar content into a
separate hosting context that does not inherit the environment set on the
window's root view. Any view re-evaluated during preference combining faulted.
Fixed by dropping `@Environment` entirely in favour of a single `AppModel.shared`
read inside `body` — Observation still tracks it, and there is no environment
left to be missing.

**2. Switching panes killed the app.**
An AttributeGraph precondition failure inside `AppKitOutlineTableCoordinator`.
Two separate causes, both fixed:

- A container-level `.animation(_:value:)` wrapped the pane, so switching panes
  drove an *animated removal* of a live table. The animation is now scoped to
  the status banner alone.
- Even without the animation, destroying a `Table` while it was mid-diff (right
  after a search edit) still aborted. Panes are therefore kept instantiated and
  only toggled for visibility, so no table is ever torn down. That in turn is
  why search is an inline field rather than `.searchable(placement: .toolbar)` —
  four live panes cannot share one toolbar.

Hidden panes also release keyboard focus, so an offscreen search field cannot
hold the caret.

**3. The same trap in Refresh.** ⌘R set `isLoading`, which swapped the panes out
for a spinner — the identical teardown-a-live-table pattern. Only the first load
replaces the panes now; a refresh keeps them mounted and shows an inline
progress line instead.

### Not yet exercised

The live write and revert round trip against Launch Services. Doing so means
changing a real association on the machine, which was deliberately not done.
The read, catalog, split-detection and history-store paths are verified; the
`setDefault` and `revert` calls are not. Test them from the UI on a file type
you do not mind reassigning — History will put it back.
