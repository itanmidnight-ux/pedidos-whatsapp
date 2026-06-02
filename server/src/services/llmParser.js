const { Ollama } = require('ollama');
const { getDB } = require('../db/database');

const ollama = new Ollama({ host: 'http://localhost:11434' });

const FIADO_WORDS = [
  'después', 'despues', 'mañana', 'manana', 'viernes', 'lunes', 'martes',
  'miércoles', 'miercoles', 'jueves', 'sábado', 'sabado', 'domingo',
  'le pago', 'luego pago', 'le debo', 'fiado', 'me fía', 'me fia',
  'cuando pueda', 'próxima semana', 'proxima semana', 'la semana',
];

const GREETING_WORDS = [
  'hola', 'buenos días', 'buenos dias', 'buenas tardes', 'buenas noches',
  'buenas', 'buen dia', 'buen día', 'hey', 'saludos', 'que tal', 'qué tal',
];

const COMPLAINT_WORDS = [
  'no me han pagado', 'no han llegado', 'no llegó', 'no llego', 'nunca llegó',
  'problema', 'reclamo', 'queja', 'me cobraron', 'me engañaron', 'mal servicio',
  'no funcionó', 'no funciono', 'devolver', 'devolución', 'devolucion',
  'incompleto', 'dañado', 'dañada', 'no sirve',
];

const YES_WORDS = ['si', 'sí', 'yes', 'claro', 'exacto', 'correcto', 'eso', 'ese', 'esa', 'afirmativo', 'dale', 'ok'];
const NO_WORDS  = ['no', 'nope', 'negativo', 'otro', 'otra', 'diferente', 'incorrecto'];

function normalize(str) {
  return str.toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function levenshtein(a, b) {
  const m = a.length, n = b.length;
  const dp = Array.from({ length: m + 1 }, (_, i) =>
    Array.from({ length: n + 1 }, (_, j) => (i === 0 ? j : j === 0 ? i : 0))
  );
  for (let i = 1; i <= m; i++)
    for (let j = 1; j <= n; j++)
      dp[i][j] = a[i-1] === b[j-1]
        ? dp[i-1][j-1]
        : 1 + Math.min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1]);
  return dp[m][n];
}

// Retorna { product, score } — score 0=exacto, 1=sin coincidencia
function fuzzyProductMatch(text, products) {
  const normText = normalize(text);
  const msgWords = normText.split(' ').filter(w => w.length > 2);

  let bestProduct = null;
  let bestScore   = 1;

  for (const prod of products) {
    const aliases  = JSON.parse(prod.aliases || '[]');
    const terms    = [prod.name, ...aliases];

    for (const term of terms) {
      const normTerm  = normalize(term);
      const termWords = normTerm.split(' ').filter(w => w.length > 2);

      // Coincidencia exacta de subcadena — score 0
      if (normText.includes(normTerm) || termWords.every(w => normText.includes(w))) {
        return { product: prod, score: 0 };
      }

      // Coincidencia por palabras con tolerancia Levenshtein 30%
      if (termWords.length === 0) continue;
      let hits = 0;
      for (const tw of termWords) {
        if (msgWords.some(mw => {
          const maxLen = Math.max(tw.length, mw.length);
          return maxLen > 0 && levenshtein(tw, mw) / maxLen <= 0.3;
        })) hits++;
      }
      const ratio = hits / termWords.length;
      if (ratio >= 0.5) {
        const score = 1 - ratio;
        if (score < bestScore) { bestScore = score; bestProduct = prod; }
      }
    }
  }
  return bestProduct ? { product: bestProduct, score: bestScore } : null;
}

function extractAddress(text) {
  const stop = '(mañana|manana|despues|después|le pago|fiado|me fía|\\.|$)';
  const patterns = [
    new RegExp(`para donde (.+?)(?:${stop})`, 'i'),
    new RegExp(`para (.+?)(?:${stop})`, 'i'),
    new RegExp(`a donde (.+?)(?:${stop})`, 'i'),
    new RegExp(`dirección:?\\s*(.+?)(?:${stop})`, 'i'),
    new RegExp(`entregar en (.+?)(?:${stop})`, 'i'),
    new RegExp(`llevar a (.+?)(?:${stop})`, 'i'),
  ];
  for (const p of patterns) {
    const m = text.match(p);
    if (m?.[1]?.trim().length > 1) return m[1].trim();
  }
  return null;
}

function isGreeting(text) {
  const norm = normalize(text);
  return GREETING_WORDS.some(g => norm.startsWith(g) || norm === normalize(g));
}

function isComplaint(text) {
  const norm = normalize(text);
  return COMPLAINT_WORDS.some(w => norm.includes(normalize(w)));
}

function isConfirmation(text) {
  const norm = normalize(text);
  return YES_WORDS.some(w => norm === w || norm.startsWith(w + ' '));
}

function isDenial(text) {
  const norm = normalize(text);
  return NO_WORDS.some(w => norm === w || norm.startsWith(w + ' '));
}

