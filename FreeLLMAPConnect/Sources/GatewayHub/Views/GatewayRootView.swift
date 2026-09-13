import SwiftUI

struct GatewayRootView: View {
    @Environment(GatewayStore.self) private var store
    @State private var editor: EditorDestination?

    var body: some View {
        Group {
            if store.instances.isEmpty {
                WelcomeView { editor = .add }
            } else {
                TabView {
                    NavigationStack {
                        DashboardView()
                    }
                    .tabItem { Label("Übersicht", systemImage: "gauge.with.dots.needle.50percent") }

                    NavigationStack {
                        ActivityView()
                    }
                    .tabItem { Label("Aktivität", systemImage: "waveform.path.ecg") }

                    NavigationStack {
                        ProvidersView()
                    }
                    .tabItem { Label("Provider", systemImage: "server.rack") }

                    NavigationStack {
                        ModelsView()
                    }
                    .tabItem { Label("Modelle", systemImage: "cpu") }

                    NavigationStack {
                        MoreView { editor = $0 }
                    }
                    .tabItem { Label("Mehr", systemImage: "ellipsis") }
                }
            }
        }
        .tint(.indigo)
        .sheet(item: $editor) { destination in
            ConnectionEditor(instance: destination.instance)
        }
        .alert("Gateway Hub", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.clearNotice() } }
        )) {
            Button("OK", role: .cancel) { store.clearNotice() }
        } message: {
            Text(store.notice ?? "")
        }
    }
}

enum EditorDestination: Identifiable {
    case add
    case edit(GatewayInstance)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let instance): instance.id.uuidString
        }
    }

    var instance: GatewayInstance? {
        if case let .edit(instance) = self { return instance }
        return nil
    }
}

private struct WelcomeView: View {
    let addServer: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 56))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Gateway Hub")
                    .font(.largeTitle.bold())
                Text("Verwalte FreeLLMAPI und OmniRoute zentral – auch mehrere Server gleichzeitig.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button(action: addServer) {
                Label("Ersten Server hinzufügen", systemImage: "plus.circle.fill")
                    .frame(maxWidth: 300)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Zugangsdaten bleiben ausschließlich in deinem iPhone-Schlüsselbund.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

struct MoreView: View {
    @Environment(GatewayStore.self) private var store
    let edit: (EditorDestination) -> Void

    var body: some View {
        @Bindable var store = store
        List {
            Section("Aktive Instanz") {
                Picker("Server", selection: $store.selectedID) {
                    ForEach(store.instances) { instance in
                        Text(instance.name).tag(Optional(instance.id))
                    }
                }
            }
            Section("Sicherheit") {
                Label("Passwörter und API-Keys werden pro Server im Schlüsselbund gespeichert.", systemImage: "key.horizontal.fill")
                Label("Management-Passwort und API-Key sind getrennte Berechtigungen.", systemImage: "lock.shield")
            }
            Section("Gespeicherte Verbindungen") {
                ForEach(store.instances) { instance in
                    Button {
                        edit(.edit(instance))
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(instance.name)
                                Text(instance.kind.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Mehr")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { edit(.add) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Server hinzufügen")
            }
        }
    }
}
