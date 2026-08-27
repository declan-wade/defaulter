import Foundation
import AppKit


// Read-only checks. No system state is modified.
let catalog = CatalogBuilder.build()
var pass = 0, fail = 0
func check(_ name: String, _ cond: Bool, _ note: String = "") {
    if cond { pass += 1; print("  PASS  \(name) \(note)") }
    else { fail += 1; print("  FAIL  \(name) \(note)") }
}
print("== catalog ==")
check("apps discovered", catalog.apps.count > 20, "(\(catalog.apps.count))")
check("types discovered", catalog.types.count > 300, "(\(catalog.types.count))")
check("schemes discovered", catalog.schemes.count > 10, "(\(catalog.schemes.count))")
check("no empty extensions", !catalog.types.contains { $0.ext.isEmpty })
check("no wildcard extensions", !catalog.types.contains { $0.ext == "*" })
check("all types have a UTI", !catalog.types.contains { $0.utis.isEmpty })
check("extensions are unique", Set(catalog.types.map(\.ext)).count == catalog.types.count)
check("common types present",
      ["pdf","txt","png","html","json","zip","mp4"].allSatisfy { e in catalog.types.contains { $0.ext == e } })

print("== legacy declaration handling ==")
let legacyOnly = catalog.apps.filter { $0.declaredUTIs.count <= 2 && $0.declaredExtensions.count > 20 }
check("apps using legacy CFBundleTypeExtensions are captured", !legacyOnly.isEmpty,
      "(\(legacyOnly.map { "\($0.name):\($0.declaredExtensions.count)" }.prefix(3).joined(separator: ", ")))")

print("== resolution ==")
let pdf = catalog.types.first { $0.ext == "pdf" }!
check("pdf resolves to an app", Associations.defaultApp(forExtension: "pdf") != nil,
      "(\(Associations.defaultApp(forExtension: "pdf").map(Manager.appName) ?? "none"))")
check("pdf has candidates", Associations.candidates(forExtension: pdf).count > 1,
      "(\(Associations.candidates(forExtension: pdf).count))")
let splits = catalog.types.filter { Associations.resolve($0).isSplit }
check("split detection works", !splits.isEmpty, "(\(splits.count) split types found)")

print("== history store (isolated file, no system changes) ==")
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("defaulter-verify-\(UUID()).json")
let h = History(fileURL: tmp)
let gid = UUID()
h.append([
  ChangeRecord(kind: .uti, identifier: "public.plain-text", displayLabel: ".txt",
               previousBundleID: "com.apple.TextEdit", previousAppName: "TextEdit",
               newBundleID: "com.test.app", newAppName: "Test", groupID: gid),
  ChangeRecord(kind: .uti, identifier: "net.ia.markdown", displayLabel: ".txt",
               previousBundleID: "com.apple.TextEdit", previousAppName: "TextEdit",
               newBundleID: "com.test.app", newAppName: "Test", groupID: gid),
])
check("records persisted", h.all().count == 2)
check("grouped into one undo step", h.groups().count == 1 && h.groups()[0].affectedCount == 2)
let reloaded = History(fileURL: tmp)
check("survives reload from disk", reloaded.all().count == 2)
check("group is revertible", reloaded.groups()[0].isRevertible)
h.remove(groupID: gid)
check("group removal works", h.all().isEmpty)
try? Data("{ corrupt".utf8).write(to: tmp)
check("corrupt log does not crash", History(fileURL: tmp).all().isEmpty)
try? FileManager.default.removeItem(at: tmp)

print("\n== \(pass) passed, \(fail) failed ==")
exit(fail == 0 ? 0 : 1)
