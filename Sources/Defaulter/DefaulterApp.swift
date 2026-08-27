import SwiftUI
import AppKit
import DefaulterKit

@main
struct DefaulterApp: App {
    private let model = AppModel.shared

    var body: some Scene {
        Window("Default Applications", id: "main") {
            RootView()
                .frame(minWidth: 900, minHeight: 560)
                .task { await model.load() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") {
                    Task { await model.load() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct RootView: View {
    private var model: AppModel { .shared }
    @State private var section: Pane = .byExtension

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: Binding(
                get: { section },
                set: { section = $0 ?? .byExtension }
            )) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text(section.caption)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 4)
                }
            }
        } detail: {
            Group {
                // Only the first load replaces the panes. A refresh keeps them
                // mounted, because swapping a live table out mid-update is what
                // crashed the app when switching panes.
                if model.isLoading && model.catalog.apps.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Reading installed applications…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        panes
                        if model.isLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Rescanning applications…")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                        banner
                    }
                }
            }
            .navigationTitle(section.rawValue)
            .onAppear {
                UITest.after(7, scenario: "panes", "switch to By App") { section = .byApp }
                UITest.after(14, scenario: "panes", "switch to URL Schemes") { section = .schemes }
                UITest.after(21, scenario: "panes", "switch to History") { section = .history }
                UITest.after(26, scenario: "panes", "back to By Extension") { section = .byExtension }
                UITest.after(30, scenario: "panes", "refresh while panes are live") {
                    Task { await model.load() }
                }
                UITest.after(36, scenario: "panes", "complete") { UITest.log("ALL PANES SURVIVED") }
            }
        }
    }

    /// Kept out of the pane's own subtree so its animation cannot drive an
    /// animated removal of whichever table is on screen.
    @ViewBuilder
    private var banner: some View {
        if let status = model.status {
            StatusBanner(message: status) { model.status = nil }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.snappy(duration: 0.2), value: model.status)
        }
    }

    /// Every pane stays instantiated; only its visibility changes.
    ///
    /// Swapping panes used to destroy whichever `Table` was on screen, and if
    /// that happened while the table was mid-diff (right after a search edit,
    /// for instance) SwiftUI's `AppKitOutlineTableCoordinator` aborted with an
    /// AttributeGraph precondition failure. Keeping the subtree alive removes
    /// the teardown entirely rather than narrowing the race.
    private var panes: some View {
        ZStack {
            pane(.byExtension) { ByExtensionView(isActive: section == .byExtension) }
            pane(.byApp) { ByAppView(isActive: section == .byApp) }
            pane(.schemes) { SchemesView(isActive: section == .schemes) }
            pane(.history) { HistoryView() }
        }
    }

    @ViewBuilder
    private func pane<V: View>(_ id: Pane, @ViewBuilder _ make: () -> V) -> some View {
        let active = section == id
        make()
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }
}
