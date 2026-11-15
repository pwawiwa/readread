import Testing
import AppKit
@testable import Readread

@MainActor
struct LibraryPersistenceTests {

    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "com.readread.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadreadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createTempFile(in dir: URL, name: String, contents: Data = Data("Sample content".utf8)) throws -> URL {
        let fileURL = dir.appendingPathComponent(name)
        try contents.write(to: fileURL)
        return fileURL
    }

    @Test func freshStorageStartsEmptyWithoutErrors() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let history = ReadingHistoryStore(userDefaults: defaults)
        let bookmarks = BookmarkService(userDefaults: defaults)

        #expect(history.books.isEmpty)
        #expect(history.loadError == nil)
        #expect(bookmarks.bookmarks.isEmpty)
        #expect(bookmarks.loadError == nil)
    }

    @Test func decodesLegacyRecordsWithMissingFieldsAndValidatesBounds() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyDate = Date(timeIntervalSince1970: 1_700_000_000)
        let legacyID = UUID()
        let legacyJSON: [[String: Any]] = [
            [
                "id": legacyID.uuidString,
                "title": "Legacy Book",
                "filePath": "/tmp/legacy.pdf",
                "lastPageIndex": -5,
                "totalPages": 0,
                "lastOpenedDate": legacyDate.timeIntervalSinceReferenceDate,
                "fileFormat": "pdf",
                "rotation": -90,
                "zoomLevel": -2.0
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyJSON)
        defaults.set(data, forKey: "ReadreadHistory")

        let store = ReadingHistoryStore(userDefaults: defaults)
        #expect(store.loadError == nil)
        #expect(store.books.count == 1)

        let book = try #require(store.books.first)
        #expect(book.id == legacyID)
        #expect(book.title == "Legacy Book")
        #expect(book.totalPages == nil)
        #expect(book.lastPageIndex == 0)
        #expect(book.rotation == 270)
        #expect(book.zoomLevel == 1.0)
        #expect(abs(book.importedDate.timeIntervalSince(legacyDate)) < 1.0)
    }

    @Test func corruptHistoryAndBookmarkBytesArePreserved() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let corruptBytes = Data("{not valid json".utf8)
        defaults.set(corruptBytes, forKey: "ReadreadHistory")
        defaults.set(corruptBytes, forKey: "ReadreadBookmarks")

        let history = ReadingHistoryStore(userDefaults: defaults)
        let bookmarks = BookmarkService(userDefaults: defaults)

        #expect(history.books.isEmpty)
        #expect(history.loadError != nil)
        #expect(history.corruptBackupData == corruptBytes)
        #expect(defaults.data(forKey: "ReadreadHistory") == corruptBytes)

        #expect(bookmarks.bookmarks.isEmpty)
        #expect(bookmarks.loadError != nil)
        #expect(bookmarks.corruptBackupData == corruptBytes)
        #expect(defaults.data(forKey: "ReadreadBookmarks") == corruptBytes)
    }

    @Test func persistenceRoundTripAndShortenedDocumentClamping() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        let dir = try makeTempDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: dir)
        }

        let pdfURL = try createTempFile(in: dir, name: "Novel.pdf")
        let store1 = ReadingHistoryStore(userDefaults: defaults)
        let imported = try store1.addOrUpdate(url: pdfURL)

        #expect(imported.lastOpenedDate == nil)
        #expect(imported.totalPages == nil)
        #expect(imported.lastPageIndex == 0)

        store1.updateProgress(for: imported.id, page: 8, totalPages: 12, rotation: 90, zoom: 1.5)

        let store2 = ReadingHistoryStore(userDefaults: defaults)
        let reloaded = try #require(store2.books.first)
        #expect(reloaded.id == imported.id)
        #expect(reloaded.lastPageIndex == 8)
        #expect(reloaded.totalPages == 12)
        #expect(reloaded.rotation == 90)
        #expect(reloaded.zoomLevel == 1.5)
        #expect(reloaded.lastOpenedDate != nil)

        // Simulate reopening a shortened PDF with only 4 pages
        store2.updateProgress(for: reloaded.id, page: reloaded.lastPageIndex, totalPages: 4)
        let clamped = try #require(store2.books.first)
        #expect(clamped.totalPages == 4)
        #expect(clamped.lastPageIndex == 3)
    }

    @Test func reimportDeduplicatesCanonicalURLsAndPreservesProgress() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        let dir = try makeTempDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: dir)
        }

        let realURL = try createTempFile(in: dir, name: "Manual.pdf")
        let symlinkURL = dir.appendingPathComponent("ManualLink.pdf")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: realURL)

        let store = ReadingHistoryStore(userDefaults: defaults)
        let first = try store.addOrUpdate(url: realURL)
        store.updateProgress(for: first.id, page: 4, totalPages: 10, rotation: 180, zoom: 1.25)

        // Re-import via symlink and unstandardized path
        let unstandardized = dir.appendingPathComponent(".").appendingPathComponent("ManualLink.pdf")
        let second = try store.addOrUpdate(url: unstandardized)

        #expect(store.books.count == 1)
        #expect(second.id == first.id)
        #expect(second.lastPageIndex == 4)
        #expect(second.totalPages == 10)
        #expect(second.rotation == 180)
        #expect(second.zoomLevel == 1.25)
        #expect(second.lastOpenedDate != nil)
    }

    @Test func importValidatesFormatsAndMissingFiles() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        let dir = try makeTempDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: dir)
        }

        let store = ReadingHistoryStore(userDefaults: defaults)

        let txtURL = try createTempFile(in: dir, name: "Notes.txt")
        let htmlURL = try createTempFile(in: dir, name: "Guide.htm")
        let badExtURL = try createTempFile(in: dir, name: "Image.png")
        let missingURL = dir.appendingPathComponent("Missing.pdf")

        let txtBook = try store.addOrUpdate(url: txtURL)
        let htmlBook = try store.addOrUpdate(url: htmlURL)
        #expect(txtBook.fileFormat == .txt)
        #expect(htmlBook.fileFormat == .html)
        #expect(store.books.count == 2)

        #expect(throws: LibraryError.self) {
            try store.addOrUpdate(url: badExtURL)
        }
        #expect(throws: LibraryError.self) {
            try store.addOrUpdate(url: missingURL)
        }
        #expect(throws: LibraryError.self) {
            try store.addOrUpdate(url: URL(string: "https://example.com/book.pdf")!)
        }
        #expect(store.books.count == 2)
    }

    @Test func resolveURLHandlesExistingAndDeletedFiles() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        let dir = try makeTempDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: dir)
        }

        let pdfURL = try createTempFile(in: dir, name: "Disappearing.pdf")
        let store = ReadingHistoryStore(userDefaults: defaults)
        let book = try store.addOrUpdate(url: pdfURL)

        let resolved = store.resolveURL(for: book)
        #expect(resolved != nil)
        #expect(store.isFileAvailable(for: book) == true)

        try FileManager.default.removeItem(at: pdfURL)
        #expect(store.resolveURL(for: book) == nil)
        #expect(store.isFileAvailable(for: book) == false)
    }

    @Test func bookmarksSupportIdempotentAddToggleRoundTripAndBookRemoval() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bookA = UUID()
        let bookB = UUID()

        let service1 = BookmarkService(userDefaults: defaults)
        service1.addBookmark(bookId: bookA, pageIndex: 2)
        service1.addBookmark(bookId: bookA, pageIndex: 2)
        service1.addBookmark(bookId: bookA, pageIndex: 5)
        service1.addBookmark(bookId: bookB, pageIndex: 1)

        #expect(service1.bookmarks(for: bookA).map(\.pageIndex) == [2, 5])
        #expect(service1.isBookmarked(bookId: bookA, pageIndex: 2) == true)

        service1.toggleBookmark(bookId: bookA, pageIndex: 2)
        #expect(service1.isBookmarked(bookId: bookA, pageIndex: 2) == false)
        #expect(service1.bookmarks(for: bookA).map(\.pageIndex) == [5])

        service1.toggleBookmark(bookId: bookA, pageIndex: 2)
        #expect(service1.bookmarks(for: bookA).map(\.pageIndex) == [2, 5])

        let service2 = BookmarkService(userDefaults: defaults)
        #expect(service2.bookmarks(for: bookA).map(\.pageIndex) == [2, 5])
        #expect(service2.bookmarks(for: bookB).map(\.pageIndex) == [1])

        service2.removeBookmarks(for: bookA)
        #expect(service2.bookmarks(for: bookA).isEmpty)
        #expect(service2.bookmarks(for: bookB).map(\.pageIndex) == [1])
    }
}
