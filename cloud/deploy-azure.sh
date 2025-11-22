#!/usr/bin/env bash
set -euo pipefail

# Deploys Azure resources and the Azure Functions app in cloud/functions.
# - Creates/updates Resource Group, Storage Account, and Function App (Node 18, Consumption).
# - Assigns System-Assigned Managed Identity and RBAC on the Storage Account (Blob/Table Data Contributor).
# - Sets required app settings (storage endpoints, containers, email defaults).
# - Builds the Functions (TypeScript) and zip deploys them.
#
# Prereqs:
# - Azure CLI >= 2.45
# - Logged in: az login; correct subscription selected
# - Node 18+ installed locally (for build)
# - Azure Functions Core Tools optional (not required for deploy)
#
# Usage:
#   ./cloud/deploy-azure.sh \
#     --env dev \
#     --location eastus2 \
#     --resource-group rg-tm-tickets-dev \
#     --storage sttmticketsdev123 \
#     --function-app fa-tm-tickets-dev \
#     --email-sender noreply@yourdomain.com \
#     --default-recipients tickets@yourdomain.com
#
# Notes:
# - Authentication (Easy Auth) and Graph Mail.Send consent require tenant admin and are left as guided manual steps.

function die() { echo "Error: $*" >&2; exit 1; }

ENV=""
LOCATION=""
RG=""
STORAGE=""
FUNC_APP=""
EMAIL_SENDER=""
DEFAULT_RECIPIENTS=""
SUBJECT_PREFIX="[Ticket] "

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --resource-group) RG="$2"; shift 2 ;;
    --storage) STORAGE="$2"; shift 2 ;;
    --function-app) FUNC_APP="$2"; shift 2 ;;
    --email-sender) EMAIL_SENDER="$2"; shift 2 ;;
    --default-recipients) DEFAULT_RECIPIENTS="$2"; shift 2 ;;
    --subject-prefix) SUBJECT_PREFIX="$2"; shift 2 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -n "$LOCATION" ]] || die "--location is required"
[[ -n "$RG" ]] || die "--resource-group is required"
[[ -n "$STORAGE" ]] || die "--storage is required (lowercase, unique)"
[[ -n "$FUNC_APP" ]] || die "--function-app is required"

echo "Using:"
echo "  RG:           $RG"
echo "  Location:     $LOCATION"
echo "  Storage:      $STORAGE"
echo "  Function App: $FUNC_APP"
echo "  Email sender: ${EMAIL_SENDER:-<unset>}"
echo "  Recipients:   ${DEFAULT_RECIPIENTS:-<unset>}"

# Ensure we are in repo root
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
# Functions live under cloud/functions relative to this script
FUNCS_DIR="$SCRIPT_DIR/functions"

[[ -d "$FUNCS_DIR" ]] || die "Functions directory not found at $FUNCS_DIR"

echo "Creating resource group..."
az group create -n "$RG" -l "$LOCATION" 1>/dev/null

echo "Creating storage account (or updating if exists)..."
az storage account create \
  -g "$RG" -n "$STORAGE" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 1>/dev/null

echo "Creating Function App (Linux, Node 18, Consumption)..."
az functionapp create \
  -g "$RG" -n "$FUNC_APP" \
  --consumption-plan-location "$LOCATION" \
  --runtime node \
  --runtime-version 20 \
  --functions-version 4 \
  --storage-account "$STORAGE" \
  --os-type Linux 1>/dev/null || true

echo "Assigning system-assigned managed identity..."
az functionapp identity assign -g "$RG" -n "$FUNC_APP" 1>/dev/null || true
MI_PRINCIPAL_ID=$(az functionapp identity show -g "$RG" -n "$FUNC_APP" --query principalId -o tsv)
MI_CLIENT_ID=$(az functionapp identity show -g "$RG" -n "$FUNC_APP" --query clientId -o tsv)
[[ -n "$MI_PRINCIPAL_ID" ]] || die "Failed to get managed identity principalId"

