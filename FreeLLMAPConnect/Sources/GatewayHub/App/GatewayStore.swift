import Foundation
import Observation

@MainActor
@Observable
final class GatewayStore {
    private(set) var instances: [GatewayInstance] = []
    var selectedID: UUID?
    private(set) var refreshingIDs: Set<UUID> = []
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
