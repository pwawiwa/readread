import Foundation
import SwiftUI

struct PageBookmark: Identifiable, Codable, Hashable {
    let id: UUID
    let bookId: UUID
    let pageIndex: Int
    let label: String?
    let dateAdded: Date
}

@MainActor
class BookmarkService: ObservableObject {
    @Published var bookmarks: [PageBookmark] = []
    private let saveKey = "ReadreadBookmarks"
    
    init() {
        load()
    }
    
    func addBookmark(bookId: UUID, pageIndex: Int, label: String? = nil) {
        if !isBookmarked(bookId: bookId, pageIndex: pageIndex) {
            let bookmark = PageBookmark(id: UUID(), bookId: bookId, pageIndex: pageIndex, label: label, dateAdded: Date())
            bookmarks.append(bookmark)
            save()
        }
    }
    
    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }
    
    func bookmarks(for bookId: UUID) -> [PageBookmark] {
        bookmarks.filter { $0.bookId == bookId }.sorted { $0.pageIndex < $1.pageIndex }
    }
    
    func isBookmarked(bookId: UUID, pageIndex: Int) -> Bool {
        bookmarks.contains { $0.bookId == bookId && $0.pageIndex == pageIndex }
    }
    
    func toggleBookmark(bookId: UUID, pageIndex: Int) {
        if let existing = bookmarks.first(where: { $0.bookId == bookId && $0.pageIndex == pageIndex }) {
            removeBookmark(id: existing.id)
        } else {
            addBookmark(bookId: bookId, pageIndex: pageIndex)
        }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            UserDefaults.standard.set(data, forKey: saveKey)
        } catch {
            print("Failed to save bookmarks: \(error)")
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }
        do {
            bookmarks = try JSONDecoder().decode([PageBookmark].self, from: data)
        } catch {
            print("Failed to load bookmarks: \(error)")
        }
    }
}
