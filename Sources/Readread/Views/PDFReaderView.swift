import AppKit
import PDFKit
import SwiftUI

class PagedPDFView: PDFView {
    var onNavigatePrevious: (() -> Void)?
    var onNavigateNext: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let disallowedModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard disallowedModifiers.isEmpty else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123, 126, 116: // Left, Up, Page Up
            if let onNavigatePrevious {
                onNavigatePrevious()
            } else {
                goToPreviousPage(nil)
            }
        case 124, 125, 121: // Right, Down, Page Down
            if let onNavigateNext {
                onNavigateNext()
            } else {
                goToNextPage(nil)
            }
        case 49: // Space (Shift+Space goes backward)
            if event.modifierFlags.contains(.shift) {
                if let onNavigatePrevious {
                    onNavigatePrevious()
                } else {
                    goToPreviousPage(nil)
                }
            } else {
                if let onNavigateNext {
                    onNavigateNext()
                } else {
                    goToNextPage(nil)
                }
            }
        default:
            super.keyDown(with: event)
        }
    }
}

struct PDFReaderView: NSViewRepresentable {
    let document: PDFDocument
    @ObservedObject var controller: ReaderController
    var onSelectionChanged: ((String, CGRect) -> Void)?
    var onClearSelection: (() -> Void)?

    func makeNSView(context: Context) -> PagedPDFView {
        let pdfView = PagedPDFView()
        pdfView.document = document
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.backgroundColor = NSColor.brokenWhitePaper
        pdfView.autoScales = false
        pdfView.postsFrameChangedNotifications = true
        pdfView.delegate = context.coordinator

        pdfView.onNavigatePrevious = { [weak controller] in
            controller?.perform(.previousPage)
        }
        pdfView.onNavigateNext = { [weak controller] in
            controller?.perform(.nextPage)
        }

        controller.pdfView = pdfView
        context.coordinator.observe(pdfView: pdfView)

        DispatchQueue.main.async {
            pdfView.window?.makeFirstResponder(pdfView)
            controller.recalculateFitScaleIfNeeded()
        }

        return pdfView
    }

    func updateNSView(_ pdfView: PagedPDFView, context: Context) {
        context.coordinator.parent = self
        controller.pdfView = pdfView

        pdfView.onNavigatePrevious = { [weak controller] in
            controller?.perform(.previousPage)
        }
        pdfView.onNavigateNext = { [weak controller] in
            controller?.perform(.nextPage)
        }

        context.coordinator.isProgrammaticUpdate = true
        defer { context.coordinator.isProgrammaticUpdate = false }

        if pdfView.document !== document {
            pdfView.document = document
            controller.applyRotationOffset(preservePage: false)
        }

        let maxIndex = max(0, document.pageCount - 1)
        let clampedIndex = min(max(0, controller.currentPageIndex), maxIndex)
        if let targetPage = document.page(at: clampedIndex), pdfView.currentPage != targetPage {
            pdfView.go(to: targetPage)
            DispatchQueue.main.async {
                self.onClearSelection?()
            }
        }

        switch controller.zoomMode {
        case .fitPage, .fitWidth:
            controller.recalculateFitScaleIfNeeded()
        case .manual(let targetScale):
            let clamped = ReaderController.clampedScale(targetScale)
            if abs(pdfView.scaleFactor - clamped) > 0.005 {
                pdfView.autoScales = false
                pdfView.scaleFactor = clamped
            }
        }
    }

    static func dismantleNSView(_ nsView: PagedPDFView, coordinator: Coordinator) {
        coordinator.tearDown()
        nsView.delegate = nil
        nsView.onNavigatePrevious = nil
        nsView.onNavigateNext = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PDFViewDelegate {
        var parent: PDFReaderView
        var isProgrammaticUpdate = false
        private weak var observedPDFView: PagedPDFView?

        init(_ parent: PDFReaderView) {
            self.parent = parent
        }

        deinit {
            tearDown()
        }

        func observe(pdfView: PagedPDFView) {
            tearDown()
            observedPDFView = pdfView

            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(pageChanged(_:)),
                name: .PDFViewPageChanged,
                object: pdfView
            )
            center.addObserver(
                self,
                selector: #selector(selectionChanged(_:)),
                name: .PDFViewSelectionChanged,
                object: pdfView
            )
            center.addObserver(
                self,
                selector: #selector(scaleChanged(_:)),
                name: .PDFViewScaleChanged,
                object: pdfView
            )
            center.addObserver(
                self,
                selector: #selector(frameChanged(_:)),
                name: NSView.frameDidChangeNotification,
                object: pdfView
            )
        }

        func tearDown() {
            NotificationCenter.default.removeObserver(self)
            observedPDFView = nil
        }

        @objc func pageChanged(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let pageIndex = pdfView.document?.index(for: currentPage) else { return }

            DispatchQueue.main.async {
                if self.parent.controller.currentPageIndex != pageIndex {
                    self.parent.controller.currentPageIndex = pageIndex
                    self.parent.onClearSelection?()
                    self.parent.controller.recalculateFitScaleIfNeeded()
                }
            }
        }

        @objc func scaleChanged(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let pdfView = notification.object as? PDFView else { return }

            let currentScale = ReaderController.clampedScale(pdfView.scaleFactor)
            DispatchQueue.main.async {
                switch self.parent.controller.zoomMode {
                case .fitPage, .fitWidth:
                    break
                case .manual(let existing):
                    if abs(existing - currentScale) > 0.01 {
                        self.parent.controller.zoomMode = .manual(currentScale)
                        self.parent.controller.effectiveScaleFactor = currentScale
                        self.parent.onClearSelection?()
                    }
                }
            }
        }

        @objc func frameChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            DispatchQueue.main.async {
                self.parent.controller.recalculateFitScaleIfNeeded()
                self.emitSelectionRectIfActive(in: pdfView)
            }
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            emitSelectionRectIfActive(in: pdfView)
        }

        private func emitSelectionRectIfActive(in pdfView: PDFView) {
            guard let currentSelection = pdfView.currentSelection,
                  let page = currentSelection.pages.first,
                  let text = currentSelection.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                DispatchQueue.main.async {
                    self.parent.onClearSelection?()
                }
                return
            }

            let swiftUIRect = Self.swiftUISelectionRect(for: currentSelection, on: page, in: pdfView)
            DispatchQueue.main.async {
                self.parent.onSelectionChanged?(text, swiftUIRect)
            }
        }

        static func swiftUISelectionRect(for selection: PDFSelection, on page: PDFPage, in pdfView: PDFView) -> CGRect {
            let pageBounds = selection.bounds(for: page)
            let viewRect = pdfView.convert(pageBounds, from: page)
            return CGRect(
                x: viewRect.minX,
                y: pdfView.bounds.height - viewRect.maxY,
                width: viewRect.width,
                height: viewRect.height
            )
        }
    }
}
