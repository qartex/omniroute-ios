import SwiftUI

struct ModelsView: View {
    @Environment(GatewayStore.self) private var store
    @State private var scope: ModelScope = .models
    @State private var searchText = ""

    var body: some View {
        Group {
            if let instance = store.selectedInstance {
                let snapshot = store.dashboard(for: instance)
                List {
                    Section {
                        Picker("Ansicht", selection: $scope) {
                            ForEach(ModelScope.allCases) { scope in Text(scope.title).tag(scope) }
                        }
                        .pickerStyle(.segmented)
                        TextField(scope == .models ? "Modelle suchen" : "Combos suchen", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if snapshot.unavailableSections.contains(.models) {
                        Section { UnavailableNotice(title: "Modelldaten nicht verfügbar", message: "Melde dich an oder prüfe, ob diese Instanz /api/models und /api/combos/auto bereitstellt.") }
                    } else if scope == .models {
                        ModelListSection(models: filtered(snapshot.models))
                    } else {
                        ComboListSection(combos: filtered(snapshot.combos))
                    }
                }
                .refreshable { await store.refresh(instance) }
            } else {
                ContentUnavailableView("Kein Server ausgewählt", systemImage: "cpu")
            }
        }
        .navigationTitle(scope == .models ? "Modelle" : "Combos")
        .toolbar { RefreshToolbarAction() }
    }

    private func filtered(_ models: [GatewayModel]) -> [GatewayModel] {
        guard !searchText.isEmpty else { return models }
        return models.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.id.localizedCaseInsensitiveContains(searchText) || $0.provider.localizedCaseInsensitiveContains(searchText) }
    }

    private func filtered(_ combos: [GatewayCombo]) -> [GatewayCombo] {
        guard !searchText.isEmpty else { return combos }
        return combos.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.id.localizedCaseInsensitiveContains(searchText) }
    }
}

private enum ModelScope: String, CaseIterable, Identifiable {
    case models
    case combos
    var id: String { rawValue }
    var title: String { self == .models ? "Modelle" : "Combos" }
}

private struct ModelListSection: View {
    let models: [GatewayModel]

    var body: some View {
        Section(models.isEmpty ? "Keine Modelle" : "\(models.count) Modelle") {
            if models.isEmpty {
                ContentUnavailableView("Keine Modelle", systemImage: "cpu")
            } else {
                ForEach(models) { model in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.name).font(.headline)
                            Spacer()
                            if model.available == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Verfügbar") }
                        }
                        Text(model.id).font(.caption.monospaced()).foregroundStyle(.indigo)
                        Text(model.provider).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct ComboListSection: View {
    let combos: [GatewayCombo]

    var body: some View {
        Section(combos.isEmpty ? "Keine Auto-Combos" : "Auto-Combos") {
            if combos.isEmpty {
                ContentUnavailableView("Keine Combos", systemImage: "sparkles")
            } else {
                ForEach(combos) { combo in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(combo.name).font(.headline)
                            Spacer()
                            Text(combo.id).font(.caption.monospaced()).foregroundStyle(.indigo)
                        }
                        Text(comboSummary(combo)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func comboSummary(_ combo: GatewayCombo) -> String {
        let candidates = combo.candidateCount.map { "\($0) Kandidaten" } ?? "Kandidaten unbekannt"
        let context = combo.contextLength.map { "Kontext \(formatContext($0))" } ?? "Kontext unbekannt"
        return "\(candidates) · \(context)"
    }

    private func formatContext(_ value: Int) -> String {
        value >= 1_000_000 ? "\(String(format: "%.2f", Double(value) / 1_000_000))M" : "\(value / 1_000)K"
    }
}
