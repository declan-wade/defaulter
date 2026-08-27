import Foundation
import AppKit
import UniformTypeIdentifiers

public enum AssociationError: LocalizedError {
    case unknownType(String)
    case noSuchApp(String)
    case setFailed(target: String, underlying: String)
    case partiallyApplied(target: String, succeeded: [String], failed: [(String, String)])

    public var errorDescription: String? {
        switch self {
        case .unknownType(let t):
            return "macOS does not recognise the type “\(t)”."
        case .noSuchApp(let id):
            return "Could not find the application “\(id)”."
        case .setFailed(let target, let underlying):
            return "Could not set the default for \(target): \(underlying)"
        case .partiallyApplied(let target, let succeeded, let failed):
            let f = failed.map { "\($0.0) (\($0.1))" }.joined(separator: ", ")
            return "Set \(succeeded.count) of \(succeeded.count + failed.count) types for \(target). Failed: \(f)"
        }
    }
}

/// Reads and writes Launch Services default handlers.
///
/// Reads go through `NSWorkspace`, which reflects the live Launch Services
/// database. Writes use the modern async `NSWorkspace` setter, falling back to
/// the older `LSSetDefaultRoleHandler…` call when it reports a failure — the two
/// disagree on a handful of system-declared types.
public enum Associations {

    // MARK: - Reading

    public static func defaultApp(forUTI uti: String) -> URL? {
        guard let type = UTType(uti) else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    public static func candidates(forUTI uti: String) -> [URL] {
        guard let type = UTType(uti) else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: type)
    }

    public static func defaultApp(forScheme scheme: String) -> URL? {
        guard let url = URL(string: "\(scheme):") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    public static func candidates(forScheme scheme: String) -> [URL] {
        guard let url = URL(string: "\(scheme):") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    /// The default handler for a whole extension, resolved through its primary
    /// UTI. Returns nil when nothing is registered.
    public static func defaultApp(forExtension ext: String) -> URL? {
        guard let type = UTType(filenameExtension: ext) else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    /// Every app that can open any UTI belonging to this extension, de-duplicated.
    public static func candidates(forExtension record: TypeRecord) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for uti in record.utis {
            for url in candidates(forUTI: uti) {
                let path = url.standardizedFileURL.path
                if seen.insert(path).inserted { result.append(url) }
            }
        }
        return result
    }

    /// Reports whether every UTI behind an extension resolves to the same app.
    /// A `.split` result is the situation that makes Finder's behaviour look
    /// random: some files of that extension open in one app, some in another.
    public enum Resolution: Sendable, Equatable {
        case none
        case unified(URL)
        case split([String: URL?])

        public var primaryApp: URL? {
            switch self {
            case .none: return nil
            case .unified(let u): return u
            case .split(let m): return m.values.compactMap { $0 }.first
            }
        }
        public var isSplit: Bool { if case .split = self { return true }; return false }
    }

    public static func resolve(_ record: TypeRecord) -> Resolution {
        var mapping: [String: URL?] = [:]
        for uti in record.utis {
            mapping[uti] = defaultApp(forUTI: uti)
        }
        let distinct = Set(mapping.values.map { $0?.standardizedFileURL.path ?? "∅" })
        if distinct.count <= 1 {
            if let first = mapping.values.compactMap({ $0 }).first { return .unified(first) }
            return .none
        }
        return .split(mapping)
    }

    // MARK: - Writing

    /// Sets the default app for a single UTI.
    public static func setDefault(app: URL, forUTI uti: String) async throws {
        guard let type = UTType(uti) else { throw AssociationError.unknownType(uti) }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
        } catch {
            // Fall back to the older Launch Services call, which still succeeds
            // for some system-declared types the modern API rejects.
            guard let bundleID = Bundle(url: app)?.bundleIdentifier else {
                throw AssociationError.setFailed(target: uti, underlying: error.localizedDescription)
            }
            let status = LSSetDefaultRoleHandlerForContentType(
                uti as CFString, .all, bundleID as CFString)
            guard status == noErr else {
                throw AssociationError.setFailed(
                    target: uti,
                    underlying: "\(error.localizedDescription) (fallback OSStatus \(status))")
            }
        }
    }

    /// Sets the default app for *every* UTI behind an extension.
    ///
    /// This is the operation users actually mean when they say "open .txt files
    /// in BBEdit". Setting only the primary UTI leaves the others pointing
    /// elsewhere, which is the usual cause of "I changed it and it didn't work".
    @discardableResult
    public static func setDefault(app: URL, forExtension record: TypeRecord) async throws -> [String] {
        var succeeded: [String] = []
        var failed: [(String, String)] = []
        for uti in record.utis {
            do {
                try await setDefault(app: app, forUTI: uti)
                succeeded.append(uti)
            } catch {
                failed.append((uti, error.localizedDescription))
            }
        }
        if succeeded.isEmpty, let first = failed.first {
            throw AssociationError.setFailed(target: ".\(record.ext)", underlying: first.1)
        }
        if !failed.isEmpty {
            throw AssociationError.partiallyApplied(
                target: ".\(record.ext)", succeeded: succeeded, failed: failed)
        }
        return succeeded
    }

    public static func setDefault(app: URL, forScheme scheme: String) async throws {
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme)
        } catch {
            guard let bundleID = Bundle(url: app)?.bundleIdentifier else {
                throw AssociationError.setFailed(target: scheme, underlying: error.localizedDescription)
            }
            let status = LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleID as CFString)
            guard status == noErr else {
                throw AssociationError.setFailed(
                    target: "\(scheme)://",
                    underlying: "\(error.localizedDescription) (fallback OSStatus \(status))")
            }
        }
    }

    // MARK: - App lookup

    public static func appURL(forBundleID id: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    public static func bundleID(for url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }
}
