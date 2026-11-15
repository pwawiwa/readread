import Foundation
@testable import Readread

final class MockTranslationTransport: TranslationHTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let handler: Handler

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        record(request)
        return try await handler(request)
    }

    private func record(_ request: URLRequest) {
        lock.withLock {
            _requests.append(request)
        }
    }
}

enum TranslationTestFixtures {
    static func makeHTTPResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    static func makeMyMemoryJSON(translatedText: String, responseStatus: Int = 200, details: String = "") -> Data {
        let payload: [String: Any] = [
            "responseStatus": responseStatus,
            "responseDetails": details,
            "responseData": [
                "translatedText": translatedText
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    static func queryItem(_ name: String, from request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    static func timeoutError() -> Error {
        URLError(.timedOut)
    }

    static func connectionError() -> Error {
        URLError(.cannotConnectToHost)
    }

    static func makeRect(x: Double, y: Double, width: Double, height: Double) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    static func makeSize(width: Double, height: Double) -> CGSize {
        CGSize(width: width, height: height)
    }

    static func readBuildScript(fromTestFilePath filePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = packageRoot.appendingPathComponent("build_app.sh")
        return try String(contentsOf: scriptURL, encoding: .utf8)
    }
}
