import SwiftUI
import PDFKit

// Custom PDFView subclass that handles arrow keys for page navigation
class PagedPDFView: PDFView {
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: // Left arrow
            goToPreviousPage(nil)
        case 124: // Right arrow
            goToNextPage(nil)
        case 126: // Up arrow
            goToPreviousPage(nil)
        case 125: // Down arrow
            goToNextPage(nil)
        default:
            super.keyDown(with: event)
        }
    }
}

struct PDFReaderView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    @Binding var scaleFactor: CGFloat
    @Binding var rotation: Int
    var onSelectionChanged: ((String, CGRect) -> Void)?
    
    func makeNSView(context: Context) -> PagedPDFView {
        let pdfView = PagedPDFView()
        pdfView.document = document
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.backgroundColor = NSColor.brokenWhitePaper
        pdfView.autoScales = true
        pdfView.delegate = context.coordinator
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleFitToPage(_:)),
            name: .init("FitToPageTrigger"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleFitToWidth(_:)),
            name: .init("FitToWidthTrigger"),
            object: nil
        )
        
        // Ensure PDFView gets keyboard focus
        DispatchQueue.main.async {
            pdfView.window?.makeFirstResponder(pdfView)
        }
        
        return pdfView
    }
    
    func updateNSView(_ pdfView: PagedPDFView, context: Context) {
        if pdfView.document != document {
            pdfView.document = document
        }
        
        if let targetPage = document.page(at: currentPageIndex), pdfView.currentPage != targetPage {
            pdfView.go(to: targetPage)
        }
        
        if let currentPage = pdfView.currentPage {
            if currentPage.rotation != rotation {
                currentPage.rotation = rotation
                pdfView.layoutDocumentView()
                pdfView.go(to: currentPage)
                
                // Recalculate selection box position adaptively after rotation
                if let currentSelection = pdfView.currentSelection,
                   let page = currentSelection.pages.first,
                   let text = currentSelection.string {
                    let bounds = currentSelection.bounds(for: page)
                    let viewRect = pdfView.convert(bounds, from: page)
                    let swiftUI_Y = pdfView.bounds.height - viewRect.midY
                    let swiftUIRect = CGRect(x: viewRect.midX, y: swiftUI_Y, width: viewRect.width, height: viewRect.height)
                    DispatchQueue.main.async {
                        context.coordinator.parent.onSelectionChanged?(text, swiftUIRect)
                    }
                }
            }
        }
        
        // Only update scale factor if significantly different to prevent zoom reset loop
        if abs(pdfView.scaleFactor - scaleFactor) > 0.02 {
            pdfView.autoScales = false
            pdfView.scaleFactor = scaleFactor
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PDFViewDelegate {
        var parent: PDFReaderView
        
        init(_ parent: PDFReaderView) {
            self.parent = parent
        }
        
        @objc func handleFitToPage(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView ?? NSApp.keyWindow?.firstResponder as? PDFView else { return }
            pdfView.autoScales = true
            pdfView.fitToPage()
            let newScale = pdfView.scaleFactor
            DispatchQueue.main.async {
                self.parent.scaleFactor = newScale
            }
        }
        
        @objc func handleFitToWidth(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView ?? NSApp.keyWindow?.firstResponder as? PDFView else { return }
            pdfView.autoScales = false
            pdfView.fitToWidth()
            let newScale = pdfView.scaleFactor
            DispatchQueue.main.async {
                self.parent.scaleFactor = newScale
            }
        }
        
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let pageIndex = pdfView.document?.index(for: currentPage) else { return }
            
            DispatchQueue.main.async {
                if self.parent.currentPageIndex != pageIndex {
                    self.parent.currentPageIndex = pageIndex
                }
            }
        }
        
        @objc func scaleChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            let currentScale = pdfView.scaleFactor
            DispatchQueue.main.async {
                if abs(self.parent.scaleFactor - currentScale) > 0.02 {
                    self.parent.scaleFactor = currentScale
                }
            }
        }
        
        @objc func selectionChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentSelection = pdfView.currentSelection,
                  let page = currentSelection.pages.first,
                  let text = currentSelection.string else {
                DispatchQueue.main.async {
                    self.parent.onSelectionChanged?("", .zero)
                }
                return
            }
            
            let bounds = currentSelection.bounds(for: page)
            let viewRect = pdfView.convert(bounds, from: page)
            
            let swiftUI_Y = pdfView.bounds.height - viewRect.midY
            let swiftUIRect = CGRect(x: viewRect.midX, y: swiftUI_Y, width: viewRect.width, height: viewRect.height)
            
            DispatchQueue.main.async {
                self.parent.onSelectionChanged?(text, swiftUIRect)
            }
        }
    }
}
