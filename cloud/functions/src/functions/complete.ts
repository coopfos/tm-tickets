import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { getContainerClient } from "../shared/storage";
import { getAuthUser, parseCsv, guid } from "../shared/util";
import { sendMailViaGraph } from "../shared/graph";

const COMPLETED_CONTAINER_ENV = "COMPLETED_CONTAINER";
const COMPLETED_META_CONTAINER_ENV = "COMPLETED_META_CONTAINER";
const COMPLETED_DEFAULT = "tickets-completed";
const COMPLETED_META_DEFAULT = "tickets-completed-meta";

app.http("tickets-complete", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "tickets/complete",
  handler: async (req: HttpRequest, ctx: InvocationContext): Promise<HttpResponseInit> => {
    try {
      const body = (await req.json()) as any;
      const id: string = body?.id || guid();
      const pdfBase64: string | undefined = body?.pdfBase64;
      const filename = body?.fileName || `${id}.pdf`;
      const recipients: string[] = body?.recipients || parseCsv(process.env["DEFAULT_EMAIL_RECIPIENTS"]) || [];
      const subjectPrefix = process.env["EMAIL_SUBJECT_PREFIX"] || "[Ticket] ";
      const sender = process.env["EMAIL_SENDER"];

      if (!pdfBase64) return { status: 400, jsonBody: { error: "Missing pdfBase64" } };
      if (!sender) return { status: 500, jsonBody: { error: "EMAIL_SENDER not configured" } };

      const user = getAuthUser(req, ctx);
      const now = new Date().toISOString();
      const meta = {
        id,
        completedAt: now,
        completedBy: user?.userDetails,
        subject: body?.subject || `${subjectPrefix}${id}`,
        ...body?.metadata,
      };

      // Store PDF
      const completed = getContainerClient(COMPLETED_CONTAINER_ENV, COMPLETED_DEFAULT);
      await completed.createIfNotExists();
      const pdfBuffer = Buffer.from(pdfBase64, "base64");
      await completed.getBlockBlobClient(filename).upload(pdfBuffer, pdfBuffer.length, {
        blobHTTPHeaders: { blobContentType: "application/pdf" },
      });

      // Store metadata
      const metaContainer = getContainerClient(COMPLETED_META_CONTAINER_ENV, COMPLETED_META_DEFAULT);
      await metaContainer.createIfNotExists();
      await metaContainer
        .getBlockBlobClient(`${id}.json`)
        .upload(JSON.stringify(meta), Buffer.byteLength(JSON.stringify(meta)), {
          blobHTTPHeaders: { blobContentType: "application/json" },
        });

      // Email distribution via Graph
      if (recipients.length > 0) {
        const mailRes = await sendMailViaGraph({
          senderUser: sender,
          subject: meta.subject,
          bodyHtml: body?.emailBodyHtml || `Ticket ${id} attached.`,
          to: recipients,
          attachmentBase64: pdfBase64,
          attachmentName: filename,
        });
        if (!mailRes.ok) {
          const text = await mailRes.text();
          ctx.error(`Graph sendMail failed: ${mailRes.status} ${text}`);
          return { status: 502, jsonBody: { error: "Failed to send email", details: text } };
        }
      }

      return { status: 200, jsonBody: { id, fileName: filename, emailedTo: recipients, completedAt: now } };
    } catch (e: any) {
      ctx.error("tickets-complete error", e);
      return { status: 500, jsonBody: { error: e?.message || "Server error" } };
    }
  },
});
