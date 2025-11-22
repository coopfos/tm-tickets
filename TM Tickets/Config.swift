import Foundation

enum AppConfig {
    // Default Function App base URL. Can be overridden in-app via Settings.
    private static let defaultApiBaseURLString = "https://tm-tickets-classic.azurewebsites.net"

    private static let kApiBaseURLKey = "api_base_url"
    private static let kBearerTokenKey = "bearer_token"
    private static let kMsalClientIdKey = "msal_client_id"
    private static let kMsalTenantIdKey = "msal_tenant_id"
    private static let kMsalRedirectUriKey = "msal_redirect_uri"
    private static let kApiScopeKey = "api_scope"

    static var apiBaseURLString: String {
        get { UserDefaults.standard.string(forKey: kApiBaseURLKey) ?? defaultApiBaseURLString }
        set { UserDefaults.standard.set(newValue, forKey: kApiBaseURLKey) }
    }

    static var apiBaseURL: URL? {
        URL(string: apiBaseURLString)
    }

    // Temporarily store a bearer token for calling the API (e.g., Easy Auth protected).
    // Configure this in-app via Settings during development.
    static var bearerToken: String? {
        get {
            let v = UserDefaults.standard.string(forKey: kBearerTokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (v?.isEmpty ?? true) ? nil : v
        }
        set {
            if let value = newValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserDefaults.standard.set(value, forKey: kBearerTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: kBearerTokenKey)
            }
        }
    }

    // MSAL configuration
    static var msalClientId: String {
        get { UserDefaults.standard.string(forKey: kMsalClientIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kMsalClientIdKey) }
    }

    static var msalTenantId: String {
        get { UserDefaults.standard.string(forKey: kMsalTenantIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kMsalTenantIdKey) }
    }

    static var msalRedirectUri: String {
        get { UserDefaults.standard.string(forKey: kMsalRedirectUriKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kMsalRedirectUriKey) }
    }

    // API scope for delegated token, e.g. "api://<web-app-client-id>/user_impersonation"
    static var apiScope: String {
        get { UserDefaults.standard.string(forKey: kApiScopeKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kApiScopeKey) }
    }

    static var isMSALConfigured: Bool {
        !msalClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !msalTenantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !msalRedirectUri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Lightweight migration helpers
extension AppConfig {
    private static var legacyHosts: [String] {
        [
            "tm-tickets-bwb3bfgkfnbxdmbv.eastus2-01.azurewebsites.net",
            "tm-tickets.azurewebsites.net"
        ]
    }

    static func migrateBaseURLIfNeeded() {
        let ud = UserDefaults.standard
        if var stored = ud.string(forKey: kApiBaseURLKey) {
            stored = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if stored.hasSuffix("/api") { stored.removeLast(4) }
            if let url = URL(string: stored), let host = url.host, legacyHosts.contains(host) {
                ud.set(defaultApiBaseURLString, forKey: kApiBaseURLKey)
                return
            }
            ud.set(stored, forKey: kApiBaseURLKey)
        }
    }
}
