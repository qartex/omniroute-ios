import Foundation

// MARK: - Auth

struct AuthStatus: Codable {
    var authenticated: Bool
}

struct LoginResult: Codable {
    var success: Bool
    var error: LoginError?
    
    enum CodingKeys: String, CodingKey {
        case success
        case error
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let success = try container.decodeIfPresent(Bool.self, forKey: .success) {
            self.success = success
        } else {
            self.success = false
        }
        self.error = try container.decodeIfPresent(LoginError.self, forKey: .error)
    }
}

struct LoginError: Codable {
    var message: String
    var type: String
}

// MARK: - System / Health

struct MonitoringHealth: Codable {
    var status: String?
    var timestamp: String?
    var version: String?
    var uptime: Double?
    var activeConnections: Int?
    var setupComplete: Bool?
    var circuitBreakers: CircuitBreakerSummary?
    var providerSummary: ProviderSummary?
    var providerHealth: [String: ProviderHealthEntry]?
    var sessions: SessionSummary?
    var system: SystemInfo?
    var memoryUsage: MemoryUsage?

    struct SystemInfo: Codable {
        var version: String?
        var nodeVersion: String?
        var uptime: Double?
        var pid: Int?
        var platform: String?
        var memoryUsage: MemoryUsage?
    }

    struct MemoryUsage: Codable {
        var rss: Double?
        var heapTotal: Double?
        var heapUsed: Double?
        var external: Double?
        var arrayBuffers: Double?
    }

    struct CircuitBreakerSummary: Codable {
        var closed: Int?
        var open: Int?
        var halfOpen: Int?
        var degraded: Int?
        var total: Int?
    }

    struct ProviderSummary: Codable {
        var activeCount: Int?
        var catalogCount: Int?
        var configuredCount: Int?
        var monitoredCount: Int?
    }

    struct ProviderHealthEntry: Codable {
        var state: String?
        var failures: Int?
        var retryAfterMs: Int?
        var lastFailure: String?
    }

    struct SessionSummary: Codable {
        var activeCount: Int?
        var stickyBoundCount: Int?
    }
}

struct PingResult: Codable {
    var status: String?
    var timestamp: String?
    var latencyMs: Double?
}

struct DegradationStatus: Codable {
    var active: Bool
    var summary: [String: Int]?
    var features: [String]?
}

struct DbHealth: Codable {
    var isHealthy: Bool
    var issues: [String]?
    var repairedCount: Int?
    var backupCreated: Bool?
    var autoRepair: Bool?
    var checkedAt: String?
}

struct McpStatus: Codable {
    var status: String?
    var online: Bool?
    var enabled: Bool?
    var transport: String?
    var activity: McpActivity?

    struct McpActivity: Codable {
        var totalCalls24h: Int?
        var successRate: Double?
        var avgDurationMs: Double?
        var topTools: [TopTool]?
        var lastCallAt: String?
        var lastCallTool: String?
    }

    struct TopTool: Codable {
        var tool: String?
        var calls: Int?
    }
}

struct HeadroomStatus: Codable {
    var installed: Bool?
    var running: Bool?
    var python: String?
    var url: String?
    var canStart: Bool?
}

// MARK: - Providers

struct ProvidersResponse: Codable {
    var connections: [ProviderConnection]
}

struct ProviderConnection: Codable, Identifiable, Hashable {
    var id: String
    var provider: String
    var name: String?
    var authType: String?
    var priority: Int?
    var isActive: Bool?
    var expiresAt: String?
    var tokenExpiresAt: String?
    var scope: String?
    var testStatus: String?
    var backoffLevel: Int?
    var lastHealthCheckAt: String?
    var lastTested: String?
    var tokenType: String?
    var expiresIn: Double?
    var consecutiveUseCount: Int?
    var rateLimitProtection: Bool?
    var proxyEnabled: Bool?
    var quotaVisible: Bool?
    var createdAt: String?
    var updatedAt: String?
}

