import Foundation
import AppKit

/// Headless UI smoke-test hooks.
///
/// These exist because focusing the search field crashed the app and there is
/// no way to click it from a script — CI and this development environment have
/// no accessibility permission. Setting `DEFAULTER_UITEST=1` drives the paths a
/// user's clicks would: focusing each search field, typing, selecting rows, and
/// switching panes. Every hook is inert unless the variable is set.
enum UITest {
    static let enabled = ProcessInfo.processInfo.environment["DEFAULTER_UITEST"] == "1"

    /// Which scripted scenario to run: "full" (default), "panes" (only switch
    /// panes), or "search" (only drive the search fields). Used to isolate
    /// which interaction is responsible for a failure.
    static let scenario = ProcessInfo.processInfo.environment["DEFAULTER_UITEST_SCENARIO"] ?? "full"

    static func runs(_ name: String) -> Bool {
        enabled && (scenario == "full" || scenario == name)
    }

    static func after(_ delay: Double, scenario name: String, _ label: String,
                      _ work: @escaping () -> Void) {
        guard runs(name) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSLog("UITEST: \(label)")
            work()
        }
    }

    static func after(_ delay: Double, _ label: String, _ work: @escaping () -> Void) {
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSLog("UITEST: \(label)")
            work()
        }
    }

    static func log(_ message: String) {
        guard enabled else { return }
        NSLog("UITEST: \(message)")
    }
}
