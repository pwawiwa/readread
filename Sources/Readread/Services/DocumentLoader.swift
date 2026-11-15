import AppKit
import CoreText
import Foundation
import PDFKit

enum DocumentLoadError: LocalizedError, Equatable {
    case fileNotFound(URL)
    case unreadable(URL, String)
    case corruptDocument(URL, String)
    case passwordProtected(URL)
    case unsupportedFormat(String)

    var title: String {
        switch self {
        case .fileNotFound:
            return "File Not Found"
        case .unreadable:
            return "Cannot Read File"
        case .corruptDocument:
            return "Corrupt or Invalid Document"
        case .passwordProtected:
            return "Password-Protected PDF"
        case .unsupportedFormat:
            return "Unsupported Format"
        }
    }

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "\"\(url.lastPathComponent)\" could not be found at \(url.path)."
        case .unreadable(let url, let reason):
            return "\"\(url.lastPathComponent)\" could not be opened: \(reason)"
        case .corruptDocument(let url, let reason):
            return "\"\(url.lastPathComponent)\" appears damaged or invalid: \(reason)"
        case .passwordProtected(let url):
            return "\"\(url.lastPathComponent)\" is password-protected and cannot be opened in Readread."
        case .unsupportedFormat(let format):
            return "The format \"\(format)\" is not supported."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "Re-import the book from its new location or remove it from your library."
        case .unreadable:
            return "Check file permissions or re-import the book to refresh access."
        case .corruptDocument:
            return "Try opening another copy of the file or re-exporting it."
        case .passwordProtected:
            return "Remove the password protection in Preview or another PDF tool, then re-import."
        case .unsupportedFormat:
            return "Import a PDF, EPUB, TXT, RTF, or HTML document."
        }
    }
}

@MainActor
enum DocumentLoader {
    static func load(url: URL, format: BookItem.FileFormat) throws -> PDFDocument {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw DocumentLoadError.fileNotFound(url)
        }
        guard fm.isReadableFile(atPath: url.path) else {
            throw DocumentLoadError.unreadable(url, "Permission denied.")
        }

