import PDFKit
import AppKit

extension PDFView {
    func rotateCurrentPage(clockwise: Bool = true) {
        guard let page = currentPage else { return }
        let currentRotation = page.rotation
        let newRotation = (currentRotation + (clockwise ? 90 : -90) + 360) % 360
        page.rotation = newRotation
        
        let index = currentPageIndex
        layoutDocumentView()
        
        if let index = index, let doc = document, let restoredPage = doc.page(at: index) {
            go(to: restoredPage)
        }
    }
    
    func rotateAllPages(clockwise: Bool = true) {
        guard let doc = document else { return }
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i) {
                let newRotation = (page.rotation + (clockwise ? 90 : -90) + 360) % 360
                page.rotation = newRotation
            }
        }
        let index = currentPageIndex
        layoutDocumentView()
        
        if let index = index, let restoredPage = doc.page(at: index) {
            go(to: restoredPage)
        }
    }
    
    func zoomIn() {
        scaleFactor += 0.25
    }
    
    func zoomOut() {
        scaleFactor = max(0.1, scaleFactor - 0.25)
    }
    
    func fitToWidth() {
        guard let page = currentPage, let viewBounds = documentView?.bounds else { return }
        let pageBounds = page.bounds(for: displayBox)
        let ratio = bounds.width / pageBounds.width
        scaleFactor = ratio
    }
    
    func fitToPage() {
        guard let page = currentPage else { return }
        let pageBounds = page.bounds(for: displayBox)
        let widthRatio = bounds.width / pageBounds.width
        let heightRatio = bounds.height / pageBounds.height
        scaleFactor = min(widthRatio, heightRatio)
    }
    
    var currentPageIndex: Int? {
        guard let page = currentPage else { return nil }
        return document?.index(for: page)
    }
    
    var totalPageCount: Int? {
        return document?.pageCount
    }
}
