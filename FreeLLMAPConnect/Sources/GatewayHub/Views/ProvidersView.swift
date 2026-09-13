import SwiftUI

struct ProvidersView: View {
    @Environment(GatewayStore.self) private var store
    @State private var scope: ProviderScope = .connected
    @State private var searchText = ""
    @State private var selectedCatalogItem: GatewayProviderCatalogItem?

    var body: some View {
        Group {
            if let instance = store.selectedInstance {
                let snapshot = store.dashboard(for: instance)
                List {
                    Section {
                        Picker("Provider-Ansicht", selection: $scope) {
                            ForEach(ProviderScope.allCases) { scope in Text(scope.title).tag(scope) }
                        }
                        .pickerStyle(.segmented)
                        TextField("Provider suchen", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if snapshot.unavailableSections.contains(.providers) {
                        Section { UnavailableNotice(title: "Provider-Verwaltung nicht verfügbar", message: "Melde dich an oder prüfe, ob diese Instanz den Management-Endpunkt /api/providers anbietet.") }
                    } else if scope == .connected {
                        ConnectedProviderSection(providers: filtered(snapshot.providers), instance: instance)
                    } else {
                        ProviderCatalogSection(items: filtered(snapshot.providerCatalog)) { selectedCatalogItem = $0 }
                    }
                }
                .refreshable { await store.refresh(instance) }
            } else {
                ContentUnavailableView("Kein Server ausgewählt", systemImage: "server.rack")
            }
        }
        .navigationTitle("Provider")
        .toolbar { RefreshToolbarAction() }
        .sheet(item: $selectedCatalogItem) { item in
            ProviderSetupSheet(item: item)
        }
    }

    private func filtered(_ items: [GatewayProvider]) -> [GatewayProvider] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.provider.localizedCaseInsensitiveContains(searchText) }
    }

    private func filtered(_ items: [GatewayProviderCatalogItem]) -> [GatewayProviderCatalogItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.id.localizedCaseInsensitiveContains(searchText) }
    }
}

private enum ProviderScope: String, CaseIterable, Identifiable {
    case connected
    case catalog
    var id: String { rawValue }
    var title: String { self == .connected ? "Verbunden" : "Katalog" }
}

private struct ConnectedProviderSection: View {
    @Environment(GatewayStore.self) private var store
    let providers: [GatewayProvider]
    let instance: GatewayInstance

    var body: some View {
        Section(providers.isEmpty ? "Keine verbundenen Provider" : "Verbunden") {
            if providers.isEmpty {
                ContentUnavailableView("Keine Provider", systemImage: "server.rack")
            } else {
                ForEach(providers) { provider in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(provider.name).font(.headline)
                                Text(provider.provider).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(provider.isActive == true ? "aktiv" : "pausiert")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(provider.isActive == true ? .green : .orange)
                        }
                        HStack(spacing: 12) {
                            Label(provider.modelCount.map { "\($0) Modelle" } ?? "Modelle unbekannt", systemImage: "cpu")
                            if let auth = provider.authType { Label(auth, systemImage: "key") }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            Button("Testen", systemImage: "stethoscope") { Task { await store.testProvider(provider, for: instance) } }
                                .buttonStyle(.bordered)
                            Spacer()
                            Toggle("Aktiv", isOn: Binding(
                                get: { provider.isActive ?? false },
                                set: { _ in Task { await store.toggleProvider(provider, for: instance) } }
                            ))
                            .labelsHidden()
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct ProviderCatalogSection: View {
    let items: [GatewayProviderCatalogItem]
    let add: (GatewayProviderCatalogItem) -> Void

    var body: some View {
        Section(items.isEmpty ? "Kein Provider-Katalog" : "Katalog") {
            if items.isEmpty {
                ContentUnavailableView("Kein Katalog", systemImage: "shippingbox")
            } else {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.headline)
                            Text(item.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Label("\(item.modelCount) Modelle", systemImage: "cpu")
                                if let auth = item.authType { Label(auth, systemImage: "key") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 10) {
                            if item.isFreeTier { Text("free").font(.caption.weight(.bold)).foregroundStyle(.green) }
                            Button("Hinzufügen", systemImage: "plus.circle.fill") { add(item) }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct ProviderSetupSheet: View {
    @Environment(GatewayStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: GatewayProviderCatalogItem
    @State private var name: String
    @State private var apiKey = ""
    @State private var isSaving = false

    init(item: GatewayProviderCatalogItem) {
        self.item = item
        _name = State(initialValue: item.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    LabeledContent("Anbieter", value: item.name)
                    LabeledContent("Modelle", value: "\(item.modelCount)")
                }
                Section("Verbindung") {
                    TextField("Anzeigename", text: $name)
                    SecureField("API-Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Der API-Key wird ausschließlich an die ausgewählte Gateway-Instanz gesendet und nicht in der App gespeichert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Provider hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Füge hinzu …" : "Hinzufügen") {
                        guard let instance = store.selectedInstance else { return }
                        Task {
                            isSaving = true
                            if await store.addProvider(item, name: name, apiKey: apiKey, to: instance) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
