import SwiftUI
import PDFKit

struct OutlineNode: Identifiable {
    let id = UUID()
    let title: String
    let pageIndex: Int
    var children: [OutlineNode]?
}

struct TableOfContentsView: View {
    let document: PDFDocument
    let bookId: UUID
    let currentPageIndex: Int
    let onSelectPage: (Int) -> Void
    
    @EnvironmentObject var bookmarkService: BookmarkService
    @State private var selectedTab: SidebarTab = .chapters
    @State private var outlineTree: [OutlineNode] = []
    @State private var detectedHeadings: [OutlineNode] = []
    
    enum SidebarTab: String, CaseIterable {
        case chapters = "Chapters"
        case pages = "Pages"
        case bookmarks = "Bookmarks"
    }
    
    var displayNodes: [OutlineNode] {
        if !outlineTree.isEmpty {
            return outlineTree
        } else {
            return detectedHeadings
        }
    }
    
    var bookBookmarks: [PageBookmark] {
        bookmarkService.bookmarks(for: bookId)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header & Tab Selector
            VStack(spacing: 8) {
                HStack {
                    Text("Contents")
                        .font(.headline)
                        .foregroundColor(Color.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                
                Picker("", selection: $selectedTab) {
                    ForEach(SidebarTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Tab Content
            switch selectedTab {
            case .chapters:
                List {
                    if displayNodes.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("No chapters detected")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Switch to 'Pages' tab to jump to any page")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(displayNodes) { node in
                            HStack {
                                Image(systemName: node.pageIndex == currentPageIndex ? "bookmark.fill" : "doc.text")
                                    .font(.caption)
                                    .foregroundColor(node.pageIndex == currentPageIndex ? .accentBrown : .secondary)
                                
                                Text(node.title)
                                    .font(.subheadline)
                                    .fontWeight(node.pageIndex == currentPageIndex ? .bold : .regular)
                                    .foregroundColor(node.pageIndex == currentPageIndex ? .accentBrown : Color.textPrimary)
                                    .lineLimit(2)
                                
                                Spacer()
                                
                                Text("p. \(node.pageIndex + 1)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectPage(node.pageIndex)
                            }
                        }
                    }
                }
                .listStyle(SidebarListStyle())
                
            case .pages:
                List(0..<document.pageCount, id: \.self) { pageIndex in
                    HStack {
                        Text("Page \(pageIndex + 1)")
                            .font(.subheadline)
                            .fontWeight(pageIndex == currentPageIndex ? .bold : .regular)
                            .foregroundColor(pageIndex == currentPageIndex ? .accentBrown : Color.textPrimary)
                        
                        Spacer()
                        
                        if pageIndex == currentPageIndex {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentBrown)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectPage(pageIndex)
                    }
                }
                .listStyle(SidebarListStyle())
                
            case .bookmarks:
                List {
                    if bookBookmarks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "star")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("No bookmarks saved")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Click the star button (⌘B) in toolbar to bookmark pages")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(bookBookmarks) { bm in
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                                
                                Text("Page \(bm.pageIndex + 1)")
                                    .font(.subheadline)
                                    .foregroundColor(Color.textPrimary)
                                
                                Spacer()
                                
                                Button(action: {
                                    bookmarkService.removeBookmark(id: bm.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectPage(bm.pageIndex)
                            }
                        }
                    }
                }
                .listStyle(SidebarListStyle())
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadTableOfContents()
        }
    }
    
    private func loadTableOfContents() {
        if let outline = document.outlineRoot {
            let tree = buildTree(outline)
            if !tree.isEmpty {
                self.outlineTree = tree
                return
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var headings: [OutlineNode] = []
            let total = min(document.pageCount, 150)
            
            for i in 0..<total {
                if let page = document.page(at: i), let text = page.string {
                    let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                    for line in lines.prefix(15) {
                        let upper = line.uppercased()
                        if upper.hasPrefix("CHAPTER") || upper.hasPrefix("PART") || upper.hasPrefix("BOOK") || upper.hasPrefix("SECTION") || upper.hasPrefix("BAB") {
                            headings.append(OutlineNode(title: line.capitalized, pageIndex: i))
                            break
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.detectedHeadings = headings
            }
        }
    }
    
    private func buildTree(_ outline: PDFOutline) -> [OutlineNode] {
        var nodes: [OutlineNode] = []
        for i in 0..<outline.numberOfChildren {
            if let child = outline.child(at: i) {
                var pageIndex = 0
                if let dest = child.destination, let page = dest.page {
                    pageIndex = document.index(for: page)
                }
                let children = buildTree(child)
                nodes.append(OutlineNode(
                    title: child.label ?? "Untitled",
                    pageIndex: pageIndex,
                    children: children.isEmpty ? nil : children
                ))
            }
        }
        return nodes
    }
}
