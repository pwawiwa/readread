import PDFKit
import SwiftUI

struct ReaderView: View {
    let book: BookItem
    let onBack: () -> Void

    @EnvironmentObject var historyStore: ReadingHistoryStore
    @EnvironmentObject var bookmarkService: BookmarkService

    @AppStorage("defaultZoomLevel") private var defaultZoomLevel: Double = 100.0
    @AppStorage("showTranslationOnSelection") private var showTranslationOnSelection: Bool = true

    @StateObject private var controller: ReaderController
    @State private var showGoToPage: Bool = false
    @State private var goToPageText: String = ""
    @State private var goToPageError: String? = nil
    @FocusState private var isSearchFieldFocused: Bool

    init(book: BookItem, onBack: @escaping () -> Void) {
        self.book = book
        self.onBack = onBack
        let storedDefaultZoom = UserDefaults.standard.double(forKey: "defaultZoomLevel")
        let effectiveDefault = storedDefaultZoom > 0 ? storedDefaultZoom : 100.0
        _controller = StateObject(wrappedValue: ReaderController(book: book, defaultZoomLevel: effectiveDefault))
    }

    var body: some View {
        HStack(spacing: 0) {
            if controller.showTOC, let doc = controller.document {
                TableOfContentsView(
                    document: doc,
                    bookId: book.id,
                    currentPageIndex: controller.currentPageIndex
                ) { pageIdx in
                    controller.perform(.goToPage(pageIdx))
                    controller.focusPDFView()
                }
                .frame(width: 260)

                Divider()
            }

            VStack(spacing: 0) {
                if controller.showSearch {
                    searchBar
                }

                readerContentArea

                if controller.hasActiveDocument {
                    bottomNavigationBar
                }
            }
        }
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Library")
                    }
                    .foregroundColor(Color.textPrimary)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { controller.perform(.toggleTOC) }) {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(controller.showTOC ? .accentBrown : Color.textPrimary)
                }
                .disabled(!controller.hasActiveDocument)
                .help("Toggle Contents Sidebar (⌘T)")

                pageIndicatorButton

                Divider()

                Button(action: { controller.perform(.zoomOut) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(!controller.hasActiveDocument)
                .help("Zoom Out (⌘-)")

                zoomMenu

                Button(action: { controller.perform(.zoomIn) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(!controller.hasActiveDocument)
                .help("Zoom In (⌘+)")

                Divider()

                Button(action: { controller.perform(.rotateClockwise) }) {
                    Image(systemName: "rotate.right")
                }
                .disabled(!controller.hasActiveDocument)
                .help("Rotate Clockwise (⌘R)")

                Button(action: { controller.perform(.toggleBookmark) }) {
                    Image(
                        systemName: bookmarkService.isBookmarked(bookId: book.id, pageIndex: controller.currentPageIndex)
                            ? "star.fill"
                            : "star"
                    )
                    .foregroundColor(
                        bookmarkService.isBookmarked(bookId: book.id, pageIndex: controller.currentPageIndex)
                            ? .accentBrown
                            : Color.textPrimary
                    )
                }
                .disabled(!controller.hasActiveDocument)
                .help("Toggle Bookmark (⌘B)")

                Button(action: {
                    if controller.showSearch {
                        controller.perform(.closeFind)
                    } else {
                        controller.perform(.openFind)
                        isSearchFieldFocused = true
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(controller.showSearch ? .accentBrown : Color.textPrimary)
                }
                .disabled(!controller.hasActiveDocument)
                .help("Find in Document (⌘F)")
            }
        }
        .task(id: book.id) {
            controller.onToggleBookmark = { [weak controller, weak bookmarkService] in
                guard let controller else { return }
                bookmarkService?.toggleBookmark(bookId: book.id, pageIndex: controller.currentPageIndex)
            }
            controller.load(using: historyStore)
        }
        .onDisappear {
            controller.onToggleBookmark = nil
            controller.pdfView = nil
        }
        .onChange(of: controller.currentPageIndex) { newPage in
            guard controller.hasActiveDocument else { return }
            historyStore.updateProgress(
                for: book.id,
                page: newPage,
                totalPages: controller.pageCount,
                rotation: controller.rotationOffset,
                zoom: Double(controller.effectiveScaleFactor)
            )
        }
        .onChange(of: controller.rotationOffset) { newRot in
            guard controller.hasActiveDocument else { return }
            historyStore.updateProgress(
                for: book.id,
                page: controller.currentPageIndex,
                totalPages: controller.pageCount,
                rotation: newRot,
                zoom: Double(controller.effectiveScaleFactor)
            )
        }
        .onChange(of: controller.effectiveScaleFactor) { newZoom in
            guard controller.hasActiveDocument else { return }
            historyStore.updateProgress(
                for: book.id,
                page: controller.currentPageIndex,
                totalPages: controller.pageCount,
                rotation: controller.rotationOffset,
                zoom: Double(newZoom)
            )
        }
        .onChange(of: controller.showTOC) { _ in
            DispatchQueue.main.async {
                controller.recalculateFitScaleIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ZoomInTrigger"))) { _ in
            controller.perform(.zoomIn)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ZoomOutTrigger"))) { _ in
            controller.perform(.zoomOut)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("RotateTrigger"))) { _ in
            controller.perform(.rotateClockwise)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ToggleTOCTrigger"))) { _ in
            controller.perform(.toggleTOC)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("FindTrigger"))) { _ in
            controller.perform(.openFind)
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ToggleBookmarkTrigger"))) { _ in
            controller.perform(.toggleBookmark)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("FitToPageTrigger"))) { _ in
            controller.perform(.fitToPage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("FitToWidthTrigger"))) { _ in
            controller.perform(.fitToWidth)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var readerContentArea: some View {
        switch controller.loadState {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Opening \"\(book.title)\"...")
                    .font(.headline)
                    .foregroundColor(Color.textPrimary)
                Text("Preparing pages and layout")
                    .font(.subheadline)
                    .foregroundColor(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.offWhite)

        case .failed(let error):
            VStack(spacing: 14) {
                Image(systemName: iconName(for: error))
                    .font(.system(size: 38))
                    .foregroundColor(.accentBrown)

                Text(error.title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Color.textPrimary)

                if let description = error.errorDescription {
                    Text(description)
                        .font(.body)
                        .foregroundColor(Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }

                if let recovery = error.recoverySuggestion {
                    Text(recovery)
                        .font(.subheadline)
                        .foregroundColor(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }

                HStack(spacing: 12) {
                    Button("Back to Library") {
                        onBack()
                    }
                    .buttonStyle(.bordered)

                    Button("Try Again") {
                        controller.load(using: historyStore)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentBrown)
                }
                .padding(.top, 4)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.offWhite)

        case .loaded:
            if let doc = controller.document {
                ZStack {
                    PDFReaderView(
                        document: doc,
                        controller: controller,
                        onSelectionChanged: { text, rect in
                            controller.updateSelection(
                                text: text,
                                rect: rect,
                                autoShowTranslation: showTranslationOnSelection
                            )
                        },
                        onClearSelection: {
                            controller.clearSelection()
                        }
                    )
                    .background(Color.offWhite)

                    if controller.showTranslation && !controller.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        TranslationPopover(
                            selectedText: controller.selectedText,
                            selectionRect: controller.selectionRect,
                            isPresented: $controller.showTranslation
                        )
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.textSecondary)

            TextField(
                "Find in document...",
                text: Binding(
                    get: { controller.searchQuery },
                    set: { controller.updateSearch(query: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFieldFocused)
            .onSubmit {
                controller.perform(.findNext)
            }

            if !controller.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if controller.searchMatches.isEmpty {
                    Text("No matches")
                        .font(.caption)
                        .foregroundColor(Color.textSecondary)
                } else {
                    Text("\((controller.currentSearchMatchIndex ?? 0) + 1) of \(controller.searchMatches.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(Color.textSecondary)
                }
            }

            Button(action: { controller.perform(.findPrevious) }) {
                Image(systemName: "chevron.up")
            }
            .disabled(controller.searchMatches.isEmpty)
            .help("Previous Match")

            Button(action: { controller.perform(.findNext) }) {
                Image(systemName: "chevron.down")
            }
            .disabled(controller.searchMatches.isEmpty)
            .help("Next Match")

            Button("Done") {
                controller.perform(.closeFind)
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.warmCream)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Color.primary.opacity(0.1)),
            alignment: .bottom
        )
    }

    private var bottomNavigationBar: some View {
        HStack(spacing: 12) {
            Button(action: { controller.perform(.previousPage) }) {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            .disabled(controller.currentPageIndex <= 0)
            .help("Previous Page")

            if controller.pageCount > 1 {
                Slider(
                    value: Binding(
                        get: { Double(controller.currentPageIndex) },
                        set: { controller.perform(.goToPage(Int($0))) }
                    ),
                    in: 0...Double(controller.pageCount - 1),
                    step: 1
                )
                .tint(.accentBrown)
            } else {
                Spacer()
            }

            Button(action: { controller.perform(.nextPage) }) {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .disabled(controller.currentPageIndex >= max(0, controller.pageCount - 1))
            .help("Next Page")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.warmCream)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Color.primary.opacity(0.1)),
            alignment: .top
        )
    }

    private var pageIndicatorButton: some View {
        Button(action: {
            goToPageText = "\(controller.currentPageIndex + 1)"
            goToPageError = nil
            showGoToPage = true
        }) {
            Text(controller.hasActiveDocument ? "Page \(controller.currentPageIndex + 1) of \(controller.pageCount)" : "No Document")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundColor(Color.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(!controller.hasActiveDocument)
        .popover(isPresented: $showGoToPage) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Go to Page")
                    .font(.headline)
                HStack {
                    TextField("Page", text: $goToPageText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: goToPageText) { _ in
                            goToPageError = nil
                        }
                        .onSubmit {
                            submitGoToPage()
                        }
                    Text("of \(controller.pageCount)")
                        .foregroundColor(Color.textSecondary)
                }

                if let error = goToPageError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel") { showGoToPage = false }
                    Button("Go") { submitGoToPage() }
                        .keyboardShortcut(.return)
                        .buttonStyle(.borderedProminent)
                        .tint(.accentBrown)
                }
            }
            .padding(16)
            .frame(width: 240)
        }
    }

    private var zoomMenu: some View {
        Menu {
            Button(action: { controller.perform(.fitToPage) }) {
                if controller.zoomMode == .fitPage {
                    Label("Fit Page to Window", systemImage: "checkmark")
                } else {
                    Text("Fit Page to Window")
                }
            }
            Button(action: { controller.perform(.fitToWidth) }) {
                if controller.zoomMode == .fitWidth {
                    Label("Fit Page to Width", systemImage: "checkmark")
                } else {
                    Text("Fit Page to Width")
                }
            }
            Divider()
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0], id: \.self) { preset in
                Button("\(Int(preset * 100))%\(preset == 1.0 ? " (Actual Size)" : "")") {
                    controller.perform(.zoomPreset(preset))
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(zoomLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(Color.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(Color.textPrimary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.08))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(!controller.hasActiveDocument)
        .help("Zoom Options")
    }

    private var zoomLabel: String {
        let percent = Int((controller.effectiveScaleFactor * 100).rounded())
        switch controller.zoomMode {
        case .fitPage:
            return "Fit (\(percent)%)"
        case .fitWidth:
            return "Width (\(percent)%)"
        case .manual:
            return "\(percent)%"
        }
    }

    private func submitGoToPage() {
        let trimmed = goToPageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let page = Int(trimmed), page >= 1, page <= controller.pageCount else {
            goToPageError = "Enter a page number from 1 to \(max(1, controller.pageCount))."
            return
        }
        controller.perform(.goToPage(page - 1))
        showGoToPage = false
        controller.focusPDFView()
    }

    private func iconName(for error: DocumentLoadError) -> String {
        switch error {
        case .fileNotFound:
            return "doc.questionmark"
        case .passwordProtected:
            return "lock.doc"
        case .unreadable:
            return "hand.raised"
        case .corruptDocument, .unsupportedFormat:
            return "exclamationmark.triangle"
        }
    }
}
