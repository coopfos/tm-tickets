// Runtime entry shim for Azure Functions (Node v4 new programming model)
// Ensures the worker can locate the compiled entry even if it doesn't honor package.json main.
const { app } = require('@azure/functions');
// Register compiled functions
try {
  require("./dist/src/index.js");
} catch (e) {
  console.error('Failed to load compiled functions:', e);
}
// Simple health endpoint to confirm package loaded
app.http('health', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'health',
  handler: async () => ({ status: 200, jsonBody: { ok: true, ts: new Date().toISOString() } })
});
