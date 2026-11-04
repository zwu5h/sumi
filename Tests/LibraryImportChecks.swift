import Foundation

// Portable substitutes test orchestration and cleanup, not PDFKit rendering.
protocol ObservableObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
extension URL {
    func startAccessingSecurityScopedResource() -> Bool { false }
    func stopAccessingSecurityScopedResource() {}
}
enum PDFDisplayBox { case cropBox }
struct TestThumbnail { func pngData() -> Data? { Data("thumbnail".utf8) } }
struct PDFPage {
    func thumbnail(of size: CGSize, for box: PDFDisplayBox) -> TestThumbnail { TestThumbnail() }
}
struct PDFDocument {
    static var onOpen: (() -> Void)?
    let pageCount: Int
    let isLocked: Bool
    init?(url: URL) {
        Self.onOpen?()
        guard let content = try? String(contentsOf: url, encoding: .utf8), content != "invalid" else { return nil }
        pageCount = content == "empty" ? 0 : 3
        isLocked = content == "locked"
    }
    func page(at index: Int) -> PDFPage? { index < pageCount ? PDFPage() : nil }
}

@main
struct LibraryImportChecks {
    @MainActor static func main() async throws {
        let directory = LibraryStore.documents.deletingLastPathComponent()
        let input = directory.appendingPathComponent("input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        func fixture(_ name: String, _ contents: String) throws -> URL {
            let url = input.appendingPathComponent(name + ".pdf")
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        let first = try fixture("First", "valid")
        let second = try fixture("Second", "valid")
        let broken = try fixture("Broken", "invalid")
        let locked = try fixture("Locked", "locked")
        let empty = try fixture("Empty", "empty")
        let store = LibraryStore()
        precondition(store.library.isEmpty && store.catalog.isEmpty && store.savedIDs.isEmpty, "Fresh installs must not include demos")
        store.imported = []
        store.savedIDs = []
        store.positions = [:]

        await store.importPDFs([first, broken, locked, empty, second])
        precondition(!store.isImporting && store.importProgress == nil)
        precondition(Set(store.imported.map(\.title)) == ["First", "Second"])
        precondition(store.savedIDs == Set(store.imported.map(\.id)))
        precondition(store.error?.contains("Imported 2 of 5 PDFs") == true)
        for name in ["Broken.pdf", "Locked.pdf", "Empty.pdf"] {
            precondition(store.error?.contains(name) == true)
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: LibraryStore.documents.path)
        precondition(files.count == 4, "Failed imports must leave no copied files or thumbnails")
        let restored = LibraryStore()
        precondition(Set(restored.imported.map(\.id)) == store.savedIDs)

        // Batch state is set before its first suspension; another request cannot interleave.
        let third = try fixture("Third", "valid")
        let task = Task { @MainActor in await store.importPDFs([third]) }
        while !store.isImporting { await Task.yield() }
        await store.importPDFs([first])
        await task.value
        precondition(store.imported.count == 3)
        precondition(store.error == nil)

        let beforeCancellation = try FileManager.default.contentsOfDirectory(atPath: LibraryStore.documents.path).count
        let cancelled = Task { @MainActor in await store.importPDFs([first, second]) }
        cancelled.cancel()
        await cancelled.value
        precondition(!store.isImporting && store.imported.count == 3)
        let afterCancellation = try FileManager.default.contentsOfDirectory(atPath: LibraryStore.documents.path).count
        precondition(afterCancellation == beforeCancellation)

        // Cancel while the second PDF is being parsed: keep the first, discard
        // the current file and its thumbnail, and skip the third.
        var opened = 0
        PDFDocument.onOpen = {
            opened += 1
            if opened == 2 { store.cancelImport() }
        }
        await store.importPDFs([first, second, third])
        PDFDocument.onOpen = nil
        precondition(opened == 2)
        precondition(store.imported.count == 4 && store.imported.first?.title == "First")
        precondition(!store.isImporting && !store.isCancellingImport && store.error == nil)
        let afterUserCancellation = try FileManager.default.contentsOfDirectory(atPath: LibraryStore.documents.path).count
        precondition(afterUserCancellation == beforeCancellation + 2)
        precondition(LibraryStore().imported.count == 4)
        // Cancellation is reset so a later batch can run normally.
        await store.importPDFs([second])
        precondition(store.imported.count == 5 && store.error == nil)
        store.cancelImport()
        precondition(!store.isCancellingImport)
        precondition(PDFImportProgress(completed: 2, total: 5, currentFile: "test").fraction == 0.4)
        print("PASS: batch partial success, named errors, cleanup, persistence, overlap guard, task/user cancellation and restart")
        try SourceChecks.run()
        try await ProfileChecks.run(fixture: first)
        try await SecurityRegressionChecks.run(fixture: first)
    }
}
