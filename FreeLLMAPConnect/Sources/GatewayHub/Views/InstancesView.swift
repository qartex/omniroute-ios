import SwiftUI

struct InstancesView: View {
    @Environment(GatewayStore.self) private var store
    let edit: (EditorDestination) -> Void
    @State private var instancePendingDeletion: GatewayInstance?

    var body: some View {
        List {
            ForEach(store.instances) { instance in
                Button {
                    store.selectedID = instance.id
                } label: {
                    InstanceRow(instance: instance, isSelected: instance.id == store.selectedInstance?.id)
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { instancePendingDeletion = instance } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                    Button { edit(.edit(instance)) } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    .tint(.indigo)
                }
            }
        }
        .navigationTitle("Server")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { edit(.add) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Server hinzufügen")
            }
        }
        .confirmationDialog(
            "Server wirklich entfernen?",
            isPresented: Binding(get: { instancePendingDeletion != nil }, set: { if !$0 { instancePendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Server entfernen", role: .destructive) {
                if let instancePendingDeletion { store.delete(instancePendingDeletion) }
                instancePendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) { instancePendingDeletion = nil }
        } message: {
            Text("Die lokalen Zugangsdaten für diesen Server werden ebenfalls entfernt.")
        }
    }
}

private struct InstanceRow: View {
    let instance: GatewayInstance
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: instance.kind == .omniRoute ? "point.3.connected.trianglepath.dotted" : "sparkles")
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(instance.name).font(.headline)
                    if isSelected { Text("Aktiv").font(.caption2.weight(.semibold)).foregroundStyle(.indigo) }
                }
                Text(instance.kind.title + " · " + instance.rootURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            StatusPill(health: instance.lastHealth)
        }
        .accessibilityElement(children: .combine)
    }
}
