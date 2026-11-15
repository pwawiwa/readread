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
    @Published var loadError: LibraryError?

    private let userDefaults: UserDefaults
    private let saveKey: String
    private var corruptBackupKey: String { "\(saveKey).corruptBackup" }

    init(userDefaults: UserDefaults = .standard, saveKey: String = "ReadreadBookmarks") {
        self.userDefaults = userDefaults
        self.saveKey = saveKey
        load()
    }

    var corruptBackupData: Data? {
        userDefaults.data(forKey: corruptBackupKey)
    }

    func addBookmark(bookId: UUID, pageIndex: Int, label: String? = nil) {
        let validPage = max(0, pageIndex)
        guard !isBookmarked(bookId: bookId, pageIndex: validPage) else { return }
        let bookmark = PageBookmark(
            id: UUID(),
            bookId: bookId,
            pageIndex: validPage,
            label: label,
            dateAdded: Date()
        )
        bookmarks.append(bookmark)
        save()
    }

    func removeBookmark(id: UUID) {
        let countBefore = bookmarks.count
        bookmarks.removeAll { $0.id == id }
        if bookmarks.count != countBefore {
            save()
        }
    }

    func removeBookmarks(for bookId: UUID) {
        let countBefore = bookmarks.count
        bookmarks.removeAll { $0.bookId == bookId }
        if bookmarks.count != countBefore {
            save()
        }
    }

    func bookmarks(for bookId: UUID) -> [PageBookmark] {
        bookmarks.filter { $0.bookId == bookId }.sorted { $0.pageIndex < $1.pageIndex }
    }

    func isBookmarked(bookId: UUID, pageIndex: Int) -> Bool {
        let validPage = max(0, pageIndex)
        return bookmarks.contains { $0.bookId == bookId && $0.pageIndex == validPage }
    }

    func toggleBookmark(bookId: UUID, pageIndex: Int) {
        let validPage = max(0, pageIndex)
        if let existing = bookmarks.first(where: { $0.bookId == bookId && $0.pageIndex == validPage }) {
            removeBookmark(id: existing.id)
        } else {
            addBookmark(bookId: bookId, pageIndex: validPage)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            userDefaults.set(data, forKey: saveKey)
        } catch {
            print("Failed to save bookmarks: \(error)")
        }
    }

    private func load() {
        guard let data = userDefaults.data(forKey: saveKey) else { return }
        do {
            bookmarks = try JSONDecoder().decode([PageBookmark].self, from: data)
            loadError = nil
        } catch {
            userDefaults.set(data, forKey: corruptBackupKey)
            loadError = .corruptBookmarks(message: error.localizedDescription)
            print("Failed to load bookmarks: \(error)")
        }
    }
}
