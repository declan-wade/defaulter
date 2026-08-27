import SwiftUI
import DefaulterKit

struct ByAppView: View {
    var isActive: Bool = true
    private var model: AppModel { .shared }
    @State private var search = ""
    @State private var selection: String?
    @State private var hideSystemApps = false
    @FocusState private var searchFocused: Bool

    private var apps: [AppRecord] {
        var list = model.catalog.apps.filter {
            !$0.declaredUTIs.isEmpty || !$0.declaredExtensions.isEmpty
                || !(model.ownedExtensions[$0.id]?.isEmpty ?? true)
        }
        if hideSystemApps { list = list.filter { !$0.isSystemApp } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    var body: some View {
        HSplitView {
            listPane.frame(minWidth: 260, idealWidth: 300)
            detailPane.frame(minWidth: 380, idealWidth: 520)
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Search applications", text: $search, focus: $searchFocused)
            List(selection: $selection) {
                ForEach(apps) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: model.icon(for: app.url))
                            .resizable().frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).lineLimit(1)
                            Text(ownershipCaption(app))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .tag(app.id)
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Toggle("Hide system apps", isOn: $hideSystemApps)
                    .toggleStyle(.checkbox).controlSize(.small)
                Spacer()
                Text("\(apps.count) apps").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { searchFocused = false; return }
            UITest.after(1.5, scenario: "search", "apps: focus search") { searchFocused = true }
            UITest.after(2.5, scenario: "search", "apps: type") { search = "pre" }
            UITest.after(3.5, scenario: "search", "apps: clear") { search = "" }
            UITest.after(4.5, scenario: "search", "apps: select app with most types") {
                selection = model.ownedExtensions
                    .max { $0.value.count < $1.value.count }?.key
                    ?? model.catalog.apps.first?.id
            }
        }
    }

    private func ownershipCaption(_ app: AppRecord) -> String {
        let owned = model.ownedExtensions[app.id]?.count ?? 0
        let declared = model.catalog.declarersByExtension.reduce(into: 0) { total, entry in
            if entry.value.contains(app.id) { total += 1 }
        }
        if owned == 0 { return "default for none of \(declared)" }
        return "default for \(owned) of \(max(declared, owned))"
    }

    @ViewBuilder
    private var detailPane: some View {
        if let id = selection, let app = model.catalog.appsByID[id] {
            AppDetail(app: app).id(app.id)
        } else {
            Placeholder(symbol: "square.grid.2x2",
                        title: "No application selected",
                        subtitle: "Choose an app on the left to see every file type it opens, and every type it could open.")
        }
    }
}

/// The right-hand pane: everything one app currently owns, and everything it
/// declares it can open but does not currently own.
struct AppDetail: View {
    let app: AppRecord
    private var model: AppModel { .shared }
    @State private var confirmingClaimAll = false

    private var coverage: (owned: [TypeRecord], available: [TypeRecord]) {
        model.coverage(for: app)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if app.claimsEverything {
                    Label("This app advertises that it can open any file. Only the types it names specifically are listed below.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }

                section(title: "Opens by default",
                        caption: "Double-clicking these files opens \(app.name).",
                        records: coverage.owned,
                        emptyText: "\(app.name) is not currently the default for any file type.",
                        showsAction: false)

                section(title: "Can open, but does not by default",
                        caption: "\(app.name) declares support for these. Click one to hand it over.",
                        records: coverage.available,
                        emptyText: "Nothing else declared.",
                        showsAction: true)

                if !app.declaredSchemes.isEmpty {
                    schemes
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: model.icon(for: app.url))
                .resizable().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.title2).bold()
                if let v = app.version {
                    Text("Version \(v)").font(.caption).foregroundStyle(.secondary)
                }
                Text(app.id)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary).textSelection(.enabled)
                Text(app.url.path)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head).textSelection(.enabled)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func section(title: String, caption: String, records: [TypeRecord],
                         emptyText: String, showsAction: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Text("\(records.count)")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)

            if records.isEmpty {
                Text(emptyText)
                    .font(.callout).foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                FlowGrid(records: records, showsAction: showsAction, app: app)
            }
        }
    }

    private var schemes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("URL schemes").font(.headline)
            Text("Links of these kinds can be handled by \(app.name).")
                .font(.caption).foregroundStyle(.secondary)
            let sorted = app.declaredSchemes.sorted()
            VStack(alignment: .leading, spacing: 3) {
                ForEach(sorted, id: \.self) { scheme in
                    let handler = model.schemeHandlers[scheme]
                    let isOwner = handler.flatMap { Associations.bundleID(for: $0) } == app.id
                    HStack(spacing: 6) {
                        Image(systemName: isOwner ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOwner ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                            .font(.caption)
                        Text("\(scheme)://").font(.system(.caption, design: .monospaced))
                        Spacer()
                        if !isOwner {
                            Button("Use \(app.name)") {
                                Task { await model.setDefault(app: app.url, forScheme: scheme) }
                            }
                            .controlSize(.mini)
                        }
                    }
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// Wrapping grid of extension chips.
struct FlowGrid: View {
    let records: [TypeRecord]
    let showsAction: Bool
    let app: AppRecord
    private var model: AppModel { .shared }

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 200), spacing: 6, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(records) { record in
                Button {
                    guard showsAction else { return }
                    Task { await model.setDefault(app: app.url, for: record) }
                } label: {
                    HStack(spacing: 4) {
                        Image(nsImage: model.icon(forExtension: record.ext))
                            .resizable().frame(width: 14, height: 14)
                        Text(".\(record.ext)")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        if model.isSplit(record.ext) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8)).foregroundStyle(.orange)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(showsAction ? AnyShapeStyle(.quaternary.opacity(0.5))
                                            : AnyShapeStyle(Color.accentColor.opacity(0.15)),
                                in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(helpText(record))
            }
        }
    }

    private func helpText(_ record: TypeRecord) -> String {
        let current = model.currentApp(forExtension: record.ext).map(Manager.appName) ?? "nothing"
        return showsAction
            ? "Currently opens in \(current). Click to use \(app.name) instead."
            : "\(record.displayName) — \(app.name) is the default."
    }
}
