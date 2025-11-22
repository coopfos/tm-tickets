const { app } = require('@azure/functions');
const { DefaultAzureCredential } = require('@azure/identity');
const { BlobServiceClient } = require('@azure/storage-blob');
const { TableClient } = require('@azure/data-tables');
const crypto = require('crypto');

const credential = new DefaultAzureCredential();
const blobUrl = process.env.STORAGE_BLOB_URL;
const tableUrl = process.env.STORAGE_TABLE_URL;
const containerName = (process.env.DRAFTS_CONTAINER || 'tickets-draft').trim();
const blobService = new BlobServiceClient(blobUrl, credential);
const referenceTableName = (process.env.REFERENCE_TABLE_NAME || 'Reference').trim();
const tableClient = new TableClient(tableUrl, referenceTableName, credential);

function guid() {
  return ([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g, c =>
    (c ^ crypto.randomBytes(1)[0] & 15 >> c / 4).toString(16)
  );
}

app.http('drafts-create', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'tickets/draft',
  handler: async (req, ctx) => {
    try {
      const body = await req.json();
      const id = (body && body.id) || guid();
      const now = new Date().toISOString();
      const payload = { id, savedAt: now, ...body };

      const container = blobService.getContainerClient(containerName);
      await container.createIfNotExists();
      const blobName = `${id}.json`;
      const blockBlob = container.getBlockBlobClient(blobName);
      const text = JSON.stringify(payload);
      await blockBlob.upload(text, Buffer.byteLength(text), {
        blobHTTPHeaders: { blobContentType: 'application/json' }
      });
      // Try to set index tags for efficient listing by jobNumber/date
      try {
        const tags = {};
        if (payload.jobNumber) tags.jobNumber = String(payload.jobNumber);
        if (payload.date) tags.date = String(payload.date);
        if (payload.jobName) tags.jobName = String(payload.jobName);
        await blockBlob.setTags(tags);
      } catch (e) {
        ctx.warn?.('setTags failed (non-fatal)', e);
      }

      return { status: 201, jsonBody: { id, savedAt: now } };
    } catch (e) {
      ctx.error('drafts-create error', e);
      return { status: 500, jsonBody: { error: e.message || 'Server error' } };
    }
  }
});

// GET /api/reference/technicians?prefix= -> list technicians from Reference table (PartitionKey = 'technician')
app.http('reference-tech-list', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'reference/technicians',
  handler: async (req, ctx) => {
    const url = new URL(req.url);
    const prefix = (url.searchParams.get('prefix') || '').trim();
    const pk = 'technician';
    const items = [];
    try {
      // We can't prefix-filter on a non-key column in Tables; scan PK and filter in-process
      const filter = `PartitionKey eq '${pk}'`;
      const iter = tableClient.listEntities({ queryOptions: { filter } });
      let count = 0, max = 100;
      for await (const entity of iter) {
        const techName = entity.techName || entity.TechName || entity.name || entity.Name || entity.rowKey;
        if (prefix) {
          const up = String(prefix).toUpperCase();
          if (!String(techName || '').toUpperCase().startsWith(up)) continue;
        }
        items.push({ RowKey: entity.rowKey, TechName: techName });
        count++;
        if (count >= max) break;
      }
      return { status: 200, jsonBody: { items } };
    } catch (e) {
      ctx.error('reference-tech-list error', e);
      return { status: 500, jsonBody: { error: e.message || 'Server error' } };
    }
  }
});

// GET /api/tickets/draft/{id}
app.http('drafts-get', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'tickets/draft/{id}',
  handler: async (req, ctx) => {
    try {
      const id = req.params.id;
      if (!id) return { status: 400, jsonBody: { error: 'Missing id' } };
      const container = blobService.getContainerClient(containerName);
      const blobName = `${id}.json`;
      const blockBlob = container.getBlockBlobClient(blobName);
      if (!(await blockBlob.exists())) return { status: 404, jsonBody: { error: 'Not found' } };
      const resp = await blockBlob.download();
      const chunks = [];
      for await (const chunk of resp.readableStreamBody) { chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)); }
      const text = Buffer.concat(chunks).toString('utf8');
      return { status: 200, jsonBody: JSON.parse(text) };
    } catch (e) {
      ctx.error('drafts-get error', e);
      return { status: 500, jsonBody: { error: e.message || 'Server error' } };
    }
  }
});

