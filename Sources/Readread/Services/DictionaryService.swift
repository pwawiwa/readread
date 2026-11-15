import Foundation
import CoreServices

protocol TranslationHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionTranslationTransport: TranslationHTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

actor TranslationCache {
    private var storage: [String: [String]] = [:]

    func get(_ key: String) -> [String]? {
        storage[key]
    }

    func set(_ key: String, value: [String]) {
        storage[key] = value
    }
}

final class DictionaryService: @unchecked Sendable {
    enum Language: String, CaseIterable, Identifiable, Sendable {
        case english = "English"
        case indonesian = "Indonesian"

        var id: String { rawValue }

        var code: String {
            switch self {
            case .english: return "en"
            case .indonesian: return "id"
            }
        }

        var shortLabel: String {
            code.uppercased()
        }
    }

    enum TranslationMode: String, CaseIterable, Sendable {
        case define = "Define"
        case translate = "Translate"
    }

    enum TranslationSource: String, Equatable, Sendable {
        case offlineDictionary
        case onlineTranslation
        case systemDefinition
        case wordByWordApproximation
        case sameLanguage

        var displayLabel: String {
            switch self {
            case .offlineDictionary:
                return "Offline dictionary"
            case .onlineTranslation:
                return "Online translation"
            case .systemDefinition:
                return "System definition"
            case .wordByWordApproximation:
                return "Word-by-word approximation"
            case .sameLanguage:
                return "Same language"
            }
        }
    }

    enum TranslationFailure: Error, Equatable, Sendable {
        case emptySelection
        case notFound
        case timeout
        case unavailable(String)
        case cancelled

        var userMessage: String {
            switch self {
            case .emptySelection:
                return "Select text to look up."
            case .notFound:
                return "No matching entry was found."
            case .timeout:
                return "Online translation timed out. Check your connection or try again."
            case .unavailable(let reason):
                return reason
            case .cancelled:
                return "Translation cancelled."
            }
        }
    }

    struct TranslationResult: Equatable, Sendable {
        let queryText: String
        let normalizedText: String
        let translations: [String]
        let sourceLanguage: Language
        let targetLanguage: Language
        let source: TranslationSource

        var isSystemDefinition: Bool { source == .systemDefinition }
        var isApproximate: Bool { source == .wordByWordApproximation }
    }

    enum TranslationOutcome: Equatable, Sendable {
        case success(TranslationResult)
        case failure(TranslationFailure)
    }

    struct RequestKey: Equatable, Sendable {
        let normalizedText: String
        let mode: TranslationMode
        let sourceLanguage: Language
        let targetLanguage: Language
    }

    typealias SystemDefinitionProvider = @Sendable (String) -> String?

    private let enToId: [String: [String]]
    private let idToEn: [String: [String]]
    private let cache = TranslationCache()
    private let transport: TranslationHTTPTransport
    private let systemDefinitionProvider: SystemDefinitionProvider
    private let requestTimeout: TimeInterval

    init(
        enToId: [String: [String]]? = nil,
        idToEn: [String: [String]]? = nil,
        transport: TranslationHTTPTransport = URLSessionTranslationTransport(),
        systemDefinitionProvider: @escaping SystemDefinitionProvider = DictionaryService.defaultSystemDictionaryLookup,
        requestTimeout: TimeInterval = 5.0
    ) {
        self.transport = transport
        self.systemDefinitionProvider = systemDefinitionProvider
        self.requestTimeout = requestTimeout

        if let enToId, let idToEn {
            self.enToId = enToId
            self.idToEn = idToEn
        } else {
            let loaded = DictionaryService.loadBundledDictionaries()
            self.enToId = enToId ?? loaded.enToId
            self.idToEn = idToEn ?? loaded.idToEn
        }
    }

    private static func loadBundledDictionaries() -> (enToId: [String: [String]], idToEn: [String: [String]]) {
        var loadedEnToId: [String: [String]] = [:]
        var loadedIdToEn: [String: [String]] = [:]

        if let enIdUrl = Bundle.module.url(forResource: "en_id_dictionary", withExtension: "json"),
           let data = try? Data(contentsOf: enIdUrl),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            loadedEnToId = decoded
        }

