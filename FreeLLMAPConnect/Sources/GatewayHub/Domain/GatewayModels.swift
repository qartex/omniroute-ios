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

struct GatewayHealth: Codable, Hashable, Sendable {
    var state: HealthState
    var message: String
    var version: String?
    var latencyMilliseconds: Int?

    enum HealthState: String, Codable, Hashable, Sendable {
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
    var authToken: String? = nil  // FreeLLMAP Bearer token
}

enum DashboardSection: String, CaseIterable, Hashable, Sendable {
    case overview
    case activity
    case providers
    case models
}

struct GatewayDashboard: Hashable, Sendable {
    var health: GatewayHealth
    var uptimeSeconds: Double? = nil
    var nodeVersion: String? = nil
    var platform: String? = nil
    var activeConnections: Int? = nil
    var memory: GatewayMemory? = nil
    var databaseHealthy: Bool? = nil
    var tokenPool: GatewayTokenPool? = nil
    var providerSummary: GatewayProviderSummary? = nil
    var providers: [GatewayProvider] = []
    var providerCatalog: [GatewayProviderCatalogItem] = []
    var models: [GatewayModel] = []
    var combos: [GatewayCombo] = []
    var consoleLogs: [GatewayConsoleLog] = []
    var callLogs: [GatewayCallLog] = []
    var unavailableSections: Set<DashboardSection> = []

    static func placeholder(health: GatewayHealth) -> GatewayDashboard {
        GatewayDashboard(health: health)
    }
}

struct GatewayMemory: Hashable, Sendable {
    var rssBytes: Double?
    var heapUsedBytes: Double?
    var heapTotalBytes: Double?
}

struct GatewayTokenPool: Hashable, Sendable {
    var recurring: Double?
    var firstMonth: Double?
    var boost: Double?
    var modelCount: Int?
}

struct GatewayProviderSummary: Hashable, Sendable {
    var active: Int?
    var configured: Int?
    var catalog: Int?
}

struct GatewayProvider: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var provider: String
    var authType: String?
    var isActive: Bool?
    var modelCount: Int?
    var testStatus: String?
}

struct GatewayProviderCatalogItem: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var authType: String?
    var modelCount: Int
    var isFreeTier: Bool
}

struct GatewayModel: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var provider: String
    var available: Bool?
}

struct GatewayCombo: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var candidateCount: Int?
    var contextLength: Int?
}

struct GatewayConsoleLog: Identifiable, Hashable, Sendable {
    var id: String
    var timestamp: String
    var level: String
    var component: String?
    var message: String
}

struct GatewayCallLog: Identifiable, Hashable, Sendable {
    var id: String
    var timestamp: String
    var model: String?
    var provider: String?
    var status: Int?
    var durationMilliseconds: Double?
    var error: String?
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
