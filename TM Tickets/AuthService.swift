import Foundation
import SwiftUI
import Combine
import UIKit

#if canImport(MSAL)
import MSAL
#endif

final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var accountEmail: String? = nil

    private init() {
        #if canImport(MSAL)
        Task { await refreshCurrentAccount() }
        #endif
    }

    var isConfigured: Bool { AppConfig.isMSALConfigured }

    func getAccessTokenSilently() async -> String? {
        #if canImport(MSAL)
        guard isConfigured else { return nil }
        do {
            let app = try msalApp()
            if let account = try await firstAccount(app: app) {
                let result = try await acquireTokenSilent(app: app, account: account)
                self.updateEmail(from: result.account)
                return result.accessToken
            }
        } catch {
            return nil
        }
        return nil
        #else
        return nil
        #endif
    }

    func signInInteractively(from presenter: UIViewController?) async throws -> String {
        #if canImport(MSAL)
        guard isConfigured else { throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "MSAL not configured"]) }
        let app = try msalApp()
        let result = try await acquireTokenInteractive(app: app, presenter: presenter)
        self.updateEmail(from: result.account)
        return result.accessToken
        #else
        throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "MSAL framework not linked to app"]) 
        #endif
    }

    func signOut() async {
        #if canImport(MSAL)
        do {
            let app = try msalApp()
            let accounts = try await allAccounts(app: app)
            for acct in accounts { try await removeAccount(app: app, account: acct) }
            await MainActor.run { self.accountEmail = nil }
        } catch {
            // ignore
        }
        #endif
    }

    // MARK: - Private (MSAL)
    #if canImport(MSAL)
    private func msalApp() throws -> MSALPublicClientApplication {
        let config = MSALPublicClientApplicationConfig(clientId: AppConfig.msalClientId,
                                                       redirectUri: AppConfig.msalRedirectUri,
                                                       authority: try authority())
        return try MSALPublicClientApplication(configuration: config)
    }

    private func authority() throws -> MSALAuthority {
        let url = URL(string: "https://login.microsoftonline.com/\(AppConfig.msalTenantId)")!
        return try MSALAADAuthority(url: url)
    }

    private func scopes() -> [String] { [AppConfig.apiScope] }

    private func firstAccount(app: MSALPublicClientApplication) async throws -> MSALAccount? {
        try await allAccounts(app: app).first
    }

    private func allAccounts(app: MSALPublicClientApplication) async throws -> [MSALAccount] {
        try await withCheckedThrowingContinuation { cont in
            app.allAccounts { accounts, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: accounts ?? [])
            }
        }
    }

    private func removeAccount(app: MSALPublicClientApplication, account: MSALAccount) async throws {
        try await withCheckedThrowingContinuation { cont in
            app.remove(account) { success, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: ())
            }
        }
    }

    private func acquireTokenSilent(app: MSALPublicClientApplication, account: MSALAccount) async throws -> MSALResult {
        let params = try MSALSilentTokenParameters(scopes: scopes(), account: account)
        return try await withCheckedThrowingContinuation { cont in
            app.acquireTokenSilent(with: params) { result, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let result = result else {
                    cont.resume(throwing: NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result"]))
                    return
                }
                cont.resume(returning: result)
            }
        }
    }

    private func acquireTokenInteractive(app: MSALPublicClientApplication, presenter: UIViewController?) async throws -> MSALResult {
        let webParams = MSALWebviewParameters(authPresentationViewController: presenter ?? UIApplication.shared.topViewController() ?? UIViewController())
        let params = MSALInteractiveTokenParameters(scopes: scopes(), webviewParameters: webParams)
        return try await withCheckedThrowingContinuation { cont in
            app.acquireToken(with: params) { result, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let result = result else {
                    cont.resume(throwing: NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result"]))
                    return
                }
                cont.resume(returning: result)
            }
        }
    }

    private func updateEmail(from account: MSALAccount?) {
        guard let username = account?.username, !username.isEmpty else { return }
        Task { @MainActor in self.accountEmail = username }
    }

    private func refreshCurrentAccount() async {
        do {
            let app = try msalApp()
            if let acct = try await firstAccount(app: app) { updateEmail(from: acct) }
        } catch { /* ignore */ }
    }
    #endif
}

// MARK: - UI helpers
extension UIApplication {
    func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return tab.selectedViewController.flatMap { topViewController(base: $0) } }
        if let presented = base?.presentedViewController { return topViewController(base: presented) }
        return base
    }
}
