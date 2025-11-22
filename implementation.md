**Overview**
- Goal: Add a lightweight Azure backend for the iOS app that uses Entra ID for auth, stores preset/reference data and ticket data, and emails completed tickets (PDF) via Microsoft Graph.
- Stack: Azure Functions (Node/TypeScript) + Azure Storage (Blobs + Tables) + Managed Identity + Microsoft Graph.

**What’s Included**
- Backend scaffold under `cloud/functions` with endpoints:
  - `GET /api/reference/{partition}`: fetch preset/reference values from a Table storage partition (e.g., `job-numbers`, `customers`).
  - `POST /api/tickets/draft`: save a draft ticket JSON to Blob storage; returns an `id`.
  - `GET /api/tickets/draft/{id}`: fetch a draft ticket JSON by `id`.
  - `POST /api/tickets/complete`: store completed ticket metadata + PDF and email the PDF via Microsoft Graph.
- Azure portal setup steps to enable Entra auth, storage, and Graph email using Managed Identity.

**High-Level Architecture**
- iOS app signs in with Entra ID using MSAL and calls the Azure Functions API with a bearer token.
- Function App is protected by App Service Authentication (Easy Auth). No secrets in the iOS app.
- Function App uses a system-assigned Managed Identity to access:
  - Azure Storage (Blob/Table) for persistence.
  - Microsoft Graph for sending emails from an organizational mailbox.

**Azure Resources**
- Resource Group: `rg-tm-tickets-<env>`
- Storage Account: `sttm<unique>` (Standard, General Purpose v2)
- Function App: `fa-tm-tickets-<env>` (Node 18, Consumption or Premium)
- App Registration(s): created via Function App Authentication (for the API) and native client registration for iOS

—
**Step-by-Step: Azure Portal Setup**

1) Create a Resource Group
- Portal: Resource groups > Create > Name `rg-tm-tickets-<env>` > Region close to users > Review + create.

2) Create a Storage Account
- Portal: Storage accounts > Create
  - Resource group: `rg-tm-tickets-<env>`
  - Name: `sttm<unique>` (lowercase, globally unique)
  - Region/Performance: default (Standard) is fine
  - Review + create.
- After create, open the Storage account:
  - Data storage > Containers > + Container and create:
    - `reference` (optional if using Table only)
    - `tickets-draft`
    - `tickets-completed`
    - `tickets-completed-meta`
  - Data storage > Tables > + Table and create:
    - `Reference`
  - Optional: seed `Reference` with partitions (e.g., `job-numbers`, `customers`) and rows (RowKey + columns). Use “Edit Table” view to add items.

3) Create the Function App
- Portal: Function App > Create
  - Publish: Code; Runtime stack: Node.js; Version: 18 LTS
  - Region: same as Storage
  - Hosting: Consumption (serverless) or Premium for higher throughput
  - Storage account: select `sttm<unique>`
  - Monitoring: Application Insights (recommended)
  - Review + create.

4) Enable Managed Identity for the Function App
- Open the Function App > Identity > System assigned > Status: On > Save.
- Note the Object (principal) ID; will be used for RBAC and Graph access.

5) Configure Authentication (Easy Auth)
- Function App > Authentication > Add identity provider
  - Microsoft (Entra ID)
  - App registration: Create new app (recommended)
  - Restrict to your tenant only
  - Authorization settings: Require authentication for all requests
  - Create.
- After creation, copy the App (client) ID of the created web app registration (this is the API’s audience).

6) Grant Storage RBAC to the Managed Identity
- Storage account > Access Control (IAM) > Add role assignment
  - Role: Storage Blob Data Contributor
  - Assign access to: User, group, or service principal
  - Select: the Function App’s system-assigned managed identity
  - Review + assign.
- Repeat for Role: Storage Table Data Contributor.

7) Configure App Settings for the Function App
- Function App > Configuration > Application settings > New application setting:
  - `STORAGE_BLOB_URL` = `https://<yourstorage>.blob.core.windows.net`
  - `STORAGE_TABLE_URL` = `https://<yourstorage>.table.core.windows.net`
  - `REFERENCE_TABLE_NAME` = `Reference`
  - `DRAFTS_CONTAINER` = `tickets-draft`
  - `COMPLETED_CONTAINER` = `tickets-completed`
  - `COMPLETED_META_CONTAINER` = `tickets-completed-meta`
  - `EMAIL_SENDER` = `noreply@yourdomain.com` (mailbox to send from)
  - `DEFAULT_EMAIL_RECIPIENTS` = `tickets@yourdomain.com` (comma-separated)
  - `EMAIL_SUBJECT_PREFIX` = `[Ticket] ` (optional)
- Save and restart the Function App.

/// CHECK VARIABLES, PROCEED FROM HERE

8) Enable Microsoft Graph Mail.Send for the Managed Identity
- Entra admin center > Enterprise applications
  - Find the Function App’s managed identity (same name as Function App)
  - Permissions > Application permissions > Add permission > Microsoft Graph > Application permissions > `Mail.Send` > Add permissions
  - Grant admin consent for your tenant.
