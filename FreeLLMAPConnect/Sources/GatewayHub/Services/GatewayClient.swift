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
            payload["email"] = email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let response = try await request(root: root, path: "api/auth/login", method: "POST", body: payload)
        guard (200..<300).contains(response.status) else {
            // FreeLLMAP returns 401 with JSON envelope on auth failure
            if response.status == 401 || response.status == 403 {
                let text = String(data: response.data, encoding: .utf8) ?? ""
                if text.contains("401") || text.contains("unauthorized") || text.contains("Unauthorized") {
                    throw GatewayClientError.loginRejected("Falsches Passwort oder E-Mail.")
                }
            }
            throw error(from: response)
        }

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

    func dashboard(for instance: GatewayInstance) async -> GatewayDashboard {
        let health = await health(for: instance)
        guard let root = try? GatewayURL.normalize(instance.rootURL) else {
            return .placeholder(health: health)
        }

        let monitoring = await optionalJSONObject(root: root, path: "api/monitoring/health")
        let database = await optionalJSONObject(root: root, path: "api/db/health")
        let tokenPool = await optionalJSONObject(root: root, path: "api/free-tier/summary")
        let providers = await optionalJSONObject(root: root, path: "api/providers")
        let catalog = await optionalJSONObject(root: root, path: "api/pricing/models")
        let models = await optionalJSONObject(root: root, path: "api/models")
        let combos = await optionalJSONObject(root: root, path: "api/combos/auto")
        let logs = await optionalJSONArray(root: root, path: "api/logs/console")
        let calls = await optionalJSONArray(root: root, path: "api/usage/call-logs")

        var snapshot = GatewayDashboard(health: health)
        populateOverview(&snapshot, monitoring: monitoring, database: database, tokenPool: tokenPool)
        snapshot.providers = parseProviders(providers)
        snapshot.providerCatalog = parseProviderCatalog(catalog)
        snapshot.models = parseModels(models)
        snapshot.combos = parseCombos(combos)
        snapshot.consoleLogs = parseConsoleLogs(logs)
        snapshot.callLogs = parseCallLogs(calls)

        if monitoring == nil || database == nil || tokenPool == nil { snapshot.unavailableSections.insert(.overview) }
        if providers == nil || catalog == nil { snapshot.unavailableSections.insert(.providers) }
        if models == nil || combos == nil { snapshot.unavailableSections.insert(.models) }
        if logs == nil && calls == nil { snapshot.unavailableSections.insert(.activity) }
        return snapshot
    }

    func toggleProvider(id: String, active: Bool, for instance: GatewayInstance) async throws {
        let root = try GatewayURL.normalize(instance.rootURL)
        let response = try await requestJSON(root: root, path: "api/providers/\(safePathSegment(id))", method: "PATCH", body: ["isActive": active])
        guard (200..<300).contains(response.status) else { throw error(from: response) }
    }

    func testProvider(id: String, for instance: GatewayInstance) async throws {
        let root = try GatewayURL.normalize(instance.rootURL)
        let response = try await request(root: root, path: "api/providers/\(safePathSegment(id))/test", method: "POST")
        guard (200..<300).contains(response.status) else { throw error(from: response) }
    }

    func createProvider(
        provider: GatewayProviderCatalogItem,
        name: String,
        apiKey: String,
        for instance: GatewayInstance
    ) async throws {
        let root = try GatewayURL.normalize(instance.rootURL)
        var body: [String: Any] = ["provider": provider.id, "name": name, "priority": 0]
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["apiKey"] = apiKey }
        let response = try await requestJSON(root: root, path: "api/providers", method: "POST", body: body)
        guard (200..<300).contains(response.status) else { throw error(from: response) }
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

    private func requestJSON(
        root: URL,
        path: String,
        method: String,
        body: [String: Any]
    ) async throws -> (status: Int, data: Data) {
        let url = root.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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

    private func optionalJSONObject(root: URL, path: String) async -> [String: Any]? {
        guard let response = try? await request(root: root, path: path), (200..<300).contains(response.status) else { return nil }
        return jsonObject(response.data) as? [String: Any]
    }

    private func optionalJSONArray(root: URL, path: String) async -> [[String: Any]]? {
        guard let response = try? await request(root: root, path: path), (200..<300).contains(response.status) else { return nil }
        if let array = jsonObject(response.data) as? [[String: Any]] { return array }
        let object = jsonObject(response.data) as? [String: Any]
        return (object?["logs"] as? [[String: Any]]) ?? (object?["data"] as? [[String: Any]])
    }

    private func populateOverview(
        _ snapshot: inout GatewayDashboard,
        monitoring: [String: Any]?,
        database: [String: Any]?,
        tokenPool: [String: Any]?
    ) {
        let system = monitoring?["system"] as? [String: Any]
        let memory = (system?["memoryUsage"] as? [String: Any]) ?? (monitoring?["memoryUsage"] as? [String: Any])
        snapshot.uptimeSeconds = number(monitoring?["uptime"]) ?? number(system?["uptime"])
        snapshot.nodeVersion = string(system?["nodeVersion"])
        snapshot.platform = string(system?["platform"])
        snapshot.activeConnections = integer(monitoring?["activeConnections"]) ?? integer((monitoring?["sessions"] as? [String: Any])?["activeCount"])
        snapshot.memory = GatewayMemory(rssBytes: number(memory?["rss"]), heapUsedBytes: number(memory?["heapUsed"]), heapTotalBytes: number(memory?["heapTotal"]))
        snapshot.databaseHealthy = bool(database?["isHealthy"])
        snapshot.tokenPool = GatewayTokenPool(
            recurring: number(tokenPool?["steadyRecurringTokens"]),
            firstMonth: number(tokenPool?["firstMonthRealisticTokens"]),
            boost: number(tokenPool?["boostMonthlyTokens"]),
            modelCount: integer(tokenPool?["modelCount"])
        )
        let providerSummary = monitoring?["providerSummary"] as? [String: Any]
        snapshot.providerSummary = GatewayProviderSummary(
            active: integer(providerSummary?["activeCount"]),
            configured: integer(providerSummary?["configuredCount"]),
            catalog: integer(providerSummary?["catalogCount"])
        )
    }

    private func parseProviders(_ response: [String: Any]?) -> [GatewayProvider] {
        let values = response?["connections"] as? [[String: Any]] ?? response?["providers"] as? [[String: Any]] ?? []
        return values.compactMap { value in
            guard let id = string(value["id"]) ?? string(value["provider"]) else { return nil }
            let provider = string(value["provider"]) ?? id
            return GatewayProvider(
                id: id,
                name: string(value["name"]) ?? provider.capitalized,
                provider: provider,
                authType: string(value["authType"]),
                isActive: bool(value["isActive"]),
                modelCount: integer(value["modelCount"]),
                testStatus: string(value["testStatus"])
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseProviderCatalog(_ response: [String: Any]?) -> [GatewayProviderCatalogItem] {
        guard let response else { return [] }
        let values = (response["providers"] as? [String: Any]) ?? response
        return values.compactMap { key, raw in
            guard let value = raw as? [String: Any] else { return nil }
            let models = value["models"] as? [Any] ?? []
            let name = string(value["name"]) ?? string(value["alias"]) ?? key
            return GatewayProviderCatalogItem(
                id: string(value["id"]) ?? string(value["alias"]) ?? key,
                name: name,
                authType: string(value["authType"]),
                modelCount: models.count,
                isFreeTier: key.lowercased().contains("free") || name.lowercased().contains("free")
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseModels(_ response: [String: Any]?) -> [GatewayModel] {
        let values = response?["models"] as? [[String: Any]] ?? response?["data"] as? [[String: Any]] ?? []
        return values.compactMap { value in
            let provider = string(value["provider"]) ?? "Gateway"
            guard let id = string(value["fullModel"]) ?? string(value["id"]) ?? string(value["model"]) else { return nil }
            return GatewayModel(id: id, name: string(value["name"]) ?? id, provider: provider, available: bool(value["available"]))
        }
    }

    private func parseCombos(_ response: [String: Any]?) -> [GatewayCombo] {
        let values = response?["combos"] as? [[String: Any]] ?? []
        return values.compactMap { value in
            guard let id = string(value["id"]) else { return nil }
            return GatewayCombo(
                id: id,
                name: string(value["name"]) ?? id,
                candidateCount: integer(value["candidateCount"]),
                contextLength: integer(value["context_length"]) ?? integer(value["contextLength"])
            )
        }
    }

    private func parseConsoleLogs(_ values: [[String: Any]]?) -> [GatewayConsoleLog] {
        (values ?? []).compactMap { value in
            guard let timestamp = string(value["timestamp"]) else { return nil }
            let message = string(value["msg"]) ?? string(value["message"]) ?? "–"
            return GatewayConsoleLog(id: "\(timestamp)-\(message)", timestamp: timestamp, level: string(value["level"]) ?? "info", component: string(value["component"]), message: message)
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    private func parseCallLogs(_ values: [[String: Any]]?) -> [GatewayCallLog] {
        (values ?? []).compactMap { value in
            guard let id = string(value["id"]) ?? string(value["correlationId"]), let timestamp = string(value["timestamp"]) else { return nil }
            return GatewayCallLog(
                id: id,
                timestamp: timestamp,
                model: string(value["model"]) ?? string(value["requestedModel"]),
                provider: string(value["providerDisplay"]) ?? string(value["provider"]),
                status: integer(value["status"]),
                durationMilliseconds: number(value["duration"]),
                error: string(value["error"])
            )
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    private func safePathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func integer(_ value: Any?) -> Int? { number(value).map { Int($0) } }
    private func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return ["true", "1", "yes", "ok", "healthy"].contains(value.lowercased()) }
        return nil
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
