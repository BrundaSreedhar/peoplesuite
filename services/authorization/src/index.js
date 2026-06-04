const crypto = require("crypto");
const express = require("express");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  QueryCommand,
  DeleteCommand,
  PutCommand,
} = require("@aws-sdk/lib-dynamodb");

const app = express();

const CLIENT_CREDENTIALS_TABLE =
  process.env.CLIENT_CREDENTIALS_TABLE || "Client_Credentials";
const AWS_REGION = process.env.AWS_REGION || "us-east-1";
const CREDENTIALS_SK = process.env.CLIENT_CREDENTIALS_SK || "NONE";
const PORT = Number(process.env.PORT || 8080);

const dynamoClient = new DynamoDBClient({ region: AWS_REGION });
const table = DynamoDBDocumentClient.from(dynamoClient);

function hashSecret(secret) {
  return crypto.createHash("sha256").update(secret, "utf8").digest("hex");
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.post("/peoplesuite/apis/token", async (req, res) => {
  const grantType = req.query.grant_type || "";
  const clientId = req.query.client_Id || req.query.client_id || "";
  const clientSecret = req.query.client_secret || "";

  if (grantType !== "client_credentials") {
    return res.status(400).json({ error: "unsupported_grant_type" });
  }

  if (!clientId || clientId.length > 10) {
    return res.status(400).json({ error: "invalid_client_id" });
  }

  // Lab example secret is 24 chars; spec says "up to 20" but sample exceeds that.
  if (!clientSecret || clientSecret.length > 64) {
    return res.status(400).json({ error: "invalid_client_secret" });
  }

  let items;
  try {
    const response = await table.send(
      new QueryCommand({
        TableName: CLIENT_CREDENTIALS_TABLE,
        KeyConditionExpression: "client_id = :cid",
        ExpressionAttributeValues: { ":cid": clientId },
      })
    );
    items = response.Items || [];
  } catch (err) {
    console.error("DynamoDB query failed", err);
    return res.status(500).json({ error: "storage_error", detail: String(err) });
  }

  if (items.length === 0) {
    return res.status(401).json({ error: "invalid_client" });
  }

  const item = items[0];
  if (item.client_secret !== hashSecret(clientSecret)) {
    return res.status(401).json({ error: "invalid_client" });
  }

  const accessToken = crypto.randomUUID();
  const oldSortKey = item.access_token || CREDENTIALS_SK;

  try {
    await table.send(
      new DeleteCommand({
        TableName: CLIENT_CREDENTIALS_TABLE,
        Key: { client_id: clientId, access_token: oldSortKey },
      })
    );
    await table.send(
      new PutCommand({
        TableName: CLIENT_CREDENTIALS_TABLE,
        Item: {
          client_id: clientId,
          access_token: accessToken,
          client_secret: item.client_secret,
          contact_email: item.contact_email || "",
        },
      })
    );
  } catch (err) {
    console.error("DynamoDB token persist failed", err);
    return res.status(500).json({ error: "storage_error", detail: String(err) });
  }

  return res.status(200).json({
    access_token: accessToken,
    token_type: "Bearer",
    grant_type: "client_credentials",
  });
});

app.listen(PORT, () => {
  console.log(`AuthorizationService listening on port ${PORT}`);
});
