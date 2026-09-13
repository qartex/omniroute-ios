import SwiftUI

struct ActivityView: View {
    @Environment(GatewayStore.self) private var store
    @State private var source: ActivitySource = .calls

    var body: some View {
        Group {
            if let instance = store.selectedInstance {
                let snapshot = store.dashboard(for: instance)
                List {
                    Section {
                        Picker("Quelle", selection: $source) {
                            ForEach(ActivitySource.allCases) { source in Text(source.title).tag(source) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if snapshot.unavailableSections.contains(.activity) {
                        Section { UnavailableNotice(title: "Aktivität nicht verfügbar", message: "Melde dich an oder prüfe, ob dieser Server Call-Logs und Konsolen-Logs bereitstellt.") }
                    } else if source == .calls {
                        CallLogSection(logs: snapshot.callLogs)
                    } else {
                        ConsoleLogSection(logs: snapshot.consoleLogs)
                    }
                }
                .refreshable { await store.refresh(instance) }
            } else {
                ContentUnavailableView("Kein Server ausgewählt", systemImage: "waveform.path.ecg")
            }
        }
        .navigationTitle("Aktivität")
        .toolbar { RefreshToolbarAction() }
    }
}

private enum ActivitySource: String, CaseIterable, Identifiable {
    case calls
    case console

    var id: String { rawValue }
    var title: String { self == .calls ? "Aufrufe" : "Konsole" }
}

private struct CallLogSection: View {
    let logs: [GatewayCallLog]

    var body: some View {
        Section(logs.isEmpty ? "Keine Aufrufe" : "Letzte Aufrufe") {
            if logs.isEmpty {
                ContentUnavailableView("Noch keine Call-Logs", systemImage: "clock.arrow.circlepath")
            } else {
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(log.model ?? "Unbekanntes Modell").font(.headline)
                            Spacer()
                            if let status = log.status {
                                Text("HTTP \(status)").foregroundStyle(status < 400 ? .green : .red).font(.caption.weight(.semibold))
                            }
                        }
                        Text(log.provider ?? "Provider nicht angegeben").foregroundStyle(.secondary)
                        HStack {
                            Text(log.timestamp).font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                            if let duration = log.durationMilliseconds { Text("\(Int(duration)) ms").font(.caption.monospaced()).foregroundStyle(.secondary) }
                        }
                        if let error = log.error, !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct ConsoleLogSection: View {
    let logs: [GatewayConsoleLog]

    var body: some View {
        Section(logs.isEmpty ? "Keine Konsolen-Logs" : "Konsolen-Logs") {
            if logs.isEmpty {
                ContentUnavailableView("Keine Konsolen-Logs", systemImage: "terminal")
            } else {
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(log.level.uppercased()).font(.caption.weight(.bold)).foregroundStyle(log.level.lowercased().contains("error") ? .red : .indigo)
                            Spacer()
                            Text(log.timestamp).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        }
                        Text(log.message).font(.subheadline)
                        if let component = log.component { Text(component).font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct RefreshToolbarAction: ToolbarContent {
    @Environment(GatewayStore.self) private var store

    var body: some ToolbarContent {
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
