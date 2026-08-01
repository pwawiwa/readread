# ReadRead — Native macOS E-Reader & Offline Translator 📖

A modern, high-performance native macOS e-reader built with **Swift**, **SwiftUI**, and **PDFKit**. Built specifically for comfortable reading, page-by-page pagination, adaptive page rotation, and instant text & sentence translation between **English** and **Indonesian**.

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

---

## ✨ Features

- 📄 **Native High-Fidelity Rendering**: Built on Quartz 2D & PDFKit (the same rendering engine as Preview.app). Renders text, vector graphics, and images natively without image-overlay text parsing.
- 📖 **Page-by-Page Pagination**: Single page mode, no continuous scrolling — designed for comfortable, focused reading.
- 🔠 **Instant Text & Sentence Translation**: Block any word or entire sentence to smoothly pop up a floating translation box.
  - **Define Mode**: Queries Apple macOS native system dictionaries (`DCSCopyTextDefinition`) for rich offline definitions.
  - **Translate Mode**: Translates English to Indonesian (and vice-versa) with offline dictionary lookup, stemming, and dynamic online fallback.
- 🔄 **Adaptive Page Rotation**: Rotate pages 90° clockwise (via toolbar or `⌘R`) for vertical screen reading. Text selection and translation popovers adaptively follow the rotated canvas coordinates.
- 🎨 **Comfortable Paper Themes**: Broken white (`#FAF7F0`), sepia, cream, and dark charcoal paper colors designed for minimal eye strain.
- 📌 **Collapsible Sidebar Drawer**: Quick navigation through:
  - **Chapters & Headings**: PDF Outline or auto-detected chapter headings.
  - **Pages Grid**: Direct jump to any page in the book.
  - **Bookmarks List**: View, manage, and jump to starred pages.
- 📚 **Library & Reading History**: Auto-saves reading progress, last page, rotation, and zoom level across app launches using security-scoped bookmarks.
- 📂 **Multi-Format & Drag-and-Drop Import**: Supports PDF, EPUB, TXT, RTF, and HTML with drag-and-drop batch importing.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `←` / `→` | Previous / Next Page |
| `↑` / `↓` | Previous / Next Page |
| `Space` | Next Page |
| `⌘ +` / `⌘ -` | Zoom In / Zoom Out |
| `⌘ R` | Rotate Page 90° |
| `⌘ T` | Toggle Contents & Bookmarks Sidebar |
| `⌘ B` | Bookmark Current Page |
| `⌘ F` | Find Text in Document |
| `⌘ O` | Open File Panel |

---

## 🏗 Architecture & Project Structure

```
Readread/
├── Package.swift                           # SPM Manifest (macOS 13.0+)
├── Readread.app/                           # Native standalone macOS app bundle
├── Sources/Readread/
│   ├── ReadreadApp.swift                   # App entry point & window commands
│   ├── Models/
│   │   ├── Book.swift                      # BookItem model with format support
│   │   └── ReadingHistory.swift            # Reading history & security-scoped bookmarks
│   ├── Views/
│   │   ├── HomeView.swift                  # Library grid with PDF cover previews & drop target
│   │   ├── ReaderView.swift                # Reader container & keyboard monitors
│   │   ├── PDFReaderView.swift             # PDFKit NSViewRepresentable wrapper & Y-coordinate transforms
│   │   ├── TranslationPopover.swift        # Floating translation box with auto-clamping
│   │   ├── TableOfContentsView.swift       # Collapsible sidebar (Chapters, Pages, Bookmarks)
│   │   └── SettingsView.swift              # App settings & dictionary preferences
│   ├── Services/
│   │   ├── DictionaryService.swift         # Hybrid offline EN-ID JSON & system dictionary engine
│   │   └── BookmarkService.swift           # Page bookmark management
│   ├── Extensions/
│   │   ├── ColorTheme.swift                # Dynamic Light/Dark paper color system
│   │   └── PDFViewExtensions.swift         # PDFView helper extensions
│   └── Resources/
│       ├── en_id_dictionary.json           # Offline English→Indonesian dictionary
│       └── id_en_dictionary.json           # Offline Indonesian→English dictionary
```

---

## 🚀 How to Build & Run

### Method 1: Launch Standalone App Bundle
Double-click `Readread.app` inside the project root folder or copy it to your `/Applications` folder:
```bash
open Readread.app
```

### Method 2: Command Line (SPM)
```bash
swift build
swift run Readread
```

### Method 3: Xcode
```bash
open Package.swift
```
Press `⌘R` in Xcode to build and run.

---

## 📄 License

Distributed under the MIT License.
