import { DefaultAzureCredential, GetTokenOptions, TokenCredential } from "@azure/identity";
// Node 18+ provides global fetch; declare for TypeScript without DOM lib
declare const fetch: any;

const credential: TokenCredential = new DefaultAzureCredential();

async function getGraphToken(): Promise<string> {
  const scope = "https://graph.microsoft.com/.default";
  const token = await credential.getToken(scope, {} as GetTokenOptions);
  if (!token?.token) throw new Error("Failed to acquire Graph token");
  return token.token;
}

export interface SendMailOptions {
  senderUser?: string; // user principal name or id (e.g., noreply@contoso.com)
  subject: string;
  bodyHtml: string;
  to: string[];
  cc?: string[];
  bcc?: string[];
  attachmentBase64?: string;
  attachmentName?: string;
}

export async function sendMailViaGraph(options: SendMailOptions): Promise<Response> {
  const accessToken = await getGraphToken();
  const sender = options.senderUser; // e.g. noreply@contoso.com
  if (!sender) throw new Error("Missing senderUser for sendMail");

  const message: any = {
    subject: options.subject,
    body: {
      contentType: "HTML",
      content: options.bodyHtml,
    },
    toRecipients: options.to.map((a) => ({ emailAddress: { address: a } })),
    ccRecipients: options.cc?.map((a) => ({ emailAddress: { address: a } })),
    bccRecipients: options.bcc?.map((a) => ({ emailAddress: { address: a } })),
    attachments: [],
  };

  if (options.attachmentBase64 && options.attachmentName) {
    message.attachments.push({
      '@odata.type': '#microsoft.graph.fileAttachment',
      name: options.attachmentName,
      contentType: "application/pdf",
      contentBytes: options.attachmentBase64,
    });
  }

  const payload = { message, saveToSentItems: true };

  const res = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(sender)}/sendMail`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  return res;
}
