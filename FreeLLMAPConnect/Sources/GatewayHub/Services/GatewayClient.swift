import Foundation

enum GatewayClientError: LocalizedError, Equatable {
    case invalidURL
    case missingManagementPassword
    case loginRejected(String)
    case apiKeyRejected
    case server(status: Int, message: String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Die Server-URL ist ungültig."
        case .missingManagementPassword: "Bitte das Management-Passwort eingeben."
        case .loginRejected(let message): "Anmeldung abgelehnt: \(message)"
        case .apiKeyRejected: "Der API-Key wurde abgelehnt."
        case .server(let status, let message): "Serverfehler \(status): \(message)"
        case .unavailable(let message): message
        }
    }
}

actor GatewayClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func login(instance: GatewayInstance, credentials: GatewayCredentials) async throws {
        guard !credentials.managementPassword.isEmpty else { throw GatewayClientError.missingManagementPassword }
        let root = try GatewayURL.normalize(instance.rootURL)
        var payload: [String: String] = ["password": credentials.managementPassword]
        if instance.kind.requiresEmail {
            guard let email = instance.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
                throw GatewayClientError.loginRejected("E-Mail fehlt.")
            }
            payload["email"] = email
        }
        let response = try await request(root: root, path: "api/auth/login", method: "POST", body: payload)
        guard (200..<300).contains(response.status) else { throw error(from: response) }

        // Success shapes vary by server version. A 2xx response plus the session
        // cookie is the contract; URLSession keeps the cookie host-scoped.
        if let object = jsonObject(response.data) as? [String: Any],
           let success = object["success"] as? Bool,
           !success {
            throw GatewayClientError.loginRejected(message(from: object) ?? "Passwort oder E-Mail prüfen.")
        }
    }

    func health(for instance: GatewayInstance) async -> GatewayHealth {
        do {
            let root = try GatewayURL.normalize(instance.rootURL)
            let started = ContinuousClock.now
            let ping = try await request(root: root, path: "api/health/ping")
            let elapsed = started.duration(to: .now)
            let latency = Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            if (200..<300).contains(ping.status) {
                let object = jsonObject(ping.data) as? [String: Any]
                let status = (object?["status"] as? String)?.lowercased() ?? "ok"
                let state: GatewayHealth.HealthState = ["ok", "healthy", "online"].contains(status) ? .healthy : .warning
                let deeper = try? await request(root: root, path: "api/monitoring/health")
                let deepObject = deeper.flatMap { jsonObject($0.data) as? [String: Any] }
                return GatewayHealth(
                    state: state,
                    message: (deepObject?["status"] as? String)?.capitalized ?? status.capitalized,
                    version: deepObject?["version"] as? String,
                    latencyMilliseconds: latency
                )
            }
            return GatewayHealth(state: .warning, message: "HTTP \(ping.status)", version: nil, latencyMilliseconds: latency)
        } catch {
            return GatewayHealth(state: .offline, message: error.localizedDescription, version: nil, latencyMilliseconds: nil)
        }
    }

    func verifyAPIKey(for instance: GatewayInstance, credentials: GatewayCredentials) async throws -> Int {
        guard !credentials.apiKey.isEmpty else { return 0 }
        let root = try GatewayURL.normalize(instance.rootURL)
        let response = try await request(
            root: GatewayURL.apiURL(for: root),
            path: "models",
            headers: ["Authorization": "Bearer \(credentials.apiKey)"]
        )
        guard response.status != 401 && response.status != 403 else { throw GatewayClientError.apiKeyRejected }
        guard (200..<300).contains(response.status) else { throw error(from: response) }
        let object = jsonObject(response.data) as? [String: Any]
        return (object?["data"] as? [Any])?.count ?? (object?["models"] as? [Any])?.count ?? 0
    }

    private func request(
        root: URL,
        path: String,
        method: String = "GET",
        body: [String: String]? = nil,
        headers: [String: String] = [:]
    ) async throws -> (status: Int, data: Data) {
        let url = root.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GatewayClientError.unavailable("Ungültige Serverantwort.") }
            return (http.statusCode, data)
        } catch let error as GatewayClientError {
            throw error
        } catch {
            throw GatewayClientError.unavailable("Server nicht erreichbar: \(error.localizedDescription)")
        }
    }

    private func error(from response: (status: Int, data: Data)) -> GatewayClientError {
        let object = jsonObject(response.data) as? [String: Any]
        let text = message(from: object) ?? String(data: response.data, encoding: .utf8) ?? "Unbekannter Fehler"
        if response.status == 401 || response.status == 403 { return .loginRejected(text) }
        return .server(status: response.status, message: text)
    }

    private func jsonObject(_ data: Data) -> Any? { try? JSONSerialization.jsonObject(with: data) }

    private func message(from object: [String: Any]?) -> String? {
        guard let object else { return nil }
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return nil
    }
}