struct ProviderStatsResponse: Codable {
    var providers: [ProviderStat]
}

struct ProviderStat: Codable, Identifiable, Hashable {
    var provider: String
    var nodeName: String?
    var totalRequests: Int?
    var successfulRequests: Int?
    var avgLatencyMs: Double?
    var totalTokensIn: Int?
    var totalTokensOut: Int?

    var id: String { provider }
}

struct ProviderMetricsResponse: Codable {
    var metrics: [String: ProviderMetric]
}

struct ProviderMetric: Codable, Hashable {
    var totalRequests: Int?
    var totalSuccesses: Int?
    var successRate: Double?
    var avgLatencyMs: Double?
    var lastRequestAt: String?
    var lastErrorAt: String?
    var lastStatus: Int?
    var lastErrorStatus: Int?
}

// MARK: - Activity / Logs / Audit

struct ConsoleLog: Codable, Identifiable, Hashable {
    var timestamp: String
    var level: String
    var component: String?
    var message: String
    var msg: String?

    var id: String { "\(timestamp)-\(message.prefix(40))" }
    var displayMessage: String { msg ?? message }
}

struct AuditEntry: Codable, Identifiable, Hashable {
    var id: Int
    var timestamp: String
    var action: String
    var actor: String?
    var target: String?
    var ip_address: String?
    var resource_type: String?
    var status: String?
    var request_id: String?
}

// MARK: - Call logs (activity protocol)

struct CallLog: Codable, Identifiable, Hashable {
    var id: String
    var timestamp: String
    var method: String?
    var path: String?
    var status: Int?
    var model: String?
    var requestedModel: String?
    var provider: String?
    var providerDisplay: String?
    var account: String?
    var duration: Double?
    var tokens: TokenCounts?
    var comboName: String?
    var error: String?
    var correlationId: String?
    var active: Bool?

    struct TokenCounts: Codable, Hashable {
        var in_: Int?
        var out: Int?

        enum CodingKeys: String, CodingKey { case in_ = "in", out }
    }
}

// MARK: - Models / Combos

struct ModelsResponse: Codable {
    var models: [ModelEntry]
}

struct ModelEntry: Codable, Identifiable, Hashable {
    var provider: String
    var model: String
    var name: String
    var fullModel: String?
    var alias: String?
    var available: Bool?

    var id: String { fullModel ?? "\(provider)/\(model)" }
}

struct CombosResponse: Codable {
    var combos: [ComboSummary]
    var total: Int?
}

struct ComboSummary: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var variant: String?
    var type: String?
    var isHidden: Bool?
    var candidateCount: Int?
    var context_length: Int?
    var max_output_tokens: Int?
    var candidatePool: [String]?
}

struct FreeModelsResponse: Codable {
    var models: [FreeModel]
}

struct FreeModel: Codable, Identifiable, Hashable {
    var provider: String
    var modelId: String
    var displayName: String
    var monthlyTokens: Int?
    var creditTokens: Int?
    var freeType: String?
    var poolKey: String?

    var id: String { "\(provider)/\(modelId)" }
}

struct FreeTierSummary: Codable {
    var steadyRecurringTokens: Double?
    var steadyWithRecurringCreditsTokens: Double?
    var firstMonthRealisticTokens: Double?
    var boostMonthlyTokens: Double?
    var uncappedProviders: [String]?
    var modelCount: Int?
    var poolCount: Int?
}

// MARK: - Analytics

struct CompressionAnalytics: Codable {
    var totalRequests: Int?
    var totalTokensSaved: Int?
    var avgSavingsPct: Double?
    var avgDurationMs: Double?
    var byMode: [String: Int]?
    var byEngine: [String: Int]?
    var byProvider: [String: Int]?
    var last24h: [HourlyPoint]
}

struct HourlyPoint: Codable, Identifiable, Hashable {
    var hour: String
    var count: Int?
    var tokensSaved: Int?

    var id: String { hour }
}

