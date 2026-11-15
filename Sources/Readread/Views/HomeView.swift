import SwiftUI
import PDFKit
import UniformTypeIdentifiers

private enum LibraryAlert: Identifiable {
    case importError(String)
    case missingBook(BookItem)

    var id: String {
        switch self {
        case .importError(let message):
            return "import-\(message)"
        case .missingBook(let book):
            return "missing-\(book.id.uuidString)"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var historyStore: ReadingHistoryStore
    @EnvironmentObject var bookmarkService: BookmarkService

    let onOpenBook: (BookItem) -> Void
    let onImportFile: () -> Void

    @State private var showingSettings = false
    @State private var isTargetedForDrop = false
    @State private var activeAlert: LibraryAlert?
    @State private var inlineErrorMessage: String?

    var sortedBooks: [BookItem] {
        historyStore.books.sorted { $0.activityDate > $1.activityDate }
    }

    private let columns = [GridItem(.adaptive(minimum: 185, maximum: 230), spacing: 26)]

    private var collectionCountLabel: String {
        let count = historyStore.books.count
        return count == 1 ? "1 book" : "\(count) books"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.editorialCanvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    if let loadError = historyStore.loadError {
                        HistoryRecoveryBanner(
                            error: loadError,
                            onImport: onImportFile,
                            onDismiss: { historyStore.dismissLoadError() }
                        )
                        .padding(.horizontal, 30)
                        .padding(.top, 16)
                    }

                    if let inlineErrorMessage {
                        ImportErrorBanner(
                            message: inlineErrorMessage,
                            onImport: onImportFile,
                            onDismiss: { self.inlineErrorMessage = nil }
                        )
                        .padding(.horizontal, 30)
                        .padding(.top, 12)
                    }

                    if historyStore.books.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Library")
                                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                                        .foregroundColor(Color.editorialInk)
                                    Spacer()
                                    Text(collectionCountLabel)
                                        .font(.subheadline)
                                        .foregroundColor(Color.editorialSecondaryInk)
                                }

                                LazyVGrid(columns: columns, spacing: 26) {
                                    ForEach(sortedBooks) { book in
                                        ShelfBookItem(
                                            book: book,
                                            isAvailable: historyStore.isFileAvailable(for: book),
                                            resolveURL: { historyStore.resolveURL(for: book) },
                                            onOpen: { handleOpen(book) },
                                            onRemove: { removeBook(book) }
                                        )
                                    }
                                }
                            }
                            .padding(30)
                        }
                    }
                }

                if isTargetedForDrop {
                    dropTargetOverlay
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                handleDroppedFiles(providers: providers)
                return true
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: onImportFile) {
                        Label("Import Books", systemImage: "plus")
                    }
                    .help("Import books (Command-O)")

                    Button(action: { showingSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                    .help("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .importError(let message):
                    return Alert(
                        title: Text("Could Not Import Some Files"),
                        message: Text(message),
                        primaryButton: .default(Text("Import Another File")) {
                            onImportFile()
                        },
                        secondaryButton: .cancel(Text("OK"))
                    )
                case .missingBook(let book):
                    return Alert(
                        title: Text("Book File Not Found"),
                        message: Text("\"\(book.title)\" could not be found at \(book.filePath). Check whether it was moved or deleted, or remove it from your library."),
                        primaryButton: .destructive(Text("Remove from Library")) {
                            removeBook(book)
                        },
                        secondaryButton: .cancel(Text("Cancel"))
                    )
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundColor(Color.editorialAccent)
                .accessibilityHidden(true)

            Text("Your reading room is empty")
                .font(.system(.title, design: .serif).weight(.semibold))
                .foregroundColor(Color.editorialInk)

            Text("Import a PDF, EPUB, TXT, RTF, or HTML book, or drag and drop files anywhere in this window.")
                .font(.subheadline)
                .foregroundColor(Color.editorialSecondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button(action: onImportFile) {
                Text("Import Books")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Color.editorialAccent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropTargetOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.editorialAccent, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                .background(Color.editorialAccent.opacity(0.06).cornerRadius(14))
                .padding(14)

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Color.editorialAccent)
                Text("Drop books to add to your library")
                    .font(.headline)
                    .foregroundColor(Color.editorialInk)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.editorialPaper)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        }
        .allowsHitTesting(false)
    }

    private func handleOpen(_ book: BookItem) {
        if historyStore.isFileAvailable(for: book) {
            onOpenBook(book)
        } else {
            activeAlert = .missingBook(book)
        }
    }

    private func removeBook(_ book: BookItem) {
        historyStore.remove(bookId: book.id)
        bookmarkService.removeBookmarks(for: book.id)
    }

    private func handleDroppedFiles(providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var droppedURLs: [URL] = []

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    lock.lock()
                    droppedURLs.append(url)
                    lock.unlock()
                } else if let url = item as? URL {
                    lock.lock()
                    droppedURLs.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            var failures: [String] = []
            for url in droppedURLs {
                do {
                    try historyStore.addOrUpdate(url: url)
                } catch {
                    let suggestion = (error as? LocalizedError)?.recoverySuggestion ?? ""
                    let detail = suggestion.isEmpty ? error.localizedDescription : "\(error.localizedDescription) \(suggestion)"
                    failures.append(detail)
                }
            }
            if !failures.isEmpty {
                let message = failures.joined(separator: "\n")
                inlineErrorMessage = message
                activeAlert = .importError(message)
            }
        }
    }
}

