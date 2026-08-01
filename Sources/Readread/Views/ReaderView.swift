import SwiftUI
import PDFKit

struct ReaderView: View {
    let book: BookItem
    let onBack: () -> Void
    
    @EnvironmentObject var historyStore: ReadingHistoryStore
    @EnvironmentObject var bookmarkService: BookmarkService
    
    @State private var pdfDocument: PDFDocument?
    @State private var currentPageIndex: Int = 0
    @State private var scaleFactor: CGFloat = 1.0
    @State private var rotation: Int = 0
    
    @State private var showTOC: Bool = false
    @State private var showSearch: Bool = false
    @State private var searchQuery: String = ""
    @AppStorage("defaultZoomLevel") private var defaultZoomLevel: Double = 100.0
    
    @State private var selectedText: String = ""
    @State private var selectionRect: CGRect = .zero
    @State private var showTranslation: Bool = false
    
    @State private var showGoToPage: Bool = false
    @State private var goToPageText: String = ""
    @State private var keyMonitor: Any?
    
    var body: some View {
        HStack(spacing: 0) {
            // Collapsible Sidebar Drawer
            if showTOC {
                if let doc = pdfDocument {
                    TableOfContentsView(document: doc, bookId: book.id, currentPageIndex: currentPageIndex) { pageIdx in
                        currentPageIndex = pageIdx
                    }
                    .frame(width: 260)
                    .transition(.move(edge: .leading))
                    
                    Divider()
                }
            }
            
            // Main Content Area
            ZStack {
                VStack(spacing: 0) {
                    if showSearch {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            TextField("Search...", text: $searchQuery)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Button("Done") {
                                showSearch = false
                                searchQuery = ""
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                    }
                    
                    if let doc = pdfDocument {
                        PDFReaderView(
                            document: doc,
                            currentPageIndex: $currentPageIndex,
                            scaleFactor: $scaleFactor,
                            rotation: $rotation
                        ) { text, rect in
                            selectedText = text
                            selectionRect = rect
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                showTranslation = true
                            } else {
                                showTranslation = false
                            }
                        }
                        .background(Color.offWhite)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView("Loading document...")
                            Text(book.title)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Bottom Bar
                    HStack {
                        Button(action: { previousPage() }) {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                        }
                        .disabled(currentPageIndex == 0)
                        
                        let totalPages = pdfDocument?.pageCount ?? 1
                        if totalPages > 1 {
                            Slider(value: Binding(
                                get: { Double(currentPageIndex) },
                                set: { currentPageIndex = Int($0) }
                            ), in: 0...Double(totalPages - 1), step: 1)
                        } else {
                            Spacer()
                        }
                        
                        Button(action: { nextPage() }) {
                            Image(systemName: "chevron.right")
                                .font(.headline)
                        }
                        .disabled(currentPageIndex >= (pdfDocument?.pageCount ?? 1) - 1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.2)),
                        alignment: .top
                    )
                }
                
                // Floating Translation Popover Box
                if showTranslation && !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    TranslationPopover(selectedText: selectedText, selectionRect: selectionRect, isPresented: $showTranslation)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .animation(.easeInOut(duration: 0.15), value: showTranslation)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showTOC)
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Library")
                    }
                    .foregroundColor(Color.textPrimary)
                }
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    withAnimation {
                        showTOC.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(showTOC ? .accentBrown : Color.textPrimary)
                }
                .help("Toggle Contents Sidebar (⌘T)")
                
