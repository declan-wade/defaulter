import Foundation

/// Common extensions seeded into the catalog so the list is useful even when
/// no installed app declares them. The scan adds ~1,300 more on a typical Mac;
/// these guarantee the familiar ones are always present and always sensible.
let seedExtensions: [String] = [
    // Documents
    "txt", "rtf", "rtfd", "pdf", "doc", "docx", "odt", "pages", "tex", "epub", "mobi",
    "md", "markdown", "mdown", "org", "adoc", "textile",
    // Spreadsheets & data
    "csv", "tsv", "xls", "xlsx", "ods", "numbers", "parquet", "arrow",
    // Presentations
    "ppt", "pptx", "odp", "key",
    // Images
    "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "avif",
    "svg", "ico", "icns", "psd", "ai", "eps", "raw", "cr2", "cr3", "nef", "arw", "dng",
    "orf", "rw2", "exr", "hdr",
    // Audio
    "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "oga", "opus", "wma",
    "alac", "mid", "midi", "caf", "dsf",
    // Video
    "mp4", "m4v", "mov", "avi", "mkv", "webm", "flv", "wmv", "mpg", "mpeg", "m2ts",
    "ts", "3gp", "ogv", "vob", "srt", "vtt", "ass",
    // Archives & disk images
    "zip", "tar", "gz", "tgz", "bz2", "xz", "zst", "7z", "rar", "dmg", "iso", "pkg",
    "cpgz", "sit", "lz4",
    // Code & markup
    "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx", "rs", "go", "java", "kt",
    "kts", "scala", "clj", "rb", "py", "pyi", "pl", "php", "lua", "r", "jl", "dart",
    "ex", "exs", "erl", "hs", "ml", "fs", "vb", "cs", "sql", "sh", "bash", "zsh",
    "fish", "ps1", "bat", "cmd", "asm", "s",
    "js", "mjs", "cjs", "jsx", "ts", "tsx", "vue", "svelte", "astro",
    "html", "htm", "xhtml", "css", "scss", "sass", "less", "styl",
    "json", "jsonc", "json5", "yaml", "yml", "toml", "xml", "plist", "ini", "cfg",
    "conf", "env", "properties", "proto", "graphql", "gql",
    // Build & tooling
    "lock", "gradle", "cmake", "mk", "makefile", "dockerfile", "tf", "tfvars",
    "nix", "bazel", "bzl", "podspec", "gemspec", "cabal",
    // Fonts
    "ttf", "otf", "woff", "woff2", "ttc", "dfont",
    // Apple-specific
    "app", "xcodeproj", "xcworkspace", "playground", "swiftpm", "framework", "bundle",
    "kext", "dext", "component", "prefpane", "saver", "qlgenerator", "mdimporter",
    "workflow", "scpt", "scptd", "applescript", "shortcut", "terminal", "mobileconfig",
    "webloc", "url", "download", "crdownload", "part",
    // 3D & CAD
    "obj", "stl", "fbx", "dae", "gltf", "glb", "usdz", "usd", "usda", "usdc", "blend",
    "3mf", "step", "stp", "iges", "dwg", "dxf", "skp",
    // Notebooks & science
    "ipynb", "rmd", "qmd", "mat", "nc", "h5", "hdf5", "fits", "sav",
    // Misc
    "log", "bak", "tmp", "torrent", "ics", "vcf", "vcard", "eml", "emlx", "msg",
    "mbox", "pem", "crt", "cer", "der", "p12", "pfx", "key", "pub", "gpg", "asc", "sig",
    "db", "sqlite", "sqlite3", "realm", "bin", "dat", "hex", "img",
]