- Optional (recommended restriction): Limit send-as to a specific mailbox using an Exchange Application Access Policy (requires Exchange Online PowerShell):
  - Connect-ExchangeOnline
  - Create the policy (once):
    - `New-ApplicationAccessPolicy -AppId <FUNCTION_APP_MANAGED_IDENTITY_APPID> -PolicyScopeGroupId <UPN or group with the sender mailbox> -AccessRight RestrictAccess -Description "TM Tickets send mail policy"`
  - Test policy:
    - `Test-ApplicationAccessPolicy -AppId <FUNCTION_APP_MANAGED_IDENTITY_APPID> -Identity <senderUPN>`

9) CORS
- Function App > CORS: Add your iOS app’s custom callback or dev origins if you call functions from a local web preview. Native iOS apps usually do not need CORS; leave disabled unless calling from WebViews.

10) Deploy the Functions code via Portal
- Build a zip from the `cloud/functions` folder on your machine:
  - In a shell: `cd cloud/functions && npm ci && npm run build && cd .. && zip -r tm-functions.zip functions/`
- Function App > Deployment Center > Zip Deploy > Upload `tm-functions.zip`.
  - Alternatively, use VS Code Azure Functions extension for one-click deploy.

11) Register the iOS App and Grant API Access
- Entra admin center > App registrations > New registration
  - Name: `TM Tickets iOS`
  - Supported account types: Single tenant (your org)
  - Redirect URI: iOS/macOS platform
    - `msauth.<your.bundle.id>://auth`
  - Register.
- Expose the API of the web app registration created in Step 5:
  - Find the web app registration (created by Easy Auth)
  - Expose an API > Set Application ID URI (e.g., `api://<web-app-client-id>`)
  - Add a scope: `user_impersonation` (admin consent required)
- Grant the iOS app permission to call the API:
  - iOS app registration > API permissions > Add a permission > My APIs > select your web app (Function App) > Delegated permissions > `user_impersonation` > Add
  - Grant admin consent.
- iOS app will request tokens for the scope: `api://<web-app-client-id>/user_impersonation`.

—
**API Endpoints**
- `GET https://<functionapp>.azurewebsites.net/api/reference/{partition}`
  - Returns: `{ partition, items: [ { PartitionKey, RowKey, ...columns } ] }`
  - Use partitions like `job-numbers`, `customers`.
- `POST https://<functionapp>.azurewebsites.net/api/tickets/draft`
  - Body: JSON, any fields you need; optional `id` (UUID generated if absent)
  - Returns: `{ id, savedAt }`
- `GET https://<functionapp>.azurewebsites.net/api/tickets/draft/{id}`
  - Returns the draft JSON.
- `POST https://<functionapp>.azurewebsites.net/api/tickets/complete`
  - Body: `{ id?, fileName?, pdfBase64, metadata?: {...}, recipients?: ["a@b.com"], subject?: "...", emailBodyHtml?: "..." }`
  - Stores PDF and metadata; sends email via Graph from `EMAIL_SENDER` to provided or default recipients.

Auth: All routes are protected by Easy Auth (Entra). The Functions are marked `authLevel: anonymous` because Easy Auth enforces auth at the front door. The iOS app must attach `Authorization: Bearer <token>`.

—
**iOS Client Integration (MSAL)**
- Add MSAL for iOS (Swift Package Manager or CocoaPods).
- MSAL config values:
  - `clientId`: the iOS App Registration’s Application (client) ID
  - `tenantId`: your tenant ID
  - `redirectUri`: `msauth.<bundle-id>://auth`
  - `scopes`: `api://<web-app-client-id>/user_impersonation`
- Sign-in and acquire token example (pseudocode):
  - Create `MSALPublicClientApplication` with `clientId` and `redirectUri`
  - Call `acquireToken` with the `scopes`
  - Use the `accessToken` in request headers to the Functions API
    - `Authorization: Bearer <token>`

—
**Operational Notes**
- Security:
  - Use Managed Identity; no secrets in code or client.
  - Restrict Graph Mail.Send via Application Access Policy (recommended).
  - Assign least-privilege RBAC on the Storage account.
- Storage model (defaults):
  - Drafts: Blob container `tickets-draft` storing `{id}.json`.
  - Completed: Blob container `tickets-completed` storing PDFs, with metadata JSON in `tickets-completed-meta`.
  - Reference data: Table `Reference` with partitions like `job-numbers`, `customers`.
- Scaling:
  - Start on Consumption plan; move to Premium if concurrency or cold start is a concern.

—
**Local Development (optional)**
- Prereqs: Node 18+, Azure Functions Core Tools, Azure CLI (for auth), Storage emulator or real Storage.
- Configure: copy `cloud/functions/local.settings.sample.json` to `local.settings.json` and set values.
- Build: `cd cloud/functions && npm ci && npm run build && func start`.

—
**Troubleshooting**
- 401/403 calling API: ensure iOS app requests the correct scope and the Function App Authentication is enabled and set to “Require authentication”.
- 403 reading/writing storage: verify RBAC roles (Blob/Table Data Contributor) are assigned to the Function App’s Managed Identity.
- 403 sending email: verify Graph `Mail.Send` app permission and admin consent; if restricted, confirm Application Access Policy allows the sender mailbox.
- Zip deploy failures: check Function App > Deployment Center logs and `Kudu` site (Advanced Tools) for details.

—
**Change Summary**
- Added Azure Functions backend scaffold at `cloud/functions` with Node/TypeScript, including endpoints for reference data, drafts, and completed tickets with Graph email.
- Added `implementation.md` (this file) with Azure Portal instructions.
- Updated `.gitignore` to ignore function build artifacts and local settings.

