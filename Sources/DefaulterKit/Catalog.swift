import Foundation
import AppKit
import UniformTypeIdentifiers

/// An immutable snapshot of everything installed on this Mac that can open files.
public struct Catalog: Sendable {
    public let apps: [AppRecord]
    public let types: [TypeRecord]
    public let schemes: [SchemeRecord]
    public let appsByID: [String: AppRecord]

    /// Extension → the apps that declare they can open it (either style).
    public let declarersByExtension: [String: Set<String>]

    public init(apps: [AppRecord], types: [TypeRecord], schemes: [SchemeRecord],
                declarersByExtension: [String: Set<String>]) {
        self.apps = apps
        self.types = types
        self.schemes = schemes
        self.declarersByExtension = declarersByExtension
        self.appsByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public static let empty = Catalog(apps: [], types: [], schemes: [], declarersByExtension: [:])
}

public enum CatalogBuilder {

    /// Directories scanned for applications. Covers the standard locations plus
    /// Setapp and Nix/Homebrew-cask style prefixes.
    public static var searchPaths: [String] {
        let home = NSHomeDirectory()
        return [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            "/System/Library/CoreServices/Applications",
            "\(home)/Applications",
            "\(home)/Applications/Setapp",
            "/Applications/Setapp",
            "/Developer/Applications",
            "/opt/homebrew-cask/Caskroom",
        ]
    }

    /// Scans the disk and builds the full catalog. Safe to call off the main
    /// thread; takes ~0.2s on a typical install.
    public static func build() -> Catalog {
        let appURLs = discoverAppBundles()

        var apps: [AppRecord] = []
        var extToDeclarers: [String: Set<String>] = [:]
        var extToUTIs: [String: Set<String>] = [:]
        var schemeToApps: [String: Set<String>] = [:]

        for url in appURLs {
            guard let record = readAppBundle(at: url) else { continue }
            apps.append(record)

            // Modern declarations: UTI → its registered extensions.
            for uti in record.declaredUTIs {
                guard let type = UTType(uti) else { continue }
                for ext in type.tags[.filenameExtension] ?? [] {
                    let e = normalise(ext)
                    guard isPlausibleExtension(e) else { continue }
                    extToUTIs[e, default: []].insert(uti)
                    extToDeclarers[e, default: []].insert(record.id)
                }
            }
            // Legacy declarations: raw extension strings.
            for ext in record.declaredExtensions {
                let e = normalise(ext)
                guard isPlausibleExtension(e) else { continue }
                extToDeclarers[e, default: []].insert(record.id)
            }
            for scheme in record.declaredSchemes {
                schemeToApps[scheme, default: []].insert(record.id)
            }
        }

        // Seed common extensions so the list is never sparse on a fresh Mac,
        // and so familiar types appear even when no third-party app claims them.
        for ext in seedExtensions where extToUTIs[ext] == nil {
            extToUTIs[ext] = []
        }

        // Resolve each extension against the system's own type database. This
        // catches UTIs that no installed app happens to declare.
        var types: [TypeRecord] = []
        types.reserveCapacity(extToUTIs.count)
        for (ext, harvested) in extToUTIs {
            let system = UTType.types(tag: ext, tagClass: .filenameExtension, conformingTo: nil)
            var ordered: [String] = []
            // The system's preferred type goes first — that is what Finder uses.
            if let preferred = UTType(filenameExtension: ext) { ordered.append(preferred.identifier) }
            for t in system where !ordered.contains(t.identifier) { ordered.append(t.identifier) }
            for h in harvested.sorted() where !ordered.contains(h) { ordered.append(h) }
            guard !ordered.isEmpty else { continue }

            let description = ordered.first.flatMap { UTType($0)?.localizedDescription }
            types.append(TypeRecord(ext: ext, utis: ordered, localizedDescription: description))
        }
        types.sort { $0.ext < $1.ext }

        let schemes = schemeToApps
            .map { SchemeRecord(scheme: $0.key, declaringAppIDs: $0.value) }
            .sorted { $0.scheme < $1.scheme }

        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return Catalog(apps: apps, types: types, schemes: schemes,
                       declarersByExtension: extToDeclarers)
    }

    // MARK: - Disk scanning

    static func discoverAppBundles() -> [URL] {
        let fm = FileManager.default
        var seen = Set<String>()
        var results: [URL] = []

        for path in searchPaths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let e = fm.enumerator(at: URL(fileURLWithPath: path),
                                        includingPropertiesForKeys: [.isDirectoryKey],
                                        options: [.skipsPackageDescendants, .skipsHiddenFiles])
            else { continue }
            for case let url as URL in e {
                guard url.pathExtension == "app" else { continue }
                e.skipDescendants()
                let resolved = url.resolvingSymlinksInPath().standardizedFileURL
                if seen.insert(resolved.path).inserted { results.append(resolved) }
            }
        }
        return results
    }

    static func readAppBundle(at url: URL) -> AppRecord? {
        guard let bundle = Bundle(url: url),
              let info = bundle.infoDictionary,
              let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty
        else { return nil }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)

        var utis = Set<String>()
        var exts = Set<String>()
        var claimsEverything = false

        for doc in (info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []) {
            for uti in stringList(doc["LSItemContentTypes"]) {
                if uti == "public.data" || uti == "public.item" || uti == "public.content" {
                    claimsEverything = true
                }
                utis.insert(uti)
            }
            for ext in stringList(doc["CFBundleTypeExtensions"]) {
                if ext == "*" { claimsEverything = true; continue }
                exts.insert(normalise(ext))
            }
        }

        // Types the app itself defines. These are real associations too.
        for key in ["UTExportedTypeDeclarations", "UTImportedTypeDeclarations"] {
            for decl in (info[key] as? [[String: Any]] ?? []) {
                if let id = decl["UTTypeIdentifier"] as? String { utis.insert(id) }
                let tags = decl["UTTypeTagSpecification"] as? [String: Any] ?? [:]
                for ext in stringList(tags["public.filename-extension"]) {
                    exts.insert(normalise(ext))
                }
            }
        }

        var schemes = Set<String>()
        for entry in (info["CFBundleURLTypes"] as? [[String: Any]] ?? []) {
            for s in stringList(entry["CFBundleURLSchemes"]) {
                schemes.insert(s.lowercased())
            }
        }

        return AppRecord(id: bundleID, url: url, name: name, version: version,
                         declaredUTIs: utis,
                         declaredExtensions: exts.filter(isPlausibleExtension),
                         declaredSchemes: schemes,
                         claimsEverything: claimsEverything)
    }

    // MARK: - Helpers

    /// Info.plist keys are inconsistently a string or an array of strings.
    static func stringList(_ value: Any?) -> [String] {
        if let array = value as? [String] { return array }
        if let single = value as? String { return [single] }
        return []
    }

    static func normalise(_ ext: String) -> String {
        var e = ext.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while e.hasPrefix(".") { e.removeFirst() }
        return e
    }

    /// Filters out the junk that real Info.plists contain — empty strings,
    /// wildcards, and absurdly long values.
    static func isPlausibleExtension(_ ext: String) -> Bool {
        guard !ext.isEmpty, ext.count <= 16, ext != "*" else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-_~"))
        return ext.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
