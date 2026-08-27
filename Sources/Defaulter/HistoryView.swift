import SwiftUI
import DefaulterKit

struct HistoryView: View {
    private var model: AppModel { .shared }
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            if model.historyGroups.isEmpty {
                Placeholder(symbol: "clock.arrow.circlepath",
                            title: "No changes yet",
                            subtitle: "Every default you change here is recorded so you can put it back exactly as it was.")
            } else {
                List {
                    ForEach(model.historyGroups) { group in
                        HistoryRow(group: group)
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text(model.historyGroups.isEmpty
                     ? "History is stored at ~/Library/Application Support/Defaulter/history.json"
                     : "\(model.historyGroups.count) change\(model.historyGroups.count == 1 ? "" : "s") recorded")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear History…") { confirmingClear = true }
                    .controlSize(.small)
                    .disabled(model.historyGroups.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .confirmationDialog("Clear the change history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current file associations stay exactly as they are. You just lose the ability to revert them from here.")
        }
    }
}

struct HistoryRow: View {
    let group: ChangeGroup
    private var model: AppModel { .shared }
    @State private var reverting = false

    private var previousURL: URL? {
        group.records.first?.previousBundleID.flatMap { Associations.appURL(forBundleID: $0) }
    }
    private var newURL: URL? {
        group.records.first.flatMap { Associations.appURL(forBundleID: $0.newBundleID) }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.displayLabel)
                        .font(.system(.body, design: .monospaced)).bold()
                    if group.affectedCount > 1 {
                        Text("\(group.affectedCount) types")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    AppLabel(url: previousURL, size: 14).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    AppLabel(url: newURL, size: 14).font(.caption)
                }
                Text(group.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if group.isRevertible {
                Button {
                    reverting = true
                    Task {
                        await model.revert(group)
                        reverting = false
                    }
                } label: {
                    if reverting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                    }
                }
                .controlSize(.small)
                .disabled(reverting)
            } else {
                Text("Nothing to restore")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .help("There was no default app for this type before the change, so there is nothing to put back.")
            }
        }
        .padding(.vertical, 4)
    }
}