                Button(action: {
                    goToPageText = "\(currentPageIndex + 1)"
                    showGoToPage = true
                }) {
                    Text("Page \(currentPageIndex + 1) of \(pdfDocument?.pageCount ?? 1)")
                        .font(.caption.bold())
                        .foregroundColor(Color.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showGoToPage) {
                    VStack(spacing: 12) {
                        Text("Go to Page").font(.headline)
                        HStack {
                            TextField("Page", text: $goToPageText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80)
                                .onSubmit {
                                    jumpToPage()
                                }
                            Text("of \(pdfDocument?.pageCount ?? 1)")
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 12) {
                            Button("Cancel") { showGoToPage = false }
                            Button("Go") { jumpToPage() }
                                .keyboardShortcut(.return)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(16)
                    .frame(width: 220)
                }
                
                // Easy Zoom Controls
                Button(action: { NotificationCenter.default.post(name: .init("FitToPageTrigger"), object: nil) }) {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                }
                .help("Fit Page to Window")
                
                Button(action: { NotificationCenter.default.post(name: .init("FitToWidthTrigger"), object: nil) }) {
                    Image(systemName: "arrow.left.and.right")
                }
                .help("Fit Page to Width")
                
                Button(action: { scaleFactor = max(0.2, scaleFactor - 0.1) }) { Image(systemName: "minus.magnifyingglass") }
                
                Menu {
                    Button("Fit Page to Window") { NotificationCenter.default.post(name: .init("FitToPageTrigger"), object: nil) }
                    Button("Fit Page to Width") { NotificationCenter.default.post(name: .init("FitToWidthTrigger"), object: nil) }
                    Divider()
                    Button("50%") { scaleFactor = 0.5 }
                    Button("75%") { scaleFactor = 0.75 }
                    Button("100% (Actual Size)") { scaleFactor = 1.0 }
                    Button("125%") { scaleFactor = 1.25 }
                    Button("150%") { scaleFactor = 1.50 }
                    Button("200%") { scaleFactor = 2.0 }
                    Button("300%") { scaleFactor = 3.0 }
                    Button("400%") { scaleFactor = 4.0 }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(Int(scaleFactor * 100))%")
                            .font(.caption.bold())
                            .foregroundColor(Color.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(Color.textPrimary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { scaleFactor = min(5.0, scaleFactor + 0.1) }) { Image(systemName: "plus.magnifyingglass") }
                
                Button(action: { rotation = (rotation + 90) % 360 }) { Image(systemName: "rotate.right") }
                
                Button(action: {
                    bookmarkService.toggleBookmark(bookId: book.id, pageIndex: currentPageIndex)
                }) {
                    Image(systemName: bookmarkService.isBookmarked(bookId: book.id, pageIndex: currentPageIndex) ? "star.fill" : "star")
                }
                
                Button(action: { showSearch.toggle() }) { Image(systemName: "magnifyingglass") }
            }
        }
        .onAppear {
            loadDocument()
            currentPageIndex = book.lastPageIndex
            rotation = book.rotation
            scaleFactor = book.zoomLevel > 0 ? book.zoomLevel : defaultZoomLevel / 100.0
            setupKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onChange(of: currentPageIndex) { newPage in
            historyStore.updateProgress(for: book.id, page: newPage, totalPages: pdfDocument?.pageCount, rotation: rotation, zoom: scaleFactor)
        }
        .onChange(of: rotation) { newRot in
            historyStore.updateProgress(for: book.id, page: currentPageIndex, totalPages: pdfDocument?.pageCount, rotation: newRot, zoom: scaleFactor)
        }
        .onChange(of: scaleFactor) { newZoom in
            historyStore.updateProgress(for: book.id, page: currentPageIndex, totalPages: pdfDocument?.pageCount, rotation: rotation, zoom: newZoom)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ToggleTOCTrigger"))) { _ in
            withAnimation {
                showTOC.toggle()
            }
        }
    }
    
    private func previousPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
        }
    }
    
    private func nextPage() {
        if let doc = pdfDocument, currentPageIndex < doc.pageCount - 1 {
            currentPageIndex += 1
        }
    }
    
    private func setupKeyboardMonitor() {
        removeKeyboardMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123, 126, 116:
                DispatchQueue.main.async { self.previousPage() }
                return nil
            case 124, 125, 121, 49:
                DispatchQueue.main.async { self.nextPage() }
                return nil
            default:
                return event
            }
        }
    }
    
    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func loadDocument() {
        guard let url = historyStore.resolveURL(for: book) else { return }
        _ = url.startAccessingSecurityScopedResource()
        
        if book.fileFormat == .pdf {
            pdfDocument = PDFDocument(url: url)
        } else {
            pdfDocument = createPDFFromText(url: url)
        }
    }
    
    private func jumpToPage() {
        if let page = Int(goToPageText), page >= 1, page <= (pdfDocument?.pageCount ?? 1) {
            currentPageIndex = page - 1
        }
        showGoToPage = false
    }
    
    private func createPDFFromText(url: URL) -> PDFDocument? {
        do {
            let attrStr: NSAttributedString
            if book.fileFormat == .epub {
                attrStr = try loadEPUBText(url: url)
            } else {
                let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                    .documentType: (book.fileFormat == .html ? NSAttributedString.DocumentType.html :
                                   book.fileFormat == .rtf ? NSAttributedString.DocumentType.rtf : NSAttributedString.DocumentType.plain)
                ]
                attrStr = try NSAttributedString(url: url, options: options, documentAttributes: nil)
            }
            
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
            textView.textStorage?.setAttributedString(attrStr)
            
            let printInfo = NSPrintInfo.shared
            printInfo.paperSize = NSSize(width: 600, height: 800)
            printInfo.topMargin = 40
            printInfo.bottomMargin = 40
            printInfo.leftMargin = 40
            printInfo.rightMargin = 40
            
            let printOp = NSPrintOperation(view: textView, printInfo: printInfo)
            printOp.showsPrintPanel = false
            printOp.showsProgressPanel = false
            
            let pdfData = textView.dataWithPDF(inside: textView.bounds)
            return PDFDocument(data: pdfData)
        } catch {
            print("Error loading text document: \(error)")
            return nil
        }
    }
    
    private func loadEPUBText(url: URL) throws -> NSAttributedString {
        // Try reading EPUB container or extracting HTML files from ZIP archive
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", url.path, "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()
        
        // Find HTML files inside extracted EPUB
        let enumerator = fm.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        var fullHTML = "<html><head><style>body { font-family: -apple-system, sans-serif; font-size: 15px; line-height: 1.6; color: #2C2C2A; padding: 20px; }</style></head><body>"
        
        var htmlFiles: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "html" || ext == "xhtml" || ext == "htm" {
                htmlFiles.append(fileURL)
            }
        }
        
        htmlFiles.sort { $0.path < $1.path }
        
        for htmlURL in htmlFiles {
            if let str = try? String(contentsOf: htmlURL, encoding: .utf8) {
                // Strip <html> and <body> tags to concatenate cleanly
                var bodyContent = str
                if let bodyRange = str.range(of: "<body[^>]*>", options: .regularExpression) {
                    bodyContent = String(str[bodyRange.upperBound...])
                }
                if let endBodyRange = bodyContent.range(of: "</body>") {
                    bodyContent = String(bodyContent[..<endBodyRange.lowerBound])
                }
                fullHTML += bodyContent + "<hr/>"
            }
        }
        
        fullHTML += "</body></html>"
        
        if let data = fullHTML.data(using: .utf8) {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            if let attrStr = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                return attrStr
            }
        }
        
        return NSAttributedString(string: "Failed to parse EPUB content.")
    }
}
