import SwiftUI
import AppKit
import UniformTypeIdentifiers

class DictionaryServiceWrapper: ObservableObject {
    let service = DictionaryService()
}

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedBookId: UUID?
    @Published var pendingOpenURLs: [URL] = []

    func enqueueOpenURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pendingOpenURLs.append(contentsOf: urls)
    }
}

final class ReadreadAppDelegate: NSObject, NSApplicationDelegate {
    private weak var navigationState: AppNavigationState?
    private var bufferedURLs: [URL] = []

    @MainActor
    func attach(_ navigationState: AppNavigationState) {
        self.navigationState = navigationState
        if !bufferedURLs.isEmpty {
            let urls = bufferedURLs
            bufferedURLs.removeAll()
            navigationState.enqueueOpenURLs(urls)
        }
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let navigationState = self.navigationState {
                navigationState.enqueueOpenURLs(urls)
            } else {
                self.bufferedURLs.append(contentsOf: urls)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct ReadreadApp: App {
    @NSApplicationDelegateAdaptor(ReadreadAppDelegate.self) private var appDelegate
    @StateObject private var historyStore = ReadingHistoryStore()
    @StateObject private var bookmarkService = BookmarkService()
    @StateObject private var dictionaryService = DictionaryServiceWrapper()
    @StateObject private var navigationState = AppNavigationState()

    private var hasActiveBook: Bool {
        navigationState.selectedBookId != nil
    }

    var body: some Scene {
        Window("Readread", id: "main") {
            ContentView()
                .environmentObject(historyStore)
                .environmentObject(bookmarkService)
                .environmentObject(dictionaryService)
                .environmentObject(navigationState)
                .frame(minWidth: 850, minHeight: 650)
                .handlesExternalEvents(preferring: Set(["*"]), allowing: Set(["*"]))
                .onAppear {
                    appDelegate.attach(navigationState)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onOpenURL { url in
                    navigationState.enqueueOpenURLs([url])
                }
        }
        .windowStyle(TitleBarWindowStyle())
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Books...") {
                    NotificationCenter.default.post(name: .init("OpenFileMenuTrigger"), object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("View") {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .init("ZoomInTrigger"), object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!hasActiveBook)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .init("ZoomOutTrigger"), object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!hasActiveBook)

                Button("Fit to Page") {
                    NotificationCenter.default.post(name: .init("FitToPageTrigger"), object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!hasActiveBook)

                Button("Fit to Width") {
                    NotificationCenter.default.post(name: .init("FitToWidthTrigger"), object: nil)
                }
                .keyboardShortcut("9", modifiers: .command)
                .disabled(!hasActiveBook)

                Divider()

                Button("Rotate Page") {
                    NotificationCenter.default.post(name: .init("RotateTrigger"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!hasActiveBook)

                Button("Toggle Table of Contents") {
                    NotificationCenter.default.post(name: .init("ToggleTOCTrigger"), object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!hasActiveBook)
            }
            CommandMenu("Find") {
                Button("Find in Document") {
                    NotificationCenter.default.post(name: .init("FindTrigger"), object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!hasActiveBook)
            }
            CommandMenu("Bookmarks") {
                Button("Toggle Bookmark") {
                    NotificationCenter.default.post(name: .init("ToggleBookmarkTrigger"), object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!hasActiveBook)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var historyStore: ReadingHistoryStore
    @EnvironmentObject var navigationState: AppNavigationState

    @State private var importAlertMessage: String?

    var selectedBook: BookItem? {
        historyStore.books.first { $0.id == navigationState.selectedBookId }
    }

    var body: some View {
        Group {
            if let book = selectedBook {
                ReaderView(book: book) {
                    navigationState.selectedBookId = nil
                }
                .id(book.id)
            } else {
                HomeView(
                    onOpenBook: { book in
                        navigationState.selectedBookId = book.id
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
        .onChange(of: navigationState.pendingOpenURLs) { urls in
            guard !urls.isEmpty else { return }
            navigationState.pendingOpenURLs.removeAll()
            importAndOpen(urls: urls)
        }
        .onAppear {
            if !navigationState.pendingOpenURLs.isEmpty {
                let urls = navigationState.pendingOpenURLs
                navigationState.pendingOpenURLs.removeAll()
                importAndOpen(urls: urls)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        .alert(
            "Could Not Open File",
            isPresented: Binding(
                get: { importAlertMessage != nil },
                set: { if !$0 { importAlertMessage = nil } }
            )
        ) {
            Button("Import Another File") {
                importAlertMessage = nil
                openFilePanel()
            }
            Button("OK", role: .cancel) {
                importAlertMessage = nil
            }
        } message: {
            Text(importAlertMessage ?? "")
        }
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = BookItem.supportedUTTypes

        if panel.runModal() == .OK {
            let urls = panel.urls
            DispatchQueue.main.async {
                importAndOpen(urls: urls)
            }
        }
    }

    private func importAndOpen(urls: [URL]) {
        var firstImported: BookItem?
        var failures: [String] = []

        for url in urls {
            do {
                let book = try historyStore.addOrUpdate(url: url)
                if firstImported == nil {
                    firstImported = book
                }
            } catch {
                let suggestion = (error as? LocalizedError)?.recoverySuggestion ?? ""
                let detail = suggestion.isEmpty ? error.localizedDescription : "\(error.localizedDescription) \(suggestion)"
                failures.append(detail)
            }
        }

        if let firstImported {
            navigationState.selectedBookId = firstImported.id
        }
        if !failures.isEmpty {
            importAlertMessage = failures.joined(separator: "\n")
        }
    }
}