function buildPrompt(message, products) {
  const list = products.map(p => {
    const al = JSON.parse(p.aliases || '[]').join(', ');
    return `  id:${p.id} | "${p.name}"${al ? ` (también: ${al})` : ''} | $${p.price}`;
  }).join('\n');

  return `Eres un asistente de pedidos para una empresa de alimentos concentrados para animales.

PRODUCTOS DISPONIBLES:
${list || '  (sin productos configurados)'}

MENSAJE DEL CLIENTE: "${message}"

TAREA:
1. Identifica el producto pedido. Si está mal escrito, encuentra el más parecido.
2. Extrae la dirección (palabras: "para donde", "para", "a donde", "dirección", "en").
3. Detecta si es fiado (palabras: "después", "mañana", "le pago", "fiado", "luego").
4. Extrae el nombre del cliente si lo menciona.

Responde SOLO con JSON, sin texto adicional:
{"product_name":null,"product_id":null,"delivery_address":null,"is_fiado":false,"customer_name":null,"confidence":"low"}`;
}

async function parseOrderMessage(waMessage) {
  const db       = getDB();
  const products = db.prepare('SELECT * FROM products WHERE available = 1').all();

  const is_fiado = FIADO_WORDS.some(w => waMessage.toLowerCase().includes(w));
  const addr     = extractAddress(waMessage);
  const fuzzy    = fuzzyProductMatch(waMessage, products);

  // Base desde reglas
  let result = {
    product_id:           fuzzy?.product?.id   ?? null,
    product_name:         fuzzy?.product?.name ?? null,
    delivery_address:     addr,
    is_fiado,
    customer_name:        null,
    confidence:           fuzzy ? (fuzzy.score === 0 ? 'high' : 'medium') : 'low',
    needs_confirmation:   fuzzy && fuzzy.score > 0 && fuzzy.score < 0.6,
    source:               'rules',
  };

  try {
    const response = await ollama.generate({
      model:   process.env.OLLAMA_MODEL || 'qwen2.5:3b',
      prompt:  buildPrompt(waMessage, products),
      options: { temperature: 0.05, num_predict: 180 },
      stream:  false
    });

    const raw       = response.response?.trim() || '';
    const jsonMatch = raw.match(/\{[\s\S]*?\}/);
    if (!jsonMatch) throw new Error('no JSON');
    const parsed = JSON.parse(jsonMatch[0]);

    // Resolver product via fuzzy sobre resultado del LLM
    if (parsed.product_name) {
      const match = fuzzyProductMatch(parsed.product_name, products);
      if (match) {
        parsed.product_id          = match.product.id;
        parsed.product_name        = match.product.name;
        parsed.needs_confirmation  = match.score > 0 && match.score < 0.6;
        // Si LLM encontró exacto (score=0), marcar como high y sin confirmación
        if (match.score === 0) {
          parsed.confidence        = 'high';
          parsed.needs_confirmation = false;
        }
      } else {
        parsed.product_id   = null;
        parsed.product_name = null;
      }
    }

    // Fallback: si LLM no encontró producto pero fuzzy sí
    if (!parsed.product_id && fuzzy) {
      parsed.product_id         = fuzzy.product.id;
      parsed.product_name       = fuzzy.product.name;
      parsed.needs_confirmation = fuzzy.score > 0;
    }

    if (!parsed.delivery_address) parsed.delivery_address = addr;
    if (typeof parsed.is_fiado !== 'boolean') parsed.is_fiado = is_fiado;
    parsed.source = 'llm';
    result = parsed;

  } catch { /* usa result de reglas */ }

  return result;
}

// ── Fase 4: Multi-product extraction ─────────────────────────
const QTY_RE  = /(\d+)?\s*(?:bultos?|sacos?|kilos?|kg|unidades?|bolsas?|paquetes?)?\s*(?:de\s+|del?\s+)?/i;
const SPLIT_RE = /\s+(?:y|más|mas|también|tambien|\+|,)\s+/i;

function parseMultiItems(text, products) {
  const norm = text.replace(/\s+/g, ' ').trim();
  // Only attempt multi-parse if likely multiple items
  if (!SPLIT_RE.test(norm)) return null;

  const segments = norm.split(SPLIT_RE).map(s => s.trim()).filter(Boolean);
  if (segments.length < 2) return null;

  const items = [];
  for (const seg of segments) {
    const qtyMatch = seg.match(/^(\d+)\s*/);
    const qty      = qtyMatch ? parseInt(qtyMatch[1]) : 1;
    const cleaned  = seg.replace(/^(\d+)\s*(bultos?|sacos?|kilos?|kg|unidades?|bolsas?|paquetes?)?\s*(?:de\s+|del?\s+)?/i, '').trim();
    const match    = fuzzyProductMatch(cleaned, products);
    if (match) {
      items.push({
        product_id:    match.product.id,
        product_name:  match.product.name,
        product_price: match.product.price,
        quantity:      qty,
        confidence:    match.score === 0 ? 'high' : match.score < 0.5 ? 'medium' : 'low',
        needs_confirmation: match.score > 0.3,
      });
    }
  }
  return items.length >= 2 ? items : null;
}

module.exports = { parseOrderMessage, parseMultiItems, fuzzyProductMatch, extractAddress, isGreeting, isComplaint, isConfirmation, isDenial };