private struct HistoryRecoveryBanner: View {
    let error: LibraryError
    let onImport: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(Color.editorialAccent)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.localizedDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Color.editorialInk)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(Color.editorialSecondaryInk)
                }
            }

            Spacer()

            Button("Import Books", action: onImport)
                .buttonStyle(.borderedProminent)
                .tint(Color.editorialAccent)

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
                .foregroundColor(Color.editorialSecondaryInk)
        }
        .padding(14)
        .background(Color.editorialPaper)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.editorialRule, lineWidth: 1))
    }
}

private struct ImportErrorBanner: View {
    let message: String
    let onImport: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(Color.editorialAccent)
                .font(.title3)

            Text(message)
                .font(.subheadline)
                .foregroundColor(Color.editorialInk)
                .lineLimit(3)

            Spacer()

            Button("Import Another File", action: onImport)
                .buttonStyle(.bordered)

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
                .foregroundColor(Color.editorialSecondaryInk)
        }
        .padding(14)
        .background(Color.editorialPaper)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.editorialRule, lineWidth: 1))
    }
}

private struct ShelfBookItem: View {
    let book: BookItem
    let isAvailable: Bool
    let resolveURL: () -> URL?
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var thumbnailImage: NSImage?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.editorialPaper)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)

                    if let thumb = thumbnailImage {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(6)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: book.fileFormat.icon)
                                .font(.system(size: 36))
                                .foregroundColor(Color.editorialAccent.opacity(0.85))
                            Text(book.title)
                                .font(.system(.caption, design: .serif))
                                .foregroundColor(Color.editorialSecondaryInk)
                                .lineLimit(3)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                    }

                    VStack {
                        HStack {
                            Spacer()
                            Text(book.fileFormat.displayName)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.editorialPaper.opacity(0.92))
                                .foregroundColor(Color.editorialInk)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.editorialRule, lineWidth: 0.75)
                                )
                                .padding(8)
                        }
                        Spacer()
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.editorialAccent, lineWidth: isFocused ? 2.5 : 0)
                )
            }
            .buttonStyle(.plain)
            .focused($isFocused)
            .accessibilityLabel("\(book.title), \(pageStatusText), \(dateStatusText)")

            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.system(.headline, design: .serif))
                        .foregroundColor(Color.editorialInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(pageStatusText)
                        .font(.subheadline)
                        .foregroundColor(isAvailable ? Color.editorialSecondaryInk : Color.editorialAccent)

                    Text(dateStatusText)
                        .font(.caption)
                        .foregroundColor(Color.editorialSecondaryInk)
                }

                Spacer(minLength: 4)

                Menu {
                    Button("Open", action: onOpen)
                    Divider()
                    Button("Remove from Library", action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundColor(Color.editorialSecondaryInk)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24, height: 24)
                .accessibilityLabel("Actions for \(book.title)")
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open", action: onOpen)
            Divider()
            Button("Remove from Library", action: onRemove)
        }
        .task(id: book.id) {
            loadThumbnail()
        }
    }

    private var pageStatusText: String {
        if !isAvailable {
            return "File missing"
        }
        if let total = book.totalPages, total > 0 {
            let current = min(book.lastPageIndex + 1, total)
            return "Page \(current) of \(total)"
        }
        if book.lastOpenedDate != nil {
            return "Page \(book.lastPageIndex + 1)"
        }
        return "Not opened yet"
    }

    private var dateStatusText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        if let opened = book.lastOpenedDate {
            return "Opened " + formatter.localizedString(for: opened, relativeTo: Date())
        }
        return "Added " + formatter.localizedString(for: book.importedDate, relativeTo: Date())
    }

    private func loadThumbnail() {
        guard book.fileFormat == .pdf, let url = resolveURL() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            if let doc = PDFDocument(url: url), let firstPage = doc.page(at: 0) {
                let image = firstPage.thumbnail(of: CGSize(width: 240, height: 320), for: .cropBox)
                DispatchQueue.main.async {
                    self.thumbnailImage = image
                }
            }
        }
    }
}
