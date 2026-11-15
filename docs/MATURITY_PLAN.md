# Readread maturity implementation plan

Use this plan to coordinate implementation and verification across three agents. It records source-level defects and proposed contracts for the native macOS reader. It does not claim that the repairs or runtime checks have passed. The visual direction is defined in [Design direction](../DESIGN.md).

## File ownership

Each agent edits only its assigned files in its isolated output directory. The integrating agent reviews and combines the results.

| Owner | Files and responsibilities |
| --- | --- |
| A: Library and persistence | `Models/Book.swift`, `Models/ReadingHistory.swift`, `Services/BookmarkService.swift`, `Views/HomeView.swift`, `Views/SettingsView.swift`, `Extensions/ColorTheme.swift`, `ReadreadApp.swift`, library and persistence tests |
| B: Reader and document loading | `Views/ReaderView.swift`, `Views/PDFReaderView.swift`, `Views/TableOfContentsView.swift`, `Extensions/PDFViewExtensions.swift`, document loader and reader state types, reader and loader tests |
| C: Translation and packaging | `Services/DictionaryService.swift`, `Views/TranslationPopover.swift`, translation state types, `build_app.sh`, translation tests |
| Integrator | `Package.swift`, shared fixtures, documentation, cross-stream integration, packaged launch, GUI verification, final AntiSlop delivery gate |

Paths in this table are relative to `Sources/Readread`, except `Package.swift` and `build_app.sh`. Test files belong under `Tests`. Coordinate any shared API change before editing another owner's caller.

## Source-level findings

These findings come from the source inspected before implementation. Reproduce the corresponding runtime symptoms and preserve the observations before fixing them.

| Area | Fault in the inspected source | Observable consequence to verify |
| --- | --- | --- |
| Startup | The packaging script puts the resource bundle in `Contents/Resources`; the generated `Bundle.module` accessor searches the app root and an absolute build path. | A relocated app can fail when its developer build directory is unavailable. |
| Packaging | The script continues after failed commands and prints success unconditionally. | An outdated or incomplete app can appear to be a successful build. |
| Import | Existing-book import defaults `lastPage` to zero; unsupported extensions default to PDF. | Reimport can reset progress and add unreadable files. |
| History | The reader records page count only after page, zoom, or rotation changes. | A book opened without a state change can retain an unknown count. |
| Library | Unknown page counts render as one; import timestamps render as opened timestamps. | The library presents unsupported progress and activity claims. |
| File access | URL resolution starts security-scoped access, and multiple callers start access again without balancing it. | Resource access leaks across thumbnails and reader lifetimes. |
| Loading | Failed resolution or parsing leaves `pdfDocument` unset with no failure state. | Missing and corrupt files leave an indefinite loading indicator. |
| Commands | Zoom, rotate, find, and bookmark menu notifications have no reader subscribers. Fit commands discover the PDF view through the first responder. | Menu actions do nothing, and fit actions depend on focus. |
| Keyboard | A global event monitor consumes arrows and Space regardless of the focused control. | Typing and editing search or page fields can navigate the document. |
| PDF bridge | The coordinator retains the initial representable value; rotation overwrites intrinsic page rotation; scale updates travel asynchronously in both directions. | Callbacks become stale, original orientation changes, and zoom/page updates can race. |
| Selection | The selection rectangle contains a midpoint as its origin and is rendered in a different container coordinate space. | The translation popup drifts when search, layout, scale, or rotation changes. |
| Translation | A mutable cache is accessed from multiple queues; network calls block on a semaphore; old requests can update the popup after a new selection. | Translation can block, race, or display a result for the wrong word. |
| Translation semantics | String contents determine success; system definitions count as translations; same-language requests use a bilingual dictionary. | The displayed result can have the wrong meaning or language. |
| Search | The search field is never connected to document search. | Find has no document effect. |
| Contents | Nested outline nodes are built but only top-level nodes are displayed. | Nested chapters are inaccessible. |
| Text formats | A fixed-height text view is captured as PDF; the constructed print operation never runs. | Long text can be clipped to a single page. |
| EPUB | Extracted HTML files are sorted by filename instead of the publication spine; extraction status and temporary cleanup are ignored. | Chapters can appear in the wrong order, and corrupt input can look like an empty book. |

