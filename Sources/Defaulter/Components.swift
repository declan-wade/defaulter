import SwiftUI
import AppKit
import DefaulterKit

/// An app icon plus its name, the unit that appears all over this UI.
struct AppLabel: View {
    let url: URL?
    var size: CGFloat = 16
    var showPath = false
    private var model: AppModel { .shared }

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: model.icon(for: url))
                .resizable()
                .frame(width: size, height: size)
            if let url {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Manager.appName(url))
                    if showPath {
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            } else {
                Text("None").foregroundStyle(.secondary)
            }
        }
    }
}

/// The "this extension resolves to more than one app" warning. This is the
/// condition that makes macOS look broken, so it gets a real explanation
/// rather than just a badge.
struct SplitWarning: View {
    let record: TypeRecord
    let mapping: [String: URL?]
    private var model: AppModel { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Split association", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.headline)
            Text("macOS knows \(record.utis.count) different types for .\(record.ext), and they do not all open in the same app. That is why some .\(record.ext) files may open somewhere unexpected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(mapping.keys.sorted(), id: \.self) { uti in
                    HStack(spacing: 6) {
                        Text(uti)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        AppLabel(url: mapping[uti] ?? nil, size: 14)
                            .font(.caption)
                    }
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            Text("Choosing an app below sets all \(record.utis.count) of them together.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.3)))
    }
}

/// A selectable list of candidate applications.
struct AppChooser: View {
    let candidates: [URL]
    let current: URL?
    let onChoose: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open with")
                .font(.headline)

            if candidates.isEmpty {
                Text("No installed app declares support for this type.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(candidates, id: \.path) { url in
                        let isCurrent = url.standardizedFileURL.path == current?.standardizedFileURL.path
                        Button {
                            onChoose(url)
                        } label: {
                            HStack(spacing: 8) {
                                AppLabel(url: url, size: 22, showPath: true)
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(isCurrent ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .frame(maxHeight: 260)

            Button("Choose Another App…") { browseForApp() }
                .controlSize(.small)
        }
    }

    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            onChoose(url)
        }
    }
}

/// Transient banner for the result of an action.
struct StatusBanner: View {
    let message: StatusMessage
    let onDismiss: () -> Void

    private var color: Color {
        switch message.tone {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        }
    }
    private var symbol: String {
        switch message.tone {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.text).font(.callout)
                if let detail = message.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.25)))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// Empty-selection placeholder.
struct Placeholder: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline).foregroundStyle(.secondary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An inline search field.
///
/// Deliberately not `.searchable(placement: .toolbar)`. The toolbar version
/// hoists its content into a separate hosting context, and keeping every pane
/// alive (which is what stops SwiftUI's table coordinator from crashing during
/// a pane switch) would leave four of them competing for one toolbar.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused(focus)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
