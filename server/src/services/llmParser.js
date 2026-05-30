const { Ollama } = require('ollama');
const { getDB } = require('../db/database');

const ollama = new Ollama({ host: 'http://localhost:11434' });

const FIADO_WORDS = [
  'después', 'despues', 'mañana', 'manana', 'viernes', 'lunes', 'martes',
  'miércoles', 'miercoles', 'jueves', 'sábado', 'sabado', 'domingo',
  'le pago', 'luego pago', 'le debo', 'fiado', 'me fía', 'me fia',
  'cuando pueda', 'próxima semana', 'proxima semana', 'la semana', 'mañana le'
];

function ruleBasedParse(message, products) {
  const msg = message.toLowerCase();

  const is_fiado = FIADO_WORDS.some(w => msg.includes(w));

  let delivery_address = null;
  const stopWords = '(mañana|manana|despues|después|le pago|fiado|me fía|,|\\.|$)';
  const addressPatterns = [
    new RegExp(`para donde (.+?)(?:${stopWords})`, 'i'),
    new RegExp(`a donde (.+?)(?:${stopWords})`, 'i'),
    new RegExp(`dirección:?\\s*(.+?)(?:${stopWords})`, 'i'),
    new RegExp(`entregar en (.+?)(?:${stopWords})`, 'i'),
  ];
  for (const p of addressPatterns) {
    const m = message.match(p);
    if (m) { delivery_address = m[1].trim(); break; }
  }

  let product_name = null;
  let product_id = null;
  if (products.length > 0) {
    for (const prod of products) {
      const aliases = JSON.parse(prod.aliases || '[]');
      const terms = [prod.name, ...aliases].map(t => t.toLowerCase());
      if (terms.some(t => msg.includes(t))) {
        product_name = prod.name;
        product_id = prod.id;
        break;
      }
    }
  }

  let customer_name = null;
  const namePatterns = [/soy (.+?)(?:,|\.|$)/i, /habla (.+?)(?:,|\.|$)/i, /de parte de (.+?)(?:,|\.|$)/i];
  for (const p of namePatterns) {
    const m = message.match(p);
    if (m) { customer_name = m[1].trim(); break; }
  }

  return {
    product_name, product_id, delivery_address,
    is_fiado, customer_name,
    confidence: product_name ? 'medium' : 'low',
    source: 'rules'
  };
}

function buildPrompt(message, products) {
  const productList = products
    .map(p => `- "${p.name}" (aliases: ${JSON.parse(p.aliases || '[]').join(', ')}) precio: $${p.price}`)
    .join('\n');

  return `Eres un asistente que extrae datos de pedidos de productos para animales.

PRODUCTOS DISPONIBLES:
${productList || '(sin productos aun)'}

MENSAJE DEL CLIENTE:
"${message}"

Responde ÚNICAMENTE con JSON válido sin explicaciones:
{"product_name":null,"product_id":null,"delivery_address":null,"is_fiado":false,"customer_name":null,"confidence":"low"}

Reglas:
- is_fiado=true si contiene: "después","mañana","le pago","fiado","me fía","luego pago"
- delivery_address: extrae "para donde X","a donde X","en X"
- product_name: busca coincidencia con aliases
- confidence: "high" si detectas todo, "medium" si algo, "low" si nada`;
}

async function parseOrderMessage(waMessage, senderName) {
  const db = getDB();
  const products = db.prepare('SELECT * FROM products WHERE available = 1').all();

  // Intenta LLM primero
  try {
    const response = await ollama.generate({
      model: process.env.OLLAMA_MODEL || 'llama3.2:1b',
      prompt: buildPrompt(waMessage, products),
      options: { temperature: 0.1, num_predict: 250 },
      stream: false
    });

    const raw = response.response?.trim() || '';
    const jsonMatch = raw.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error('No JSON');

    const parsed = JSON.parse(jsonMatch[0]);

    if (parsed.product_name) {
      const match = products.find(p => {
        const aliases = JSON.parse(p.aliases || '[]');
        return [p.name, ...aliases].some(a =>
          a.toLowerCase().includes(parsed.product_name.toLowerCase()) ||
          parsed.product_name.toLowerCase().includes(a.toLowerCase())
        );
      });
      if (match) { parsed.product_id = match.id; parsed.product_name = match.name; }
    }

    parsed.source = 'llm';
    return parsed;
  } catch {
    // Fallback a reglas si LLM falla (sin RAM, timeout, etc.)
    return ruleBasedParse(waMessage, products);
  }
}

module.exports = { parseOrderMessage };
