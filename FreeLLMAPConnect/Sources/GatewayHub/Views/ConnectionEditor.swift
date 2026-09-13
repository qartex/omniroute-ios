import SwiftUI

struct ConnectionEditor: View {
    @Environment(GatewayStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let existing: GatewayInstance?

    @State private var kind: GatewayKind
    @State private var name: String
    @State private var rootURL: String
    @State private var email: String
    @State private var password: String
    @State private var apiKey: String
    @State private var showPassword = false
    @State private var showAPIKey = false
    @State private var isConnecting = false
    @State private var resultMessage: String?

    init(instance: GatewayInstance?) {
        existing = instance
        _kind = State(initialValue: instance?.kind ?? .omniRoute)
        _name = State(initialValue: instance?.name ?? "")
        _rootURL = State(initialValue: instance?.rootURL ?? "")
        _email = State(initialValue: instance?.email ?? "")
        let credentials = instance.map { GatewayCredentials.load(for: $0.id) } ?? GatewayCredentials()
        _password = State(initialValue: credentials.managementPassword)
        _apiKey = State(initialValue: credentials.apiKey)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Servertyp") {
                    Picker("Software", selection: $kind) {
                        ForEach(GatewayKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(kind.subtitle).font(.footnote).foregroundStyle(.secondary)
                }

                Section("Verbindung") {
                    TextField("Anzeigename", text: $name, prompt: Text(kind.title + " Server"))
                    TextField("Server-URL", text: $rootURL, prompt: Text(defaultURL))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    if rootURL.lowercased().hasPrefix("http://") {
                        Label("HTTP ist nur für vertrauenswürdige private Server geeignet.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Management-Anmeldung") {
                    if kind.requiresEmail {
                        TextField("E-Mail", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Group {
                            if showPassword {
                                TextField(kind.managementPasswordLabel, text: $password)
                            } else {
                                SecureField(kind.managementPasswordLabel, text: $password)
                            }
                        }
                        .textContentType(.password)
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(showPassword ? "Passwort verbergen" : "Passwort anzeigen")
                    }
                    Text(kind == .omniRoute
                         ? "OmniRoute benötigt das Management-Passwort – keinen API-Key und keine E-Mail."
                         : "FreeLLMAPI verwendet E-Mail und Passwort.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("API-Zugang (optional)") {
                    HStack {
                        Group {
                            if showAPIKey { TextField("API-Key", text: $apiKey) }
                            else { SecureField("API-Key", text: $apiKey) }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button { showAPIKey.toggle() } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(showAPIKey ? "API-Key verbergen" : "API-Key anzeigen")
                    }
                    Text("Wird getrennt vom Management-Passwort gespeichert und für /v1/models geprüft.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let resultMessage {
                    Section("Ergebnis") {
                        Text(resultMessage)
                            .foregroundStyle(resultMessage.hasPrefix("Erfolgreich") ? .green : .red)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Server hinzufügen" : "Server bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isConnecting ? "Verbinde …" : "Sichern") {
                        Task { await saveAndConnect() }
                    }
                    .disabled(isConnecting || rootURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var defaultURL: String {
        kind == .omniRoute ? "https://gateway.example.com" : "https://freellmapi.example.com"
    }

    private func saveAndConnect() async {
        guard let normalizedURL = try? GatewayURL.normalize(rootURL).absoluteString else {
            resultMessage = "Die Server-URL ist ungültig."
            return
        }
        let instance = GatewayInstance(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.title : name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            rootURL: normalizedURL,
            email: kind.requiresEmail ? email.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            lastHealth: existing?.lastHealth,
            lastUpdatedAt: existing?.lastUpdatedAt
        )
        let credentials = GatewayCredentials(managementPassword: password, apiKey: apiKey)
        store.save(instance, credentials: credentials)
        isConnecting = true

        // Always attempt login for FreeLLMAP if credentials provided
        if !password.isEmpty {
            let signedIn = await store.signIn(instance, credentials: credentials)
            resultMessage = signedIn ? "Erfolgreich verbunden und angemeldet." : (store.notice ?? "Anmeldung abgelehnt.")
        } else {
            await store.refresh(instance)
            resultMessage = "Erfolgreich gespeichert. Der öffentliche Status wurde geprüft."
        }
        if !apiKey.isEmpty, let keyMessage = await store.verifyAPIKey(instance, credentials: credentials) {
            resultMessage = (resultMessage ?? "") + "\n\(keyMessage)"
        }
        isConnecting = false
    }
}