// GET /api/tickets/draft?jobNumber=6014 -> list draft ticket metadata by job number
app.http('drafts-list-by-job', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'tickets/draft',
  handler: async (req, ctx) => {
    try {
      const url = new URL(req.url);
      const jobNumber = (url.searchParams.get('jobNumber') || '').trim();
      const items = [];
      if (!jobNumber) return { status: 400, jsonBody: { error: 'Missing jobNumber' } };
      // Prefer Blob Index Tags query if available
      try {
        const where = `@tag.jobNumber = '${jobNumber.replace(/'/g, "''")}' AND @container = '${containerName}'`;
        const iter = blobService.findBlobsByTags(where);
        for await (const b of iter) {
          // b contains name and tagProperties
          items.push({
            id: b.name.replace(/\.json$/i, ''),
            jobNumber: jobNumber,
            jobName: (b.tags && (b.tags.jobName || b.tags.jobname)) || undefined,
            date: (b.tags && b.tags.date) || undefined
          });
        }
      } catch (e) {
        // Fall back to scanning blobs and reading tags
        const container = blobService.getContainerClient(containerName);
        for await (const blob of container.listBlobsFlat()) {
          if (!blob.name.endsWith('.json')) continue;
          const blockBlob = container.getBlockBlobClient(blob.name);
          try {
            const tagResp = await blockBlob.getTags();
            const tags = tagResp.tags || {};
            if (String(tags.jobNumber || '') === jobNumber) {
              items.push({
                id: blob.name.replace(/\.json$/i, ''),
                jobNumber: jobNumber,
                jobName: tags.jobName || undefined,
                date: tags.date || undefined
              });
              continue;
            }
          } catch {}
          // If tags missing or mismatched, try reading blob content and match by payload.jobNumber
          try {
            const dl = await blockBlob.download();
            const chunks = [];
            for await (const chunk of dl.readableStreamBody) { chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)); }
            const text = Buffer.concat(chunks).toString('utf8');
            const json = JSON.parse(text);
            if (json && String(json.jobNumber || '') === jobNumber) {
              items.push({
                id: blob.name.replace(/\.json$/i, ''),
                jobNumber: jobNumber,
                jobName: json.jobName || undefined,
                date: json.date || undefined
              });
              // Opportunistically backfill tags for faster future queries
              try {
                const toSet = { jobNumber: String(jobNumber) };
                if (json.date) toSet.date = String(json.date);
                if (json.jobName) toSet.jobName = String(json.jobName);
                await blockBlob.setTags(toSet);
              } catch {}
            }
          } catch {}
        }
      }
      // Optional: sort by date desc if present
      items.sort((a, b) => String(b.date || '').localeCompare(String(a.date || '')));
      return { status: 200, jsonBody: { items } };
    } catch (e) {
      ctx.error('drafts-list-by-job error', e);
      return { status: 500, jsonBody: { error: e.message || 'Server error' } };
    }
  }
});

// DELETE /api/tickets/draft/{id}
app.http('drafts-delete', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'tickets/draft/{id}',
  handler: async (req, ctx) => {
    try {
      const id = req.params.id;
      if (!id) return { status: 400, jsonBody: { error: 'Missing id' } };
      const container = blobService.getContainerClient(containerName);
      const blobName = `${id}.json`;
      const blockBlob = container.getBlockBlobClient(blobName);
      const exists = await blockBlob.exists();
      if (!exists) return { status: 404, jsonBody: { error: 'Not found' } };
      await blockBlob.delete();
      return { status: 204 };
    } catch (e) {
      ctx.error('drafts-delete error', e);
      return { status: 500, jsonBody: { error: e.message || 'Server error' } };
    }
  }
});

// GET /api/tickets/next-number -> { ticketNumber }
app.http('tickets-next-number', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'tickets/next-number',
  handler: async (req, ctx) => {
    const prefix = (process.env.TICKET_NUMBER_PREFIX || 'T-').trim();
    const start = parseInt(process.env.TICKET_NUMBER_START || '1000', 10) || 1000;
    const pk = 'ticket-seq';
    const rk = 'counter';
    const maxRetries = 5;
    try {
      await tableClient.createTable();
    } catch {}
    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        let entity;
        try {
          entity = await tableClient.getEntity(pk, rk);
        } catch (e) {
          // initialize at start-1 so first increment equals start
          await tableClient.createEntity({ partitionKey: pk, rowKey: rk, value: start - 1 });
          entity = await tableClient.getEntity(pk, rk);
        }
        const current = Number(entity.value || 0);
        const next = current + 1;
        // optimistic update using etag
        await tableClient.updateEntity({ partitionKey: pk, rowKey: rk, value: next }, 'Replace', { etag: entity.etag });
        const ticketNumber = `${prefix}${next}`;
        return { status: 200, jsonBody: { ticketNumber } };
      } catch (e) {
        // on precondition failed, retry
        if (String(e.message || '').includes('PreconditionFailed')) {
          await new Promise(r => setTimeout(r, 50 * (attempt + 1)));
          continue;
        }
        ctx.error('tickets-next-number error', e);
        return { status: 500, jsonBody: { error: e.message || 'Server error' } };
      }
    }
    return { status: 503, jsonBody: { error: 'Sequence contention, try again' } };
  }
});