        switch format {
        case .pdf:
            return try loadPDF(url: url)
        case .txt:
            return try loadTextDocument(url: url, format: .txt)
        case .rtf:
            return try loadTextDocument(url: url, format: .rtf)
        case .html:
            return try loadTextDocument(url: url, format: .html)
        case .epub:
            let attrStr = try extractEPUBAttributedString(url: url)
            return try paginateAttributedString(attrStr, sourceURL: url)
        }
    }

    private static func loadPDF(url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw DocumentLoadError.corruptDocument(url, "Could not parse PDF structure.")
        }
        if document.isLocked {
            throw DocumentLoadError.passwordProtected(url)
        }
        if document.pageCount == 0 {
            throw DocumentLoadError.corruptDocument(url, "The PDF contains zero pages.")
        }
        return document
    }

    private static func loadTextDocument(url: URL, format: BookItem.FileFormat) throws -> PDFDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DocumentLoadError.unreadable(url, error.localizedDescription)
        }

        let attrStr: NSAttributedString
        switch format {
        case .txt:
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1)
            guard let decoded = text else {
                throw DocumentLoadError.corruptDocument(url, "Could not decode text encoding.")
            }
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 8
            let bodyFont = NSFont(name: "Georgia", size: 13)
                ?? NSFont(name: "Helvetica Neue", size: 13)
                ?? NSFont.userFont(ofSize: 13)
                ?? NSFont.systemFont(ofSize: 13)
            attrStr = NSAttributedString(
                string: decoded,
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraphStyle
                ]
            )

        case .rtf:
            do {
                attrStr = try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
            } catch {
                throw DocumentLoadError.corruptDocument(url, "Could not parse RTF content.")
            }

        case .html:
            do {
                attrStr = try NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ],
                    documentAttributes: nil
                )
            } catch {
                throw DocumentLoadError.corruptDocument(url, "Could not parse HTML content.")
            }

        case .pdf, .epub:
            throw DocumentLoadError.unsupportedFormat(format.rawValue)
        }

        return try paginateAttributedString(attrStr, sourceURL: url)
    }

    static func paginateAttributedString(
        _ attributedString: NSAttributedString,
        sourceURL: URL? = nil,
        pageSize: CGSize = CGSize(width: 612, height: 792),
        margins: NSEdgeInsets = NSEdgeInsets(top: 54, left: 54, bottom: 54, right: 54)
    ) throws -> PDFDocument {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: pdfData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw DocumentLoadError.corruptDocument(
                sourceURL ?? URL(fileURLWithPath: "document"),
                "Failed to initialize PDF context."
            )
        }

        let printableRect = CGRect(
            x: margins.left,
            y: margins.bottom,
            width: max(100, pageSize.width - margins.left - margins.right),
            height: max(100, pageSize.height - margins.top - margins.bottom)
        )

        if attributedString.length == 0 {
            context.beginPDFPage(nil)
            context.endPDFPage()
            context.closePDF()
            guard let emptyDoc = PDFDocument(data: pdfData as Data) else {
                throw DocumentLoadError.corruptDocument(
                    sourceURL ?? URL(fileURLWithPath: "document"),
                    "Failed to generate PDF document."
                )
            }
            return emptyDoc
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGPath(rect: printableRect, transform: nil)
        var currentIndex = 0
        let totalLength = attributedString.length

        while currentIndex < totalLength {
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: currentIndex, length: 0),
                path,
                nil
            )
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length <= 0 {
                // Prevent infinite loop if a single glyph/attachment cannot fit in printableRect
                break
            }

            context.beginPDFPage(nil)
            context.saveGState()
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.restoreGState()
            context.endPDFPage()

            currentIndex += visibleRange.length
        }

        context.closePDF()

        guard let document = PDFDocument(data: pdfData as Data), document.pageCount > 0 else {
            throw DocumentLoadError.corruptDocument(
                sourceURL ?? URL(fileURLWithPath: "document"),
                "Generated PDF has no pages."
            )
        }
        return document
    }

    // MARK: - EPUB Extraction & Spine Parsing

    static func extractEPUBAttributedString(url: URL) throws -> NSAttributedString {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("readread-epub-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempDir)
        }

        let entries = try listZipEntries(url: url)
        try validateArchiveEntries(entries, baseDirectory: tempDir, archiveURL: url)
        try unzipArchive(url: url, destination: tempDir)

        let containerURL = tempDir.appendingPathComponent("META-INF/container.xml")
        guard fm.fileExists(atPath: containerURL.path) else {
            throw DocumentLoadError.corruptDocument(url, "Missing META-INF/container.xml.")
        }

        let containerData = try Data(contentsOf: containerURL)
        guard let opfRelativePath = EPUBContainerParser.parseRootfilePath(data: containerData) else {
            throw DocumentLoadError.corruptDocument(url, "Invalid EPUB container.xml (no rootfile found).")
        }

        let opfURL = try safeResolve(relativePath: opfRelativePath, relativeTo: tempDir, rootDirectory: tempDir, archiveURL: url)
        guard fm.fileExists(atPath: opfURL.path) else {
            throw DocumentLoadError.corruptDocument(url, "Missing EPUB package document (\(opfRelativePath)).")
        }

        let opfData = try Data(contentsOf: opfURL)
        let opfPackage = try EPUBPackageParser.parse(data: opfData, archiveURL: url)
        guard !opfPackage.spineIdRefs.isEmpty else {
            throw DocumentLoadError.corruptDocument(url, "EPUB spine contains no chapters.")
        }

        let opfBaseDir = opfURL.deletingLastPathComponent()
        let combined = NSMutableAttributedString()
        var loadedChapterCount = 0

        for idRef in opfPackage.spineIdRefs {
            guard let manifestItem = opfPackage.manifest[idRef] else { continue }
            let cleanHref = manifestItem.href.components(separatedBy: "#").first ?? manifestItem.href
            let decodedHref = cleanHref.removingPercentEncoding ?? cleanHref
            let chapterURL = try safeResolve(
                relativePath: decodedHref,
                relativeTo: opfBaseDir,
                rootDirectory: tempDir,
                archiveURL: url
            )

            guard fm.fileExists(atPath: chapterURL.path) else { continue }
            let ext = chapterURL.pathExtension.lowercased()
            let isHTML = ext == "xhtml" || ext == "html" || ext == "htm"
                || manifestItem.mediaType.contains("html")
            guard isHTML else { continue }

            let chapterData = try Data(contentsOf: chapterURL)
            if let chapterAttr = try? NSAttributedString(
                data: chapterData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            ) {
                if loadedChapterCount > 0 {
                    combined.append(NSAttributedString(string: "\n\n"))
                }
                combined.append(chapterAttr)
                loadedChapterCount += 1
            }
        }

        guard loadedChapterCount > 0, combined.length > 0 else {
            throw DocumentLoadError.corruptDocument(url, "No readable chapters found in EPUB spine.")
        }

        return combined
    }

    private static func listZipEntries(url: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z", "-1", url.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw DocumentLoadError.corruptDocument(url, "Unable to inspect EPUB archive: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw DocumentLoadError.corruptDocument(
                url,
                errText.isEmpty ? "Invalid or corrupt ZIP archive (status \(process.terminationStatus))." : errText
            )
        }

        let output = String(data: outData, encoding: .utf8) ?? ""
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func validateArchiveEntries(_ entries: [String], baseDirectory: URL, archiveURL: URL) throws {
        let canonicalBase = baseDirectory.standardizedFileURL.path
        let basePrefix = canonicalBase.hasSuffix("/") ? canonicalBase : canonicalBase + "/"

        for entry in entries {
            if entry.hasPrefix("/") || entry.hasPrefix("\\") {
                throw DocumentLoadError.corruptDocument(archiveURL, "Archive contains unsafe absolute path: \(entry)")
            }
            let components = entry.components(separatedBy: CharacterSet(charactersIn: "/\\"))
            if components.contains("..") {
                throw DocumentLoadError.corruptDocument(archiveURL, "Archive contains unsafe traversal path: \(entry)")
            }
            let resolved = baseDirectory.appendingPathComponent(entry).standardizedFileURL.path
            if resolved != canonicalBase && !resolved.hasPrefix(basePrefix) {
                throw DocumentLoadError.corruptDocument(archiveURL, "Archive entry escapes destination directory: \(entry)")
            }
        }
    }

    private static func unzipArchive(url: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", destination.path]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw DocumentLoadError.corruptDocument(url, "Unable to extract EPUB archive: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw DocumentLoadError.corruptDocument(
                url,
                errText.isEmpty ? "EPUB extraction failed (status \(process.terminationStatus))." : errText
            )
        }
    }

    private static func safeResolve(
        relativePath: String,
        relativeTo base: URL,
        rootDirectory: URL,
        archiveURL: URL
    ) throws -> URL {
        if relativePath.hasPrefix("/") {
            throw DocumentLoadError.corruptDocument(archiveURL, "Unsafe absolute reference in EPUB: \(relativePath)")
        }
        let resolved = base.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = rootDirectory.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard resolved.path == rootPath || resolved.path.hasPrefix(rootPrefix) else {
            throw DocumentLoadError.corruptDocument(archiveURL, "Path traversal detected in EPUB: \(relativePath)")
        }
        return resolved
    }
}

