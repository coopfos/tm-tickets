TM Tickets – Session Context

Latest Updates (session)
- Resolved 404s in job browser by deploying `reference-job-list` to `tm-tickets-classic` and adding client-side debug/logging for URLs.
- Job lookup robustness:
  - Server `GET /api/reference/job-numbers/{jobNumber}` now finds by either Table RowKey or the `JobNumber`/`jobNumber` column, with case-insensitive attempts.
  - Server normalizes fields and now returns `JobNumber`, `RowKey`, `Description` (job name), and `CustomerName` for both list and single-get.
  - iOS uses the human Job Number for display and stores RowKey internally for validation to avoid flicker; no RowKey is shown to users.
- Job list UI: shows "<jobNumber> - <jobName>" and selecting fills Job Number, Job Name, and Customer Name reliably.
- Drafts enhancements:
  - New endpoints on classic app:
    - GET `/api/tickets/draft?jobNumber=<value>` → `{ items: [ { id, jobNumber, jobName?, date } ] }`.
    - DELETE `/api/tickets/draft/{id}`.
  - Draft save (POST) now sets blob index tags: `jobNumber`, `date`, `jobName`.
  - List-by-job prefers tag query; if tags missing (legacy drafts), falls back to scanning blobs and reading JSON, then backfills tags.
  - iOS Load Draft screen now supports searching by job number, shows date and name, allows swipe-to-delete.
- Date/time UX:
  - Load list shows friendly dates like "Nov 20, 2025 11:23" (HH:mm).
  - Drafts save timestamps in Eastern Time.
- Ticket editor polish:
  - Removed duplicate Customer field; order is Job Number → Job Name → Customer → Date → Technician.
  - Added Delete Draft button with confirmation; calls backend DELETE and dismisses on success.

Overview
- Goal: iOS app that saves/loads service tickets via Azure, with Entra ID auth, Storage for data, and Graph email.
- Stack: Azure Functions (Node/TS for full backend; minimal JS functions for smoke tests), Azure Storage (Blob + Table), Managed Identity, MSAL in iOS (optional for now).

Function Apps
- Flex app (original): tm-tickets (eastus2)
  - Easy Auth enabled (AAD); allowed audience api://66ac27e9-4892-474e-af06-596e2566445c.
  - Deployment friction: needs “Save code settings” in Portal; 404s occurred because functions weren’t loaded.
  - Currently de-emphasized for testing.
- Classic app (smoke-test target): tm-tickets-classic
  - Linux Consumption, Node 20; simple Zip Deploy works.
  - Managed Identity enabled; has Storage Blob/Table Data Contributor roles.
  - Used for current save/load flows while Flex app is sorted out.

Storage
- Storage account: sttmtickets
- Containers: tickets-draft, tickets-completed, tickets-completed-meta
- Table: Reference
  - Partitions used: job-numbers (RowKey = jobNumber), ticket-seq/counter (for next-number)

Endpoints (classic app)
- POST /api/tickets/draft: save draft JSON to Blob (name = <id>.json)
- GET /api/tickets/draft/{id}: return draft JSON by id
- GET /api/tickets/draft?jobNumber=<value>: list drafts by job number (uses blob index tags; falls back to scanning/backfill)
- DELETE /api/tickets/draft/{id}: delete a draft blob
- GET /api/tickets/next-number: returns { ticketNumber } generated via Reference table optimistic counter
- GET /api/reference/job-numbers/{jobNumber}: returns { JobNumber, RowKey, Description, CustomerName, Status } (lookup by RowKey OR JobNumber)
- GET /api/reference/job-numbers?prefix=<value>: returns { items: [ { RowKey, JobNumber, Description, CustomerName, Status } ] } (job list/prefix)

iOS App Changes
- Default Base URL updated to tm-tickets-classic; migration at launch moves old hosts to classic.
- Robust URL building avoids double “/api”. Settings shows computed Draft POST URL + Health URL.
- New Ticket behavior
  - Fetches immutable Ticket Number from /tickets/next-number (fallback to GUID on failure).
  - Job Number entry validates against Reference table; auto-populates Job Name and Customer Name; read-only fields; green/red indicator. Uses human Job Number for display but validates with RowKey when applicable.
  - Save Draft posts with id = Ticket Number (blob named <TicketNumber>.json).
- Load Draft flow
  - Home → Load Draft: enter Ticket Number to GET /tickets/draft/{id} and open; or search by Job Number to list drafts for that job (tap to open, swipe to delete).
- Browse Jobs
  - Magnifying glass opens a searchable list (prefix) backed by /reference/job-numbers?prefix=; items render as "<jobNumber> - <jobName>".

CSV Seeding (Reference table)
- Tool: cloud/tools/seed-reference-from-csv.js (Node)
- Headers (case-insensitive): jobNumber, jobName, customerName, status(optional)
- Maps to Table entity: PartitionKey=job-numbers, RowKey=jobNumber, Description=jobName, CustomerName=customerName, Status=status
- Usage:
  - cd cloud/tools && npm i
  - node cloud/tools/seed-reference-from-csv.js \\
      --connection-string "DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net" \\
      --file jobs.csv --table Reference --partition job-numbers
  - Or: node cloud/tools/seed-reference-from-csv.js --account-name sttmtickets --account-key "<KEY>" --file jobs.csv --table Reference --partition job-numbers

Auth
- Classic app routes are anonymous for dev to simplify testing.
- Flex app uses Easy Auth (AAD); when re-enabled, app must attach MSAL token with scope api://66ac27e9-4892-474e-af06-596e2566445c/user_impersonation.
- Managed Identity granted Graph Mail.Send on the flex app; will need to grant on classic if email is added there.

Status
- Job browsing and lookup (list + exact) are working on classic app.
- Job lookup supports both RowKey and JobNumber; case-insensitive matching.
- Draft list-by-job and delete are working; legacy drafts are included via fallback + backfill.

Troubleshooting Checklist
- App Settings → Base URL: https://tm-tickets-classic.azurewebsites.net (no trailing /api)
- Health (optional): confirm any available health endpoint; draft save works on classic.
- Exact lookup works: curl -i "https://tm-tickets-classic.azurewebsites.net/api/reference/job-numbers/6014" (or a real job number)
- List lookup works: curl -i "https://tm-tickets-classic.azurewebsites.net/api/reference/job-numbers?prefix=60"
- Reference table rows:
  - PartitionKey=job-numbers; RowKey=<JOBNUMBER> (uppercased recommended)
  - Description=<Job Name>; CustomerName=<Customer Name>; Status=<Open/Closed>
 - Drafts:
   - List by job number: curl -s "https://tm-tickets-classic.azurewebsites.net/api/tickets/draft?jobNumber=6014"
   - Delete draft: curl -X DELETE -i "https://tm-tickets-classic.azurewebsites.net/api/tickets/draft/<ID>"

Next Steps (After 404 resolved)
- Optionally enforce Save only when job number validated (prevent red-X saves).
- Add paging/“load more” to job list endpoint for large datasets.
- Consider adding a time picker in the editor to capture HH:mm explicitly.
- Re-enable Easy Auth and integrate MSAL token in iOS for production security.
- Add POST /api/tickets/complete to classic app and wire “Submit Ticket” for email flow.
