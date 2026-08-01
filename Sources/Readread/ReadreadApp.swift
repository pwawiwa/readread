import SwiftUI
import UniformTypeIdentifiers

class DictionaryServiceWrapper: ObservableObject {
    let service = DictionaryService()
}

@main
struct ReadreadApp: App {
    @StateObject private var historyStore = ReadingHistoryStore()
    @StateObject private var bookmarkService = BookmarkService()
    @StateObject private var dictionaryService = DictionaryServiceWrapper()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(historyStore)
                .environmentObject(bookmarkService)
                .environmentObject(dictionaryService)
                .frame(minWidth: 850, minHeight: 650)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(TitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open File...") {
                    NotificationCenter.default.post(name: .init("OpenFileMenuTrigger"), object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("View") {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .init("ZoomInTrigger"), object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .init("ZoomOutTrigger"), object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
                Button("Rotate Page") {
                    NotificationCenter.default.post(name: .init("RotateTrigger"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Toggle Table of Contents") {
                    NotificationCenter.default.post(name: .init("ToggleTOCTrigger"), object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            CommandMenu("Find") {
                Button("Find in Document") {
                    NotificationCenter.default.post(name: .init("FindTrigger"), object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("Bookmarks") {
                Button("Toggle Bookmark") {
                    NotificationCenter.default.post(name: .init("ToggleBookmarkTrigger"), object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var historyStore: ReadingHistoryStore
    @State private var selectedBookId: UUID?
    
    var selectedBook: BookItem? {
        historyStore.books.first { $0.id == selectedBookId }
    }
    
    var body: some View {
        Group {
            if let book = selectedBook {
                ReaderView(book: book) {
                    selectedBookId = nil
                }
            } else {
                HomeView(
                    onOpenBook: { book in
                        selectedBookId = book.id
                    },
                    onImportFile: {
                        openFilePanel()
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenFileMenuTrigger"))) { _ in
            openFilePanel()
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = BookItem.supportedUTTypes
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                historyStore.addOrUpdate(url: url)
            }
            if let firstUrl = panel.urls.first,
               let newBook = historyStore.books.first(where: { historyStore.resolveURL(for: $0) == firstUrl }) {
                selectedBookId = newBook.id
            }
        }
    }
}