struct AutoRoutingAnalytics: Codable {
    var totalRequests: Int?
    var variantBreakdown: [String: Int]?
    var topProviders: [TopProvider]?

    struct TopProvider: Codable, Hashable {
        var provider: String?
        var requests: Int?
    }
}

struct CacheStats: Codable {
    var size: Int?
    var maxSize: Int?
    var bytes: Int?
    var maxBytes: Int?
    var hits: Int?
    var misses: Int?
    var evictions: Int?
    var hitRate: Double?
}

// MARK: - Settings

struct GatewaySettings: Codable {
    var cloudEnabled: Bool?
    var tailscaleEnabled: Bool?
    var tailscaleUrl: String?
    var comboStrategy: String?
    var requestRetry: Int?
    var maxRetryIntervalSec: Int?
    var requireLogin: Bool?
    var oidcEnabled: Bool?
    var promptCacheAffinityEnabled: Bool?
    var disableSessionStickiness: Bool?
    var stickyRoundRobinLimit: Int?
}

struct ConcurrencyStatus: Codable {
    var timestamp: String?
    var rateLimits: [String: String]?
    var semaphores: [String: Int]?
}

// MARK: - Provider catalog (pricing/models)

struct PricingModelsResponse: Codable {
    // response is a map of providerKey -> PricingProvider
    var providers: [String: PricingProvider] = [:]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        providers = try container.decode([String: PricingProvider].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(providers)
    }
}

struct PricingProvider: Codable, Identifiable, Hashable {
    var id: String?
    var alias: String?
    var name: String
    var authType: String?
    var format: String?
    var models: [PricingModel]?

    var key: String { alias ?? id ?? name }
}

struct PricingModel: Codable, Hashable {
    var id: String
    var name: String?
    var custom: Bool?
}

// MARK: - Combo create / provider create request bodies

struct ComboCreateRequest: Codable {
    var name: String
    var description: String?
    var strategy: String
    var models: [String]
}

struct ProviderCreateRequest: Codable {
    var provider: String
    var apiKey: String?
    var name: String
    var priority: Int?
    var providerSpecificData: ProviderSpecificData?
}

struct ProviderSpecificData: Codable {
    var importFreeModelsOnly: Bool?
}

struct ValidateProviderRequest: Codable {
    var provider: String
    var apiKey: String?
}

struct ValidateProviderResult: Codable {
    var valid: Bool
    var error: String?
}

// MARK: - Usage / Cost analytics

struct UsageAnalytics: Codable {
    var summary: UsageSummary
    var dailyTrend: [DailyTrendPoint]
    var byModel: [UsageByModel]
    var byProvider: [UsageByProvider]
    var range: String?
}

struct UsageSummary: Codable {
    var totalRequests: Int?
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var uniqueModels: Int?
    var uniqueAccounts: Int?
    var successfulRequests: Int?
    var successRatePct: Double?
    var avgLatencyMs: Double?
    var totalCost: Double?
    var fallbackCount: Int?
    var firstRequest: String?
    var lastRequest: String?
}

struct DailyTrendPoint: Codable, Identifiable, Hashable {
    var date: String
    var requests: Int?
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var cost: Double?
    var id: String { date }
}

struct UsageByModel: Codable, Identifiable, Hashable {
    var model: String
    var provider: String?
    var rawModel: String?
    var requests: Int?
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var avgLatencyMs: Double?
    var successRatePct: String?
    var lastUsed: String?
    var cost: Double?
    var id: String { model }

    var successRate: Double? {
        guard let s = successRatePct else { return nil }
        return Double(s.replacingOccurrences(of: "%", with: ""))
    }
}

struct UsageByProvider: Codable, Identifiable, Hashable {
    var provider: String
    var requests: Int?
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var avgLatencyMs: Double?
    var successRatePct: String?
    var cost: Double?
    var id: String { provider }

    var successRate: Double? {
        guard let s = successRatePct else { return nil }
        return Double(s.replacingOccurrences(of: "%", with: ""))
    }
}