echo "Granting Storage Blob/Table Data Contributor to managed identity..."
STORAGE_ID=$(az storage account show -g "$RG" -n "$STORAGE" --query id -o tsv)
az role assignment create --assignee-object-id "$MI_PRINCIPAL_ID" --role "Storage Blob Data Contributor" --scope "$STORAGE_ID" 1>/dev/null || true
az role assignment create --assignee-object-id "$MI_PRINCIPAL_ID" --role "Storage Table Data Contributor" --scope "$STORAGE_ID" 1>/dev/null || true

echo "Setting application settings on Function App..."
STORAGE_BLOB_URL="https://$STORAGE.blob.core.windows.net"
STORAGE_TABLE_URL="https://$STORAGE.table.core.windows.net"
APP_SETTINGS=(
  "STORAGE_BLOB_URL=$STORAGE_BLOB_URL"
  "STORAGE_TABLE_URL=$STORAGE_TABLE_URL"
  "REFERENCE_TABLE_NAME=Reference"
  "DRAFTS_CONTAINER=tickets-draft"
  "COMPLETED_CONTAINER=tickets-completed"
  "COMPLETED_META_CONTAINER=tickets-completed-meta"
)
if [[ -n "$EMAIL_SENDER" ]]; then APP_SETTINGS+=("EMAIL_SENDER=$EMAIL_SENDER"); fi
if [[ -n "$DEFAULT_RECIPIENTS" ]]; then APP_SETTINGS+=("DEFAULT_EMAIL_RECIPIENTS=$DEFAULT_RECIPIENTS"); fi
if [[ -n "$SUBJECT_PREFIX" ]]; then APP_SETTINGS+=("EMAIL_SUBJECT_PREFIX=$SUBJECT_PREFIX"); fi

az functionapp config appsettings set -g "$RG" -n "$FUNC_APP" --settings "${APP_SETTINGS[@]}" 1>/dev/null

echo "Ensuring Storage containers and table exist..."
# Create containers via az storage (requires a key or SAS). We'll use the account key for setup.
ACCOUNT_KEY=$(az storage account keys list -g "$RG" -n "$STORAGE" --query [0].value -o tsv)
az storage container create --account-name "$STORAGE" --account-key "$ACCOUNT_KEY" -n tickets-draft 1>/dev/null || true
az storage container create --account-name "$STORAGE" --account-key "$ACCOUNT_KEY" -n tickets-completed 1>/dev/null || true
az storage container create --account-name "$STORAGE" --account-key "$ACCOUNT_KEY" -n tickets-completed-meta 1>/dev/null || true
az storage table create --account-name "$STORAGE" --account-key "$ACCOUNT_KEY" --name Reference 1>/dev/null || true

echo "Building Azure Functions (TypeScript) and creating zip..."
pushd "$FUNCS_DIR" >/dev/null
npm ci
npm run build
ZIP_PATH="$REPO_ROOT/tm-functions.zip"
rm -f "$ZIP_PATH"
zip -r "$ZIP_PATH" dist host.json package.json node_modules >/dev/null
popd >/dev/null

echo "Deploying zip to Function App..."
az functionapp deployment source config-zip -g "$RG" -n "$FUNC_APP" --src "$ZIP_PATH" 1>/dev/null

echo "Done. Next steps:"
cat << NEXT

1) Enable Authentication (Easy Auth) for the Function App (manual portal step):
   - Azure Portal > Function App ($FUNC_APP) > Authentication > Add identity provider > Microsoft (Entra ID)
   - Create new app registration, require authentication for all requests.

2) Grant Microsoft Graph Mail.Send to the managed identity (tenant admin):
   - Entra admin center > Enterprise applications > $FUNC_APP (managed identity)
   - Permissions > Add > Microsoft Graph > Application permissions > Mail.Send > Add > Grant admin consent
   - Optional: Restrict to specific mailbox via Exchange Application Access Policy.

3) iOS app configuration:
   - Register a native client app for iOS; add redirect URI msauth.<bundle-id>://auth
   - Expose API on the web (Function App) registration; set Application ID URI; add user_impersonation scope
   - Grant the iOS app delegated permission to that scope, then use that scope in the app settings.

Function base URL: https://$FUNC_APP.azurewebsites.net

NEXT
