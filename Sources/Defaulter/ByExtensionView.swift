import SwiftUI
import UniformTypeIdentifiers
import DefaulterKit

struct ByExtensionView: View {
    /// Panes stay instantiated while hidden, so each one needs to know whether
    /// it is the visible one — a hidden pane must not hold keyboard focus.
    var isActive: Bool = true
    private var model: AppModel { .shared }
    @State private var search = ""
    @State private var selection: String?
    @State private var onlySplit = false
    @State private var onlyUnhandled = false
    @FocusState private var searchFocused: Bool

    private var rows: [TypeRecord] {
        var list = model.catalog.types
        if onlySplit { list = list.filter { model.isSplit($0.ext) } }
        if onlyUnhandled { list = list.filter { model.currentApp(forExtension: $0.ext) == nil } }

        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !q.isEmpty else { return list }

        var matches = list.filter {
            $0.ext.contains(q)
                || ($0.localizedDescription?.lowercased().contains(q) ?? false)
                || (model.currentApp(forExtension: $0.ext).map { Manager.appName($0).lowercased().contains(q) } ?? false)
        }
        // Exact extension match always sorts to the top.
        matches.sort { a, b in
            if (a.ext == q) != (b.ext == q) { return a.ext == q }
            if a.ext.hasPrefix(q) != b.ext.hasPrefix(q) { return a.ext.hasPrefix(q) }
            return a.ext < b.ext
        }
        return matches
    }

    /// Lets the user act on an extension macOS knows about but that no
    /// installed app declares, so the search box is never a dead end.
    private var synthesised: TypeRecord? {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !q.isEmpty, !q.contains(" "),
              !model.catalog.types.contains(where: { $0.ext == q }),
              let type = UTType(filenameExtension: q)
        else { return nil }
        return TypeRecord(ext: q, utis: [type.identifier],
                          localizedDescription: type.localizedDescription)
    }

    /// One array backing the table. Row identity has to stay stable or the
    /// AppKit table coordinator behind `Table` hits a precondition failure.
    private var displayRows: [TypeRecord] {
        if let synthesised { return [synthesised] + rows }
        return rows
    }

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 340, idealWidth: 460)
            detailPane
                .frame(minWidth: 320, idealWidth: 380)
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Search extension, kind or app",
                        text: $search, focus: $searchFocused)
            Table(displayRows, selection: $selection) {
                TableColumn("Extension") { record in
                    HStack(spacing: 6) {
                        Image(nsImage: model.icon(forExtension: record.ext))
                            .resizable().frame(width: 16, height: 16)
                        Text(".\(record.ext)").font(.system(.body, design: .monospaced))
                        if model.isSplit(record.ext) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).font(.caption)
                                .help("Different types behind this extension open in different apps")
                        }
                    }
                }
                .width(min: 110, ideal: 130)

                TableColumn("Kind") { record in
                    Text(record.displayName).lineLimit(1).foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 160)

                TableColumn("Opens With") { record in
                    AppLabel(url: model.currentApp(forExtension: record.ext))
                }
                .width(min: 120, ideal: 160)
            }
            .tableStyle(.inset)
            .onChange(of: displayRows.count) {
                // Drop a selection whose row no longer exists, rather than
                // leaving the table pointing at a missing id.
                if let selection, !displayRows.contains(where: { $0.ext == selection }) {
                    self.selection = nil
                }
            }

            Divider()
            HStack(spacing: 12) {
                Toggle("Split only", isOn: $onlySplit)
                Toggle("Unassigned only", isOn: $onlyUnhandled)
                Spacer()
                Text("\(rows.count) of \(model.catalog.types.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { searchFocused = false; return }
            UITest.after(1.5, scenario: "search", "extensions: focus search") { searchFocused = true }
            UITest.after(2.5, scenario: "search", "extensions: type") { search = "pdf" }
            UITest.after(3.5, scenario: "search", "extensions: select row") { selection = "pdf" }
            UITest.after(4.5, scenario: "search", "extensions: split filter") {
                search = ""; onlySplit = true
            }
            UITest.after(5.0, scenario: "search", "extensions: select split row") {
                selection = model.catalog.types.first { model.isSplit($0.ext) }?.ext
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let ext = selection,
           let record = model.typeRecord(for: ext) ?? (synthesised?.ext == ext ? synthesised : nil) {
            TypeDetail(record: record)
                .id(record.ext)
        } else {
            Placeholder(symbol: "doc.text.magnifyingglass",
                        title: "No file type selected",
                        subtitle: "Choose an extension on the left to see which app opens it and change it.")
        }
    }
}

/// The right-hand pane: everything about one extension, and the control to change it.
struct TypeDetail: View {
    let record: TypeRecord
    private var model: AppModel { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if case .split(let mapping) = model.resolutions[record.ext] {
                    SplitWarning(record: record, mapping: mapping)
                }

                AppChooser(candidates: model.candidates(for: record),
                           current: model.currentApp(forExtension: record.ext)) { url in
                    Task { await model.setDefault(app: url, for: record) }
                }

                identifiers
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: model.icon(forExtension: record.ext))
                .resizable().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(".\(record.ext)")
                    .font(.system(.title2, design: .monospaced)).bold()
                Text(record.displayName).foregroundStyle(.secondary)
                if let current = model.currentApp(forExtension: record.ext) {
                    HStack(spacing: 4) {
                        Text("Currently opens in").font(.caption).foregroundStyle(.secondary)
                        AppLabel(url: current, size: 13).font(.caption).bold()
                    }
                    .padding(.top, 2)
                } else {
                    Text("No default app assigned")
                        .font(.caption).foregroundStyle(.orange).padding(.top, 2)
                }
            }
            Spacer()
        }
    }

    private var identifiers: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(record.utis, id: \.self) { uti in
                    HStack {
                        Text(uti).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        AppLabel(url: Associations.defaultApp(forUTI: uti), size: 13).font(.caption)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Type identifiers (\(record.utis.count))").font(.subheadline)
        }
    }
}
