import Foundation
import CoreServices

class DictionaryService {
    enum Language: String, CaseIterable, Identifiable {
        case english = "English"
        case indonesian = "Indonesian"
        var id: String { rawValue }
    }
    
    struct TranslationResult {
        let word: String
        let translations: [String]
        let sourceLanguage: Language
        let targetLanguage: Language
        let isSystemDefinition: Bool
    }
    
    private var enToId: [String: [String]] = [:]
    private var idToEn: [String: [String]] = [:]
    private var dynamicCache: [String: [String]] = [:]
    
    init() {
        loadDictionaries()
    }
    
    private func loadDictionaries() {
        if let enIdUrl = Bundle.module.url(forResource: "en_id_dictionary", withExtension: "json") {
            do {
                let data = try Data(contentsOf: enIdUrl)
                enToId = try JSONDecoder().decode([String: [String]].self, from: data)
            } catch {
                print("Failed to load en_id_dictionary: \(error)")
            }
        }
        
        if let idEnUrl = Bundle.module.url(forResource: "id_en_dictionary", withExtension: "json") {
            do {
                let data = try Data(contentsOf: idEnUrl)
                idToEn = try JSONDecoder().decode([String: [String]].self, from: data)
            } catch {
                print("Failed to load id_en_dictionary: \(error)")
            }
        }
    }
    
    func translate(word: String, from source: Language, to target: Language, allowOnline: Bool = true) -> TranslationResult? {
        let cleanText = cleanSentence(word)
        guard !cleanText.isEmpty else { return nil }
        
        let isMultiWord = cleanText.contains(" ")
        let dict = source == .english ? enToId : idToEn
        let langKey = "\(source.rawValue.prefix(2))_\(target.rawValue.prefix(2))_\(cleanText.lowercased())"
        
        // 1. Dynamic Cache
        if let cached = dynamicCache[langKey] {
            return TranslationResult(word: cleanText, translations: cached, sourceLanguage: source, targetLanguage: target, isSystemDefinition: false)
        }
        
        // 2. Local Dictionary & Stemming Lookup (Single Words)
        if !isMultiWord {
            let lower = cleanText.lowercased()
            if let translations = dict[lower] {
                return TranslationResult(word: cleanText, translations: translations, sourceLanguage: source, targetLanguage: target, isSystemDefinition: false)
            }
            
            // Stemming rules (e.g. doubting -> doubt, treacheries -> treachery)
            if source == .english {
                var stems: [String] = []
                if lower.hasSuffix("ies") && lower.count > 4 { stems.append(String(lower.dropLast(3)) + "y") }
                if lower.hasSuffix("ing") && lower.count > 5 { stems.append(String(lower.dropLast(3))) }
                if lower.hasSuffix("ed") && lower.count > 4 { stems.append(String(lower.dropLast(2))) }
                if lower.hasSuffix("s") && lower.count > 3 { stems.append(String(lower.dropLast())) }
                
                for stem in stems {
                    if let translations = dict[stem] {
                        return TranslationResult(word: cleanText, translations: translations, sourceLanguage: source, targetLanguage: target, isSystemDefinition: false)
                    }
                }
            }
        }
        
        // 3. Multi-word sentence or missing word: query Online Sentence Translation Engine (if allowed)
        if allowOnline, let onlineSentenceTranslation = fetchOnlineTranslation(word: cleanText, from: source, to: target) {
            // Discard online result if it returned the exact same input word
            if onlineSentenceTranslation.lowercased() != cleanText.lowercased() {
                let result = capitalizeFirst(onlineSentenceTranslation)
                dynamicCache[langKey] = [result]
                return TranslationResult(word: cleanText, translations: [result], sourceLanguage: source, targetLanguage: target, isSystemDefinition: false)
            }
        }
        
        // 4. Offline multi-word fallback: translate individual words and stitch together
        if isMultiWord {
            let words = cleanText.components(separatedBy: .whitespaces)
            var translatedWords: [String] = []
            for w in words {
                let wClean = w.lowercased().trimmingCharacters(in: .punctuationCharacters)
                if let trs = dict[wClean], let firstTr = trs.first {
                    translatedWords.append(firstTr)
                } else {
                    translatedWords.append(w)
                }
            }
            let stitchedSentence = capitalizeFirst(translatedWords.joined(separator: " "))
            return TranslationResult(word: cleanText, translations: [stitchedSentence], sourceLanguage: source, targetLanguage: target, isSystemDefinition: false)
        }
        
        // 5. Single word macOS System Dictionary fallback
        if let systemDef = lookupSystemDictionary(word: cleanText) {
            let cleanedDef = cleanSystemDefinition(systemDef)
            return TranslationResult(word: cleanText, translations: [cleanedDef], sourceLanguage: source, targetLanguage: target, isSystemDefinition: true)
        }
        
        return TranslationResult(word: cleanText, translations: [target == .indonesian ? "Tidak ada terjemahan" : "No translation found"], sourceLanguage: source, targetLanguage: target, isSystemDefinition: false)
    }
    
    func define(word: String, language: Language) -> TranslationResult? {
        let cleanText = cleanSentence(word)
        guard !cleanText.isEmpty else { return nil }
        
        if let systemDef = lookupSystemDictionary(word: cleanText) {
            let cleanedDef = cleanSystemDefinition(systemDef)
            return TranslationResult(word: cleanText, translations: [cleanedDef], sourceLanguage: language, targetLanguage: language, isSystemDefinition: true)
        }
        
        return translate(word: word, from: language, to: language == .english ? .indonesian : .english, allowOnline: true)
    }
    
    private func fetchOnlineTranslation(word: String, from source: Language, to target: Language) -> String? {
        let srcCode = source == .english ? "en" : "id"
        let tgtCode = target == .indonesian ? "id" : "en"
        
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://api.mymemory.translated.net/get?q=\(encodedWord)&langpair=\(srcCode)|\(tgtCode)") else {
            return nil
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String? = nil
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["responseData"] as? [String: Any],
                  let match = responseData["translatedText"] as? String,
                  !match.isEmpty else {
                return
            }
            
            // Clean percent encoding (%20 -> space) and HTML entities
            let rawMatch = match.replacingOccurrences(of: "% ", with: "%")
            var cleanedMatch = rawMatch.removingPercentEncoding ?? rawMatch
            cleanedMatch = cleanedMatch.replacingOccurrences(of: "%20", with: " ")
            cleanedMatch = cleanedMatch.replacingOccurrences(of: "&quot;", with: "\"")
            cleanedMatch = cleanedMatch.replacingOccurrences(of: "&#39;", with: "'")
            cleanedMatch = cleanedMatch.replacingOccurrences(of: "&amp;", with: "&")
            
            let finalStr = cleanedMatch.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Discard if the result contains raw percent encoding artifacts (e.g. %D0, %81)
            if finalStr.contains("%") {
                return
            }
            
            resultText = finalStr
        }.resume()
        
        _ = semaphore.wait(timeout: .now() + 2.5)
        return resultText
    }
    
    private func lookupSystemDictionary(word: String) -> String? {
        let nsWord = word as NSString
        let range = CFRangeMake(0, nsWord.length)
        if let definition = DCSCopyTextDefinition(nil, nsWord as CFString, range) {
            return String(definition.takeRetainedValue())
        }
        return nil
    }
    
    private func cleanSystemDefinition(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 350 {
            cleaned = String(cleaned.prefix(350)) + "..."
        }
        return cleaned
    }
    
    private func cleanSentence(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func capitalizeFirst(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return text.prefix(1).capitalized + text.dropFirst()
    }
}
