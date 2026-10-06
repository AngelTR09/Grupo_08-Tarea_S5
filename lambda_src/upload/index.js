const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const Busboy = require("busboy");
const { v4: uuidv4 } = require("uuid");

const s3 = new S3Client({});
const BUCKET = process.env.S3_BUCKET;
const PREFIX = process.env.UPLOAD_PREFIX || "uploads/";
const MAX_BYTES = 10 * 1024 * 1024; // 10 MB (según el diagrama)
const ALLOWED = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/gif": "gif",
  "image/webp": "webp",
};

exports.handler = async (event) => {
  try {
    // En este punto se guarda el header original : el "boundary" del multipart distinguen las mayúsculas y minúsculas, 
    
    const contentType = event.headers?.["content-type"] || ""
    if (type.startsWith("multipart/form-data")) {
      file = await parseMultipart(event, contentType);
    } else if (type.startsWith("application/json")) {
      const raw = event.isBase64Encoded
        ? Buffer.from(event.body, "base64").toString("utf8")
        : event.body;
      const body = JSON.parse(raw);
      file = { mimeType: body.contentType, buffer: Buffer.from(body.data, "base64") };
    } else {
      return reply(400, { error: "Usa multipart/form-data o application/json con base64" });
    }

    if (!file || !file.buffer || file.buffer.length === 0) {
      return reply(400, { error: "No se recibió ninguna imagen" });
    }
    if (!ALLOWED[file.mimeType]) {
      return reply(415, { error: `Tipo no permitido: ${file.mimeType}. Usa jpg, png, gif o webp` });
    }
    if (file.buffer.length > MAX_BYTES) {
      return reply(413, { error: "La imagen supera los 10 MB" });
    }

    const key = `${PREFIX}${uuidv4()}.${ALLOWED[file.mimeType]}`;

    await s3.send(new PutObjectCommand({
      Bucket: BUCKET,
      Key: key,
      Body: file.buffer,
      ContentType: file.mimeType,
    }));

    return reply(201, { message: "Imagen recibida", key });
  } catch (err) {
    console.error(err);
    return reply(500, { error: "Error interno" });
  }
};

function parseMultipart(event, contentType) {
  return new Promise((resolve, reject) => {
    const bb = Busboy({ headers: { "content-type": contentType } });
    const chunks = [];
    let mimeType;

    bb.on("file", (_field, stream, info) => {
      mimeType = info.mimeType;
      stream.on("data", (d) => chunks.push(d));
    });
    bb.on("finish", () => resolve({ mimeType, buffer: Buffer.concat(chunks) }));
    bb.on("error", reject);

    bb.end(Buffer.from(event.body || "", event.isBase64Encoded ? "base64" : "utf8"));
  });
}

function reply(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}
