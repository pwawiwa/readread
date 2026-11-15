# Readread design direction

Use this direction when implementing or reviewing Readread's native macOS interface. The user selected an editorial reading room: a warmer palette, book-focused typography, and a more spacious library. AntiSlop applies during implementation.

## Design read

Readread is a native macOS reading room for sustained book reading. Warm paper, book typography, and spacious shelves give the library its character; the document remains the reader's focal point.

The design dials are **ENERGY 1 / RHYTHM 2 / MOTION 1**. The interface is calm, uses consistent layouts with deliberate differences between library and reader, and relies on hover and focus feedback rather than decorative animation.

## Palette and typography

The interaction review uses Apple's [toolbar guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars) for grouping common actions and menu equivalents, [popover guidance](https://developer.apple.com/design/human-interface-guidelines/popovers) for compact selection annotations and dismissal, and [progress guidance](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) for honest loading feedback. These guide native behavior; the editorial palette and typography come from the owner's direction.

These are proposed light-appearance tokens. Verify contrast in rendered controls before delivery and define coordinated dark-appearance values.

| Token | Proposed value | Purpose |
| --- | --- | --- |
| Canvas | `#F5F0E7` | Warm surrounding space separates the book from application chrome. |
| Paper | `#FCFAF5` | A quiet surface supports book covers and annotations. |
| Ink | `#2F2B25` | Strong text contrast supports sustained reading. |
| Secondary ink | `#6B6258` | Metadata remains readable without competing with titles. |
| Accent | `#8A4B2C` | Restrained rust marks the primary action and active state. |

Use macOS system serif for the library title and book names. It connects the interface to editorial typography without requiring a downloaded font. Use system sans for controls, status, and metadata so native interactions remain easy to scan. Keep system semantic colors for native control states where they provide better accessibility.

The reading background changes the space around a PDF. It must not imply that the original PDF content has been recolored. Name the preference accordingly unless page tinting is implemented and verified.

## Library composition

The library helps you recognize a book and resume reading. Give actual covers and book titles visual priority. Use roughly 28 to 32 points of outer spacing and 24 to 28 points between shelf items, adapting to available width.

Use real PDF thumbnails. If a cover is unavailable, show the title and existing file-type symbol as an honest fallback. A modest cover shadow can distinguish the physical page from the canvas; avoid layering a second floating card around every cover.

Each book presents its title, accurate page status, and meaningful date. Unknown page counts stay unknown. An import timestamp must not appear as a successful-open timestamp. Counts shown in the library must derive from the actual collection.

Keep the established Library-to-Reader navigation and settings entry. Make each book keyboard-operable with a native button and visible focus. Provide an explicit **Import Books** action, drag-target feedback, and a working removal action. The empty state explains how to add the first book. Errors name the affected file and the available recovery action.

## Reader composition

The page is the dominant element. Warm surrounding space and restrained controls support reading without competing with the document.

Group toolbar actions by task: library and contents; page and zoom; find and bookmarks. Keep secondary actions in an appropriate menu when necessary to fit the minimum window width. Preserve discoverability and keyboard shortcuts. Avoid several visually similar fit buttons when a clear zoom menu can expose the same actions.

Show actual current and total pages. Disable document-dependent controls during loading and failure. Contents use native lists and disclosures for nested chapters. Every sidebar item must have a real destination.

Loading, unavailable, corrupt, and password-protected states belong in the reader content area. Each state explains what happened and offers an action that works. Page entry must show invalid input; search must show matches or a clear no-result state.

## Selection annotation

The translation popup is a compact paper annotation anchored to selected text. Use serif for the selected word and readable sans for its result. A single subtle shadow communicates its position above the page.

Keep **Translate** and **Define** as a native segmented control. Display the correct language direction. Distinguish offline dictionary output, online translation, definitions, and word-by-word approximation with quiet, accurate text.

Constrain popup width and height to the available PDF viewport. Choose placement above or below the selection and keep all edges visible. Long results scroll. Provide an accessible close button and Escape dismissal. Do not animate the popup with scale or bounce effects.

## Decision record

The major choices serve these purposes:

| Decision | Reason |
| --- | --- |
| Warm paper surfaces | Reduce visual competition with the book and express the selected reading-room mood. |
| Serif title typography | Establish a repeated editorial identity tied to reading. |
| Sans controls and metadata | Preserve the clarity and familiarity of native macOS tools. |
| Spacious book shelves | Separate titles and support recognition through their real covers. |
| Actual covers and honest fallbacks | Identify books without inventing artwork or metadata. |
| Limited rust accent | Direct attention to meaningful actions and state. |
| Restrained popup elevation | Distinguish a temporary annotation from document content. |
| Minimal motion | Keep sustained reading and selection stable. |

## Verification requirements

Inspect light and dark appearance, the minimum supported window size, normal window size, long titles, many books, and empty/loading/error states. Check text contrast on the actual rendered surfaces. Verify every control with mouse and keyboard, including visible focus and Escape dismissal.

Do not invent a logo, app icon, cover art, statistics, or content. Existing real document covers and native file-type symbols are sufficient for this scope. Record the final AntiSlop gate and element-by-element click results in the implementation verification record; this design direction is not a claim that those checks have passed.
