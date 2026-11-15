import AppKit
import Foundation
import PDFKit
import SwiftUI

enum ReaderLoadState: Equatable {
    case loading
    case loaded(pageCount: Int)
    case failed(DocumentLoadError)
}

enum ZoomMode: Equatable {
    case manual(CGFloat)
    case fitPage
    case fitWidth

    var scaleValue: CGFloat? {
        if case .manual(let scale) = self {
            return scale
        }
        return nil
    }
}

enum ReaderCommand: Equatable {
    case zoomIn
    case zoomOut
    case zoomPreset(CGFloat)
    case fitToPage
    case fitToWidth
    case rotateClockwise
    case toggleTOC
    case openFind
    case closeFind
    case findNext
    case findPrevious
    case previousPage
    case nextPage
    case goToPage(Int)
    case toggleBookmark
}

@MainActor
final class ReaderController: ObservableObject {
    let book: BookItem
    let defaultZoomLevel: Double

    @Published private(set) var loadState: ReaderLoadState = .loading
    @Published private(set) var document: PDFDocument?
    @Published private(set) var intrinsicRotations: [Int] = []

    @Published var currentPageIndex: Int = 0
    @Published var rotationOffset: Int = 0
    @Published var zoomMode: ZoomMode = .manual(1.0)
    @Published var effectiveScaleFactor: CGFloat = 1.0

    @Published var showTOC: Bool = false
    @Published var showSearch: Bool = false
    @Published var searchQuery: String = ""
    @Published private(set) var searchMatches: [PDFSelection] = []
    @Published private(set) var currentSearchMatchIndex: Int? = nil

    @Published var selectedText: String = ""
    @Published var selectionRect: CGRect = .zero
    @Published var showTranslation: Bool = false

    weak var pdfView: PagedPDFView?
    var onToggleBookmark: (() -> Void)?

    var hasActiveDocument: Bool {
        if case .loaded = loadState, document != nil {
            return true
        }
        return false
    }

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    nonisolated static func normalizedRotation(_ degrees: Int) -> Int {
        ((degrees % 360) + 360) % 360
    }

