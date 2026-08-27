import SwiftUI
import DefaulterKit

struct SchemesView: View {
    var isActive: Bool = true
    private var model: AppModel { .shared }
    @State private var search = ""
    @State private var selection: String?
    @State private var showAll = false
    @FocusState private var searchFocused: Bool

    /// The schemes people actually want to manage, pinned to the top.
    private static let common = ["http", "https", "mailto", "tel", "sms",
                                 "webcal", "ftp", "ssh", "vnc", "facetime"]

    private var rows: [SchemeRecord] {
        var list = model.catalog.schemes
        if !showAll {
            list = list.filter { Self.common.contains($0.scheme) || model.schemeHandlers[$0.scheme] != nil }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.scheme.contains(q) || $0.displayName.lowercased().contains(q)
            }
        }
        return list.sorted { a, b in
            let ai = Self.common.firstIndex(of: a.scheme) ?? Int.max
            let bi = Self.common.firstIndex(of: b.scheme) ?? Int.max
            if ai != bi { return ai < bi }
            return a.scheme < b.scheme
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                SearchField(prompt: "Search schemes", text: $search, focus: $searchFocused)
                Table(rows, selection: $selection) {
                    TableColumn("Scheme") { r in
                        Text("\(r.scheme)://").font(.system(.body, design: .monospaced))
                    }.width(min: 100, ideal: 130)
                    TableColumn("Kind") { r in
                        Text(r.displayName).foregroundStyle(.secondary).lineLimit(1)
                    }.width(min: 90, ideal: 140)
                    TableColumn("Handled By") { r in
                        AppLabel(url: model.schemeHandlers[r.scheme])
                    }.width(min: 120, ideal: 160)
                }
                .tableStyle(.inset)
                .onChange(of: rows.count) {
                    if let selection, !rows.contains(where: { $0.scheme == selection }) {
                        self.selection = nil
                    }
                }

                Divider()
                HStack {
                    Toggle("Show all \(model.catalog.schemes.count) schemes", isOn: $showAll)
                        .toggleStyle(.checkbox).controlSize(.small)
                    Spacer()
                    Text("\(rows.count) shown").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .frame(minWidth: 340, idealWidth: 460)
            .onChange(of: isActive, initial: true) { _, active in
                guard active else { searchFocused = false; return }
                UITest.after(1.5, scenario: "search", "schemes: focus search") { searchFocused = true }
                UITest.after(2.5, scenario: "search", "schemes: type") { search = "http" }
                UITest.after(3.5, scenario: "search", "schemes: select https") { selection = "https" }
                UITest.after(4.5, scenario: "search", "schemes: show all") { search = ""; showAll = true }
            }

            detail.frame(minWidth: 320, idealWidth: 380)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let scheme = selection,
           let record = model.catalog.schemes.first(where: { $0.scheme == scheme }) {
            SchemeDetail(record: record).id(scheme)
        } else {
            Placeholder(symbol: "link",
                        title: "No scheme selected",
                        subtitle: "Choose a scheme to set which app opens links of that kind — including your default browser and mail client.")
        }
    }
}

struct SchemeDetail: View {
    let record: SchemeRecord
    private var model: AppModel { .shared }

    private var candidates: [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in Associations.candidates(forScheme: record.scheme) {
            if seen.insert(url.standardizedFileURL.path).inserted { result.append(url) }
        }
        // Include apps that declare the scheme even if Launch Services does not
        // list them as candidates yet.
        for id in record.declaringAppIDs {
            guard let app = model.catalog.appsByID[id] else { continue }
            if seen.insert(app.url.standardizedFileURL.path).inserted { result.append(app.url) }
        }
        return result.sorted { Manager.appName($0).localizedStandardCompare(Manager.appName($1)) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 40)).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(record.scheme)://")
                            .font(.system(.title2, design: .monospaced)).bold()
                        Text(record.displayName).foregroundStyle(.secondary)
                        if let current = model.schemeHandlers[record.scheme] {
                            HStack(spacing: 4) {
                                Text("Currently handled by").font(.caption).foregroundStyle(.secondary)
                                AppLabel(url: current, size: 13).font(.caption).bold()
                            }
                        } else {
                            Text("No handler assigned").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                }

                if record.scheme == "http" || record.scheme == "https" {
                    Label("http:// and https:// are set separately. Set both to fully change your default browser.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }

                AppChooser(candidates: candidates,
                           current: model.schemeHandlers[record.scheme]) { url in
                    Task { await model.setDefault(app: url, forScheme: record.scheme) }
                }
            }
            .padding(16)
        }
    }
}
