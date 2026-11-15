import PDFKit
import SwiftUI

struct OutlineNode: Identifiable, Equatable {
    let id: String
    let title: String
    let pageIndex: Int?
    var children: [OutlineNode]?
}

@MainActor
enum OutlineBuilder {
    static func buildOutline(from document: PDFDocument) -> [OutlineNode] {
        guard let root = document.outlineRoot else { return [] }
        return buildNodes(from: root, in: document, pathPrefix: "root")
    }

    private static func buildNodes(
        from outline: PDFOutline,
        in document: PDFDocument,
        pathPrefix: String
    ) -> [OutlineNode] {
        var nodes: [OutlineNode] = []
        for i in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: i) else { continue }
            let nodePath = "\(pathPrefix).\(i)"
            let resolvedPage = resolvePageIndex(for: child, in: document)
            let childNodes = buildNodes(from: child, in: document, pathPrefix: nodePath)

            // Every sidebar item must have a real destination (direct or via first child).
            let effectivePage = resolvedPage ?? childNodes.first(where: { $0.pageIndex != nil })?.pageIndex
            guard effectivePage != nil || !childNodes.isEmpty else { continue }

            let rawLabel = child.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (rawLabel?.isEmpty == false) ? rawLabel! : "Untitled Section"

            nodes.append(
                OutlineNode(
                    id: nodePath,
                    title: title,
                    pageIndex: effectivePage,
                    children: childNodes.isEmpty ? nil : childNodes
                )
            )
        }
        return nodes
    }

    private static func resolvePageIndex(for outline: PDFOutline, in document: PDFDocument) -> Int? {
        let targetPage: PDFPage?
        if let destPage = outline.destination?.page {
            targetPage = destPage
        } else if let goToAction = outline.action as? PDFActionGoTo {
            targetPage = goToAction.destination.page
        } else {
            targetPage = nil
        }

        guard let page = targetPage else { return nil }
        let index = document.index(for: page)
        guard index != NSNotFound, index >= 0, index < document.pageCount else { return nil }
        return index
    }

    static func detectHeadings(in document: PDFDocument, maxPages: Int = 150) -> [OutlineNode] {
        var headings: [OutlineNode] = []
        let total = min(document.pageCount, maxPages)

        for i in 0..<total {
            guard let page = document.page(at: i), let text = page.string else { continue }
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for line in lines.prefix(15) {
                let upper = line.uppercased()
                if upper.hasPrefix("CHAPTER")
                    || upper.hasPrefix("PART")
                    || upper.hasPrefix("BOOK")
                    || upper.hasPrefix("SECTION")
                    || upper.hasPrefix("BAB") {
                    headings.append(
                        OutlineNode(
                            id: "heading.\(i)",
                            title: line,
                            pageIndex: i,
                            children: nil
                        )
                    )
                    break
                }
            }
        }
        return headings
    }
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
    @State private var loadedDocumentID: ObjectIdentifier?

    enum SidebarTab: String, CaseIterable {
        case chapters = "Chapters"
        case pages = "Pages"
        case bookmarks = "Bookmarks"
    }

    var displayNodes: [OutlineNode] {
        !outlineTree.isEmpty ? outlineTree : detectedHeadings
    }

    var bookBookmarks: [PageBookmark] {
        bookmarkService.bookmarks(for: bookId)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("Contents")
                        .font(.headline)
                        .foregroundColor(Color.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Picker("Contents Section", selection: $selectedTab) {
                    ForEach(SidebarTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)
            .background(Color.sidebarBg)

            Divider()

            switch selectedTab {
            case .chapters:
                if displayNodes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No Table of Contents")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Color.textPrimary)
                        Text("This document has no embedded outline. Switch to Pages to jump directly.")
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(displayNodes, children: \.children) { node in
                        if let pageIndex = node.pageIndex {
                            Button(action: { onSelectPage(pageIndex) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: pageIndex == currentPageIndex ? "bookmark.fill" : "doc.text")
                                        .font(.caption)
                                        .foregroundColor(pageIndex == currentPageIndex ? .accentBrown : .secondary)

                                    Text(node.title)
                                        .font(.subheadline)
                                        .fontWeight(pageIndex == currentPageIndex ? .semibold : .regular)
                                        .foregroundColor(pageIndex == currentPageIndex ? .accentBrown : Color.textPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    Spacer()

                                    Text("p. \(pageIndex + 1)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(Color.textSecondary)
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.sidebar)
                }

            case .pages:
                List(0..<document.pageCount, id: \.self) { pageIndex in
                    Button(action: { onSelectPage(pageIndex) }) {
                        HStack {
                            Text("Page \(pageIndex + 1)")
                                .font(.subheadline)
                                .fontWeight(pageIndex == currentPageIndex ? .semibold : .regular)
                                .foregroundColor(pageIndex == currentPageIndex ? .accentBrown : Color.textPrimary)

                            Spacer()

                            if pageIndex == currentPageIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentBrown)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)

            case .bookmarks:
                if bookBookmarks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "star")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No Bookmarks Yet")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Color.textPrimary)
                        Text("Use the Bookmark button or press Command+B to save your place.")
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(bookBookmarks) { bm in
                            HStack {
                                Button(action: { onSelectPage(bm.pageIndex) }) {
                                    HStack {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.accentBrown)
                                            .font(.caption)

                                        Text("Page \(bm.pageIndex + 1)")
                                            .font(.subheadline)
                                            .foregroundColor(Color.textPrimary)

                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    bookmarkService.removeBookmark(id: bm.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove Bookmark")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
        }
        .background(Color.sidebarBg)
        .onAppear {
            loadTableOfContentsIfNeeded()
        }
        .onChange(of: ObjectIdentifier(document)) { _ in
            loadTableOfContentsIfNeeded()
        }
    }

    private func loadTableOfContentsIfNeeded() {
        let docID = ObjectIdentifier(document)
        guard loadedDocumentID != docID else { return }
        loadedDocumentID = docID

        let tree = OutlineBuilder.buildOutline(from: document)
        if !tree.isEmpty {
            outlineTree = tree
            detectedHeadings = []
        } else {
            outlineTree = []
            detectedHeadings = OutlineBuilder.detectHeadings(in: document)
        }
    }
}
