const { app } = require('@azure/functions');
app.http('hello', {
  methods: [ 'GET' ],
  authLevel: 'anonymous',
  route: 'hello',
  handler: async (req, ctx) => ({ status: 200, jsonBody: { ok: true, now: new Date().toISOString() } })
});
