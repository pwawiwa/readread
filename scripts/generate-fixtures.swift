import AppKit
import PDFKit

let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/private/tmp/readread-fixtures", isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let data = NSMutableData()
var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
let consumer = CGDataConsumer(data: data)!
let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
for page in 1...3 {
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let title = "Readread verification / Chapter \(page)"
    (title as NSString).draw(at: NSPoint(x: 60, y: 705), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
    let lines = [
        "house book water hello world",
        "A quiet house beside the water.",
        "Search marker: chapter\(page)token",
        "Select house to test English to Indonesian translation.",
        "Page \(page) has selectable text for the reader checks."
    ]
    for (index, line) in lines.enumerated() {
        (line as NSString).draw(at: NSPoint(x: 60, y: 640 - index * 40), withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
}
context.closePDF()
let document = PDFDocument(data: data as Data)!
document.page(at: 1)!.rotation = 90
let outline = PDFOutline()
let chapter = PDFOutline()
chapter.label = "First chapter"
chapter.destination = PDFDestination(page: document.page(at: 0)!, at: .zero)
let nested = PDFOutline()
nested.label = "Nested second chapter"
nested.destination = PDFDestination(page: document.page(at: 1)!, at: .zero)
chapter.insertChild(nested, at: 0)
outline.insertChild(chapter, at: 0)
let last = PDFOutline()
last.label = "Last chapter"
last.destination = PDFDestination(page: document.page(at: 2)!, at: .zero)
outline.insertChild(last, at: 1)
document.outlineRoot = outline
guard document.write(to: destination.appendingPathComponent("Reader checks.pdf")) else { fatalError("Cannot write PDF fixture") }

let longText = (1...240).map { "Paragraph \($0): A house beside the water. This book checks that every line remains readable after pagination." }.joined(separator: "\n\n") + "\nEND_OF_BOOK_SENTINEL"
try longText.write(to: destination.appendingPathComponent("Long book.txt"), atomically: true, encoding: .utf8)
let attributed = NSAttributedString(string: longText, attributes: [.font: NSFont.systemFont(ofSize: 14)])
try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: destination.appendingPathComponent("Long book.rtf"))
let html = "<!doctype html><html><body>" + longText.components(separatedBy: "\n\n").map { "<p>\($0)</p>" }.joined() + "</body></html>"
try html.write(to: destination.appendingPathComponent("Long book.html"), atomically: true, encoding: .utf8)
try Data("This is not a PDF".utf8).write(to: destination.appendingPathComponent("Corrupt book.pdf"))
print("Created selectable PDF, long TXT/RTF/HTML, and corrupt PDF fixtures in \(destination.path)")
