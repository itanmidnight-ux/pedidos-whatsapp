'use strict';
// El panel admin NO duplica logica de negocio -- todo pedido/edicion de
// producto pasa por la API real del server principal (mismas validaciones,
// mismo multer, misma tabla product_images). Solo se le agrega una cara
// de formularios HTML encima. Usa fetch nativo de Node (18+) -- no hace
// falta axios/form-data para esto, incluido soporte multipart via FormData
// nativo para la subida de imagenes.
const MAIN_API_URL = `http://127.0.0.1:${process.env.PORT || 3000}`;

async function apiRequest(token, method, path, { json, form } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  let body;
  if (json !== undefined) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(json);
  } else if (form !== undefined) {
    body = form; // FormData nativo -- fetch fija el Content-Type/boundary solo
  }
  const res = await fetch(`${MAIN_API_URL}${path}`, { method, headers, body });
  let data = null;
  try { data = await res.json(); } catch { /* respuesta sin cuerpo JSON (ej. imagen) */ }
  return { status: res.status, ok: res.ok, data };
}

async function fetchImage(token, filename) {
  const res = await fetch(`${MAIN_API_URL}/api/products/images/${encodeURIComponent(filename)}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return res;
}

module.exports = { apiRequest, fetchImage, MAIN_API_URL };
