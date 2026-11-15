import Testing
@testable import Readread

@Suite("Translation & Packaging")
struct TranslationPackagingTests {

    @Test("Language codes use ISO 639-1 including id for Indonesian")
    func languageCodes() {
        #expect(DictionaryService.Language.english.code == "en")
        #expect(DictionaryService.Language.indonesian.code == "id")
        #expect(DictionaryService.Language.english.shortLabel == "EN")
        #expect(DictionaryService.Language.indonesian.shortLabel == "ID")
    }

    @Test("Bundled offline dictionary translates known English and Indonesian words")
    func bundledOfflineDictionaryLookup() async {
        let transport = MockTranslationTransport { _ in
            Issue.record("Online transport should not be called for offline dictionary hits")
            throw TranslationTestFixtures.connectionError()
        }
        let service = DictionaryService(transport: transport)

        let enToId = await service.translate(text: "house", from: .english, to: .indonesian, allowOnline: true)
        guard case .success(let enResult) = enToId else {
            Issue.record("Expected offline dictionary hit for 'house'")
            return
        }
        #expect(enResult.source == .offlineDictionary)
        #expect(!enResult.translations.isEmpty)
        #expect(enResult.translations.contains("rumah"))

        let idToEn = await service.translate(text: "rumah", from: .indonesian, to: .english, allowOnline: true)
        guard case .success(let idResult) = idToEn else {
            Issue.record("Expected offline dictionary hit for 'rumah'")
            return
        }
        #expect(idResult.source == .offlineDictionary)
        #expect(idResult.translations.contains(where: { $0.localizedCaseInsensitiveContains("house") }))
        #expect(transport.requests.isEmpty)
    }

    @Test("Whitespace and punctuation normalize for lookup while preserving display text")
    func normalizationPreservesDisplayText() async {
        let service = DictionaryService(
            enToId: ["book": ["buku"]],
            idToEn: [:]
        )

        let outcome = await service.translate(text: "  \u{201C}book,\u{201D}\n ", from: .english, to: .indonesian, allowOnline: false)
        guard case .success(let result) = outcome else {
            Issue.record("Expected normalized lookup to succeed")
            return
        }
        #expect(result.queryText == "\u{201C}book,\u{201D}")
        #expect(result.normalizedText == "book")
        #expect(result.translations == ["buku"])

        let emptyOutcome = await service.translate(text: "   ...   ", from: .english, to: .indonesian, allowOnline: false)
        #expect(emptyOutcome == .failure(.emptySelection))
    }

    @Test("Same-language request is handled explicitly without dictionary or network")
    func sameLanguageBehavior() async {
        let transport = MockTranslationTransport { _ in
            Issue.record("Network should not be called for same-language requests")
            throw TranslationTestFixtures.connectionError()
        }
        let service = DictionaryService(
            enToId: ["book": ["buku"]],
            idToEn: ["buku": ["book"]],
            transport: transport
        )

        let outcome = await service.translate(text: "book", from: .english, to: .english, allowOnline: true)
        guard case .success(let result) = outcome else {
            Issue.record("Expected explicit same-language result")
            return
        }
        #expect(result.source == .sameLanguage)
        #expect(transport.requests.isEmpty)
    }

    @Test("Define mode returns system definition and never falls back to network")
    func defineModeNoNetworkFallback() {
        let transport = MockTranslationTransport { _ in
            Issue.record("Define mode must never call network")
            throw TranslationTestFixtures.connectionError()
        }

        let hitService = DictionaryService(
            enToId: ["book": ["buku"]],
            idToEn: [:],
            transport: transport,
            systemDefinitionProvider: { word in
                word == "book" ? "<b>book</b>: a written or printed work" : nil
            }
        )

        let hit = hitService.define(text: "  book! ", language: .english)
        guard case .success(let hitResult) = hit else {
            Issue.record("Expected system definition hit")
            return
        }
        #expect(hitResult.source == .systemDefinition)
        #expect(hitResult.translations == ["book: a written or printed work"])

        let miss = hitService.define(text: "nonexistentword", language: .english)
        #expect(miss == .failure(.notFound))
        #expect(transport.requests.isEmpty)
    }

    @Test("Offline miss and word-by-word approximation are distinguished explicitly")
    func offlineMissAndWordByWordApproximation() async {
        let service = DictionaryService(
            enToId: ["good": ["baik"], "morning": ["pagi"]],
            idToEn: [:]
        )

        let singleMiss = await service.translate(text: "serendipity", from: .english, to: .indonesian, allowOnline: false)
        #expect(singleMiss == .failure(.notFound))

        let approx = await service.translate(text: "good morning everyone", from: .english, to: .indonesian, allowOnline: false)
        guard case .success(let approxResult) = approx else {
            Issue.record("Expected word-by-word approximation for multi-word offline fallback")
            return
        }
        #expect(approxResult.source == .wordByWordApproximation)
        #expect(approxResult.isApproximate)
        #expect(approxResult.translations == ["Baik pagi everyone"])
    }

