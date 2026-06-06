const { NlpManager } = require('@nlpjs/basic');
const { getDB } = require('../db/database');

// ── Constantes ─────────────────────────────────────────────────
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

const YES_WORDS  = ['si', 'sí', 'yes', 'claro', 'exacto', 'correcto', 'eso', 'ese', 'esa', 'afirmativo', 'dale', 'ok'];
const NO_WORDS   = ['no', 'nope', 'negativo', 'otro', 'otra', 'diferente', 'incorrecto'];

// ── Utilidades (sin cambios) ────────────────────────────────────
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

      if (normText.includes(normTerm) || termWords.every(w => normText.includes(w))) {
        return { product: prod, score: 0 };
      }

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

// ── NLP.js Manager ─────────────────────────────────────────────
let _manager        = null;
let _productHash    = '';
let _trainingPromise = null;

function _hashProducts(products) {
  return products.map(p => `${p.id}:${p.name}:${p.aliases}`).join('|');
}

async function _buildManager(products) {
  const mgr = new NlpManager({
    languages: ['es'],
    forceNER:  true,
    nlu:       { log: false },
    ner:       { builtins: [] },
  });

  // ── Saludos ──
  for (const u of [
    'hola', 'hola buenos días', 'hola buenas tardes', 'hola buenas noches',
    'buenos días', 'buenas tardes', 'buenas noches', 'buenas',
    'buen día', 'hey', 'hey hola', 'saludos', 'qué tal', 'que tal',
    'hola cómo están', 'hola como estan', 'hola están disponibles',
    'buen día señorita', 'buenas señor', 'hola señora', 'hola señorita',
    'saludos cómo están', 'hola están trabajando', 'buenos días tienen disponible',
    'buenas tardes señores', 'hola buenas quería preguntar', 'buen día señores',
  ]) mgr.addDocument('es', u, 'greeting');

  // ── Pedidos ──
  for (const u of [
    'quiero pedir', 'quiero un pedido', 'necesito pedir', 'quiero hacer un pedido',
    'me puede mandar', 'me manda', 'mándame', 'me envía', 'quiero que me manden',
    'necesito que me envíen', 'por favor mándame', 'me hace el favor de mandar',
    'quiero comprar', 'voy a llevar', 'me llevo', 'voy a pedir',
    'solicito', 'requiero', 'quiero adquirir', 'necesito conseguir',
    'me colabora con', 'me despacha', 'quiero que me despachen',
    'quiero dos bultos', 'necesito cinco sacos', 'quiero un costal',
    'me manda tres kilos', 'quiero diez libras', 'necesito una arroba',
    'quiero pedir para mi negocio', 'para mi finca necesito', 'para el ganado necesito',
    'quiero concentrado', 'necesito alimento para', 'quiero el producto',
    'me puede despachar un pedido', 'quiero que me lleven',
    'hola quiero', 'buenas necesito', 'buenos días quiero pedir', 'hola me manda',
    'necesito una carga', 'quiero media carga', 'me despacha un pedido',
    'quiero el de siempre', 'lo mismo de la semana pasada', 'igual que el anterior',
    'me mandan para', 'quiero pedirles', 'les quiero hacer un pedido',
    'buenas quiero pedir', 'hola necesito pedir', 'buenas tardes quiero',
    'para mi casa quiero', 'a mi domicilio mándame',
  ]) mgr.addDocument('es', u, 'order.add');

  // ── Consulta de productos / precios ──
  for (const u of [
    'qué productos tienen', 'qué venden', 'cuáles son sus productos',
    'qué tienen disponible', 'me manda la lista', 'lista de productos',
    'qué hay disponible', 'cuánto vale', 'cuánto cuesta', 'qué precio tiene',
    'me puede dar los precios', 'cuáles son los precios', 'catálogo de productos',
    'información sobre sus productos', 'qué manejan', 'qué trabajan',
    'tienen disponible alguno', 'me manda el menú', 'menú de productos',
    'qué tienen hoy', 'qué tienen para animales', 'qué alimentos manejan',
  ]) mgr.addDocument('es', u, 'product.list');

  // ── Quejas ──
  for (const u of [
    'no llegó mi pedido', 'no ha llegado nada', 'nunca llegó', 'lleva mucho tiempo',
    'tengo un problema', 'quiero hacer una queja', 'quiero reclamar algo',
    'mal servicio', 'me cobraron de más', 'error en el pedido',
    'producto dañado', 'llegó incompleto', 'no sirve', 'está en mal estado',
    'me engañaron', 'no funciona', 'no me han atendido', 'problema con mi pedido',
    'el producto llegó dañado', 'no coincide con lo pedido', 'me mandaron lo incorrecto',
    'pésimo servicio', 'muy mal', 'están fallando', 'no cumplen',
  ]) mgr.addDocument('es', u, 'complaint');

  // ── Confirmación ──
  for (const u of [
    'sí', 'si', 'yes', 'claro', 'correcto', 'eso es',
    'exacto', 'afirmativo', 'dale', 'ok', 'okay', 'está bien',
    'de acuerdo', 'sí señor', 'sí señora', 'claro que sí', 'por supuesto',
    'eso mismo', 'eso quiero', 'sí es ese', 'perfecto', 'listo',
    'eso es lo que quiero', 'sí confirmo', 'confirmo', 'acepto', 'así es',
  ]) mgr.addDocument('es', u, 'confirmation');

  // ── Negación / Cancelación ──
  for (const u of [
    'no', 'nope', 'negativo', 'no gracias', 'cancela', 'cancelar',
    'no quiero', 'otro', 'otra cosa', 'diferente', 'incorrecto',
    'no es ese', 'no eso no', 'no me interesa', 'no por el momento',
    'más tarde', 'no todavía', 'déjalo', 'olvídalo', 'no es lo que quiero',
    'no ese no', 'equivocado', 'no ese producto',
  ]) mgr.addDocument('es', u, 'denial');

  // ── Despedida ──
  for (const u of [
    'gracias', 'muchas gracias', 'gracias señora', 'gracias señor',
    'hasta luego', 'nos vemos', 'chao', 'bye', 'adiós', 'adios',
    'listo gracias', 'ok gracias', 'bien gracias', 'hasta mañana',
    'que les vaya bien', 'hasta pronto', 'que pasen bien',
  ]) mgr.addDocument('es', u, 'farewell');

  // ── Entidades: Unidades ──
  mgr.addNamedEntityText('unit', 'bulto',    ['es'], ['bulto', 'bultos', 'saco', 'sacos', 'costal', 'costales']);
  mgr.addNamedEntityText('unit', 'kg',       ['es'], ['kg', 'kilo', 'kilos', 'kilogramo', 'kilogramos']);
  mgr.addNamedEntityText('unit', 'arroba',   ['es'], ['arroba', 'arrobas']);
  mgr.addNamedEntityText('unit', 'libra',    ['es'], ['libra', 'libras']);
  mgr.addNamedEntityText('unit', 'tonelada', ['es'], ['tonelada', 'toneladas', 'ton']);
  mgr.addNamedEntityText('unit', 'carga',    ['es'], ['carga', 'cargas', 'media carga']);
  mgr.addNamedEntityText('unit', 'paquete',  ['es'], ['paquete', 'paquetes', 'bolsa', 'bolsas']);

  // ── Entidades: Cantidad (regex) ──
  mgr.addRegexEntity('quantity', 'es', /\b(\d{1,4})\b/);

  // ── Entidades: Productos desde DB ──
  for (const prod of products) {
    const aliases = JSON.parse(prod.aliases || '[]').filter(Boolean);
    const terms   = [prod.name, ...aliases];
    mgr.addNamedEntityText('product', String(prod.id), ['es'], terms);
  }

  // ── Respuestas automáticas ──
  mgr.addAnswer('es', 'greeting',      '¡Hola! Bienvenido a Concentrados Monserrath. ¿En qué le podemos ayudar?');
  mgr.addAnswer('es', 'farewell',      '¡Hasta luego! Gracias por contactarnos.');
  mgr.addAnswer('es', 'product.list',  'Con gusto le informamos sobre nuestros productos disponibles.');

  await mgr.train();
  return mgr;
}

