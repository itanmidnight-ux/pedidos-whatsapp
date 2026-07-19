'use strict';
const fs = require('fs');
const path = require('path');

// Abstraccion de almacenamiento de archivos -- por defecto disco local
// (comportamiento identico al de siempre, cero cambios, cero dependencias
// nuevas). Si se configura S3_BUCKET (+ S3_ENDPOINT/credenciales), cambia a
// un bucket S3-compatible (Cloudflare R2, MinIO, S3 real) sin tocar el
// codigo que la usa -- necesario el dia que haya mas de una instancia del
// server escribiendo al mismo storage (horizontal scaling, Fase 2). El SDK
// de AWS (@aws-sdk/client-s3) se carga solo bajo demanda (require
// perezoso) -- una instalacion que se queda en disco local (el caso de
// hoy) nunca instala ni paga ese peso.
const APPDATA_ROOT = process.env.APPDATA || process.env.HOME || process.env.USERPROFILE;
const USE_S3 = !!process.env.S3_BUCKET;

let s3 = null;
function getS3() {
  if (s3) return s3;
  let mod;
  try {
    mod = require('@aws-sdk/client-s3');
  } catch (_e) {
    throw new Error('S3_BUCKET esta configurado pero falta la dependencia -- corre: npm install @aws-sdk/client-s3');
  }
  const { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand, HeadObjectCommand } = mod;
  const client = new S3Client({
    region: process.env.S3_REGION || 'auto',
    endpoint: process.env.S3_ENDPOINT || undefined,
    forcePathStyle: process.env.S3_FORCE_PATH_STYLE === 'true',
    credentials: process.env.S3_ACCESS_KEY_ID ? {
      accessKeyId: process.env.S3_ACCESS_KEY_ID,
      secretAccessKey: process.env.S3_SECRET_ACCESS_KEY,
    } : undefined,
  });
  s3 = { client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand, HeadObjectCommand };
  return s3;
}

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks);
}

// Un FileStore por "carpeta logica" (product-images, profile-pics, etc) --
// mismo nombre que hoy usan los distintos multer.diskStorage del proyecto,
// para que migrar un call site sea solo cambiar de multer.diskStorage a
// esto, sin mover archivos existentes de lugar.
class FileStore {
  constructor(name) {
    this.name = name;
    this.localDir = path.join(APPDATA_ROOT, 'pedidos-bot', name);
    if (!USE_S3) fs.mkdirSync(this.localDir, { recursive: true });
  }

  async save(filename, buffer) {
    if (USE_S3) {
      const { client, PutObjectCommand } = getS3();
      await client.send(new PutObjectCommand({ Bucket: process.env.S3_BUCKET, Key: `${this.name}/${filename}`, Body: buffer }));
    } else {
      fs.writeFileSync(path.join(this.localDir, filename), buffer);
    }
  }

  async read(filename) {
    if (USE_S3) {
      const { client, GetObjectCommand } = getS3();
      const res = await client.send(new GetObjectCommand({ Bucket: process.env.S3_BUCKET, Key: `${this.name}/${filename}` }));
      return streamToBuffer(res.Body);
    }
    return fs.readFileSync(path.join(this.localDir, filename));
  }

  async exists(filename) {
    if (USE_S3) {
      const { client, HeadObjectCommand } = getS3();
      try {
        await client.send(new HeadObjectCommand({ Bucket: process.env.S3_BUCKET, Key: `${this.name}/${filename}` }));
        return true;
      } catch (_e) { return false; }
    }
    return fs.existsSync(path.join(this.localDir, filename));
  }

  async delete(filename) {
    if (USE_S3) {
      const { client, DeleteObjectCommand } = getS3();
      try { await client.send(new DeleteObjectCommand({ Bucket: process.env.S3_BUCKET, Key: `${this.name}/${filename}` })); } catch (_e) {}
    } else {
      try { fs.unlinkSync(path.join(this.localDir, filename)); } catch (_e) {}
    }
  }

  // Solo disco local: entrega la ruta real para usar con res.sendFile()
  // directo, sin leer el archivo entero a memoria primero. En modo S3 no
  // aplica -- el caller debe usar read()+res.send(buffer) en su lugar.
  localPath(filename) {
    return path.join(this.localDir, filename);
  }
}

function createStore(name) {
  return new FileStore(name);
}

module.exports = { createStore, USE_S3 };