    @Test("Online translation validates URL encoding, caches result, and tags provenance")
    func onlineSuccessAndCaching() async {
        let transport = MockTranslationTransport { request in
            let url = request.url!
            let langpair = TranslationTestFixtures.queryItem("langpair", from: request)
            let query = TranslationTestFixtures.queryItem("q", from: request)
            #expect(langpair == "en|id")
            #expect(query == "hello & welcome")

            let data = TranslationTestFixtures.makeMyMemoryJSON(translatedText: "halo &amp; selamat datang")
            return (data, TranslationTestFixtures.makeHTTPResponse(url: url, statusCode: 200))
        }

        let service = DictionaryService(enToId: [:], idToEn: [:], transport: transport)

        let first = await service.translate(text: "hello & welcome", from: .english, to: .indonesian, allowOnline: true)
        guard case .success(let firstResult) = first else {
            Issue.record("Expected online translation to succeed")
            return
        }
        #expect(firstResult.source == .onlineTranslation)
        #expect(firstResult.translations == ["Halo & selamat datang"])
        #expect(transport.requests.count == 1)

        let second = await service.translate(text: "hello & welcome", from: .english, to: .indonesian, allowOnline: true)
        #expect(second == first)
        #expect(transport.requests.count == 1)
    }

    @Test("HTTP errors, provider errors, and timeouts surface explicit failure states")
    func onlineErrorStates() async {
        let httpErrorTransport = MockTranslationTransport { request in
            let data = TranslationTestFixtures.makeMyMemoryJSON(translatedText: "")
            return (data, TranslationTestFixtures.makeHTTPResponse(url: request.url!, statusCode: 503))
        }
        let httpService = DictionaryService(enToId: [:], idToEn: [:], transport: httpErrorTransport)
        let httpOutcome = await httpService.translate(text: "ephemeral", from: .english, to: .indonesian, allowOnline: true)
        if case .failure(.unavailable(let msg)) = httpOutcome {
            #expect(msg.contains("503"))
        } else {
            Issue.record("Expected HTTP 503 to surface .unavailable failure, got \(httpOutcome)")
        }

        let providerErrorTransport = MockTranslationTransport { request in
            let data = TranslationTestFixtures.makeMyMemoryJSON(translatedText: "INVALID", responseStatus: 403, details: "Quota exceeded")
            return (data, TranslationTestFixtures.makeHTTPResponse(url: request.url!, statusCode: 200))
        }
        let providerService = DictionaryService(enToId: [:], idToEn: [:], transport: providerErrorTransport)
        let providerOutcome = await providerService.translate(text: "ephemeral", from: .english, to: .indonesian, allowOnline: true)
        #expect(providerOutcome == .failure(.unavailable("Quota exceeded")))

        let timeoutTransport = MockTranslationTransport { _ in
            throw TranslationTestFixtures.timeoutError()
        }
        let timeoutService = DictionaryService(enToId: [:], idToEn: [:], transport: timeoutTransport)
        let timeoutOutcome = await timeoutService.translate(text: "ephemeral", from: .english, to: .indonesian, allowOnline: true)
        #expect(timeoutOutcome == .failure(.timeout))
    }