function _getManager() {
  const db       = getDB();
  const products = db.prepare('SELECT id, name, aliases FROM products WHERE available=1').all();
  const hash     = _hashProducts(products);

  if (_manager && hash === _productHash) return Promise.resolve(_manager);

  if (!_trainingPromise || hash !== _productHash) {
    _trainingPromise = _buildManager(products).then(mgr => {
      _manager     = mgr;
      _productHash = hash;
      return mgr;
    }).catch(err => {
      _trainingPromise = null;
      throw err;
    });
  }
  return _trainingPromise;
}

// Pre-entrenar al cargar el módulo (no bloqueante)
setImmediate(() => _getManager().catch(() => {}));

// ── parseOrderMessage ──────────────────────────────────────────
async function parseOrderMessage(waMessage) {
  const db       = getDB();
  const products = db.prepare('SELECT * FROM products WHERE available=1').all();

  const is_fiado = FIADO_WORDS.some(w => waMessage.toLowerCase().includes(w));
  const addr     = extractAddress(waMessage);
  const fuzzy    = fuzzyProductMatch(waMessage, products);

  let result = {
    product_id:         fuzzy?.product?.id   ?? null,
    product_name:       fuzzy?.product?.name ?? null,
    delivery_address:   addr,
    is_fiado,
    customer_name:      null,
    confidence:         fuzzy ? (fuzzy.score === 0 ? 'high' : 'medium') : 'low',
    needs_confirmation: fuzzy ? (fuzzy.score > 0 && fuzzy.score < 0.6) : false,
    source:             'rules',
    intent:             null,
    quantity:           null,
  };

  try {
    const mgr = await _getManager();
    const nlp = await mgr.process('es', waMessage);

    result.intent = nlp.intent;

    // Cantidad desde NER
    const qtyEnt = nlp.entities?.find(e => e.entity === 'quantity');
    if (qtyEnt) result.quantity = parseInt(qtyEnt.sourceText, 10) || null;

    // Unidad desde NER
    const unitEnt = nlp.entities?.find(e => e.entity === 'unit');
    if (unitEnt) result.unit = unitEnt.option;

    // Producto desde NER (si fuzzy no encontró nada)
    if (!result.product_id) {
      const prodEnt = nlp.entities?.find(e => e.entity === 'product');
      if (prodEnt) {
        const prod = products.find(p => String(p.id) === prodEnt.option);
        if (prod) {
          result.product_id         = prod.id;
          result.product_name       = prod.name;
          result.confidence         = 'high';
          result.needs_confirmation = false;
        }
      }
    }

    // Aumentar confianza si NLP confirma que es un pedido
    if (nlp.intent === 'order.add' && result.product_id && nlp.score > 0.7) {
      result.confidence = 'high';
      if (fuzzy && fuzzy.score === 0) result.needs_confirmation = false;
    }

    result.source = 'nlpjs';
  } catch { /* usa resultado de reglas */ }

  return result;
}

// ── parseMultiItems (sin cambios) ──────────────────────────────
const QTY_RE  = /(\d+)?\s*(?:bultos?|sacos?|kilos?|kg|unidades?|bolsas?|paquetes?)?\s*(?:de\s+|del?\s+)?/i;
const SPLIT_RE = /\s+(?:y|más|mas|también|tambien|\+|,)\s+/i;

function parseMultiItems(text, products) {
  const norm = text.replace(/\s+/g, ' ').trim();
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

// ── getIntent (util extra para uso futuro) ─────────────────────
async function getIntent(text) {
  try {
    const mgr = await _getManager();
    const r   = await mgr.process('es', text);
    return { intent: r.intent, score: r.score };
  } catch {
    return { intent: 'unknown', score: 0 };
  }
}

module.exports = {
  parseOrderMessage, parseMultiItems, fuzzyProductMatch, extractAddress,
  isGreeting, isComplaint, isConfirmation, isDenial, getIntent,
};
