import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { getContainerClient } from "../shared/storage";
import { getAuthUser, guid } from "../shared/util";

const DRAFTS_CONTAINER_ENV = "DRAFTS_CONTAINER";
const DRAFTS_DEFAULT = "tickets-draft";

app.http("drafts-create", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "tickets/draft",
  handler: async (req: HttpRequest, ctx: InvocationContext): Promise<HttpResponseInit> => {
    try {
      const body = (await req.json()) as any;
      const id: string = body?.id || guid();
      const now = new Date().toISOString();
      const user = getAuthUser(req, ctx);

      const payload = {
        id,
        createdAt: now,
        createdBy: user?.userDetails,
        ...body,
      };

      const container = getContainerClient(DRAFTS_CONTAINER_ENV, DRAFTS_DEFAULT);
      await container.createIfNotExists();
      const blobName = `${id}.json`;
      const blockBlob = container.getBlockBlobClient(blobName);
      await blockBlob.upload(JSON.stringify(payload), Buffer.byteLength(JSON.stringify(payload)), {
        blobHTTPHeaders: { blobContentType: "application/json" },
      });

      return { status: 201, jsonBody: { id, savedAt: now } };
    } catch (e: any) {
      ctx.error("drafts-create error", e);
      return { status: 500, jsonBody: { error: e?.message || "Server error" } };
    }
  },
});

app.http("drafts-get", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "tickets/draft/{id}",
  handler: async (req: HttpRequest, ctx: InvocationContext): Promise<HttpResponseInit> => {
    try {
      const id = (req.params as any)?.id;
      if (!id) return { status: 400, jsonBody: { error: "Missing id" } };

      const container = getContainerClient(DRAFTS_CONTAINER_ENV, DRAFTS_DEFAULT);
      const blobName = `${id}.json`;
      const blockBlob = container.getBlockBlobClient(blobName);
      if (!(await blockBlob.exists())) return { status: 404, jsonBody: { error: "Not found" } };
      const resp = await blockBlob.download();
      const text = await streamToString(resp.readableStreamBody as any);
      return { status: 200, jsonBody: JSON.parse(text) };
    } catch (e: any) {
      ctx.error("drafts-get error", e);
      return { status: 500, jsonBody: { error: e?.message || "Server error" } };
    }
  },
});

async function streamToString(readable: NodeJS.ReadableStream | ReadableStream | null | undefined): Promise<string> {
  if (!readable) return "";
  const chunks: Buffer[] = [];
  // Support NodeJS.ReadableStream (preferred in Azure SDK for Node)
  const nodeReadable: any = readable as any;
  for await (const chunk of nodeReadable) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}
