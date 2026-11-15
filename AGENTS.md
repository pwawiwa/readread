# Readread development

Read `DESIGN.md` before changing the interface and `pstack-models.md` before delegating work. The product is a native macOS book reader with automatic English/Indonesian translation for selected text.

Use the installed `antislop` core and UI skills during UI work. This project uses during mode and the editorial reading-room direction recorded in `DESIGN.md`. Use pstack's `principle-test-behavior-not-implementation`, `principle-fix-root-causes`, and `principle-prove-it-works` for repairs and verification.

Use Astra for planning when requested, then the cheaper implementation and verification models in `pstack-models.md`. Give parallel writers separate workspaces and integrate only their owned files. Review the combined diff and run the integrated checks.

Run `swift test` for behavioral regressions and `./build_app.sh` for the app bundle. Verify the packaged app outside the source tree. Exercise changed controls in the real macOS app and record evidence; compilation does not establish that a control works. Do not claim unobserved UI checks passed.

Keep reading position distinct from reading completion. Unknown page counts stay unknown. Preserve a book's saved position when importing it again. Errors must provide a useful next action, and translation results must identify their source.

Use the technical-documentation skill when updating developer documentation.
