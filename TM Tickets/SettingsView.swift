import SwiftUI
import Combine

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiBaseURL: String = AppConfig.apiBaseURLString
    @State private var bearerToken: String = AppConfig.bearerToken ?? ""

    // MSAL config
    @State private var msalClientId: String = AppConfig.msalClientId
    @State private var msalTenantId: String = AppConfig.msalTenantId
    @State private var msalRedirectUri: String = AppConfig.msalRedirectUri
    @State private var apiScope: String = AppConfig.apiScope
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("API")) {
                    TextField("Base URL", text: $apiBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    if let base = URL(string: apiBaseURL) {
                        let draftURL = ApiClient.draftEndpointURL(from: base)
                        let helloURL = ApiClient.helloEndpointURL(from: base)
                        let jobListURL = ApiClient.jobListURL(from: base, prefix: "J-")
                        let jobLookupURL = ApiClient.jobLookupURL(from: base, jobNumber: "J-1001")
                        HStack(alignment: .firstTextBaseline) {
                            Text("Draft POST URL:")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text(draftURL.absoluteString)
                                .font(.footnote).textSelection(.enabled)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text("Health URL:")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text(helloURL.absoluteString)
                                .font(.footnote).textSelection(.enabled)
                            Spacer()
                            Button("Test") {
                                Task { await testConnection(url: helloURL) }
                            }
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text("Job List URL:")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text(jobListURL.absoluteString)
                                .font(.footnote).textSelection(.enabled)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text("Job Lookup URL:")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text(jobLookupURL.absoluteString)
                                .font(.footnote).textSelection(.enabled)
                        }
                    }
                    if URL(string: apiBaseURL) == nil {
                        Text("Invalid URL").font(.footnote).foregroundStyle(.red)
                    }
                }

                Section(header: Text("Auth (Optional)"), footer: Text("Paste an access token if your Function App requires Azure AD auth (Easy Auth). Leave empty if unauthenticated.").font(.footnote)) {
                    TextEditor(text: $bearerToken)
                        .frame(minHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Image(systemName: bearerToken.isEmpty ? "exclamationmark.triangle" : "checkmark.seal")
                            .foregroundStyle(bearerToken.isEmpty ? .orange : .green)
                        Text(bearerToken.isEmpty ? "No token set — calls may be 401" : "Token set")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !bearerToken.isEmpty {
                            Button("Clear") { bearerToken = "" }
                        }
                    }
                }

                Section(header: Text("Microsoft Login (MSAL)"), footer: Text("Configure MSAL and sign in to acquire tokens for the API scope. Requires adding the MSAL package and URL scheme in Xcode.").font(.footnote)) {
                    TextField("MSAL Client ID", text: $msalClientId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Tenant ID (GUID)", text: $msalTenantId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Redirect URI (msauth.<bundle>://auth)", text: $msalRedirectUri)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("API Scope (api://<web-app-client-id>/user_impersonation)", text: $apiScope)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        let configured = !msalClientId.isEmpty && !msalTenantId.isEmpty && !msalRedirectUri.isEmpty && !apiScope.isEmpty
                        Image(systemName: configured ? "checkmark.seal" : "exclamationmark.triangle")
                            .foregroundStyle(configured ? .green : .orange)
                        Text(configured ? "MSAL configured" : "MSAL not fully configured")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if let email = auth.accountEmail {
                        HStack {
                            Image(systemName: "person.crop.circle.fill").foregroundStyle(.blue)
                            Text("Signed in as \(email)")
                            Spacer()
                            Button("Sign out") { Task { await auth.signOut() } }
                        }
                    } else {
                        Button {
                            Task {
                                do {
                                    _ = try await auth.signInInteractively(from: UIApplication.shared.topViewController())
                                } catch {
                                    // Optionally surface error via a toast
                                }
                            }
                        } label: {
                            Label("Sign in with Microsoft", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .disabled(!AppConfig.isMSALConfigured)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndClose() }
                        .disabled(URL(string: apiBaseURL) == nil)
                }
            }
        }
    }

    private func saveAndClose() {
        AppConfig.apiBaseURLString = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.bearerToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.msalClientId = msalClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.msalTenantId = msalTenantId.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.msalRedirectUri = msalRedirectUri.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.apiScope = apiScope.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }

    // MARK: - Connection test
    private func testConnection(url: URL) async {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = AppConfig.bearerToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            await MainActor.run {
                // ephemeral UI toast substitute
                print("Health check \(url.absoluteString) -> \(code)")
            }
        } catch {
            await MainActor.run {
                print("Health check error: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    SettingsView()
}
