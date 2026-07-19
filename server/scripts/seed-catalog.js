#!/usr/bin/env node
// Seed de catalogo de ejemplo para el sitio publico (Supermercado GO) --
// ~100 productos realistas de supermercado en Cucuta, para que el sitio no
// se vea vacio desde el dia uno. Idempotente: no duplica productos que ya
// existan por nombre. Los productos no traen foto real -- el sitio publico
// muestra un placeholder por categoria hasta que se suba una foto real
// desde el panel admin.
// Uso: node scripts/seed-catalog.js
'use strict';
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const { Pool } = require('pg');

function connectionConfig() {
  if (process.env.DATABASE_URL) return { connectionString: process.env.DATABASE_URL };
  return {
    host:     process.env.PG_HOST     || '127.0.0.1',
    port:     Number(process.env.PG_PORT || 5432),
    database: process.env.PG_DATABASE || 'supermercado',
    user:     process.env.PG_USER     || 'pedidosbot',
    password: process.env.PG_PASSWORD,
  };
}

const CATALOG = {
  'Frutas y Verduras': [
    ['Banano', 1800], ['Manzana Roja', 3500], ['Naranja', 2200], ['Papa Criolla', 3800],
    ['Papa Pastusa', 2600], ['Tomate Chonto', 2800], ['Cebolla Cabezona', 2400],
    ['Zanahoria', 1900], ['Aguacate Hass', 4500], ['Plátano Verde', 1600],
    ['Limón Tahití', 2000], ['Cilantro (atado)', 1200],
  ],
  'Carnes y Pollo': [
    ['Pechuga de Pollo (lb)', 9500], ['Muslo de Pollo (lb)', 7200], ['Carne de Res Molida (lb)', 12500],
    ['Lomo de Res (lb)', 18900], ['Chuleta de Cerdo (lb)', 11500], ['Costilla de Cerdo (lb)', 10800],
    ['Salchicha Ranchera x5', 8500], ['Chorizo Santarrosano x4', 9800], ['Pollo Entero', 22000],
    ['Carne para Asar (lb)', 16500],
  ],
  'Lácteos y Huevos': [
    ['Leche Entera 1L', 4200], ['Leche Deslactosada 1L', 4800], ['Queso Campesino 500g', 11500],
    ['Queso Mozzarella 250g', 8900], ['Yogurt Natural 1L', 7500], ['Yogurt Griego 150g', 3200],
    ['Huevos AA x30', 16500], ['Mantequilla 250g', 6800], ['Kumis 1L', 6200], ['Arequipe 250g', 5500],
  ],
  'Panadería': [
    ['Pan Tajado Blanco', 5200], ['Pan Tajado Integral', 5800], ['Pan Francés x6', 3500],
    ['Arepa de Maíz Blanco x5', 4200], ['Arepa de Maíz Amarillo x5', 4200], ['Torta de Vainilla (porción)', 6500],
    ['Galletas de Avena x6', 4800], ['Croissant x4', 6200],
  ],
  'Abarrotes': [
    ['Arroz Diana 500g', 2600], ['Aceite Girasol 1L', 9500], ['Azúcar Blanca 1kg', 4200],
    ['Sal Refisal 500g', 1600], ['Panela Redonda x2', 4500], ['Lentejas 500g', 3800],
    ['Fríjol Cargamanto 500g', 5200], ['Pasta Espagueti 500g', 3200], ['Atún en Lata 170g', 5500],
    ['Sardinas en Lata 425g', 6200], ['Chocolate de Mesa 500g', 8500], ['Café Molido 500g', 14500],
    ['Avena en Hojuelas 500g', 4800], ['Harina de Trigo 1kg', 3600],
  ],
  'Bebidas': [
    ['Coca-Cola 1.5L', 6500], ['Agua Cristal 600ml', 2000], ['Jugo Hit Naranja 1L', 5200],
    ['Colombiana 1.5L', 6200], ['Gaseosa Manzana Postobón 1.5L', 6200], ['Cerveza Águila x6', 21500],
    ['Malta Leona 330ml', 2800], ['Té Frío Limón 400ml', 3200], ['Café Instantáneo 170g', 12500],
    ['Agua con Gas 500ml', 2400],
  ],
  'Aseo del Hogar': [
    ['Detergente en Polvo 1kg', 9800], ['Jabón en Barra Rey x3', 5500], ['Suavizante de Telas 900ml', 8200],
    ['Limpiador Multiusos 1L', 6500], ['Cloro Blanqueador 1L', 4200], ['Esponjilla de Acero x3', 2800],
    ['Papel Higiénico x12', 18500], ['Servilletas x100', 3800], ['Bolsas de Basura x20', 5200],
    ['Ambientador en Aerosol', 9500],
  ],
  'Cuidado Personal': [
    ['Jabón de Baño x3', 6500], ['Shampoo Anticaspa 400ml', 15500], ['Crema Dental 90g', 5800],
    ['Cepillo de Dientes', 4200], ['Desodorante en Barra', 8500], ['Papel Higiénico Suave x4', 7500],
    ['Toallas Higiénicas x10', 6800], ['Pañales Talla M x30', 32500], ['Jabón Líquido de Manos 500ml', 7200],
    ['Alcohol Antiséptico 350ml', 5500],
  ],
  'Mascotas': [
    ['Concentrado para Perro Adulto 8kg', 62000], ['Concentrado para Gato 3kg', 38500],
    ['Arena para Gato 4kg', 22500], ['Snacks para Perro x200g', 12500], ['Correa para Perro', 25000],
    ['Shampoo para Mascotas 500ml', 18500], ['Pechuga de Pollo para Mascota (lb)', 8500],
    ['Juguete para Perro', 15000],
  ],
  'Congelados': [
    ['Papas a la Francesa Congeladas 1kg', 9800], ['Nuggets de Pollo 400g', 11500],
    ['Mix de Vegetales Congelados 500g', 6800], ['Helado de Vainilla 1L', 14500],
    ['Pizza Congelada Familiar', 18500], ['Empanadas Congeladas x10', 12500],
    ['Croquetas de Pollo 400g', 10500], ['Pulpa de Fruta Congelada 500g', 7500],
  ],
};

async function main() {
  const pool = new Pool(connectionConfig());
  const client = await pool.connect();
  let inserted = 0, skipped = 0;
  try {
    await client.query('BEGIN');
    for (const [category, items] of Object.entries(CATALOG)) {
      for (const [name, price] of items) {
        const { rows } = await client.query('SELECT id FROM products WHERE name = $1', [name]);
        if (rows[0]) { skipped++; continue; }
        await client.query(
          `INSERT INTO products (name, price, aliases, available, category) VALUES ($1, $2, '[]', 1, $3)`,
          [name, price, category]
        );
        inserted++;
      }
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }

  console.log(`Catálogo de ejemplo: ${inserted} productos insertados, ${skipped} ya existían.`);
  await pool.end();
}

main().catch(e => { console.error('Error sembrando catálogo:', e.message); process.exit(1); });
