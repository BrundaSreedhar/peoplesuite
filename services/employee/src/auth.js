const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  QueryCommand,
  ScanCommand,
} = require("@aws-sdk/lib-dynamodb");

const CLIENT_CREDENTIALS_TABLE =
  process.env.CLIENT_CREDENTIALS_TABLE || "Client_Credentials";
const AWS_REGION = process.env.AWS_REGION || "us-east-1";

const dynamoClient = new DynamoDBClient({ region: AWS_REGION });
const credentialsTable = DynamoDBDocumentClient.from(dynamoClient);

function extractBearerToken(req) {
  const authHeader = req.headers.authorization || "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return null;
  }
  const token = authHeader.slice(7).trim();
  return token || null;
}

async function tokenIsValid(accessToken) {
  try {
    const response = await credentialsTable.send(
      new QueryCommand({
        TableName: CLIENT_CREDENTIALS_TABLE,
        IndexName: "AccessTokenIndex",
        KeyConditionExpression: "access_token = :token",
        ExpressionAttributeValues: { ":token": accessToken },
        Limit: 1,
      })
    );
    return (response.Items || []).length > 0;
  } catch {
    const response = await credentialsTable.send(
      new ScanCommand({
        TableName: CLIENT_CREDENTIALS_TABLE,
        FilterExpression: "access_token = :token",
        ExpressionAttributeValues: { ":token": accessToken },
        Limit: 1,
      })
    );
    return (response.Items || []).length > 0;
  }
}

function requireBearerToken(req, res, next) {
  const token = extractBearerToken(req);
  if (!token) {
    return res
      .status(401)
      .json({ error: "missing_or_invalid_authorization" });
  }

  tokenIsValid(token)
    .then((valid) => {
      if (!valid) {
        return res.status(401).json({ error: "invalid_access_token" });
      }
      return next();
    })
    .catch((err) => {
      console.error("Token validation failed", err);
      return res.status(500).json({ error: "storage_error", detail: String(err) });
    });
}

module.exports = { requireBearerToken };