    nonisolated static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(5.0, max(0.2, scale))
    }

    init(book: BookItem, defaultZoomLevel: Double = 100.0) {
        self.book = book
        self.defaultZoomLevel = defaultZoomLevel
        let initialScale = book.zoomLevel > 0 ? CGFloat(book.zoomLevel) : CGFloat(defaultZoomLevel / 100.0)
        let clamped = Self.clampedScale(initialScale)
        self.zoomMode = .manual(clamped)
        self.effectiveScaleFactor = clamped
        self.rotationOffset = Self.normalizedRotation(book.rotation)
    }

    func load(using historyStore: ReadingHistoryStore) {
        loadState = .loading
        document = nil
        intrinsicRotations = []
        clearSearch()
        clearSelection()

        guard let url = historyStore.resolveURL(for: book) else {
            loadState = .failed(.fileNotFound(URL(fileURLWithPath: book.filePath)))
            return
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let loadedDoc = try DocumentLoader.load(url: url, format: book.fileFormat)
            installLoadedDocument(loadedDoc, historyStore: historyStore)
        } catch let loadError as DocumentLoadError {
            loadState = .failed(loadError)
        } catch {
            loadState = .failed(.unreadable(url, error.localizedDescription))
        }
    }

    func installLoadedDocument(_ loadedDoc: PDFDocument, historyStore: ReadingHistoryStore? = nil) {
        document = loadedDoc
        intrinsicRotations = (0..<loadedDoc.pageCount).map { loadedDoc.page(at: $0)?.rotation ?? 0 }

        let maxPage = max(0, loadedDoc.pageCount - 1)
        let clampedPage = min(max(0, book.lastPageIndex), maxPage)
        currentPageIndex = clampedPage

        applyRotationOffset(preservePage: false)
        loadState = .loaded(pageCount: loadedDoc.pageCount)

        historyStore?.updateProgress(
            for: book.id,
            page: clampedPage,
            totalPages: loadedDoc.pageCount,
            rotation: rotationOffset,
            zoom: Double(effectiveScaleFactor)
        )
    }

    func perform(_ command: ReaderCommand) {
        switch command {
        case .toggleTOC:
            withAnimation(.easeInOut(duration: 0.2)) {
                showTOC.toggle()
            }
            return
        case .closeFind:
            showSearch = false
            clearSearch()
            focusPDFView()
            return
        default:
            break
        }

        guard hasActiveDocument else { return }

        switch command {
        case .zoomIn:
            let next = Self.clampedScale(effectiveScaleFactor + 0.1)
            zoomMode = .manual(next)
            effectiveScaleFactor = next
        case .zoomOut:
            let next = Self.clampedScale(effectiveScaleFactor - 0.1)
            zoomMode = .manual(next)
            effectiveScaleFactor = next
        case .zoomPreset(let scale):
            let clamped = Self.clampedScale(scale)
            zoomMode = .manual(clamped)
            effectiveScaleFactor = clamped
        case .fitToPage:
            zoomMode = .fitPage
            recalculateFitScaleIfNeeded()
        case .fitToWidth:
            zoomMode = .fitWidth
            recalculateFitScaleIfNeeded()
        case .rotateClockwise:
            rotationOffset = Self.normalizedRotation(rotationOffset + 90)
            applyRotationOffset(preservePage: true)
            recalculateFitScaleIfNeeded()
        case .openFind:
            showSearch = true
        case .findNext:
            stepSearchMatch(forward: true)
        case .findPrevious:
            stepSearchMatch(forward: false)
        case .previousPage:
            if currentPageIndex > 0 {
                currentPageIndex -= 1
                clearSelection()
            }
        case .nextPage:
            if currentPageIndex < pageCount - 1 {
                currentPageIndex += 1
                clearSelection()
            }
        case .goToPage(let pageIndex):
            let maxPage = max(0, pageCount - 1)
            let clamped = min(max(0, pageIndex), maxPage)
            if clamped != currentPageIndex {
                currentPageIndex = clamped
                clearSelection()
            }
        case .toggleBookmark:
            onToggleBookmark?()
        case .toggleTOC, .closeFind:
            break
        }
    }

    func applyRotationOffset(preservePage: Bool) {
        guard let doc = document else { return }
        let savedPageIndex = currentPageIndex

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let intrinsic = i < intrinsicRotations.count ? intrinsicRotations[i] : 0
            let target = Self.normalizedRotation(intrinsic + rotationOffset)
            if page.rotation != target {
                page.rotation = target
            }
        }

        if let pdfView {
            pdfView.layoutDocumentView()
            if preservePage,
               let targetPage = doc.page(at: savedPageIndex),
               pdfView.currentPage != targetPage {
                pdfView.go(to: targetPage)
            }
        }
        clearSelection()
    }

    func recalculateFitScaleIfNeeded() {
        guard let pdfView, hasActiveDocument else { return }
        switch zoomMode {
        case .fitPage:
            if let computed = pdfView.fitToPageScale() {
                let clamped = Self.clampedScale(computed)
                pdfView.autoScales = false
                if abs(pdfView.scaleFactor - clamped) > 0.005 {
                    pdfView.scaleFactor = clamped
                }
                effectiveScaleFactor = clamped
            }
        case .fitWidth:
            if let computed = pdfView.fitToWidthScale() {
                let clamped = Self.clampedScale(computed)
                pdfView.autoScales = false
                if abs(pdfView.scaleFactor - clamped) > 0.005 {
                    pdfView.scaleFactor = clamped
                }
                effectiveScaleFactor = clamped
            }
        case .manual:
            break
        }
    }

    // MARK: - Search

    func updateSearch(query: String) {
        searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let doc = document else {
            clearSearch()
            return
        }

        let matches = doc.findString(trimmed, withOptions: [.caseInsensitive])
        searchMatches = matches
        pdfView?.highlightedSelections = matches.isEmpty ? nil : matches

        if matches.isEmpty {
            currentSearchMatchIndex = nil
        } else {
            currentSearchMatchIndex = 0
            navigateToSearchMatch(at: 0)
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchMatches = []
        currentSearchMatchIndex = nil
        pdfView?.highlightedSelections = nil
    }

    private func stepSearchMatch(forward: Bool) {
        guard !searchMatches.isEmpty else { return }
        let current = currentSearchMatchIndex ?? (forward ? -1 : 0)
        let count = searchMatches.count
        let nextIndex = forward
            ? (current + 1) % count
            : (current - 1 + count) % count
        currentSearchMatchIndex = nextIndex
        navigateToSearchMatch(at: nextIndex)
    }

    private func navigateToSearchMatch(at index: Int) {
        guard index >= 0, index < searchMatches.count else { return }
        let selection = searchMatches[index]
        clearSelection()

        if let page = selection.pages.first,
           let pageIndex = document?.index(for: page) {
            currentPageIndex = pageIndex
        }
        pdfView?.go(to: selection)
    }

    // MARK: - Selection & Focus

    func updateSelection(text: String, rect: CGRect, autoShowTranslation: Bool) {
        selectedText = text
        selectionRect = rect
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        showTranslation = hasText && autoShowTranslation
    }

    func clearSelection() {
        selectedText = ""
        selectionRect = .zero
        showTranslation = false
    }

    func focusPDFView() {
        guard let pdfView else { return }
        pdfView.window?.makeFirstResponder(pdfView)
    }
}