// MARK: - EPUB XML Parsers

private final class EPUBContainerParser: NSObject, XMLParserDelegate {
    private var rootfilePath: String?

    static func parseRootfilePath(data: Data) -> String? {
        let parserDelegate = EPUBContainerParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else { return nil }
        return parserDelegate.rootfilePath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        if localName == "rootfile", let fullPath = attributeDict["full-path"], !fullPath.isEmpty {
            if rootfilePath == nil {
                rootfilePath = fullPath
            }
        }
    }
}

private struct EPUBPackage {
    struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
    }

    var manifest: [String: ManifestItem] = [:]
    var spineIdRefs: [String] = []
}

private final class EPUBPackageParser: NSObject, XMLParserDelegate {
    private var package = EPUBPackage()

    static func parse(data: Data, archiveURL: URL) throws -> EPUBPackage {
        let delegate = EPUBPackageParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw DocumentLoadError.corruptDocument(archiveURL, "Could not parse EPUB OPF package XML.")
        }
        return delegate.package
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        switch localName {
        case "item":
            if let id = attributeDict["id"],
               let href = attributeDict["href"] {
                let mediaType = attributeDict["media-type"] ?? ""
                package.manifest[id] = EPUBPackage.ManifestItem(id: id, href: href, mediaType: mediaType)
            }
        case "itemref":
            if let idref = attributeDict["idref"], !idref.isEmpty {
                package.spineIdRefs.append(idref)
            }
        default:
            break
        }
    }
}
