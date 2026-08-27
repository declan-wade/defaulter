import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Observation
import DefaulterKit

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case byExtension = "By Extension"
    case byApp = "By App"
    case schemes = "URL Schemes"
    case history = "History"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .byExtension: return "doc.text.magnifyingglass"
        case .byApp:       return "square.grid.2x2"
        case .schemes:     return "link"
        case .history:     return "clock.arrow.circlepath"
        }
    }
    var caption: String {
        switch self {
        case .byExtension: return "Pick a file type, choose which app opens it"
        case .byApp:       return "Pick an app, see and change everything it opens"
        case .schemes:     return "Choose the default browser, mail client and more"
        case .history:     return "Undo any change made here"
        }
    }
}

/// Status banner shown after an action.
struct StatusMessage: Identifiable, Equatable {
    enum Tone { case success, warning, failure }
    let id = UUID()
    let tone: Tone
    let text: String
    var detail: String?
}

@MainActor
@Observable
final class AppModel {
    /// The one model instance for the app's lifetime.
    ///
    /// Deliberately not passed through `@Environment`. SwiftUI hoists toolbar
    /// and `searchable` content into a separate hosting context that does not
    /// inherit the environment set on the window's root view, so any view
    /// re-evaluated during preference combining crashed with "No Observable
    /// object of type AppModel found". Reading the singleton inside `body`
    /// still registers with Observation, so updates propagate normally.
    static let shared = AppModel()

    var catalog: Catalog = .empty
    var isLoading = true

    /// ext → how its UTIs currently resolve.
    var resolutions: [String: Associations.Resolution] = [:]
    /// scheme → current handler.
    var schemeHandlers: [String: URL] = [:]
    /// bundle ID → extensions this app is currently the default for.
    var ownedExtensions: [String: Set<String>] = [:]

    var status: StatusMessage?
    var historyGroups: [ChangeGroup] = []

    private let manager = Manager()
    private var iconCache: [String: NSImage] = [:]

    // MARK: - Loading

    func load() async {
        isLoading = true
        let built = await Task.detached(priority: .userInitiated) {
            CatalogBuilder.build()
        }.value
        catalog = built
        await refreshResolutions()
        isLoading = false
    }

    /// Re-reads every current default from Launch Services. Cheap (~0.15s),
    /// so it runs after any change rather than trying to patch state in place —
    /// changing one UTI can shift what other extensions resolve to.
    func refreshResolutions() async {
        let types = catalog.types
        let schemes = catalog.schemes.map(\.scheme)
        let result = await Task.detached(priority: .userInitiated) { () -> ([String: Associations.Resolution], [String: URL]) in
            var res: [String: Associations.Resolution] = [:]
            res.reserveCapacity(types.count)
            for t in types { res[t.ext] = Associations.resolve(t) }
            var handlers: [String: URL] = [:]
            for s in schemes {
                if let url = Associations.defaultApp(forScheme: s) { handlers[s] = url }
            }
            return (res, handlers)
        }.value

        resolutions = result.0
        schemeHandlers = result.1

        var owned: [String: Set<String>] = [:]
        for (ext, resolution) in resolutions {
            guard let url = resolution.primaryApp,
                  let id = Associations.bundleID(for: url) else { continue }
            owned[id, default: []].insert(ext)
        }
        ownedExtensions = owned
        historyGroups = History.shared.groups()
    }

    // MARK: - Derived views of the data

    func typeRecord(for ext: String) -> TypeRecord? {
        catalog.types.first { $0.ext == ext }
    }

    func currentApp(forExtension ext: String) -> URL? {
        resolutions[ext]?.primaryApp
    }

    func isSplit(_ ext: String) -> Bool {
        resolutions[ext]?.isSplit ?? false
    }

