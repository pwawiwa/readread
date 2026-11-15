import Foundation
import UniformTypeIdentifiers

enum LibraryError: LocalizedError, Equatable {
    case invalidURL(String)
    case unsupportedFormat(fileName: String, fileExtension: String)
    case fileNotFound(fileName: String, path: String)
    case unreadableFile(fileName: String)
    case corruptHistory(message: String)
    case corruptBookmarks(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let urlString):
            return "Cannot import \"\(urlString)\" because it is not a local file."
        case .unsupportedFormat(let fileName, let ext):
            let extLabel = ext.isEmpty ? "no extension" : ".\(ext)"
            return "Cannot import \"\(fileName)\" (\(extLabel) is not supported)."
        case .fileNotFound(let fileName, _):
            return "\"\(fileName)\" could not be found."
        case .unreadableFile(let fileName):
            return "\"\(fileName)\" cannot be read."
        case .corruptHistory:
            return "Your saved library history could not be read."
        case .corruptBookmarks:
            return "Your saved bookmarks could not be read."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Choose a local PDF, EPUB, TXT, RTF, or HTML file from your Mac."
        case .unsupportedFormat:
            return "Supported formats are PDF, EPUB, TXT, RTF, and HTML."
        case .fileNotFound:
            return "Check whether the file was moved or deleted, or remove it from your library."
        case .unreadableFile:
            return "Check file permissions in Finder and try importing the file again."
        case .corruptHistory:
            return "A backup of the unreadable data was preserved. Import books to start a fresh library."
        case .corruptBookmarks:
            return "A backup of the unreadable bookmark data was preserved."
        }
    }
}