    @Test("In-flight online request respects task cancellation")
    func taskCancellation() async {
        let transport = MockTranslationTransport { request in
            try await Task.sleep(nanoseconds: 500_000_000)
            let data = TranslationTestFixtures.makeMyMemoryJSON(translatedText: "terlambat")
            return (data, TranslationTestFixtures.makeHTTPResponse(url: request.url!, statusCode: 200))
        }
        let service = DictionaryService(enToId: [:], idToEn: [:], transport: transport)

        let task = Task {
            await service.translate(text: "slowword", from: .english, to: .indonesian, allowOnline: true)
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()

        let outcome = await task.value
        #expect(outcome == .failure(.cancelled))
    }

    @Test("Delayed result for selection A cannot overwrite newer selection B, and dismissal blocks stale updates")
    @MainActor
    func staleResultAndDismissalProtection() async {
        let transport = MockTranslationTransport { request in
            let q = TranslationTestFixtures.queryItem("q", from: request) ?? ""
            if q == "firstword" {
                try await Task.sleep(nanoseconds: 150_000_000)
                return (
                    TranslationTestFixtures.makeMyMemoryJSON(translatedText: "kata pertama"),
                    TranslationTestFixtures.makeHTTPResponse(url: request.url!, statusCode: 200)
                )
            } else {
                try await Task.sleep(nanoseconds: 20_000_000)
                return (
                    TranslationTestFixtures.makeMyMemoryJSON(translatedText: "kata kedua"),
                    TranslationTestFixtures.makeHTTPResponse(url: request.url!, statusCode: 200)
                )
            }
        }
        let service = DictionaryService(enToId: [:], idToEn: [:], transport: transport)
        let controller = TranslationController(debounceNanoseconds: 20_000_000)

        controller.requestLookup(
            selectedText: "firstword",
            mode: .translate,
            sourceLanguage: .english,
            targetLanguage: .indonesian,
            service: service,
            immediate: true
        )

        try? await Task.sleep(nanoseconds: 10_000_000)

        controller.requestLookup(
            selectedText: "secondword",
            mode: .translate,
            sourceLanguage: .english,
            targetLanguage: .indonesian,
            service: service,
            immediate: true
        )

        // Wait deterministically up to 2s for controller to finish loading under parallel load
        for _ in 0..<200 {
            if !controller.isLoading { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(controller.failure == nil)
        #expect(controller.isLoading == false)
        #expect(controller.result?.normalizedText == "secondword")
        #expect(controller.result?.translations == ["Kata kedua"])

        controller.requestLookup(
            selectedText: "firstword",
            mode: .translate,
            sourceLanguage: .english,
            targetLanguage: .indonesian,
            service: service,
            immediate: true
        )
        controller.dismiss()
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(controller.isDismissed == true)
        #expect(controller.result == nil)

        // Also verify debouncing skips superseded rapid selections
        let debouncedTransport = MockTranslationTransport { request in
            let q = TranslationTestFixtures.queryItem("q", from: request) ?? ""
            return (
                TranslationTestFixtures.makeMyMemoryJSON(translatedText: "hasil \(q)"),
                TranslationTestFixtures.makeHTTPResponse(url: request.url!, statusCode: 200)
            )
        }
        let debouncedService = DictionaryService(enToId: [:], idToEn: [:], transport: debouncedTransport)
        let debouncedController = TranslationController(debounceNanoseconds: 60_000_000)

        debouncedController.requestLookup(
            selectedText: "first",
            mode: .translate,
            sourceLanguage: .english,
            targetLanguage: .indonesian,
            service: debouncedService,
            immediate: false
        )
        debouncedController.requestLookup(
            selectedText: "final",
            mode: .translate,
            sourceLanguage: .english,
            targetLanguage: .indonesian,
            service: debouncedService,
            immediate: false
        )

        for _ in 0..<200 {
            if !debouncedController.isLoading { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(debouncedTransport.requests.count == 1)
        #expect(debouncedController.result?.normalizedText == "final")
    }

    @Test("Popover layout stays within PDF viewport bounds")
    func popoverLayoutBounds() {
        let viewport = TranslationTestFixtures.makeSize(width: 800, height: 600)

        let topLeftRect = TranslationTestFixtures.makeRect(x: 5, y: 10, width: 40, height: 18)
        let topLeftLayout = TranslationPopover.computeLayout(selectionRect: topLeftRect, viewportSize: viewport)
        #expect(topLeftLayout.center.x - topLeftLayout.size.width / 2 >= 12)
        #expect(topLeftLayout.center.y - topLeftLayout.size.height / 2 >= 12)
        #expect(topLeftLayout.center.y > topLeftRect.maxY)

        let bottomRightRect = TranslationTestFixtures.makeRect(x: 760, y: 560, width: 30, height: 18)
        let bottomRightLayout = TranslationPopover.computeLayout(selectionRect: bottomRightRect, viewportSize: viewport)
        #expect(bottomRightLayout.center.x + bottomRightLayout.size.width / 2 <= viewport.width - 12)
        #expect(bottomRightLayout.center.y + bottomRightLayout.size.height / 2 <= viewport.height - 12)
        #expect(bottomRightLayout.center.y < bottomRightRect.minY)
    }

    @Test("Packaging script uses strict mode, places resource bundle at app root, and declares document types")
    func buildScriptValidation() throws {
        let script = try TranslationTestFixtures.readBuildScript(fromTestFilePath: #filePath)
        #expect(script.contains("set -euo pipefail"))
        #expect(script.contains("${APP_DIR}/${RESOURCE_BUNDLE}"))
        #expect(script.contains("CFBundleDocumentTypes"))
        #expect(script.contains("com.adobe.pdf"))
        #expect(script.contains("public.plain-text"))
        #expect(script.contains("public.rtf"))
        #expect(script.contains("public.html"))
        #expect(script.contains("org.idpf.epub-container"))
    }
}