// GET /api/reference/job-numbers/{jobNumber}
// Looks up by either RowKey or JobNumber column (case-insensitive attempts)
app.http('reference-job-get', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'reference/job-numbers/{jobNumber}',
  handler: async (req, ctx) => {
    const inputRaw = (req.params.jobNumber || '').trim();
    if (!inputRaw) return { status: 400, jsonBody: { error: 'Missing jobNumber' } };
    const pk = 'job-numbers';
    const esc = (v) => String(v).replace(/'/g, "''");
    const candidates = [inputRaw, inputRaw.toUpperCase(), inputRaw.toLowerCase()]
      .filter((v, i, a) => a.indexOf(v) === i);
    try {
      let entity;
      for (const val of candidates) {
        const f = `PartitionKey eq '${esc(pk)}' and (RowKey eq '${esc(val)}' or JobNumber eq '${esc(val)}' or jobNumber eq '${esc(val)}')`;
        const iter = tableClient.listEntities({ queryOptions: { filter: f } });
        for await (const e of iter) { entity = e; break; }
        if (entity) break;
      }
      if (!entity) return { status: 404, jsonBody: { error: 'Not found' } };
      // Normalize entity properties to plain JSON with fallbacks for various column names
      const description = entity.Description || entity.description || entity.JobName || entity.jobName || entity.NAME || entity.Name;
      const customerName = entity.CustomerName || entity.customerName || entity.Customer || entity.customer;
      // Prefer new field name `projectManager`, fallback to legacy aliases
      const projectManager = entity.projectManager || entity.ProjectManager || entity.pmName || entity.PMName || entity.pm;
      const result = {
        PartitionKey: entity.partitionKey,
        RowKey: entity.rowKey,
        JobNumber: entity.JobNumber || entity.jobNumber || entity.rowKey,
        Description: description,
        Status: entity.Status,
        CustomerName: customerName,
        projectManager: projectManager
      };
      return { status: 200, jsonBody: result };
    } catch (e) {
      ctx.error('reference-job-get error', e);
      return { status: 500, jsonBody: { error: e.message || 'Server error' } };
    }
  }
});

// GET /api/reference/job-numbers?prefix=J-10 -> list jobs (RowKey starts with prefix)
app.http('reference-job-list', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'reference/job-numbers',
  handler: async (req, ctx) => {
    const url = new URL(req.url);
    const prefix = (url.searchParams.get('prefix') || '').trim();
    const pk = "job-numbers";
    const items = [];
    try {
      let filter = `PartitionKey eq '${pk}'`;
      if (prefix) {
        // Prefix range filter: RowKey >= prefix AND RowKey < prefix + \uffff
        const upper = prefix.toUpperCase();
        const hi = upper + "\uffff";
        filter += ` and RowKey ge '${upper}' and RowKey lt '${hi}'`;
      }
      const iter = tableClient.listEntities({ queryOptions: { filter } });
      let count = 0, max = 50;
      for await (const entity of iter) {
        const description = entity.Description || entity.description || entity.JobName || entity.jobName || entity.NAME || entity.Name;
        const customerName = entity.CustomerName || entity.customerName || entity.Customer || entity.customer;
        items.push({
          RowKey: entity.rowKey,
          JobNumber: entity.JobNumber || entity.jobNumber || entity.rowKey,
          Description: description,
          CustomerName: customerName,
          Status: entity.Status
        });
        count++;
        if (count >= max) break;
      }
      return { status: 200, jsonBody: { items } };
    } catch (e) {
      ctx.error('reference-job-list error', e);
      return { status: 500, jsonBody: { error: e.message || 'Server error' } };
    }
  }
});
