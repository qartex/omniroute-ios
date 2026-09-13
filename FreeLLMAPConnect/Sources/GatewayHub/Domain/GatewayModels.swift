import Foundation

enum GatewayKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case omniRoute
    case freeLLMAPI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .omniRoute: "OmniRoute"
        case .freeLLMAPI: "FreeLLMAPI"
        }
    }

    var subtitle: String {
        switch self {
        case .omniRoute: "Gateway verwalten, Anbieter und Routing überwachen"
        case .freeLLMAPI: "Modelle, Budget und Routing verwalten"
        }
    }

    var requiresEmail: Bool { self == .freeLLMAPI }
    var managementPasswordLabel: String { self == .omniRoute ? "Management-Passwort" : "Passwort" }
}

struct GatewayInstance: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var kind: GatewayKind
    var rootURL: String
    var email: String?
    var lastHealth: GatewayHealth?
    var lastUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        kind: GatewayKind,
        rootURL: String,
        email: String? = nil,
        lastHealth: GatewayHealth? = nil,
        lastUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rootURL = rootURL
        self.email = email
        self.lastHealth = lastHealth
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct GatewayHealth: Codable, Hashable {
    var state: HealthState
    var message: String
    var version: String?
    var latencyMilliseconds: Int?

    enum HealthState: String, Codable, Hashable {
        case healthy
        case warning
        case offline
        case unknown

        var title: String {
            switch self {
            case .healthy: "Erreichbar"
            case .warning: "Eingeschränkt"
            case .offline: "Nicht erreichbar"
            case .unknown: "Noch nicht geprüft"
            }
        }
    }
}

struct GatewayCredentials: Equatable {
    var managementPassword: String = ""
    var apiKey: String = ""
}

struct GatewayURL {
    static func normalize(_ value: String) throws -> URL {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GatewayClientError.invalidURL }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text), components.host != nil else {
            throw GatewayClientError.invalidURL
        }
        var segments = components.path.split(separator: "/").map(String.init)
        // Users frequently copy the dashboard URL (for example /home). API and
        // management endpoints always live at the server root, never below it.
        if ["v1", "home", "dashboard"].contains(segments.first?.lowercased() ?? "") {
            segments = []
        } else if segments.last?.lowercased() == "v1" {
            segments.removeLast()
        }
        components.path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        guard let normalized = components.url else { throw GatewayClientError.invalidURL }
        return normalized
    }

    static func apiURL(for rootURL: URL) -> URL { rootURL.appendingPathComponent("v1") }
}
