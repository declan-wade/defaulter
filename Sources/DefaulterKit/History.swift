import Foundation
import AppKit

/// One recorded change to a single Launch Services association.
public struct ChangeRecord: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case uti, scheme }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    /// The UTI or scheme actually written.
    public let identifier: String
    /// What the user was looking at when they made the change (".txt", "https").
    public let displayLabel: String
    public let previousBundleID: String?
    public let previousAppName: String?
    public let newBundleID: String
    public let newAppName: String
    /// Changes made as one user action share a group, so reverting an
    /// extension with several UTIs behind it puts all of them back together.
    public let groupID: UUID

    public init(id: UUID = UUID(), date: Date = Date(), kind: Kind, identifier: String,
                displayLabel: String, previousBundleID: String?, previousAppName: String?,
                newBundleID: String, newAppName: String, groupID: UUID) {
        self.id = id
        self.date = date
        self.kind = kind
        self.identifier = identifier
        self.displayLabel = displayLabel
        self.previousBundleID = previousBundleID
        self.previousAppName = previousAppName
        self.newBundleID = newBundleID
        self.newAppName = newAppName
        self.groupID = groupID
    }

    /// True when there was no handler before, so there is nothing to restore.
    public var isRevertible: Bool { previousBundleID != nil }
}

/// A group of changes made by one user action, presented as a single undoable step.
public struct ChangeGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let records: [ChangeRecord]

    public var date: Date { records.map(\.date).max() ?? .distantPast }
    public var displayLabel: String { records.first?.displayLabel ?? "" }
    public var newAppName: String { records.first?.newAppName ?? "" }
    public var previousAppName: String? {
        let names = Set(records.compactMap(\.previousAppName))
        if names.count == 1 { return names.first }
        if names.isEmpty { return nil }
        return "\(names.count) apps"
    }
    public var kind: ChangeRecord.Kind { records.first?.kind ?? .uti }
    public var isRevertible: Bool { records.contains(where: \.isRevertible) }
    public var affectedCount: Int { records.count }
}

/// Append-only, atomically written log of every change the app has made.
public final class History: @unchecked Sendable {
    public static let shared = History()

    private let queue = DispatchQueue(label: "au.codex.defaulter.history")
    private var cache: [ChangeRecord]

    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        let resolved = fileURL ?? History.defaultFileURL()
        self.fileURL = resolved
        self.cache = History.load(from: resolved)
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Defaulter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private static func load(from url: URL) -> [ChangeRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A corrupt log must never stop the app from working; it is a
        // convenience record, not the source of truth.
        return (try? decoder.decode([ChangeRecord].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cache) else { return }
        // Atomic write so an interrupted save cannot truncate the log.
        try? data.write(to: fileURL, options: .atomic)
    }

    public func append(_ records: [ChangeRecord]) {
        guard !records.isEmpty else { return }
        queue.sync {
            cache.append(contentsOf: records)
            // Keep the log bounded; the oldest entries are the least useful.
            if cache.count > 2000 { cache.removeFirst(cache.count - 2000) }
            persist()
        }
    }

    public func all() -> [ChangeRecord] {
        queue.sync { cache }
    }

    /// Change groups, newest first.
    public func groups() -> [ChangeGroup] {
        let records = all()
        let grouped = Dictionary(grouping: records, by: \.groupID)
        return grouped
            .map { ChangeGroup(id: $0.key, records: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.date > $1.date }
    }

    public func clear() {
        queue.sync {
            cache.removeAll()
            persist()
        }
    }

    public func remove(groupID: UUID) {
        queue.sync {
            cache.removeAll { $0.groupID == groupID }
            persist()
        }
    }

    /// Puts every association in a group back to what it was.
    /// Returns the records that could not be restored, with the reason.
    @discardableResult
    public func revert(_ group: ChangeGroup) async -> [(ChangeRecord, String)] {
        var failures: [(ChangeRecord, String)] = []
        for record in group.records {
            guard let previousID = record.previousBundleID else {
                failures.append((record, "there was no handler before this change"))
                continue
            }
            guard let appURL = Associations.appURL(forBundleID: previousID) else {
                failures.append((record, "“\(record.previousAppName ?? previousID)” is no longer installed"))
                continue
            }
            do {
                switch record.kind {
                case .uti:    try await Associations.setDefault(app: appURL, forUTI: record.identifier)
                case .scheme: try await Associations.setDefault(app: appURL, forScheme: record.identifier)
                }
            } catch {
                failures.append((record, error.localizedDescription))
            }
        }
        if failures.count < group.records.count {
            remove(groupID: group.id)
        }
        return failures
    }
}
