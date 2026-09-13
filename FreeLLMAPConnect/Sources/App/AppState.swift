import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var isLoggingIn: Bool = false
    @Published var loginError: String?
    @Published var serverURL: String
    @Published var email: String = ""
    @Published var password: String

    var client: FreeLLMAPClient { Gateway.shared.client }

    private let emailKey = "freellmapi.email"
    private let urlKey = "freellmapi.serverURL"
    private let pwKeychainKey = "freellmapi.password.keychain"
    private let legacyPwKey = "freellmapi.password"
    private let legacyEmailKey = "freellmapi.email"


    init() {
        let storedURL = UserDefaults.standard.string(forKey: "freellmapi.serverURL") ?? ""
        
        // Keychain migration check: if password is still in UserDefaults, move it to Keychain & purge from UserDefaults
        var storedPW = KeychainHelper.loadString(key: pwKeychainKey) ?? ""
        if storedPW.isEmpty, let legacyPW = UserDefaults.standard.string(forKey: "freellmapi.password"), !legacyPW.isEmpty {
            _ = KeychainHelper.save(key: pwKeychainKey, string: legacyPW)
            UserDefaults.standard.removeObject(forKey: legacyPwKey)
            storedPW = legacyPW
        }

        self.serverURL = storedURL
        self.password = storedPW
        applyServerURL()
    }

    func saveConnection() {
        UserDefaults.standard.set(email, forKey: emailKey)
        UserDefaults.standard.set(serverURL, forKey: urlKey)
        if !password.isEmpty {
            _ = KeychainHelper.save(key: pwKeychainKey, string: password)
        } else {
            _ = KeychainHelper.delete(key: pwKeychainKey)
        }
        // Purge any accidental legacy clear-text storage
        UserDefaults.standard.removeObject(forKey: legacyPwKey)
        UserDefaults.standard.removeObject(forKey: legacyEmailKey)
    }

    func applyServerURL() {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return }
        
        let urlString: String
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            urlString = "https://" + trimmed
        } else {
            urlString = trimmed
        }

        if let url = URL(string: urlString), url.host != nil {
            Gateway.shared.configure(url: url)
        }
    }

    func login() async {
        guard !serverURL.isEmpty, !email.isEmpty, !password.isEmpty else {
            loginError = "Server-URL, Email und Passwort erforderlich."
            return
        }
        isLoggingIn = true
        loginError = nil
        applyServerURL()
        do {
            let result = try await client.login(email: email, password: password)
            if result.success {
                saveConnection()
                isLoggedIn = true
            } else {
                loginError = result.error?.message ?? "Login abgelehnt."
            }
        } catch {
            loginError = error.localizedDescription
        }
        isLoggingIn = false
    }

    func logout() async {
        try? await client.logout()
        password = ""
        _ = KeychainHelper.delete(key: pwKeychainKey)
        UserDefaults.standard.removeObject(forKey: legacyPwKey)
        isLoggedIn = false
    }
}
