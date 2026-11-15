import AppKit
import Foundation
import PDFKit
import Testing
@testable import Readread

@MainActor
@Suite("Reader and Document Loading")
struct ReaderDocumentTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("readread-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeThreePagePDF(at url: URL? = nil) throws -> PDFDocument {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "ReaderDocumentTests", code: 1)
        }

        for page in 1...3 {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let lines = [
                "Readread verification Chapter \(page)",
                "house book water hello world",
                "Search marker: chapter\(page)token"
            ]
            for (idx, line) in lines.enumerated() {
                (line as NSString).draw(
                    at: NSPoint(x: 60, y: 700 - idx * 36),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 16),
                        .foregroundColor: NSColor.black
                    ]
                )
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()

        let doc = PDFDocument(data: data as Data)!
        doc.page(at: 1)!.rotation = 90

        let root = PDFOutline()
        let first = PDFOutline()
        first.label = "First chapter"
        first.destination = PDFDestination(page: doc.page(at: 0)!, at: .zero)

        let nested = PDFOutline()
        nested.label = "Nested second chapter"
        nested.destination = PDFDestination(page: doc.page(at: 1)!, at: .zero)
        first.insertChild(nested, at: 0)
        root.insertChild(first, at: 0)

        let last = PDFOutline()
        last.label = "Last chapter"
        last.destination = PDFDestination(page: doc.page(at: 2)!, at: .zero)
        root.insertChild(last, at: 1)
        doc.outlineRoot = root

        if let url {
            doc.write(to: url)
        }
        return doc
    }

    private func makeEPUB(at epubURL: URL, in tempDir: URL) throws {
        let workDir = tempDir.appendingPathComponent("epub-src-\(UUID().uuidString)", isDirectory: true)
        let metaInf = workDir.appendingPathComponent("META-INF", isDirectory: true)
        let oebps = workDir.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)

        try "application/epub+zip".write(
            to: workDir.appendingPathComponent("mimetype"),
            atomically: true,
            encoding: .utf8
        )

        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try containerXML.write(
            to: metaInf.appendingPathComponent("container.xml"),
            atomically: true,
            encoding: .utf8
        )

        // Filenames intentionally conflict with spine order: z_first.xhtml comes BEFORE a_second.xhtml.
        let opfXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Ordered Chapters</dc:title>
          </metadata>
          <manifest>
            <item id="ch1" href="z_first.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="a_second.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
            <itemref idref="ch2"/>
          </spine>
        </package>
        """
        try opfXML.write(
            to: oebps.appendingPathComponent("content.opf"),
            atomically: true,
            encoding: .utf8
        )

        try "<html><body><p>SPINE_CHAPTER_ONE_FIRST</p></body></html>".write(
            to: oebps.appendingPathComponent("z_first.xhtml"),
            atomically: true,
            encoding: .utf8
        )
        try "<html><body><p>SPINE_CHAPTER_TWO_SECOND</p></body></html>".write(
            to: oebps.appendingPathComponent("a_second.xhtml"),
            atomically: true,
            encoding: .utf8
        )

        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = workDir
        zip.arguments = ["-q", "-r", epubURL.path, "mimetype", "META-INF", "OEBPS"]
        try zip.run()
        zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)
    }

    // MARK: - DocumentLoader Tests

    @Test func missingCorruptAndLockedPDFFailExplicitly() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let missingURL = dir.appendingPathComponent("missing.pdf")
        #expect(throws: DocumentLoadError.fileNotFound(missingURL)) {
            _ = try DocumentLoader.load(url: missingURL, format: .pdf)
        }

        let corruptURL = dir.appendingPathComponent("corrupt.pdf")
        try Data("This is not a PDF".utf8).write(to: corruptURL)
        do {
            _ = try DocumentLoader.load(url: corruptURL, format: .pdf)
            Issue.record("Expected corruptDocument error")
        } catch let error as DocumentLoadError {
            if case .corruptDocument(let url, _) = error {
                #expect(url == corruptURL)
            } else {
                Issue.record("Unexpected error case: \(error)")
            }
        }

        let sourceDoc = try makeThreePagePDF()
        let lockedURL = dir.appendingPathComponent("locked.pdf")
        let wroteLocked = sourceDoc.write(
            to: lockedURL,
            withOptions: [
                .userPasswordOption: "secret123",
                .ownerPasswordOption: "owner123"
            ]
        )
        #expect(wroteLocked)

        #expect(throws: DocumentLoadError.passwordProtected(lockedURL)) {
            _ = try DocumentLoader.load(url: lockedURL, format: .pdf)
        }
    }

    @Test func longTextRTFAndHTMLPaginateWithSearchableEndingSentinel() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let longText = (1...240)
            .map { "Paragraph \($0): A house beside the water. Every line remains readable after pagination." }
            .joined(separator: "\n\n") + "\nEND_OF_BOOK_SENTINEL"

        let txtURL = dir.appendingPathComponent("long.txt")
        try longText.write(to: txtURL, atomically: true, encoding: .utf8)
        let txtDoc = try DocumentLoader.load(url: txtURL, format: .txt)
        #expect(txtDoc.pageCount > 1)
        #expect(!txtDoc.findString("END_OF_BOOK_SENTINEL", withOptions: []).isEmpty)

        let rtfURL = dir.appendingPathComponent("long.rtf")
        let attr = NSAttributedString(string: longText, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let rtfData = try attr.data(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try rtfData.write(to: rtfURL)
        let rtfDoc = try DocumentLoader.load(url: rtfURL, format: .rtf)
        #expect(rtfDoc.pageCount > 1)
        #expect(!rtfDoc.findString("END_OF_BOOK_SENTINEL", withOptions: []).isEmpty)

        let htmlURL = dir.appendingPathComponent("long.html")
        let html = "<!doctype html><html><body>" + longText
            .components(separatedBy: "\n\n")
            .map { "<p>\($0)</p>" }
            .joined() + "</body></html>"
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)
        let htmlDoc = try DocumentLoader.load(url: htmlURL, format: .html)
        #expect(htmlDoc.pageCount > 1)
        #expect(!htmlDoc.findString("END_OF_BOOK_SENTINEL", withOptions: []).isEmpty)
    }

    @Test func epubFollowsSpineOrderAndRejectsMalformedOrTraversalArchives() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let epubURL = dir.appendingPathComponent("ordered.epub")
        try makeEPUB(at: epubURL, in: dir)

        let epubDoc = try DocumentLoader.load(url: epubURL, format: .epub)
        let combinedText = (0..<epubDoc.pageCount)
            .compactMap { epubDoc.page(at: $0)?.string }
            .joined(separator: "\n")

        let firstRange = combinedText.range(of: "SPINE_CHAPTER_ONE_FIRST")
        let secondRange = combinedText.range(of: "SPINE_CHAPTER_TWO_SECOND")
        #expect(firstRange != nil)
        #expect(secondRange != nil)
        if let firstRange, let secondRange {
            #expect(firstRange.lowerBound < secondRange.lowerBound)
        }

        let badEPUB = dir.appendingPathComponent("bad.epub")
        try Data("not a zip".utf8).write(to: badEPUB)
        do {
            _ = try DocumentLoader.load(url: badEPUB, format: .epub)
            Issue.record("Expected corruptDocument error for malformed EPUB")
        } catch let error as DocumentLoadError {
            if case .corruptDocument = error {
                // expected
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }

        #expect(throws: DocumentLoadError.self) {
            try DocumentLoader.validateArchiveEntries(
                ["META-INF/container.xml", "../escape.xhtml"],
                baseDirectory: dir,
                archiveURL: epubURL
            )
        }
    }

    // MARK: - ReaderController State, Rotation, Zoom, Search

    @Test func controllerClampsPageAndRotatesFourTimesRestoringIntrinsicOrientation() throws {
        let doc = try makeThreePagePDF()
        let book = BookItem(
            title: "Three Page",
            filePath: "/tmp/three.pdf",
            lastPageIndex: 99,
            totalPages: 0,
            fileFormat: .pdf,
            rotation: 0,
            zoomLevel: 1.0
        )
        let controller = ReaderController(book: book)

        // Commands should do nothing before a document is loaded
        controller.perform(.nextPage)
        controller.perform(.rotateClockwise)
        #expect(!controller.hasActiveDocument)
        #expect(controller.rotationOffset == 0)

        controller.installLoadedDocument(doc)
        #expect(controller.hasActiveDocument)
        #expect(controller.pageCount == 3)
        #expect(controller.currentPageIndex == 2)

        controller.perform(.goToPage(1))
        #expect(controller.currentPageIndex == 1)

        // Page 0 starts at 0, Page 1 starts at 90
        #expect(doc.page(at: 0)?.rotation == 0)
        #expect(doc.page(at: 1)?.rotation == 90)

        for step in 1...4 {
            controller.perform(.rotateClockwise)
            #expect(controller.currentPageIndex == 1)
            #expect(controller.rotationOffset == (step * 90) % 360)
        }

        #expect(controller.rotationOffset == 0)
        #expect(doc.page(at: 0)?.rotation == 0)
        #expect(doc.page(at: 1)?.rotation == 90)
    }

    @Test func fitModesRecalculateOnViewportChangeWithoutSwitchingToManual() throws {
        let doc = try makeThreePagePDF()
        let book = BookItem(title: "Fit", filePath: "/tmp/fit.pdf", fileFormat: .pdf)
        let controller = ReaderController(book: book)
        controller.installLoadedDocument(doc)

        let pdfView = PagedPDFView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        pdfView.document = doc
        controller.pdfView = pdfView

        controller.perform(.fitToWidth)
        #expect(controller.zoomMode == .fitWidth)
        let narrowScale = controller.effectiveScaleFactor

        pdfView.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        controller.recalculateFitScaleIfNeeded()
        #expect(controller.zoomMode == .fitWidth)
        #expect(controller.effectiveScaleFactor > narrowScale)

        controller.perform(.fitToPage)
        #expect(controller.zoomMode == .fitPage)
        let tallScale = controller.effectiveScaleFactor

        pdfView.frame = NSRect(x: 0, y: 0, width: 1200, height: 400)
        controller.recalculateFitScaleIfNeeded()
        #expect(controller.zoomMode == .fitPage)
        #expect(controller.effectiveScaleFactor < tallScale)
    }

    @Test func searchFindsMultipleMatchesNavigatesAndNeverTriggersTranslation() throws {
        let doc = try makeThreePagePDF()
        let book = BookItem(title: "Search", filePath: "/tmp/search.pdf", fileFormat: .pdf)
        let controller = ReaderController(book: book)
        controller.installLoadedDocument(doc)

        controller.updateSelection(text: "house", rect: CGRect(x: 10, y: 10, width: 40, height: 20), autoShowTranslation: true)
        #expect(controller.showTranslation)

        controller.updateSearch(query: "house")
        #expect(controller.searchMatches.count == 3)
        #expect(controller.currentSearchMatchIndex == 0)
        #expect(!controller.showTranslation)

        controller.perform(.findNext)
        #expect(controller.currentSearchMatchIndex == 1)
        #expect(controller.currentPageIndex == 1)
        #expect(!controller.showTranslation)

        controller.perform(.findPrevious)
        #expect(controller.currentSearchMatchIndex == 0)
        #expect(controller.currentPageIndex == 0)

        controller.updateSearch(query: "NONEXISTENT_TOKEN_XYZ")
        #expect(controller.searchMatches.isEmpty)
        #expect(controller.currentSearchMatchIndex == nil)
    }

    @Test func outlineBuilderPreservesNestedHierarchyAndDestinations() throws {
        let doc = try makeThreePagePDF()
        let tree = OutlineBuilder.buildOutline(from: doc)

        #expect(tree.count == 2)
        #expect(tree[0].title == "First chapter")
        #expect(tree[0].pageIndex == 0)
        #expect(tree[0].children?.count == 1)
        #expect(tree[0].children?[0].title == "Nested second chapter")
        #expect(tree[0].children?[0].pageIndex == 1)
        #expect(tree[1].title == "Last chapter")
        #expect(tree[1].pageIndex == 2)
    }
}