## Shared implementation contracts

Agree these contracts before the workers change public signatures:

1. Keep the existing `BookItem` fields readable from saved history. Decode missing newer fields with compatible defaults. Validate page, scale, and rotation values at the persistence boundary. Represent unknown counts honestly.
2. Give `ReadingHistoryStore` and `BookmarkService` injectable `UserDefaults` instances for isolated tests. Keep progress updates separate from importing and successfully opening a book.
3. Make `addOrUpdate` preserve progress unless the caller explicitly supplies a replacement. Return the imported `BookItem` so the app can select its ID directly. Report invalid input with a typed error. A changed signature must be coordinated with every caller.
4. Make `resolveURL(for:)` resolve only. The operation that reads a file owns its paired security-scoped access. Refresh stale bookmarks and handle missing files explicitly.
5. B provides a shared `DocumentLoader` interface, initially `@MainActor static func load(url: URL, format: BookItem.FileFormat) throws -> PDFDocument`. If conversion needs an asynchronous interface, B informs A before implementation. Avoid duplicate document conversion in import and reader code.
6. Preserve the public `TranslationPopover(selectedText:selectionRect:isPresented:)` initializer unless B and C agree otherwise. The selection rectangle is a genuine rectangle in the PDF container's SwiftUI coordinates. Attach the overlay directly to that container.
7. Interpret saved rotation as a document-level offset applied to each page's original intrinsic rotation. A full four-rotation cycle restores the original orientation. Never accumulate the offset by rereading already-mutated rotation values.
8. Route reader commands to the intended reader and its own PDF view. Do not discover the target through the first responder. Refresh coordinator inputs on every representable update and remove observers during teardown.
9. Give translation results explicit provenance and failure states. Use cancellable asynchronous network requests and isolated cache access. A request key includes normalized text, mode, source language, and target language; an older request cannot replace a newer result.
10. Preserve or explicitly coordinate `DictionaryServiceWrapper`, which is declared in the app file but consumed by the translation popup. A owns the declaration; C owns the service API.

## Implement in stages

### Stage 1: Establish launch and data safety

1. Record the baseline build result and startup behavior.
2. Add the Swift package test target and isolated fixture support.
3. Make packaging fail on errors and place resources where the runtime actually resolves them.
4. Verify a packaged app outside the repository without relying on the absolute build fallback.
5. Separate reader loading, loaded, and failed states. Show actionable errors for missing, unreadable, corrupt, and password-protected input.
6. Validate imports, deduplicate canonical file locations, preserve existing progress, and support application file-open events.
7. Preserve corrupt persisted bytes for recovery instead of silently replacing them with an empty history.
8. Record actual page count immediately after a successful load and constrain restored page indices to that document.

### Stage 2: Repair reader state and commands

1. Remove the global navigation event monitor. Handle navigation keys only when the PDF view has focus, with appropriate modifier handling.
2. Connect all existing application commands through one reader command path. Disable commands that have no active document.
3. Track manual zoom, fit-page, and fit-width behavior explicitly. Recalculate fit modes after viewport, sidebar, page, and rotation changes.
4. Apply document rotation offsets without changing original PDF orientation. Keep the current page stable through rotation and zoom.
5. Refresh the PDF coordinator and clean up observers. Prevent obsolete queued notifications from overwriting newer state.
6. Position selection annotations in the same coordinate space as the rendered PDF. Clear or reposition them after relevant document changes.
7. Make page entry validation visible and keep ordinary text editing independent of page navigation.

### Stage 3: Make selection translation dependable

1. Normalize whitespace and punctuation without destroying the selected text shown to the reader.
2. Keep offline dictionaries immutable and isolate mutable caches.
3. Replace semaphore-based networking with cancellable async requests. Validate HTTP and provider status, encode queries safely, and expose timeout and unavailable states.
4. Distinguish dictionary translations, online translations, definitions, and approximate word-by-word output. Do not infer success from translated strings.
5. Define same-language behavior explicitly. Define mode must not unexpectedly block the interface on a network fallback.
6. Debounce changing drag selections, cancel superseded work, and apply results only to the current request key.
7. Honor automatic-selection settings. Support Escape and close-button dismissal without immediately reopening from stale callbacks.
8. Use correct language codes, including `id` for Indonesian.

