import AppKit
import PDFKit

extension PDFView {
    func rotatedPageSize(for page: PDFPage) -> CGSize {
        let pageBounds = page.bounds(for: displayBox)
        let normalizedRotation = ((page.rotation % 360) + 360) % 360
        if normalizedRotation == 90 || normalizedRotation == 270 {
            return CGSize(width: pageBounds.height, height: pageBounds.width)
        }
        return pageBounds.size
    }

    func fitToWidthScale(padding: CGFloat = 24) -> CGFloat? {
        guard let page = currentPage else { return nil }
        let pageSize = rotatedPageSize(for: page)
        guard pageSize.width > 0, bounds.width > padding else { return nil }
        return (bounds.width - padding) / pageSize.width
    }

    func fitToPageScale(padding: CGFloat = 24) -> CGFloat? {
        guard let page = currentPage else { return nil }
        let pageSize = rotatedPageSize(for: page)
        guard pageSize.width > 0, pageSize.height > 0,
              bounds.width > padding, bounds.height > padding else { return nil }
        let widthRatio = (bounds.width - padding) / pageSize.width
        let heightRatio = (bounds.height - padding) / pageSize.height
        return min(widthRatio, heightRatio)
    }

    func fitToWidth() {
        guard let ratio = fitToWidthScale() else { return }
        autoScales = false
        scaleFactor = ratio
    }

    func fitToPage() {
        guard let ratio = fitToPageScale() else { return }
        autoScales = false
        scaleFactor = ratio
    }

    func zoomIn() {
        autoScales = false
        scaleFactor = min(5.0, scaleFactor + 0.25)
    }

    func zoomOut() {
        autoScales = false
        scaleFactor = max(0.2, scaleFactor - 0.25)
    }

    var currentPageIndex: Int? {
        guard let page = currentPage else { return nil }
        return document?.index(for: page)
    }

    var totalPageCount: Int? {
        return document?.pageCount
    }
}