    /// Candidate apps for a type: everything Launch Services offers, plus any
    /// app that declared the extension the legacy way (which Launch Services
    /// will not return for a UTI it never registered against).
    func candidates(for record: TypeRecord) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in Associations.candidates(forExtension: record) {
            if seen.insert(url.standardizedFileURL.path).inserted { result.append(url) }
        }
        for id in catalog.declarersByExtension[record.ext] ?? [] {
            guard let app = catalog.appsByID[id] else { continue }
            if seen.insert(app.url.standardizedFileURL.path).inserted { result.append(app.url) }
        }
        return result.sorted { Manager.appName($0).localizedStandardCompare(Manager.appName($1)) == .orderedAscending }
    }

    /// Extensions an app declares it can open, split into ones it currently
    /// owns and ones it does not.
    func coverage(for app: AppRecord) -> (owned: [TypeRecord], available: [TypeRecord]) {
        let declared = catalog.declarersByExtension.compactMap { (ext, ids) -> String? in
            ids.contains(app.id) ? ext : nil
        }
        let ownedSet = ownedExtensions[app.id] ?? []
        let union = Set(declared).union(ownedSet)
        var owned: [TypeRecord] = []
        var available: [TypeRecord] = []
        for ext in union.sorted() {
            guard let record = typeRecord(for: ext) else { continue }
            if ownedSet.contains(ext) { owned.append(record) } else { available.append(record) }
        }
        return (owned, available)
    }

    func app(named url: URL) -> String { Manager.appName(url) }

    func icon(for url: URL?) -> NSImage {
        guard let url else { return NSWorkspace.shared.icon(for: .data) }
        let key = url.standardizedFileURL.path
        if let cached = iconCache[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: key)
        image.size = NSSize(width: 32, height: 32)
        iconCache[key] = image
        return image
    }

    func icon(forExtension ext: String) -> NSImage {
        let key = "ext:\(ext)"
        if let cached = iconCache[key] { return cached }
        let image: NSImage
        if let type = UTType(filenameExtension: ext) {
            image = NSWorkspace.shared.icon(for: type)
        } else {
            image = NSWorkspace.shared.icon(for: .data)
        }
        image.size = NSSize(width: 20, height: 20)
        iconCache[key] = image
        return image
    }

    // MARK: - Actions

    func setDefault(app appURL: URL, for record: TypeRecord) async {
        let outcome = await manager.setDefault(app: appURL, for: record)
        await refreshResolutions()
        let name = Manager.appName(appURL)

        if outcome.isCompleteSuccess {
            if let group = outcome.group {
                let extra = group.affectedCount > 1 ? " (\(group.affectedCount) types)" : ""
                status = StatusMessage(tone: .success,
                                       text: "“\(name)” now opens .\(record.ext)\(extra).")
            } else {
                status = StatusMessage(tone: .success,
                                       text: "“\(name)” already opens .\(record.ext).")
            }
        } else if outcome.group != nil {
            status = StatusMessage(
                tone: .warning,
                text: "Partly applied for .\(record.ext).",
                detail: "macOS refused \(outcome.failures.count) of this type's identifiers: "
                    + outcome.failures.map(\.identifier).joined(separator: ", "))
        } else {
            status = StatusMessage(
                tone: .failure,
                text: "Could not set “\(name)” for .\(record.ext).",
                detail: outcome.failures.first?.reason)
        }
    }

    func setDefault(app appURL: URL, forScheme scheme: String) async {
        let outcome = await manager.setDefault(app: appURL, forScheme: scheme)
        await refreshResolutions()
        let name = Manager.appName(appURL)
        if outcome.isCompleteSuccess {
            status = StatusMessage(tone: .success, text: "“\(name)” now handles \(scheme):// links.")
        } else {
            status = StatusMessage(tone: .failure,
                                   text: "Could not set “\(name)” for \(scheme)://.",
                                   detail: outcome.failures.first?.reason)
        }
    }

    func revert(_ group: ChangeGroup) async {
        let failures = await History.shared.revert(group)
        await refreshResolutions()
        if failures.isEmpty {
            status = StatusMessage(tone: .success,
                                   text: "Reverted \(group.displayLabel) to “\(group.previousAppName ?? "its previous app")”.")
        } else if failures.count < group.records.count {
            status = StatusMessage(tone: .warning,
                                   text: "Partly reverted \(group.displayLabel).",
                                   detail: failures.first?.1)
        } else {
            status = StatusMessage(tone: .failure,
                                   text: "Could not revert \(group.displayLabel).",
                                   detail: failures.first?.1)
        }
    }

    func clearHistory() {
        History.shared.clear()
        historyGroups = []
        status = StatusMessage(tone: .success, text: "History cleared. Existing defaults were not changed.")
    }
}
