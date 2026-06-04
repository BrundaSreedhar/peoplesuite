const express = require("express");
const multer = require("multer");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
} = require("@aws-sdk/lib-dynamodb");
const {
  S3Client,
  GetObjectCommand,
  PutObjectCommand,
} = require("@aws-sdk/client-s3");
const { requireBearerToken } = require("./auth");

const app = express();
const upload = multer({ storage: multer.memoryStorage() });

const EMPLOYEE_PROFILES_TABLE =
  process.env.EMPLOYEE_PROFILES_TABLE || "Employee_Profiles";
const PHOTO_BUCKET = process.env.PHOTO_BUCKET || "";
const AWS_REGION = process.env.AWS_REGION || "us-east-1";
const PORT = Number(process.env.PORT || 8081);
const DATE_FORMAT = "YYYY-MM-DD";

const EMPLOYEE_ID_PATTERN = /^\d{7}$/;
const COUNTRY_PATTERN = /^[A-Z]{2}$/;

const dynamoClient = new DynamoDBClient({ region: AWS_REGION });
const profilesTable = DynamoDBDocumentClient.from(dynamoClient);
const s3 = new S3Client({ region: AWS_REGION });

app.use(express.json({ limit: "10mb" }));

function photoKey(employeeId) {
  return `employees/${employeeId}/photo`;
}

function validateEmployeeId(employeeId, res) {
  if (!EMPLOYEE_ID_PATTERN.test(employeeId)) {
    res.status(400).json({ error: "employee_id must be exactly 7 digits" });
    return false;
  }
  return true;
}

function parseProfilePayload(payload, res) {
  const required = ["first_name", "last_name", "start_date", "country"];
  const missing = required.filter((field) => !(field in payload));
  if (missing.length > 0) {
    res.status(400).json({ error: "missing_fields", fields: missing });
    return null;
  }

  const country = String(payload.country).toUpperCase();
  if (!COUNTRY_PATTERN.test(country)) {
    res
      .status(400)
      .json({ error: "country must be a 2-letter ISO-3166 code" });
    return null;
  }

  const startDate = String(payload.start_date);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(startDate)) {
    res
      .status(400)
      .json({ error: `start_date must use format ${DATE_FORMAT}` });
    return null;
  }

  const parsed = new Date(`${startDate}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== startDate) {
    res
      .status(400)
      .json({ error: `start_date must use format ${DATE_FORMAT}` });
    return null;
  }

  const firstName = String(payload.first_name).trim();
  const lastName = String(payload.last_name).trim();
  if (!firstName || !lastName) {
    res.status(400).json({ error: "first_name and last_name are required" });
    return null;
  }

  return {
    first_name: firstName,
    last_name: lastName,
    start_date: startDate,
    country,
  };
}

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.get(
  "/peoplesuite/apis/employees/:employeeId/profile",
  requireBearerToken,
  async (req, res) => {
    const { employeeId } = req.params;
    if (!validateEmployeeId(employeeId, res)) return;

    try {
      const response = await profilesTable.send(
        new GetCommand({
          TableName: EMPLOYEE_PROFILES_TABLE,
          Key: { employee_id: employeeId },
        })
      );
      if (!response.Item) {
        return res.status(404).json({ error: "profile_not_found" });
      }
      return res.status(200).json(response.Item);
    } catch (err) {
      return res.status(500).json({ error: "storage_error", detail: String(err) });
    }
  }
);

app.post(
  "/peoplesuite/apis/employees/:employeeId/profile",
  requireBearerToken,
  async (req, res) => {
    const { employeeId } = req.params;
    if (!validateEmployeeId(employeeId, res)) return;

    const profileFields = parseProfilePayload(req.body || {}, res);
    if (!profileFields) return;

    const item = { employee_id: employeeId, ...profileFields };

    try {
      await profilesTable.send(
        new PutCommand({
          TableName: EMPLOYEE_PROFILES_TABLE,
          Item: item,
        })
      );
      return res.status(201).json(item);
    } catch (err) {
      return res.status(500).json({ error: "storage_error", detail: String(err) });
    }
  }
);

app.get(
  "/peoplesuite/apis/employees/:employeeId/photo",
  requireBearerToken,
  async (req, res) => {
    const { employeeId } = req.params;
    if (!validateEmployeeId(employeeId, res)) return;

    if (!PHOTO_BUCKET) {
      return res.status(500).json({ error: "photo storage is not configured" });
    }

    const key = photoKey(employeeId);

    try {
      const response = await s3.send(
        new GetObjectCommand({ Bucket: PHOTO_BUCKET, Key: key })
      );
      const body = await streamToBuffer(response.Body);
      res.set("Content-Type", response.ContentType || "application/octet-stream");
      return res.status(200).send(body);
    } catch (err) {
      const code = err.name || err.Code || "";
      if (code === "NoSuchKey" || code === "NotFound") {
        return res.status(404).json({ error: "photo_not_found" });
      }
      return res.status(500).json({ error: "storage_error", detail: String(err) });
    }
  }
);

app.post(
  "/peoplesuite/apis/employees/:employeeId/photo",
  requireBearerToken,
  upload.single("file"),
  async (req, res) => {
    const { employeeId } = req.params;
    if (!validateEmployeeId(employeeId, res)) return;

    if (!PHOTO_BUCKET) {
      return res.status(500).json({ error: "photo storage is not configured" });
    }

    const key = photoKey(employeeId);
    let data;
    let contentType;

    if (req.file) {
      data = req.file.buffer;
      contentType = req.file.mimetype || "application/octet-stream";
    } else {
      const payload = req.body || {};
      const encoded = payload.photo_base64 || payload.content;
      if (!encoded) {
        return res.status(400).json({
          error: "provide multipart file field 'file' or JSON photo_base64",
        });
      }
      try {
        data = Buffer.from(encoded, "base64");
      } catch {
        return res.status(400).json({ error: "invalid base64 photo content" });
      }
      contentType = payload.content_type || "image/jpeg";
    }

    if (!data || data.length === 0) {
      return res.status(400).json({ error: "empty photo payload" });
    }

    try {
      await s3.send(
        new PutObjectCommand({
          Bucket: PHOTO_BUCKET,
          Key: key,
          Body: data,
          ContentType: contentType,
        })
      );
      return res.status(201).json({
        employee_id: employeeId,
        bucket: PHOTO_BUCKET,
        key,
        content_type: contentType,
        size_bytes: data.length,
      });
    } catch (err) {
      return res.status(500).json({ error: "storage_error", detail: String(err) });
    }
  }
);

app.listen(PORT, () => {
  console.log(`Employee service listening on port ${PORT}`);
});
