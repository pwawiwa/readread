import Foundation
import UniformTypeIdentifiers

struct BookItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var filePath: String
    var bookmarkData: Data?
    var lastPageIndex: Int
    var totalPages: Int
    var lastOpenedDate: Date
    var fileFormat: FileFormat
    var rotation: Int
    var zoomLevel: Double
    
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
            self.rawValue.uppercased()
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
    }
    
    static var supportedUTTypes: [UTType] {
        return [
            .pdf,
            .plainText,
            .text,
            .rtf,
            .html,
            UTType(filenameExtension: "epub") ?? .data
        ]
    }
    
    init(id: UUID = UUID(), title: String, filePath: String, bookmarkData: Data? = nil, lastPageIndex: Int = 0, totalPages: Int = 0, lastOpenedDate: Date = Date(), fileFormat: FileFormat, rotation: Int = 0, zoomLevel: Double = 1.0) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.bookmarkData = bookmarkData
        self.lastPageIndex = lastPageIndex
        self.totalPages = totalPages
        self.lastOpenedDate = lastOpenedDate
        self.fileFormat = fileFormat
        self.rotation = rotation
        self.zoomLevel = zoomLevel
    }
    
    init(url: URL) {
        self.id = UUID()
        self.title = url.deletingPathExtension().lastPathComponent
        self.filePath = url.path
        self.bookmarkData = nil
        self.lastPageIndex = 0
        self.totalPages = 0
        self.lastOpenedDate = Date()
        self.rotation = 0
        self.zoomLevel = 1.0
        
        let ext = url.pathExtension.lowercased()
        if let format = FileFormat(rawValue: ext) {
            self.fileFormat = format
        } else {
            self.fileFormat = .pdf
        }
    }
}