        if let idEnUrl = Bundle.module.url(forResource: "id_en_dictionary", withExtension: "json"),
           let data = try? Data(contentsOf: idEnUrl),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            loadedIdToEn = decoded
        }

        return (loadedEnToId, loadedIdToEn)
    }

    static func normalizeDisplayText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeForLookup(_ text: String) -> String {
        let collapsed = normalizeDisplayText(text)
        let trimSet = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        return collapsed.trimmingCharacters(in: trimSet)
    }

    // MARK: - Synchronous Offline Lookup

    func lookupOffline(text: String, from source: Language, to target: Language) -> TranslationOutcome {
        let displayText = Self.normalizeDisplayText(text)
        let normalized = Self.normalizeForLookup(text)
        guard !normalized.isEmpty else {
            return .failure(.emptySelection)
        }

        if source == target {
            return .success(
                TranslationResult(
                    queryText: displayText,
                    normalizedText: normalized,
                    translations: ["Source and target languages are both \(source.rawValue)."],
                    sourceLanguage: source,
                    targetLanguage: target,
                    source: .sameLanguage
                )
            )
        }

        if let exact = lookupDictionary(normalized: normalized, displayText: displayText, from: source, to: target) {
            return .success(exact)
        }

        return .failure(.notFound)
    }

    // MARK: - Async Translation

    func translate(
        text: String,
        from source: Language,
        to target: Language,
        allowOnline: Bool = true
    ) async -> TranslationOutcome {
        let displayText = Self.normalizeDisplayText(text)
        let normalized = Self.normalizeForLookup(text)
        guard !normalized.isEmpty else {
            return .failure(.emptySelection)
        }

        if source == target {
            return .success(
                TranslationResult(
                    queryText: displayText,
                    normalizedText: normalized,
                    translations: ["Source and target languages are both \(source.rawValue)."],
                    sourceLanguage: source,
                    targetLanguage: target,
                    source: .sameLanguage
                )
            )
        }

        // 1. Immutable offline dictionary (exact + stemming)
        if let offline = lookupDictionary(normalized: normalized, displayText: displayText, from: source, to: target) {
            return .success(offline)
        }

        // 2. Isolated online translation cache
        let cacheKey = "\(source.code)_\(target.code)_\(normalized.lowercased())"
        if let cached = await cache.get(cacheKey) {
            return .success(
                TranslationResult(
                    queryText: displayText,
                    normalizedText: normalized,
                    translations: cached,
                    sourceLanguage: source,
                    targetLanguage: target,
                    source: .onlineTranslation
                )
            )
        }

        // 3. Cancellable online translation
        if allowOnline {
            do {
                try Task.checkCancellation()
                let onlineText = try await fetchOnlineTranslation(query: normalized, from: source, to: target)
                let result = capitalizeFirst(onlineText)
                await cache.set(cacheKey, value: [result])
                return .success(
                    TranslationResult(
                        queryText: displayText,
                        normalizedText: normalized,
                        translations: [result],
                        sourceLanguage: source,
                        targetLanguage: target,
                        source: .onlineTranslation
                    )
                )
            } catch is CancellationError {
                return .failure(.cancelled)
            } catch let failure as TranslationFailure {
                return .failure(failure)
            } catch {
                return .failure(.unavailable("Online translation is unavailable."))
            }
        }

        // 4. Offline-only word-by-word approximation for multi-word selections
        if normalized.contains(" "),
           let approximation = wordByWordApproximation(normalized: normalized, displayText: displayText, from: source, to: target) {
            return .success(approximation)
        }

        return .failure(.notFound)
    }

    // MARK: - Define Mode (Never blocks on network)

    func define(text: String, language: Language) -> TranslationOutcome {
        let displayText = Self.normalizeDisplayText(text)
        let normalized = Self.normalizeForLookup(text)
        guard !normalized.isEmpty else {
            return .failure(.emptySelection)
        }

        if let rawDefinition = systemDefinitionProvider(normalized) {
            let cleaned = cleanSystemDefinition(rawDefinition)
            if !cleaned.isEmpty {
                return .success(
                    TranslationResult(
                        queryText: displayText,
                        normalizedText: normalized,
                        translations: [cleaned],
                        sourceLanguage: language,
                        targetLanguage: language,
                        source: .systemDefinition
                    )
                )
            }
        }

        return .failure(.notFound)
    }

    // MARK: - Private Helpers

    private func lookupDictionary(
        normalized: String,
        displayText: String,
        from source: Language,
        to target: Language
    ) -> TranslationResult? {
        let dict = source == .english ? enToId : idToEn
        let lower = normalized.lowercased()

        if let translations = dict[lower] {
            return TranslationResult(
                queryText: displayText,
                normalizedText: normalized,
                translations: translations,
                sourceLanguage: source,
                targetLanguage: target,
                source: .offlineDictionary
            )
        }

        let isMultiWord = lower.contains(" ")
        if !isMultiWord && source == .english {
            for stem in englishStems(for: lower) {
                if let translations = dict[stem] {
                    return TranslationResult(
                        queryText: displayText,
                        normalizedText: normalized,
                        translations: translations,
                        sourceLanguage: source,
                        targetLanguage: target,
                        source: .offlineDictionary
                    )
                }
            }
        }

        return nil
    }

    private func englishStems(for lower: String) -> [String] {
        var stems: [String] = []
        if lower.hasSuffix("ies") && lower.count >= 4 {
            stems.append(String(lower.dropLast(3)) + "y")
        }
        if lower.hasSuffix("ing") && lower.count >= 4 {
            let base = String(lower.dropLast(3))
            stems.append(base)
            stems.append(base + "e")
            if base.count >= 2 && base.suffix(1) == String(base.dropLast().suffix(1)) {
                stems.append(String(base.dropLast()))
            }
        }
        if lower.hasSuffix("ed") && lower.count >= 4 {
            let base = String(lower.dropLast(2))
            stems.append(base)
            stems.append(base + "e")
        }
        if lower.hasSuffix("s") && lower.count >= 3 {
            stems.append(String(lower.dropLast()))
        }
        return stems
    }

    private func wordByWordApproximation(
        normalized: String,
        displayText: String,
        from source: Language,
        to target: Language
    ) -> TranslationResult? {
        let dict = source == .english ? enToId : idToEn
        let words = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard words.count > 1 else { return nil }

        var translatedWords: [String] = []
        var matchedAny = false

        for word in words {
            let cleanWord = Self.normalizeForLookup(word).lowercased()
            if let trs = dict[cleanWord], let first = trs.first {
                translatedWords.append(first)
                matchedAny = true
            } else {
                translatedWords.append(word)
            }
        }

        guard matchedAny else { return nil }
        let stitched = capitalizeFirst(translatedWords.joined(separator: " "))
        return TranslationResult(
            queryText: displayText,
            normalizedText: normalized,
            translations: [stitched],
            sourceLanguage: source,
            targetLanguage: target,
            source: .wordByWordApproximation
        )
    }

    private func fetchOnlineTranslation(query: String, from source: Language, to target: Language) async throws -> String {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "langpair", value: "\(source.code)|\(target.code)")
        ]
        guard let url = components?.url else {
            throw TranslationFailure.unavailable("Invalid translation request URL.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw TranslationFailure.cancelled
        } catch let urlError as URLError {
            switch urlError.code {
            case .cancelled:
                throw TranslationFailure.cancelled
            case .timedOut:
                throw TranslationFailure.timeout
            default:
                throw TranslationFailure.unavailable("Online translation is unavailable.")
            }
        } catch let nsError as NSError where nsError.domain == NSURLErrorDomain {
            if nsError.code == NSURLErrorCancelled {
                throw TranslationFailure.cancelled
            } else if nsError.code == NSURLErrorTimedOut {
                throw TranslationFailure.timeout
            }
            throw TranslationFailure.unavailable("Online translation is unavailable.")
        } catch {
            throw TranslationFailure.unavailable("Online translation is unavailable.")
        }

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationFailure.unavailable("Invalid server response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TranslationFailure.unavailable("Translation service returned HTTP \(httpResponse.statusCode).")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationFailure.unavailable("Invalid response from translation service.")
        }

        // Validate MyMemory provider status
        if let statusInt = json["responseStatus"] as? Int, statusInt != 200 {
            let details = json["responseDetails"] as? String
            throw TranslationFailure.unavailable(details?.isEmpty == false ? details! : "Translation provider error (\(statusInt)).")
        }
        if let statusStr = json["responseStatus"] as? String, let statusInt = Int(statusStr), statusInt != 200 {
            let details = json["responseDetails"] as? String
            throw TranslationFailure.unavailable(details?.isEmpty == false ? details! : "Translation provider error (\(statusInt)).")
        }

        guard let responseData = json["responseData"] as? [String: Any],
              let match = responseData["translatedText"] as? String,
              !match.isEmpty else {
            throw TranslationFailure.notFound
        }

        let cleanedMatch = decodeProviderText(match)
        if cleanedMatch.isEmpty || cleanedMatch.contains("%") {
            throw TranslationFailure.unavailable("Translation provider returned an unreadable response.")
        }

        if cleanedMatch.lowercased() == query.lowercased() {
            throw TranslationFailure.notFound
        }

        return cleanedMatch
    }

    private func decodeProviderText(_ match: String) -> String {
        let rawMatch = match.replacingOccurrences(of: "% ", with: "%")
        var cleaned = rawMatch.removingPercentEncoding ?? rawMatch
        cleaned = cleaned.replacingOccurrences(of: "%20", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Sendable static func defaultSystemDictionaryLookup(_ word: String) -> String? {
        let nsWord = word as NSString
        let range = CFRangeMake(0, nsWord.length)
        if let definition = DCSCopyTextDefinition(nil, nsWord as CFString, range) {
            return String(definition.takeRetainedValue())
        }
        return nil
    }

    private func cleanSystemDefinition(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 350 {
            cleaned = String(cleaned.prefix(350)) + "..."
        }
        return cleaned
    }

    private func capitalizeFirst(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return text.prefix(1).capitalized + text.dropFirst()
    }
}
