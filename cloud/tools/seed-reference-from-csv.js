#!/usr/bin/env node
/*
Seeds the Azure Table 'Reference' (or custom) from a CSV file.

Expected CSV headers (case-insensitive):
  - jobNumber (required)   -> RowKey
  - jobName (required)     -> Description
  - customerName (required)-> CustomerName
  - status (optional)      -> Status

All rows are written to PartitionKey=<--partition|job-numbers> unless a --partition-column is supplied.

Usage examples:
  node cloud/tools/seed-reference-from-csv.js \
    --account-name sttmtickets \
    --account-key <KEY> \
    --table Reference \
    --partition job-numbers \
    --file jobs.csv

  node cloud/tools/seed-reference-from-csv.js \
    --connection-string "DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net" \
    --file jobs.csv

*/
const fs = require('fs');
const path = require('path');
const { parse } = require('csv-parse/sync');
const { TableClient } = require('@azure/data-tables');

function die(msg) { console.error(`Error: ${msg}`); process.exit(1); }

function getArg(name) {
  const idx = process.argv.indexOf(`--${name}`);
  if (idx >= 0 && idx + 1 < process.argv.length) return process.argv[idx + 1];
  return undefined;
}

const accountName = getArg('account-name');
const accountKey = getArg('account-key');
const connectionString = getArg('connection-string');
const tableName = getArg('table') || 'Reference';
const partition = getArg('partition') || 'job-numbers';
const file = getArg('file');

if (!file) die('--file is required');
if (!connectionString && !(accountName && accountKey)) die('Provide either --connection-string or both --account-name and --account-key');

let conn = connectionString;
if (!conn) {
  conn = `DefaultEndpointsProtocol=https;AccountName=${accountName};AccountKey=${accountKey};EndpointSuffix=core.windows.net`;
}

const csvPath = path.resolve(file);
if (!fs.existsSync(csvPath)) die(`CSV file not found: ${csvPath}`);

const content = fs.readFileSync(csvPath, 'utf8');
const records = parse(content, {
  columns: true,
  skip_empty_lines: true,
  trim: true
});

if (!Array.isArray(records) || records.length === 0) {
  die('CSV has no data rows');
}

function pick(obj, keys) {
  const out = {};
  for (const k of keys) if (obj[k] != null && String(obj[k]).length > 0) out[k] = obj[k];
  return out;
}

(async () => {
  const client = TableClient.fromConnectionString(conn, tableName);
  try { await client.createTable(); } catch {}

  let ok = 0, failed = 0;
  for (const row of records) {
    // Header normalization
    const normalized = {};
    for (const [k, v] of Object.entries(row)) normalized[k.toLowerCase()] = v;
    const jobNumber = normalized['jobnumber'];
    const jobName = normalized['jobname'];
    const customerName = normalized['customername'];
    if (!jobNumber || !jobName || !customerName) { console.warn('Skipping row missing jobNumber/jobName/customerName:', row); failed++; continue; }

    const entity = {
      partitionKey: partition,
      rowKey: String(jobNumber),
      ...pick({ Description: jobName, CustomerName: customerName, Status: normalized['status'] }, ['Description', 'CustomerName', 'Status'])
    };
    try {
      await client.upsertEntity(entity, 'Merge');
      ok++;
    } catch (e) {
      failed++;
      console.error('Failed upsert for', entity.rowKey, e.message || e);
    }
  }
  console.log(`Done. Upserted=${ok}, Failed=${failed}`);
})();
