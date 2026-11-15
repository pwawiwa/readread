import SwiftUI

struct TranslationPopover: View {
    let selectedText: String
    let selectionRect: CGRect
    @Binding var isPresented: Bool

    @EnvironmentObject var dictionaryServiceWrapper: DictionaryServiceWrapper
    @AppStorage("sourceLanguage") private var sourceLangId: String = DictionaryService.Language.english.rawValue
    @AppStorage("targetLanguage") private var targetLangId: String = DictionaryService.Language.indonesian.rawValue

    @StateObject private var controller = TranslationController()
    @State private var selectedMode: DictionaryService.TranslationMode = .translate

    var sourceLanguage: DictionaryService.Language {
        DictionaryService.Language(rawValue: sourceLangId) ?? .english
    }

    var targetLanguage: DictionaryService.Language {
        DictionaryService.Language(rawValue: targetLangId) ?? .indonesian
    }

    var body: some View {
        GeometryReader { geo in
            let layout = Self.computeLayout(selectionRect: selectionRect, viewportSize: geo.size)
            let displaySelection = DictionaryService.normalizeDisplayText(selectedText)

            VStack(alignment: .leading, spacing: 10) {
                // Header: segmented control, language direction, accessible close button
                HStack(spacing: 8) {
                    Picker("Lookup mode", selection: $selectedMode) {
                        ForEach(DictionaryService.TranslationMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 146)

                    Spacer(minLength: 4)

                    if selectedMode == .translate {
                        Button(action: swapLanguages) {
                            HStack(spacing: 4) {
                                Text(sourceLanguage.shortLabel)
                                    .font(.caption2.weight(.semibold))
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 9, weight: .medium))
                                Text(targetLanguage.shortLabel)
                                    .font(.caption2.weight(.semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentBrown.opacity(0.14))
                            .foregroundColor(Color.accentBrown)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Swap \(sourceLanguage.rawValue) and \(targetLanguage.rawValue)")
                    }

                    Button(action: dismissPopover) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close translation")
                }

                Divider()

                // Scrollable selected text + translation/definition body
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displaySelection.isEmpty ? selectedText : displaySelection)
                            .font(.system(.title3, design: .serif).weight(.medium))
                            .foregroundColor(Color.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        resultBody
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
            }
            .padding(14)
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            .background(Color.paperWhite)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
            .position(x: layout.center.x, y: layout.center.y)
            .onAppear {
                controller.resetForPresentation()
                triggerLookup(immediate: true)
            }
            .onDisappear {
                controller.dismiss()
            }
            .onExitCommand {
                dismissPopover()
            }
            .onChange(of: selectedText) { _ in
                triggerLookup(immediate: false)
            }
            .onChange(of: selectedMode) { _ in
                triggerLookup(immediate: true)
            }
            .onChange(of: sourceLangId) { _ in
                triggerLookup(immediate: true)
            }
            .onChange(of: targetLangId) { _ in
                triggerLookup(immediate: true)
            }
        }
    }

    @ViewBuilder
    private var resultBody: some View {
        if controller.isLoading && controller.result == nil {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Looking up…")
                    .font(.subheadline)
                    .foregroundColor(Color.textSecondary)
            }
            .padding(.vertical, 4)
        } else if let result = controller.result {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(result.source.displayLabel)
                        .font(.caption)
                        .foregroundColor(Color.textSecondary)

                    if controller.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                ForEach(Array(result.translations.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .top, spacing: 6) {
                        if result.translations.count > 1 {
                            Text("•")
                                .foregroundColor(Color.accentBrown)
                                .font(.body.weight(.semibold))
                        }
                        Text(entry)
                            .font(.body)
                            .foregroundColor(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else if let failure = controller.failure {
            VStack(alignment: .leading, spacing: 6) {
                Text(failure.userMessage)
                    .font(.subheadline)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .timeout = failure {
                    Button("Try Again") {
                        triggerLookup(immediate: true)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(Color.accentBrown)
                    .buttonStyle(.plain)
                } else if case .unavailable = failure {
                    Button("Try Again") {
                        triggerLookup(immediate: true)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(Color.accentBrown)
                    .buttonStyle(.plain)
                }
            }
        } else {
            Text("No matching entry was found.")
                .font(.subheadline)
                .foregroundColor(Color.textSecondary)
        }
    }

    private func swapLanguages() {
        let previousSource = sourceLangId
        sourceLangId = targetLangId
        targetLangId = previousSource
    }

    private func dismissPopover() {
        controller.dismiss()
        isPresented = false
    }

    private func triggerLookup(immediate: Bool) {
        guard isPresented else { return }
        controller.requestLookup(
            selectedText: selectedText,
            mode: selectedMode,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            service: dictionaryServiceWrapper.service,
            immediate: immediate
        )
    }

    static func computeLayout(selectionRect: CGRect, viewportSize: CGSize) -> (size: CGSize, center: CGPoint) {
        let edgePadding: CGFloat = 12
        let gap: CGFloat = 10

        let maxWidth = max(180, viewportSize.width - edgePadding * 2)
        let width = min(340, maxWidth)

        let maxHeight = max(120, viewportSize.height - edgePadding * 2)
        let height = min(250, max(160, min(maxHeight, viewportSize.height * 0.42)))

        let minCenterX = width / 2 + edgePadding
        let maxCenterX = max(minCenterX, viewportSize.width - width / 2 - edgePadding)
        let centerX = clamp(selectionRect.midX, min: minCenterX, max: maxCenterX)

        let minCenterY = height / 2 + edgePadding
        let maxCenterY = max(minCenterY, viewportSize.height - height / 2 - edgePadding)

        let spaceAbove = selectionRect.minY - gap - edgePadding
        let preferredCenterY: CGFloat
        if spaceAbove >= height {
            preferredCenterY = selectionRect.minY - gap - height / 2
        } else {
            preferredCenterY = selectionRect.maxY + gap + height / 2
        }
        let centerY = clamp(preferredCenterY, min: minCenterY, max: maxCenterY)

        return (CGSize(width: width, height: height), CGPoint(x: centerX, y: centerY))
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        if maxValue < minValue { return minValue }
        return Swift.min(Swift.max(value, minValue), maxValue)
    }
}
