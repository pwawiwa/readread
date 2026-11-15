import Foundation
import Combine

@MainActor
final class TranslationController: ObservableObject {
    @Published private(set) var result: DictionaryService.TranslationResult?
    @Published private(set) var failure: DictionaryService.TranslationFailure?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var currentRequestKey: DictionaryService.RequestKey?
    @Published private(set) var isDismissed: Bool = false

    private var activeTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64

    init(debounceNanoseconds: UInt64 = 180_000_000) {
        self.debounceNanoseconds = debounceNanoseconds
    }

    func requestLookup(
        selectedText: String,
        mode: DictionaryService.TranslationMode,
        sourceLanguage: DictionaryService.Language,
        targetLanguage: DictionaryService.Language,
        service: DictionaryService,
        immediate: Bool = false
    ) {
        activeTask?.cancel()
        activeTask = nil
        isDismissed = false

        let normalized = DictionaryService.normalizeForLookup(selectedText)
        guard !normalized.isEmpty else {
            currentRequestKey = nil
            result = nil
            failure = .emptySelection
            isLoading = false
            return
        }

        let key = DictionaryService.RequestKey(
            normalizedText: normalized,
            mode: mode,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
        currentRequestKey = key

        if mode == .define {
            isLoading = false
            let outcome = service.define(text: selectedText, language: sourceLanguage)
            apply(outcome: outcome, for: key)
            return
        }

        // Translate mode: show instant offline result if available
        let offlineOutcome = service.lookupOffline(text: selectedText, from: sourceLanguage, to: targetLanguage)
        switch offlineOutcome {
        case .success(let offlineResult):
            self.result = offlineResult
            self.failure = nil
            // Same-language or single-word offline match needs no online request
            if offlineResult.source == .sameLanguage || !normalized.contains(" ") {
                self.isLoading = false
                return
            }
        case .failure:
            self.result = nil
            self.failure = nil
        }

        self.isLoading = true
        let delay = immediate ? 0 : debounceNanoseconds

        activeTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }

            let outcome = await service.translate(
                text: selectedText,
                from: sourceLanguage,
                to: targetLanguage,
                allowOnline: true
            )

            guard let self, !Task.isCancelled else { return }
            self.apply(outcome: outcome, for: key)
        }
    }

    func dismiss() {
        isDismissed = true
        activeTask?.cancel()
        activeTask = nil
        currentRequestKey = nil
        isLoading = false
    }

    func resetForPresentation() {
        isDismissed = false
    }

    private func apply(outcome: DictionaryService.TranslationOutcome, for key: DictionaryService.RequestKey) {
        guard !isDismissed, currentRequestKey == key else {
            return
        }

        isLoading = false
        switch outcome {
        case .success(let newResult):
            self.result = newResult
            self.failure = nil
        case .failure(.cancelled):
            break
        case .failure(let newFailure):
            // Keep an existing offline match if online enhancement only returned notFound
            if newFailure == .notFound, result != nil {
                return
            }
            self.result = nil
            self.failure = newFailure
        }
    }
}
