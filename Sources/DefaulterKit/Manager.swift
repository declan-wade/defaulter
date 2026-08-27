import Foundation
import AppKit

/// Applies association changes and records them so they can be undone.
///
/// Every write goes through here so that nothing changes a default without
/// the previous value being captured first.
public struct Manager: Sendable {
    public let history: History

    public init(history: History = .shared) {
        self.history = history
    }

    public struct Outcome: Sendable {
        public let group: ChangeGroup?
        /// Types that could not be changed, with the reason. An empty array
        /// means everything applied.
        public let failures: [(identifier: String, reason: String)]
        public var isCompleteSuccess: Bool { failures.isEmpty }
    }

    /// Makes `app` the default for every UTI behind `record`.
    public func setDefault(app appURL: URL, for record: TypeRecord) async -> Outcome {
        let newName = Manager.appName(appURL)
        let newID = Associations.bundleID(for: appURL) ?? appURL.path
        let groupID = UUID()

        var changes: [ChangeRecord] = []
        var failures: [(String, String)] = []

        for uti in record.utis {
            // Capture the before-state per UTI, before touching anything.
            let previousURL = Associations.defaultApp(forUTI: uti)
            let previousID = previousURL.flatMap { Associations.bundleID(for: $0) }
            let previousName = previousURL.map(Manager.appName)

            if previousID == newID { continue }   // already correct; nothing to record

            do {
                try await Associations.setDefault(app: appURL, forUTI: uti)
                changes.append(ChangeRecord(
                    kind: .uti, identifier: uti, displayLabel: ".\(record.ext)",
                    previousBundleID: previousID, previousAppName: previousName,
                    newBundleID: newID, newAppName: newName, groupID: groupID))
            } catch {
                failures.append((uti, error.localizedDescription))
            }
        }

        history.append(changes)
        let group = changes.isEmpty ? nil : ChangeGroup(id: groupID, records: changes)
        return Outcome(group: group, failures: failures.map { (identifier: $0.0, reason: $0.1) })
    }

    /// Makes `app` the handler for a URL scheme.
    public func setDefault(app appURL: URL, forScheme scheme: String) async -> Outcome {
        let newName = Manager.appName(appURL)
        let newID = Associations.bundleID(for: appURL) ?? appURL.path
        let groupID = UUID()

        let previousURL = Associations.defaultApp(forScheme: scheme)
        let previousID = previousURL.flatMap { Associations.bundleID(for: $0) }
        let previousName = previousURL.map(Manager.appName)

        if previousID == newID {
            return Outcome(group: nil, failures: [])
        }

        do {
            try await Associations.setDefault(app: appURL, forScheme: scheme)
            let record = ChangeRecord(
                kind: .scheme, identifier: scheme, displayLabel: "\(scheme)://",
                previousBundleID: previousID, previousAppName: previousName,
                newBundleID: newID, newAppName: newName, groupID: groupID)
            history.append([record])
            return Outcome(group: ChangeGroup(id: groupID, records: [record]), failures: [])
        } catch {
            return Outcome(group: nil, failures: [(identifier: scheme, reason: error.localizedDescription)])
        }
    }

    public static func appName(_ url: URL) -> String {
        if let info = Bundle(url: url)?.infoDictionary,
           let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String),
           !name.isEmpty {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
