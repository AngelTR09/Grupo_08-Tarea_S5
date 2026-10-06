const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const sharp = require("sharp");

const s3 = new S3Client({});
const BUCKET = process.env.S3_BUCKET;
const PROCESSED_PREFIX = process.env.PROCESSED_PREFIX || "processed/";
const SIZE = 40; 

// en este punto vemos la máscara circular en SVG y lo que queda fuera del círculo se vuelve transparente.
const CIRCLE_MASK = Buffer.from(
  `<svg width="${SIZE}" height="${SIZE}"><circle cx="${SIZE / 2}" cy="${SIZE / 2}" r="${SIZE / 2}" fill="#fff"/></svg>`
);

exports.handler = async (event) => {
  const batchItemFailures = [];

  for (const record of event.Records) {
    try {
      const s3Event = JSON.parse(record.body);

      // S3 envía un mensaje de prueba ("s3:TestEvent") al configurar la
      // notificación; no trae Records, así que se ignora.
      if (!s3Event.Records) continue;

      for (const s3Record of s3Event.Records) {
        const key = decodeURIComponent(s3Record.s3.object.key.replace(/\+/g, " "));

        const original = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: key }));
        const input = Buffer.from(await original.Body.transformToByteArray());

        const output = await sharp(input)
          .resize(SIZE, SIZE, { fit: "cover" })
          .ensureAlpha()
          .composite([{ input: CIRCLE_MASK, blend: "dest-in" }])
          .png()
          .toBuffer();

        const baseName = key.split("/").pop().replace(/\.[^.]+$/, "");
        const outKey = `${PROCESSED_PREFIX}${baseName}_circular.png`;

        await s3.send(new PutObjectCommand({
          Bucket: BUCKET,
          Key: outKey,
          Body: output,
          ContentType: "image/png",
        }));

        console.log(`Procesada: ${key} -> ${outKey}`);
      }
    } catch (err) {
      console.error("Error con el mensaje", record.messageId, err);
      batchItemFailures.push({ itemIdentifier: record.messageId });
    }
  }

  // En el reportBatchItemFailures solo se reintentan los mensajes que fallaron.
  return { batchItemFailures };
};
