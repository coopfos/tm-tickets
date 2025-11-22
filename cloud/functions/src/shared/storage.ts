import { DefaultAzureCredential } from "@azure/identity";
import { BlobServiceClient, ContainerClient } from "@azure/storage-blob";
import { TableClient } from "@azure/data-tables";
import { requireEnv } from "./util";

const credential = new DefaultAzureCredential();

function getBlobServiceClient(): BlobServiceClient {
  const accountUrl = requireEnv("STORAGE_BLOB_URL");
  return new BlobServiceClient(accountUrl, credential);
}

export function getContainerClient(nameEnv: string, fallback: string): ContainerClient {
  const containerName = process.env[nameEnv]?.trim() || fallback;
  return getBlobServiceClient().getContainerClient(containerName);
}

export function getTableClient(nameEnv: string, fallback: string): TableClient {
  const endpoint = requireEnv("STORAGE_TABLE_URL");
  const tableName = process.env[nameEnv]?.trim() || fallback;
  return new TableClient(endpoint, tableName, credential);
}

