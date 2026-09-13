import SwiftUI

struct DashboardView: View {
    @Environment(GatewayStore.self) private var store

    var body: some View {
        Group {
            if let instance = store.selectedInstance {
                DashboardContent(instance: instance)
            } else {
                ContentUnavailableView("Kein Server ausgewählt", systemImage: "server.rack")
            }
        }
        .navigationTitle("Status")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Alle Server aktualisieren")
            }
        }
    }
}

private struct DashboardContent: View {
    @Environment(GatewayStore.self) private var store
    let instance: GatewayInstance

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: instance.kind == .omniRoute ? "point.3.connected.trianglepath.dotted" : "sparkles")
                            .font(.title2)
                            .foregroundStyle(.indigo)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(instance.name).font(.title3.bold())
                            Text(instance.kind.title).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(health: instance.lastHealth)
                    }
                    Text(instance.rootURL).font(.footnote.monospaced()).foregroundStyle(.secondary)
                    if instance.rootURL.lowercased().hasPrefix("http://") {
                        Label("Die Verbindung läuft unverschlüsselt. Für öffentliche Server HTTPS verwenden.", systemImage: "exclamationmark.shield.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section("Live-Status") {
                LabeledContent("Verbindung") { Text(instance.lastHealth?.state.title ?? "Noch nicht geprüft") }
                LabeledContent("Antwort") { Text(instance.lastHealth?.message ?? "–") }
                if let latency = instance.lastHealth?.latencyMilliseconds {
                    LabeledContent("Latenz") { Text("\(latency) ms") }
                }
                if let version = instance.lastHealth?.version {
                    LabeledContent("Version") { Text(version) }
                }
                if let updated = instance.lastUpdatedAt {
                    LabeledContent("Aktualisiert") { Text(updated, style: .relative) }
                }
            }

            Section {
                Button {
                    Task { await store.refresh(instance) }
                } label: {
                    Label(store.refreshingIDs.contains(instance.id) ? "Prüfe Verbindung …" : "Status aktualisieren", systemImage: "arrow.clockwise")
                }
                .disabled(store.refreshingIDs.contains(instance.id))
            }
        }
        .refreshable { await store.refresh(instance) }
        .task(id: instance.id) { await store.refresh(instance) }
    }
}

struct StatusPill: View {
    let health: GatewayHealth?

    private var state: GatewayHealth.HealthState { health?.state ?? .unknown }
    private var color: Color {
        switch state {
        case .healthy: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }

    var body: some View {
        Label(state.title, systemImage: state == .healthy ? "checkmark.circle.fill" : "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityLabel("Status: \(state.title)")
    }
}
