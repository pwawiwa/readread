import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var historyStore: ReadingHistoryStore
    let onOpenBook: (BookItem) -> Void
    let onImportFile: () -> Void
    
    @State private var showingSettings = false
    @State private var isTargetedForDrop = false
    
    var sortedBooks: [BookItem] {
        historyStore.books.sorted { $0.lastOpenedDate > $1.lastOpenedDate }
    }
    
    let columns = [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 20)]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.offWhite.ignoresSafeArea()
                
                if historyStore.books.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 64))
                            .foregroundColor(.accentBrown)
                        Text("Import a book to get started")
                            .font(.title2.bold())
                            .foregroundColor(Color.textPrimary)
                        Text("Drag & drop files here or click below")
                            .font(.subheadline)
                            .foregroundColor(Color.textSecondary)
                        Button(action: onImportFile) {
                            Text("Open File...")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.accentBrown)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(sortedBooks) { book in
                                BookCard(book: book, resolveURL: { historyStore.resolveURL(for: book) })
                                    .onTapGesture {
                                        onOpenBook(book)
                                    }
                                    .contextMenu {
                                        Button("Open") { onOpenBook(book) }
                                        Button("Remove from History", role: .destructive) {
                                            historyStore.remove(bookId: book.id)
                                        }
                                    }
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentBrown, lineWidth: isTargetedForDrop ? 4 : 0)
                    .padding(8)
            )
            .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                handleDroppedFiles(providers: providers)
                return true
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                                .foregroundColor(Color.textPrimary)
                        }
                        Button(action: onImportFile) {
                            Image(systemName: "plus")
                                .foregroundColor(Color.textPrimary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
    
    private func handleDroppedFiles(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        historyStore.addOrUpdate(url: url)
                    }
                }
            }
        }
    }
}

struct BookCard: View {
    let book: BookItem
    let resolveURL: () -> URL?
    
    @State private var thumbnailImage: NSImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(Color.paperWhite)
                    .aspectRatio(3/4, contentMode: .fit)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                
                if let thumb = thumbnailImage {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                } else {
                    Image(systemName: book.fileFormat.icon)
                        .font(.system(size: 48))
                        .foregroundColor(.accentBrown.opacity(0.8))
                }
                
                VStack {
                    HStack {
                        Spacer()
                        Text(book.fileFormat.displayName)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentBrown)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .padding(8)
                    }
                    Spacer()
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text("Page \(book.lastPageIndex + 1) of \(max(1, book.totalPages))")
                    .font(.subheadline)
                    .foregroundColor(Color.textSecondary)
                
                Text(formattedLastOpened(book.lastOpenedDate))
                    .font(.caption)
                    .foregroundColor(Color.textSecondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(Color.warmCream)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func formattedLastOpened(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Opened " + formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func loadThumbnail() {
        guard book.fileFormat == .pdf, let url = resolveURL() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let doc = PDFDocument(url: url), let firstPage = doc.page(at: 0) {
                let image = firstPage.thumbnail(of: CGSize(width: 240, height: 320), for: .cropBox)
                DispatchQueue.main.async {
                    self.thumbnailImage = image
                }
            }
        }
    }
}
