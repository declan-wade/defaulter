import Foundation
import UniformTypeIdentifiers

/// An installed application and everything it claims it can open.
public struct AppRecord: Identifiable, Hashable, Sendable {
    public let id: String            // bundle identifier
    public let url: URL
    public let name: String
    public let version: String?

    /// UTIs declared via `CFBundleDocumentTypes` → `LSItemContentTypes`.
    public let declaredUTIs: Set<String>
    /// Raw extensions declared via the legacy `CFBundleTypeExtensions` key.
    /// Plenty of shipping apps (VS Code, for one) still declare almost
    /// everything this way, so ignoring it loses most of their associations.
    public let declaredExtensions: Set<String>
    /// URL schemes declared via `CFBundleURLTypes`.
    public let declaredSchemes: Set<String>
    /// True if the app declares a wildcard document type (`public.data`, `*`),
    /// meaning it advertises that it opens anything. Shown but never treated
    /// as if the app specifically claims each extension.
    public let claimsEverything: Bool

    public init(id: String, url: URL, name: String, version: String?,
                declaredUTIs: Set<String>, declaredExtensions: Set<String>,
                declaredSchemes: Set<String>, claimsEverything: Bool) {
        self.id = id
        self.url = url
        self.name = name
        self.version = version
        self.declaredUTIs = declaredUTIs
        self.declaredExtensions = declaredExtensions
        self.declaredSchemes = declaredSchemes
        self.claimsEverything = claimsEverything
    }

    public var isSystemApp: Bool { url.path.hasPrefix("/System/") }
}

/// A file extension, together with every UTI that claims it.
///
/// The one-extension-to-many-UTIs case is the crux of why macOS default
/// handling is confusing: `.txt` resolves to both `public.plain-text` and
/// (if iA Writer is installed) `net.ia.markdown`. Changing the default for
/// only one of them leaves some files opening in the old app.
public struct TypeRecord: Identifiable, Hashable, Sendable {
    public var id: String { ext }
    public let ext: String
    public let utis: [String]
    public let localizedDescription: String?

    public init(ext: String, utis: [String], localizedDescription: String?) {
        self.ext = ext
        self.utis = utis
        self.localizedDescription = localizedDescription
    }

    public var primaryUTI: String? { utis.first }
    public var isAmbiguous: Bool { utis.count > 1 }
    public var displayName: String {
        localizedDescription ?? utis.first.map(prettifyUTI) ?? ext.uppercased()
    }
}

private func prettifyUTI(_ uti: String) -> String {
    uti.split(separator: ".").last.map(String.init)?
        .replacingOccurrences(of: "-", with: " ")
        .capitalized ?? uti
}

/// A URL scheme (http, mailto, …) and the apps that declare it.
public struct SchemeRecord: Identifiable, Hashable, Sendable {
    public var id: String { scheme }
    public let scheme: String
    public let declaringAppIDs: Set<String>

    public init(scheme: String, declaringAppIDs: Set<String>) {
        self.scheme = scheme
        self.declaringAppIDs = declaringAppIDs
    }

    /// Well-known schemes get a friendly label; everything else shows raw.
    public var displayName: String {
        switch scheme {
        case "http", "https": return "Web page"
        case "mailto":        return "Email address"
        case "tel":           return "Phone number"
        case "sms":           return "Text message"
        case "ftp":           return "FTP server"
        case "webcal":        return "Calendar subscription"
        case "ssh":           return "SSH connection"
        case "vnc":           return "Screen sharing"
        case "facetime":      return "FaceTime call"
        default:              return scheme
        }
    }
}

/// What a default association points at, in either direction.
public enum Target: Hashable, Sendable {
    case uti(String)
    case scheme(String)

    public var label: String {
        switch self {
        case .uti(let u):    return u
        case .scheme(let s): return "\(s)://"
        }
    }
}
