Cloud deployment guide

Overview
- Backend is an Azure Functions (Node/TypeScript) app under `cloud/functions`.
- Uses Managed Identity to access Azure Storage (Blob + Table) and Microsoft Graph (Mail.Send).
- Authentication is enforced by App Service Authentication (Easy Auth) with Entra ID.

Quick Deploy (Azure CLI)
- Prereqs: Azure CLI, Node 18+, tenant admin for Graph consent, and rights to create resources.
- Login: `az login` and select the subscription.
- Run the helper script (adjust names/values):

  ./cloud/deploy-azure.sh \
    --env dev \
    --location eastus2 \
    --resource-group rg-tm-tickets-dev \
    --storage sttmticketsdev123 \
    --function-app fa-tm-tickets-dev \
    --email-sender noreply@yourdomain.com \
    --default-recipients tickets@yourdomain.com

What the script does
- Creates/updates Resource Group, Storage Account, and Function App (Node 18, Consumption, Linux).
- Enables system-assigned Managed Identity and assigns Storage Blob/Table Data Contributor roles.
- Sets app settings: `STORAGE_BLOB_URL`, `STORAGE_TABLE_URL`, container names, and email defaults.
- Builds the Functions and zip-deploys them.
- Creates Storage containers and table if not present.

Manual steps after script
- Function App > Authentication: add Microsoft (Entra ID) identity provider; require authentication for all requests.
- Entra admin center > Enterprise applications (managed identity of the function app): grant Microsoft Graph `Mail.Send` (Application) and admin consent. Optionally restrict via Exchange Application Access Policy.
- Expose an API on the web app registration created by Authentication; add `user_impersonation` delegated scope.
- Register the iOS native app and grant it the delegated scope to call the API. Use the scope in the iOS app.

Function App configuration values
- `STORAGE_BLOB_URL`: `https://<storage>.blob.core.windows.net`
- `STORAGE_TABLE_URL`: `https://<storage>.table.core.windows.net`
- `REFERENCE_TABLE_NAME`: `Reference`
- `DRAFTS_CONTAINER`: `tickets-draft`
- `COMPLETED_CONTAINER`: `tickets-completed`
- `COMPLETED_META_CONTAINER`: `tickets-completed-meta`
- `EMAIL_SENDER`: `noreply@yourdomain.com`
- `DEFAULT_EMAIL_RECIPIENTS`: `tickets@yourdomain.com` (comma-separated)
- `EMAIL_SUBJECT_PREFIX`: `[Ticket] ` (optional)

Local development (optional)
- Copy `cloud/functions/local.settings.sample.json` to `cloud/functions/local.settings.json` and fill values.
- Build and run:
  - `cd cloud/functions && npm ci && npm run build && func start`

Notes
- The GitHub Action in `.github/workflows/azure-functions.yml` is a placeholder for .NET and not used by this Node/TypeScript project.
- iOS app default base URL in `TM Tickets/Config.swift` should match your Function App URL; adjust in-app via Settings if needed.

