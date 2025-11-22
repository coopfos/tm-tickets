import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { getTableClient } from "../shared/storage";
import { requireEnv } from "../shared/util";

const TABLE_NAME_ENV = "REFERENCE_TABLE_NAME";
const DEFAULT_TABLE = "Reference";

app.http("reference-get", {
  methods: ["GET"],
  authLevel: "anonymous", // Protected by Easy Auth in production
  route: "reference/{partition}",
  handler: async (req: HttpRequest, ctx: InvocationContext): Promise<HttpResponseInit> => {
    try {
      const partition = (req.params as any)?.partition;
      if (!partition) return { status: 400, jsonBody: { error: "Missing partition" } };

      const table = getTableClient(TABLE_NAME_ENV, DEFAULT_TABLE);
      const items: any[] = [];
      for await (const entity of table.listEntities({ queryOptions: { filter: `PartitionKey eq '${partition}'` } })) {
        items.push(entity);
      }
      return { status: 200, jsonBody: { partition, items } };
    } catch (e: any) {
      ctx.error("reference-get error", e);
      return { status: 500, jsonBody: { error: e?.message || "Server error" } };
    }
  },
});
