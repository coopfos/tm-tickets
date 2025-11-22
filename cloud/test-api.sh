#!/usr/bin/env bash
set -euo pipefail

# Quick API tests against the deployed Function App using your az login context.
# Requires: az CLI logged in with a user that can get a token for the API resource.

APP_HOST=${APP_HOST:-tm-tickets-bwb3bfgkfnbxdmbv.eastus2-01.azurewebsites.net}
API_AUDIENCE=${API_AUDIENCE:-api://66ac27e9-4892-474e-af06-596e2566445c}

ACCESS_TOKEN=$(az account get-access-token --resource "$API_AUDIENCE" --query accessToken -o tsv)

echo "Testing GET /api/reference/customers"
HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://$APP_HOST/api/reference/customers")
echo "GET /reference/customers -> $HTTP_CODE"

echo "Testing POST /api/tickets/draft"
DATA='{
  "jobNumber": "J-1001",
  "jobName": "Sample job",
  "date": "2025-11-18T12:00:00Z",
  "customerName": "Contoso",
  "technician": "Alice",
  "workPerformed": "Did some work",
  "materialList": "Wire, conduit",
  "labor": [{"role": "Foreman", "regularHours": 2.5, "otHours": 0.0}]
}'

HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$DATA" \
  "https://$APP_HOST/api/tickets/draft")
echo "POST /tickets/draft -> $HTTP_CODE"