### Stage 4: Complete the advertised feature set

1. Connect search to document matches, highlighting, next and previous navigation, count, and an empty-result state. Search-generated selection must not accidentally launch translation.
2. Display nested PDF outlines and resolve supported outline destinations. Keep heading detection from racing shared PDF state.
3. Verify bookmark toggling, persistence, page navigation, and cleanup after library removal.
4. Paginate complete TXT, RTF, and HTML content with selectable text. An ending sentinel in a long fixture must remain searchable.
5. Read EPUB container metadata and publication spine order. Validate extraction, constrain archive paths, clean up temporary files, and report unsupported or corrupt books explicitly.
6. Apply the approved editorial design to complete states, including errors, loading, long titles, and an empty library.

## Behavioral verification matrix

Use concrete fixtures and assertions on observable results. A test should fail when behavior breaks and survive internal refactoring.

| Area | Required cases |
| --- | --- |
| History | Fresh storage; older records with missing fields; corrupt storage preserved; persistence round trip; repeated import keeps the same ID and page; successful first load stores actual count; shortened PDF restores a valid page. |
| Import | Supported files; unsupported extension; unreadable and corrupt file; duplicate canonical URL; mixed batch success and failure; missing file after restart. |
| Progress | Unknown count does not display `1 of 1`; initial import does not claim a successful open; displayed page and persisted page agree. |
| Bookmarks | Add is idempotent; toggle removes; storage round trip; page jump; removing a book removes its bookmarks. |
| PDF state | Three-page fixture with unique text and one intrinsically rotated page; next/previous and jump; manual scale; fit with changed viewport; four rotations restore originals; restart preserves reader state. |
| Document loading | Long text ending sentinel survives pagination; RTF and HTML remain selectable; EPUB filenames conflict with spine order but rendered content follows the spine; malformed archive fails explicitly. |
| Translation | Known English and Indonesian words; punctuation; whitespace; same-language request; definition distinction; offline miss; online success; HTTP/provider error; timeout; cancellation; delayed result A cannot replace selection B. |
| Contents and search | Nested outline; destination navigation; no outline; multiple query matches; previous/next; no result; search selection does not invoke translation. |

Use a separate defaults suite and temporary directories for tests. Do not erase the user's real library to obtain a clean fixture.

## Verify the running app

The integrator performs these checks on the actual packaged artifact and records the observed result for each control:

1. Launch the relocated app, verify its process and visible window, and inspect relevant crash or error output.
2. Import through the toolbar, File menu, drag and drop, and application file-open handling. Verify a mixed batch reports partial failure honestly.
3. Navigate the PDF through buttons, arrows, Space, slider, page entry, contents, and bookmarks.
4. Type spaces and move the caret in search and page fields. Confirm the document stays on its page.
5. Exercise zoom presets and both fit modes while toolbar controls have focus. Resize the window and open the sidebar.
6. Rotate through all four orientations. Select text near each viewport edge and verify popup bounds and result identity.
7. Select words rapidly, change translation mode and language, test offline behavior, dismiss the popup, and disable automatic selection translation.
8. Search forward and backward, clear the query, and confirm result highlighting and counts.
9. Return to the library, inspect actual progress, reopen the book, quit, and relaunch. Confirm restoration.
10. Exercise missing, corrupt, locked, long-text, and ordered-EPUB fixtures.
11. Inspect minimum supported window size, normal size, light appearance, dark appearance, long book names, keyboard focus, and every empty/loading/error state.

Capture screenshots of critical visual states and record the artifact used. A successful compilation or an agent's self-report does not establish these results.

## Completion criteria

Every repaired feature needs passing behavioral checks and direct verification where its outcome is visible. Return a failure to the responsible owner with input, action, observed result, expected result, and relevant logs. After a repair, rerun the failed flow and adjacent state transitions.

The integrator runs the AntiSlop delivery gate personally and keeps its evidence with the verification record. Mark web-only checks as inapplicable to this native application; verify equivalent native accessibility and layout behavior. Update documentation to describe only demonstrated behavior. Run the ancestry-required graph update after code changes when the tool is available, and report any unavailable verification honestly.
