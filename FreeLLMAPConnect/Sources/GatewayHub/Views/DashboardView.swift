import SwiftUI

struct DashboardView: View {
    @Environment(GatewayStore.self) private var store

    var body: some View {
        Group {
            if let instance = store.selectedInstance {
                DashboardContent(instance: instance, snapshot: store.dashboard(for: instance))
            } else {
                ContentUnavailableView("Kein Server ausgewählt", systemImage: "server.rack")
            }
        }
        .navigationTitle("Übersicht")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let instance = store.selectedInstance { Task { await store.refresh(instance) } }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Aktive Instanz aktualisieren")
            }
        }
    }
}

private struct DashboardContent: View {
    @Environment(GatewayStore.self) private var store
    let instance: GatewayInstance
    let snapshot: GatewayDashboard

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                DashboardHeader(instance: instance, health: snapshot.health)
                GatewayStatusCard(snapshot: snapshot)
                MetricsGrid(snapshot: snapshot)
                if let pool = snapshot.tokenPool { TokenPoolCard(pool: pool) }
                if snapshot.unavailableSections.contains(.overview) {
                    UnavailableNotice(title: "Einige Detailwerte fehlen", message: "Diese Instanz liefert einzelne Management-Endpunkte nicht oder die Anmeldung fehlt.")
                }
            }
            .padding()
        }
        .refreshable { await store.refresh(instance) }
        .task(id: instance.id) { await store.refresh(instance) }
    }
}

private struct DashboardHeader: View {
    let instance: GatewayInstance
    let health: GatewayHealth

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: instance.kind == .omniRoute ? "point.3.connected.trianglepath.dotted" : "sparkles")
                .font(.title2)
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(instance.name).font(.title2.bold())
                Text(instance.kind.title).foregroundStyle(.secondary)
                Text(instance.rootURL).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            StatusPill(health: health)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GatewayStatusCard: View {
    let snapshot: GatewayDashboard

    var body: some View {
        DashboardCard(title: "Gateway-Status", systemImage: "checkmark.shield") {
            Text(snapshot.health.state.title)
                .font(.title2.bold())
                .foregroundStyle(statusColor)
            Divider()
            DashboardMetricRow(label: "Antwort", value: snapshot.health.message)
            DashboardMetricRow(label: "Uptime", value: formattedUptime(snapshot.uptimeSeconds))
            DashboardMetricRow(label: "Node", value: snapshot.nodeVersion ?? "–")
            DashboardMetricRow(label: "Aktive Verbindungen", value: snapshot.activeConnections.map(String.init) ?? "–")
            DashboardMetricRow(label: "Plattform", value: snapshot.platform ?? "–")
            DashboardMetricRow(label: "Ping", value: snapshot.health.latencyMilliseconds.map { "\($0) ms" } ?? "–")
        }
    }

    private var statusColor: Color {
        switch snapshot.health.state {
        case .healthy: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }
}

private struct MetricsGrid: View {
    let snapshot: GatewayDashboard

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            CompactMetricCard(title: "Speicher (RSS)", value: formattedBytes(snapshot.memory?.rssBytes), systemImage: "memorychip")
            CompactMetricCard(title: "Heap belegt", value: formattedBytes(snapshot.memory?.heapUsedBytes), systemImage: "internaldrive")
            CompactMetricCard(title: "Heap gesamt", value: formattedBytes(snapshot.memory?.heapTotalBytes), systemImage: "archivebox")
            CompactMetricCard(title: "Datenbank", value: snapshot.databaseHealthy == nil ? "–" : (snapshot.databaseHealthy == true ? "OK" : "Prüfen"), systemImage: "cylinder", tint: snapshot.databaseHealthy == true ? .green : .indigo)
        }
    }
}

private struct TokenPoolCard: View {
    let pool: GatewayTokenPool

    var body: some View {
        DashboardCard(title: "Free-Tier Token-Pool", systemImage: "gift") {
            DashboardMetricRow(label: "Wiederkehrend / Monat", value: formattedTokens(pool.recurring))
            DashboardMetricRow(label: "Realistisch 1. Monat", value: formattedTokens(pool.firstMonth))
            DashboardMetricRow(label: "Boost / Monat", value: formattedTokens(pool.boost))
            DashboardMetricRow(label: "Modelle", value: pool.modelCount.map(String.init) ?? "–")
        }
    }
}

struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage).font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: 22))
    }
}

private struct CompactMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(tint)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: 20))
    }
}

struct DashboardMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct UnavailableNotice: View {
    let title: String
    let message: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 18))
    }
}

private func formattedBytes(_ bytes: Double?) -> String {
    guard let bytes else { return "–" }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
}

private func formattedTokens(_ tokens: Double?) -> String {
    guard let tokens else { return "–" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 2
    if tokens >= 1_000_000_000 { return "\(formatter.string(from: NSNumber(value: tokens / 1_000_000_000)) ?? "0")B" }
    if tokens >= 1_000_000 { return "\(formatter.string(from: NSNumber(value: tokens / 1_000_000)) ?? "0")M" }
    return formatter.string(from: NSNumber(value: tokens)) ?? "–"
}

private func formattedUptime(_ seconds: Double?) -> String {
    guard let seconds else { return "–" }
    let hours = Int(seconds) / 3_600
    let days = hours / 24
    return days > 0 ? "\(days) T. \(hours % 24) Std." : "\(hours) Std."
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
