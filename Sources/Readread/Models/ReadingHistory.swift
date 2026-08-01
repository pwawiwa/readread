import Foundation
import SwiftUI

@MainActor
class ReadingHistoryStore: ObservableObject {
    @Published var books: [BookItem] = []
    private let saveKey = "ReadreadHistory"
    
    init() {
        load()
    }
    
    func addOrUpdate(url: URL, lastPage: Int = 0, totalPages: Int = 0) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        let path = url.path
        let bookmark = createBookmark(for: url)
        
        if let index = books.firstIndex(where: { $0.filePath == path }) {
            books[index].lastOpenedDate = Date()
            books[index].lastPageIndex = lastPage
            if totalPages > 0 {
                books[index].totalPages = totalPages
            }
            if let bookmark = bookmark {
                books[index].bookmarkData = bookmark
            }
        } else {
            var newBook = BookItem(url: url)
            newBook.lastPageIndex = lastPage
            newBook.totalPages = totalPages
            newBook.bookmarkData = bookmark
            books.append(newBook)
        }
        sortBooks()
        save()
    }
    
    func updateProgress(for bookId: UUID, page: Int, totalPages: Int? = nil, rotation: Int? = nil, zoom: Double? = nil) {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }
        books[index].lastPageIndex = page
        if let totalPages = totalPages {
            books[index].totalPages = totalPages
        }
        if let rotation = rotation {
            books[index].rotation = rotation
        }
        if let zoom = zoom {
            books[index].zoomLevel = zoom
        }
        books[index].lastOpenedDate = Date()
        sortBooks()
        save()
    }
    
    func remove(bookId: UUID) {
        books.removeAll { $0.id == bookId }
        save()
    }
    
    func resolveURL(for book: BookItem) -> URL? {
        if let data = book.bookmarkData, let url = resolveBookmark(data) {
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
        let url = URL(fileURLWithPath: book.filePath)
        _ = url.startAccessingSecurityScopedResource()
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
    
    private func sortBooks() {
        books.sort { $0.lastOpenedDate > $1.lastOpenedDate }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(books)
            UserDefaults.standard.set(data, forKey: saveKey)
        } catch {
            print("Failed to save reading history: \(error)")
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }
        do {
            books = try JSONDecoder().decode([BookItem].self, from: data)
            sortBooks()
        } catch {
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
    
    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            return url
        } catch {
            do {
                let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                return url
            } catch {
                print("Failed to resolve bookmark: \(error)")
                return nil
            }
        }
    }
}
