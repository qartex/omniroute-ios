import Foundation
import Observation

@MainActor
@Observable
final class GatewayStore {
    private(set) var instances: [GatewayInstance] = []
    var selectedID: UUID?
    private(set) var refreshingIDs: Set<UUID> = []
    private(set) var dashboards: [UUID: GatewayDashboard] = [:]
    private(set) var notice: String?

    @ObservationIgnored private let client = GatewayClient()
    @ObservationIgnored private let defaultsKey = "gatewayhub.instances.v2"
    @ObservationIgnored private let selectedKey = "gatewayhub.selected.v2"

    init() {
        load()
    }

    var selectedInstance: GatewayInstance? {
        instances.first { $0.id == selectedID } ?? instances.first
    }

    func credentials(for instance: GatewayInstance) -> GatewayCredentials {
        GatewayCredentials.load(for: instance.id)
    }

    func save(_ instance: GatewayInstance, credentials: GatewayCredentials) {
        var sanitized = instance
        sanitized.rootURL = (try? GatewayURL.normalize(instance.rootURL).absoluteString) ?? instance.rootURL
        if let index = instances.firstIndex(where: { $0.id == sanitized.id }) {
            instances[index] = sanitized
        } else {
            instances.append(sanitized)
        }
        credentials.save(for: sanitized.id)
        selectedID = sanitized.id
        persist()
    }

    func delete(_ instance: GatewayInstance) {
        instances.removeAll { $0.id == instance.id }
        dashboards[instance.id] = nil
        GatewayCredentials.delete(for: instance.id)
        if selectedID == instance.id { selectedID = instances.first?.id }
        persist()
    }

    func refresh(_ instance: GatewayInstance) async {
        refreshingIDs.insert(instance.id)
        let health = await client.health(for: instance)
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index].lastHealth = health
            instances[index].lastUpdatedAt = .now
            persist()
        }
        let dashboard = await client.dashboard(for: instance)
        dashboards[instance.id] = dashboard
        refreshingIDs.remove(instance.id)
    }

    func refreshAll() async {
        for instance in instances { await refresh(instance) }
    }

    func signIn(_ instance: GatewayInstance, credentials: GatewayCredentials) async -> Bool {
        do {
            try await client.login(instance: instance, credentials: credentials)
            credentials.save(for: instance.id)
            notice = "Bei \(instance.name) angemeldet."
            await refresh(instance)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    func verifyAPIKey(_ instance: GatewayInstance, credentials: GatewayCredentials) async -> String? {
        do {
            let count = try await client.verifyAPIKey(for: instance, credentials: credentials)
            return count > 0 ? "API-Key gültig – \(count) Modelle gefunden." : "Kein API-Key hinterlegt."
        } catch { return error.localizedDescription }
    }

    func dashboard(for instance: GatewayInstance) -> GatewayDashboard {
        dashboards[instance.id] ?? .placeholder(health: instance.lastHealth ?? GatewayHealth(state: .unknown, message: "Noch nicht geprüft"))
    }

    func toggleProvider(_ provider: GatewayProvider, for instance: GatewayInstance) async {
        do {
            try await client.toggleProvider(id: provider.id, active: !(provider.isActive ?? false), for: instance)
            notice = "\(provider.name) wurde \((provider.isActive ?? false) ? "deaktiviert" : "aktiviert")."
            await refresh(instance)
        } catch {
            notice = error.localizedDescription
        }
    }

    func testProvider(_ provider: GatewayProvider, for instance: GatewayInstance) async {
        do {
            try await client.testProvider(id: provider.id, for: instance)
            notice = "Provider-Test für \(provider.name) erfolgreich gestartet."
            await refresh(instance)
        } catch {
            notice = error.localizedDescription
        }
    }

    func addProvider(
        _ provider: GatewayProviderCatalogItem,
        name: String,
        apiKey: String,
        to instance: GatewayInstance
    ) async -> Bool {
        do {
            try await client.createProvider(provider: provider, name: name, apiKey: apiKey, for: instance)
            notice = "\(provider.name) wurde hinzugefügt."
            await refresh(instance)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    func clearNotice() { notice = nil }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([GatewayInstance].self, from: data) else { return }
        instances = decoded
        selectedID = UserDefaults.standard.string(forKey: selectedKey).flatMap(UUID.init(uuidString:)) ?? decoded.first?.id
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(instances) { UserDefaults.standard.set(data, forKey: defaultsKey) }
        UserDefaults.standard.set(selectedID?.uuidString, forKey: selectedKey)
    }
}
