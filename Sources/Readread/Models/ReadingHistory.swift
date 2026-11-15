import Foundation
import SwiftUI

@MainActor
class ReadingHistoryStore: ObservableObject {
    @Published var books: [BookItem] = []
    @Published var loadError: LibraryError?

    private let userDefaults: UserDefaults
    private let saveKey: String
    private var corruptBackupKey: String { "\(saveKey).corruptBackup" }

    init(userDefaults: UserDefaults = .standard, saveKey: String = "ReadreadHistory") {
        self.userDefaults = userDefaults
        self.saveKey = saveKey
        load()
    }

    var corruptBackupData: Data? {
        userDefaults.data(forKey: corruptBackupKey)
    }

    func dismissLoadError() {
        loadError = nil
    }

    @discardableResult
    func addOrUpdate(url: URL, lastPage: Int? = nil, totalPages: Int? = nil) throws -> BookItem {
        guard url.isFileURL else {
            throw LibraryError.invalidURL(url.absoluteString)
        }
        guard let format = BookItem.FileFormat.from(url: url) else {
            throw LibraryError.unsupportedFormat(
                fileName: url.lastPathComponent,
                fileExtension: url.pathExtension.lowercased()
            )
        }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let canonicalURL = BookItem.canonicalFileURL(url)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw LibraryError.fileNotFound(fileName: url.lastPathComponent, path: canonicalURL.path)
        }
        guard FileManager.default.isReadableFile(atPath: canonicalURL.path) else {
            throw LibraryError.unreadableFile(fileName: url.lastPathComponent)
        }

        let bookmark = createBookmark(for: canonicalURL)

        if let index = books.firstIndex(where: { existingCanonicalPath(for: $0) == canonicalURL.path }) {
            if let validTotal = BookItem.validatedTotalPages(totalPages) {
                books[index].totalPages = validTotal
            }
            if let lastPage {
                books[index].lastPageIndex = BookItem.validatedPageIndex(
                    lastPage,
                    totalPages: books[index].totalPages
                )
            } else {
                books[index].lastPageIndex = BookItem.validatedPageIndex(
                    books[index].lastPageIndex,
                    totalPages: books[index].totalPages
                )
            }
            books[index].filePath = canonicalURL.path
            books[index].fileFormat = format
            let derivedTitle = canonicalURL.deletingPathExtension().lastPathComponent
            if !derivedTitle.isEmpty {
                books[index].title = derivedTitle
            }
            if let bookmark {
                books[index].bookmarkData = bookmark
            }
            books[index] = books[index].validated()
            let updated = books[index]
            sortBooks()
            save()
            return updated
        } else {
            var newBook = try BookItem(validating: canonicalURL)
            if let validTotal = BookItem.validatedTotalPages(totalPages) {
                newBook.totalPages = validTotal
            }
            if let lastPage {
                newBook.lastPageIndex = BookItem.validatedPageIndex(lastPage, totalPages: newBook.totalPages)
            }
            newBook.bookmarkData = bookmark
            newBook = newBook.validated()
            books.append(newBook)
            sortBooks()
            save()
            return newBook
        }
    }

    func updateProgress(for bookId: UUID, page: Int, totalPages: Int? = nil, rotation: Int? = nil, zoom: Double? = nil) {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }
        if let validTotal = BookItem.validatedTotalPages(totalPages) {
            books[index].totalPages = validTotal
        }
        books[index].lastPageIndex = BookItem.validatedPageIndex(page, totalPages: books[index].totalPages)
        if let rotation {
            books[index].rotation = BookItem.validatedRotation(rotation)
        }
        if let zoom {
            books[index].zoomLevel = BookItem.validatedZoom(zoom)
        }
        books[index].lastOpenedDate = Date()
        sortBooks()
        save()
    }

    func remove(bookId: UUID) {
        books.removeAll { $0.id == bookId }
        save()
    }

    /// Resolves the book's URL without starting security-scoped resource access.
    /// Callers that read from the returned URL own paired start/stop security-scoped access.
    func resolveURL(for book: BookItem) -> URL? {
        if let data = book.bookmarkData, let resolution = resolveBookmark(data) {
            if FileManager.default.fileExists(atPath: resolution.url.path) {
                if resolution.isStale {
                    refreshBookmark(for: book.id, url: resolution.url)
                }
                return resolution.url
            }
        }
        let fallbackURL = URL(fileURLWithPath: book.filePath)
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }
        return nil
    }

    func isFileAvailable(for book: BookItem) -> Bool {
        resolveURL(for: book) != nil
    }

    private func existingCanonicalPath(for book: BookItem) -> String {
        BookItem.canonicalFileURL(URL(fileURLWithPath: book.filePath)).path
    }

    private func refreshBookmark(for bookId: UUID, url: URL) {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if let refreshed = createBookmark(for: url) {
            books[index].bookmarkData = refreshed
            books[index].filePath = BookItem.canonicalFileURL(url).path
            save()
        }
    }

    private func sortBooks() {
        books.sort { $0.activityDate > $1.activityDate }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(books)
            userDefaults.set(data, forKey: saveKey)
        } catch {
            print("Failed to save reading history: \(error)")
        }
    }

    private func load() {
        guard let data = userDefaults.data(forKey: saveKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([BookItem].self, from: data)
            books = decoded.map { $0.validated() }
            sortBooks()
            loadError = nil
        } catch {
            userDefaults.set(data, forKey: corruptBackupKey)
            loadError = .corruptHistory(message: error.localizedDescription)
            print("Failed to load reading history: \(error)")
        }
    }

    private func createBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            do {
                return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch {
                print("Failed to create bookmark for \(url): \(error)")
                return nil
            }
        }
    }

    private func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        } catch {
            do {
                isStale = false
                let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                return (url, isStale)
            } catch {
                print("Failed to resolve bookmark: \(error)")
                return nil
            }
        }
    }
}