struct BookItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var filePath: String
    var bookmarkData: Data?
    var lastPageIndex: Int
    var totalPages: Int?
    var importedDate: Date
    var lastOpenedDate: Date?
    var fileFormat: FileFormat
    var rotation: Int
    var zoomLevel: Double

    var activityDate: Date {
        lastOpenedDate ?? importedDate
    }

    enum FileFormat: String, Codable, CaseIterable {
        case pdf, epub, txt, rtf, html

        var icon: String {
            switch self {
            case .pdf: return "doc.richtext"
            case .epub: return "book"
            case .txt: return "doc.text"
            case .rtf: return "doc.text.fill"
            case .html: return "safari"
            }
        }

        var displayName: String {
            rawValue.uppercased()
        }

        var utTypes: [UTType] {
            switch self {
            case .pdf:
                return [.pdf]
            case .epub:
                return [UTType(filenameExtension: "epub") ?? .data]
            case .txt:
                return [.plainText, .text]
            case .rtf:
                return [.rtf]
            case .html:
                return [.html]
            }
        }

        static func from(url: URL) -> FileFormat? {
            let ext = url.pathExtension.lowercased()
            if ext == "htm" {
                return .html
            }
            return FileFormat(rawValue: ext)
        }
    }

    static var supportedUTTypes: [UTType] {
        [
            .pdf,
            .plainText,
            .text,
            .rtf,
            .html,
            UTType(filenameExtension: "epub") ?? .data
        ]
    }

    static let minZoom: Double = 0.25
    static let maxZoom: Double = 5.0

    static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func validatedTotalPages(_ totalPages: Int?) -> Int? {
        guard let totalPages, totalPages > 0 else { return nil }
        return totalPages
    }

    static func validatedPageIndex(_ page: Int, totalPages: Int?) -> Int {
        let nonNegative = max(0, page)
        if let total = validatedTotalPages(totalPages) {
            return min(nonNegative, total - 1)
        }
        return nonNegative
    }

    static func validatedRotation(_ rotation: Int) -> Int {
        let mod = ((rotation % 360) + 360) % 360
        return ((mod + 45) / 90 * 90) % 360
    }

    static func validatedZoom(_ zoom: Double) -> Double {
        guard zoom.isFinite, zoom > 0 else { return 1.0 }
        return min(max(zoom, minZoom), maxZoom)
    }

    func validated() -> BookItem {
        let validTotal = BookItem.validatedTotalPages(totalPages)
        let validPage = BookItem.validatedPageIndex(lastPageIndex, totalPages: validTotal)
        let validRotation = BookItem.validatedRotation(rotation)
        let validZoom = BookItem.validatedZoom(zoomLevel)
        return BookItem(
            id: id,
            title: title.isEmpty ? URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent : title,
            filePath: filePath,
            bookmarkData: bookmarkData,
            lastPageIndex: validPage,
            totalPages: validTotal,
            importedDate: importedDate,
            lastOpenedDate: lastOpenedDate,
            fileFormat: fileFormat,
            rotation: validRotation,
            zoomLevel: validZoom
        )
    }

    init(
        id: UUID = UUID(),
        title: String,
        filePath: String,
        bookmarkData: Data? = nil,
        lastPageIndex: Int = 0,
        totalPages: Int? = nil,
        importedDate: Date = Date(),
        lastOpenedDate: Date? = nil,
        fileFormat: FileFormat,
        rotation: Int = 0,
        zoomLevel: Double = 1.0
    ) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.bookmarkData = bookmarkData
        let validTotal = BookItem.validatedTotalPages(totalPages)
        self.totalPages = validTotal
        self.lastPageIndex = BookItem.validatedPageIndex(lastPageIndex, totalPages: validTotal)
        self.importedDate = importedDate
        self.lastOpenedDate = lastOpenedDate
        self.fileFormat = fileFormat
        self.rotation = BookItem.validatedRotation(rotation)
        self.zoomLevel = BookItem.validatedZoom(zoomLevel)
    }

    init(validating url: URL) throws {
        guard url.isFileURL else {
            throw LibraryError.invalidURL(url.absoluteString)
        }
        guard let format = FileFormat.from(url: url) else {
            throw LibraryError.unsupportedFormat(
                fileName: url.lastPathComponent,
                fileExtension: url.pathExtension.lowercased()
            )
        }

        let canonical = BookItem.canonicalFileURL(url)
        let rawTitle = canonical.deletingPathExtension().lastPathComponent
        self.init(
            title: rawTitle.isEmpty ? canonical.lastPathComponent : rawTitle,
            filePath: canonical.path,
            bookmarkData: nil,
            lastPageIndex: 0,
            totalPages: nil,
            importedDate: Date(),
            lastOpenedDate: nil,
            fileFormat: format,
            rotation: 0,
            zoomLevel: 1.0
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case filePath
        case bookmarkData
        case lastPageIndex
        case totalPages
        case importedDate
        case lastOpenedDate
        case fileFormat
        case rotation
        case zoomLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let filePath = try container.decode(String.self, forKey: .filePath)
        let fallbackTitle = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
        let title = (decodedTitle?.isEmpty == false) ? decodedTitle! : fallbackTitle
        let bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        let rawTotal = try container.decodeIfPresent(Int.self, forKey: .totalPages)
        let validTotal = BookItem.validatedTotalPages(rawTotal)
        let rawPage = try container.decodeIfPresent(Int.self, forKey: .lastPageIndex) ?? 0
        let lastOpenedDate = try container.decodeIfPresent(Date.self, forKey: .lastOpenedDate)
        let importedDate = try container.decodeIfPresent(Date.self, forKey: .importedDate) ?? lastOpenedDate ?? Date()

        let format: FileFormat
        if let decodedFormat = try container.decodeIfPresent(FileFormat.self, forKey: .fileFormat) {
            format = decodedFormat
        } else if let inferred = FileFormat.from(url: URL(fileURLWithPath: filePath)) {
            format = inferred
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .fileFormat,
                in: container,
                debugDescription: "Missing or unsupported file format for \(filePath)"
            )
        }

        let rawRotation = try container.decodeIfPresent(Int.self, forKey: .rotation) ?? 0
        let rawZoom = try container.decodeIfPresent(Double.self, forKey: .zoomLevel) ?? 1.0

        self.init(
            id: id,
            title: title,
            filePath: filePath,
            bookmarkData: bookmarkData,
            lastPageIndex: rawPage,
            totalPages: validTotal,
            importedDate: importedDate,
            lastOpenedDate: lastOpenedDate,
            fileFormat: format,
            rotation: rawRotation,
            zoomLevel: rawZoom
        )
    }
}
