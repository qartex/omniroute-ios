import Foundation
import Security
import os

final class SecureSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Enforce Host Name Validation in SSL Trust Policy
        let host = challenge.protectionSpace.host
        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        // Evaluate Server TLS Trust
        var secError: CFError?
        let isTrusted = SecTrustEvaluateWithError(serverTrust, &secError)

        if isTrusted {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

actor FreeLLMAPClient {
    private let session: URLSession
    private var baseURL: URL
    private let sessionDelegate = SecureSessionDelegate()

    init(baseURL: URL) {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        config.urlCache = nil // Disable caching sensitive responses on disk
        
        self.session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        self.baseURL = baseURL
    }

    func setBaseURL(_ url: URL) {
        self.baseURL = url
    }

    var currentBaseURL: URL { baseURL }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> LoginResult {
        let body = ["email": email, "password": password]
        do {
            let data = try await postJSON("/api/auth/login", body: body)
            return try JSONDecoder().decode(LoginResult.self, from: data)
        } catch {
            if let errorAsUnauthorized = error as? FreeLLMAPError {
                if case .unauthorized(let msg) = errorAsUnauthorized {
                    return LoginResult(success: false, error: LoginError(message: msg ?? "Login fehlgeschlagen", type: "unauthorized"))
                }
            }
            throw error
        }
    }

    func authStatus() async throws -> Bool {
        let data = try await getJSON("/api/auth/status")
        let status = try JSONDecoder().decode(AuthStatus.self, from: data)
        return status.authenticated
    }

    func logout() async throws {
        _ = try? await postJSON("/api/auth/logout", body: [String: String]())
    }

    // MARK: - System / Health

    func monitoringHealth() async throws -> MonitoringHealth {
        try await decodeGet("/api/monitoring/health")
    }

    func ping() async throws -> PingResult {
        try await decodeGet("/api/health/ping")
    }

    func degradation() async throws -> DegradationStatus {
        try await decodeGet("/api/health/degradation")
    }

    func dbHealth() async throws -> DbHealth {
        try await decodeGet("/api/db/health")
    }

    func mcpStatus() async throws -> McpStatus {
        try await decodeGet("/api/mcp/status")
    }

    func headroomStatus() async throws -> HeadroomStatus {
        try await decodeGet("/api/headroom/status")
    }

    // MARK: - Providers

    func providers() async throws -> ProvidersResponse {
        try await decodeGet("/api/providers")
    }

    func providerStats() async throws -> ProviderStatsResponse {
        try await decodeGet("/api/provider-stats")
    }

    func providerMetrics() async throws -> ProviderMetricsResponse {
        try await decodeGet("/api/provider-metrics")
    }

    func testProvider(id: String) async throws {
        let safeId = sanitizePathSegment(id)
        var request = URLRequest(url: url(for: "/api/providers/\(safeId)/test"))
        request.httpMethod = "POST"
        _ = try await send(request)
    }

    func toggleProvider(id: String, active: Bool) async throws {
        let safeId = sanitizePathSegment(id)
        var request = URLRequest(url: url(for: "/api/providers/\(safeId)"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["isActive": active])
        _ = try await send(request)
    }

    // MARK: - Activity / Logs / Audit

    func consoleLogs() async throws -> [ConsoleLog] {
        try await decodeGet("/api/logs/console")
    }

    func auditLog() async throws -> [AuditEntry] {
        try await decodeGet("/api/compliance/audit-log")
    }

    func callLogs() async throws -> [CallLog] {
        try await decodeGet("/api/usage/call-logs")
    }

    // MARK: - Models / Combos

    func models() async throws -> ModelsResponse {
        try await decodeGet("/api/models")
    }

    func combos() async throws -> CombosResponse {
        try await decodeGet("/api/combos")
    }

    func autoCombos() async throws -> CombosResponse {
        try await decodeGet("/api/combos/auto")
    }

    func freeModels() async throws -> FreeModelsResponse {
        try await decodeGet("/api/free-models")
    }

    func freeTierSummary() async throws -> FreeTierSummary {
        try await decodeGet("/api/free-tier/summary")
    }

    func pricingModels() async throws -> PricingModelsResponse {
        try await decodeGet("/api/pricing/models")
    }

    func createCombo(_ request: ComboCreateRequest) async throws {
        let url = url(for: "/api/combos")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)
        _ = try await send(req)
    }

    func deleteCombo(id: String) async throws {
        let safeId = sanitizePathSegment(id)
        var req = URLRequest(url: url(for: "/api/combos/\(safeId)"))
        req.httpMethod = "DELETE"
        _ = try await send(req)
    }

    func createProvider(_ request: ProviderCreateRequest) async throws {
        let url = url(for: "/api/providers")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)
        _ = try await send(req)
    }

    func validateProvider(provider: String, apiKey: String?) async throws -> ValidateProviderResult {
        let url = url(for: "/api/providers/validate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ValidateProviderRequest(provider: provider, apiKey: apiKey))
        let data = try await send(req)
        let dec = JSONDecoder()
        return (try? dec.decode(ValidateProviderResult.self, from: data)) ?? ValidateProviderResult(valid: false, error: "Antwort konnte nicht gelesen werden")
    }

    // MARK: - Analytics

    func compressionAnalytics() async throws -> CompressionAnalytics {
        try await decodeGet("/api/analytics/compression")
    }

    func autoRoutingAnalytics() async throws -> AutoRoutingAnalytics {
        try await decodeGet("/api/analytics/auto-routing")
    }

    func cacheStats() async throws -> CacheStats {
        try await decodeGet("/api/cache/stats")
    }

    func usageAnalytics() async throws -> UsageAnalytics {
        try await decodeGet("/api/usage/analytics")
    }

    // MARK: - Settings

    func settings() async throws -> GatewaySettings {
        try await decodeGet("/api/settings")
    }

    func concurrency() async throws -> ConcurrencyStatus {
        try await decodeGet("/api/admin/concurrency")
    }

    // MARK: - Core plumbing

    private func sanitizePathSegment(_ segment: String) -> String {
        return segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? segment
    }

    private func url(for path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(trimmed)
    }

    private func decodeGet<T: Decodable>(_ path: String) async throws -> T {
        let data = try await getJSON(path)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FreeLLMAPError.decodingFailed(String(describing: error))
        }
    }

    private func getJSON(_ path: String) async throws -> Data {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func postJSON(_ path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FreeLLMAPError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            // Try to decode error response for better message
            struct APIErrorEnvelope: Codable { var error: LoginError? }
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data), let msg = envelope.error?.message, !msg.isEmpty {
                throw FreeLLMAPError.unauthorized(msg)
            }
            throw FreeLLMAPError.unauthorized("Nicht authentifiziert – Passwort prüfen.")
        default:
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw FreeLLMAPError.serverError(http.statusCode, message)
        }
    }
}

enum FreeLLMAPError: LocalizedError {
    case unauthorized(String?)
    case invalidResponse
    case decodingFailed(String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let msg):
            return msg ?? "Nicht authentifiziert – Passwort prüfen."
        case .invalidResponse: return "Ungültige Antwort vom Server."
        case .decodingFailed(let d): return "Antwort konnte nicht gelesen werden: \(d)"
        case .serverError(let code, let msg): return "Serverfehler \(code): \(msg)"
        }
    }
}
