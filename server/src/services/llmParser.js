const { NlpManager } = require('@nlpjs/basic');
const { getDB } = require('../db/database');

// ── Constantes ─────────────────────────────────────────────────
const FIADO_WORDS = [
  // Días / tiempo
  'después', 'despues', 'mañana', 'manana', 'viernes', 'lunes', 'martes',
  'miércoles', 'miercoles', 'jueves', 'sábado', 'sabado', 'domingo',
  'la semana', 'próxima semana', 'proxima semana', 'la otra semana',
  'el próximo', 'el proximo', 'el mes que', 'el viernes',
  // Pago diferido
  'le pago', 'luego pago', 'le debo', 'fiado', 'me fía', 'me fia',
  'cuando pueda', 'le cancelo', 'ya le cancelo', 'le cuadro',
  // Colombian slang deferred payment
  'horita', 'ahoritica', 'ahorita', 'ya le mando', 'le mando la plata',
  'cuando me manden', 'cuando cobre', 'cuando me paguen', 'cuando llegue',
  'cuando salga', 'cuando tenga', 'le consigo', 'me presta', 'me colabora',
  'pa la proxima', 'pa la próxima', 'horita que', 'ahorita que',
];

const GREETING_WORDS = [
  'hola', 'buenos días', 'buenos dias', 'buenas tardes', 'buenas noches',
  'buenas', 'buen dia', 'buen día', 'hey', 'saludos', 'que tal', 'qué tal',
  'como esta', 'como están', 'cómo está', 'cómo están', 'que más', 'qué más',
  'ome', 'parce', 'llave',
];

const COMPLAINT_WORDS = [
  'no me han pagado', 'no han llegado', 'no llegó', 'no llego', 'nunca llegó',
  'problema', 'reclamo', 'queja', 'me cobraron', 'me engañaron', 'mal servicio',
  'no funcionó', 'no funciono', 'devolver', 'devolución', 'devolucion',
  'incompleto', 'dañado', 'dañada', 'no sirve', 'pésimo', 'pesimo',
  'no cumplieron', 'me fallaron', 'están fallando',
];

const YES_WORDS  = ['si', 'sí', 'yes', 'claro', 'exacto', 'correcto', 'eso', 'ese', 'esa', 'afirmativo', 'dale', 'ok', 'oka', 'listo', 'bueno', 'así es', 'así', 'eso mismo'];
const NO_WORDS   = ['no', 'nope', 'negativo', 'otro', 'otra', 'diferente', 'incorrecto', 'nope', 'nel'];

// Palabras que indican contenido de pedido (para detectar orden en saludo)
const ORDER_HINT_WORDS = [
  'traer', 'trae', 'traes', 'traerme', 'llevar', 'lleva', 'llevas',
  'mandar', 'manda', 'mandas', 'mandarme', 'enviar', 'envía', 'envias',
  'despachar', 'despacha', 'pedido', 'pedir', 'pido',
  'quiero', 'necesito', 'requiero', 'solicito',
  'bulto', 'saco', 'costal', 'kilo', 'kg', 'libra', 'arroba', 'carga',
  'concentrado', 'alimento', 'levante', 'engorde', 'ponedora',
];

// Palabras a ignorar en detección de ambigüedad (aparecen en muchos productos)
const AMBIGUITY_SKIP_WORDS = new Set([
  'para', 'donde', 'como', 'todo', 'bulto', 'kilo', 'saco', 'costal',
  'quiero', 'necesito', 'favor', 'gracias', 'traer', 'trae', 'manda',
  'lleva', 'envía', 'mandar', 'puedo', 'puede', 'podría', 'podrias',
  'hola', 'buenas', 'buenos', 'bien', 'dias', 'aqui', 'allá', 'esta',
  'esto', 'eso', 'para', 'desde', 'hasta', 'arroba', 'libra', 'carga',
  'unos', 'unas', 'unos', 'algo', 'algún', 'alguna', 'todos', 'toda',
  'kilo', 'kilos', 'concentrado', 'alimento', // muy genéricos
]);

// ── Utilidades ─────────────────────────────────────────────────
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

      // Coincidencia exacta de subcadena
      if (normText.includes(normTerm) || (termWords.length > 0 && termWords.every(w => normText.includes(w)))) {
        return { product: prod, score: 0 };
      }

      // Coincidencia difusa con tolerancia Levenshtein 30%
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
  const stop = '(mañana|manana|despues|después|le pago|fiado|me fía|horita|ahorita|\\.|$)';
  const patterns = [
    new RegExp(`para donde (.+?)(?:${stop})`, 'i'),
    new RegExp(`a donde (.+?)(?:${stop})`, 'i'),
    new RegExp(`pa donde (.+?)(?:${stop})`, 'i'),
    new RegExp(`a lo de (.+?)(?:${stop})`, 'i'),
    new RegExp(`pa lo de (.+?)(?:${stop})`, 'i'),
    new RegExp(`para (.+?)(?:${stop})`, 'i'),
    new RegExp(`dirección:?\\s*(.+?)(?:${stop})`, 'i'),
    new RegExp(`entregar en (.+?)(?:${stop})`, 'i'),
    new RegExp(`llevar a (.+?)(?:${stop})`, 'i'),
    new RegExp(`al barrio (.+?)(?:${stop})`, 'i'),
    new RegExp(`a la finca (.+?)(?:${stop})`, 'i'),
    new RegExp(`vereda (.+?)(?:${stop})`, 'i'),
  ];
  for (const p of patterns) {
    const m = text.match(p);
    if (m?.[1]?.trim().length > 1) return m[1].trim();
  }
  return null;
}

function isGreeting(text) {
  const norm = normalize(text);
  return GREETING_WORDS.some(g => norm.startsWith(normalize(g)) || norm === normalize(g));
}

function hasOrderContent(text) {
  const norm = normalize(text);
  return ORDER_HINT_WORDS.some(w => norm.includes(w));
}

function isComplaint(text) {
  const norm = normalize(text);
  return COMPLAINT_WORDS.some(w => norm.includes(normalize(w)));
}

function isConfirmation(text) {
  const norm = normalize(text);
  return YES_WORDS.some(w => norm === normalize(w) || norm.startsWith(normalize(w) + ' '));
}

function isDenial(text) {
  const norm = normalize(text);
  return NO_WORDS.some(w => norm === normalize(w) || norm.startsWith(normalize(w) + ' '));
}

// Detecta cuando el usuario menciona una categoría que coincide con múltiples productos
// Ej: "un bulto de engorde" → hay "engorde cerdo" y "engorde pollo" → ambiguo
function findAmbiguousCategory(text, products) {
  if (!products || products.length === 0) return null;
  const normText = normalize(text);
  const msgWords = normText.split(' ').filter(w => w.length >= 4 && !AMBIGUITY_SKIP_WORDS.has(w));

  for (const word of msgWords) {
    const matching = products.filter(prod => {
      const aliases = JSON.parse(prod.aliases || '[]');
      const terms   = [prod.name, ...aliases];
      // Check exact word presence in product name/alias
      return terms.some(t => {
        const nt = normalize(t);
        return nt.includes(word) || levenshtein(word, nt.split(' ').find(w2 => w2.length >= 4 && Math.abs(w2.length - word.length) <= 2) || '') / Math.max(word.length, 4) <= 0.25;
      });
    });

    // Ambiguo: palabra coincide con 2+ productos pero no todos
    if (matching.length >= 2 && matching.length < products.length) {
      // Make sure it's not a generic hit — verify the word is actually in the product names
      const confirmed = matching.filter(prod => {
        const terms = [prod.name, ...JSON.parse(prod.aliases || '[]')];
        return terms.some(t => normalize(t).split(' ').some(tw =>
          tw.length >= 4 && levenshtein(tw, word) / Math.max(tw.length, word.length) <= 0.2
        ));
      });
      if (confirmed.length >= 2) {
        return { keyword: word, candidates: confirmed };
      }
    }
  }
  return null;
}

// ── NLP.js Manager ─────────────────────────────────────────────
let _manager         = null;
let _productHash     = '';
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

  // ── Saludos ──────────────────────────────────────────────────
  for (const u of [
    'hola', 'hola buenos días', 'hola buenas tardes', 'hola buenas noches',
    'buenos días', 'buenas tardes', 'buenas noches', 'buenas',
    'buen día', 'hey', 'hey hola', 'saludos', 'qué tal', 'que tal',
    'cómo están', 'como están', 'hola están disponibles', 'están trabajando',
    'buen día señorita', 'buenas señor', 'hola señora', 'hola señorita',
    'buenas tardes señores', 'hola buenas quería preguntar',
    'ome qué más', 'parce buenas', 'llave qué más', 'qué más pues',
    'hola cómo les va', 'hola todo bien', 'buenos días señores',
    'hola hay alguien', 'buenas están', 'hola atienden',
    'hola buenas quería saber', 'hola buenas quería preguntar algo',
    'saludos cordiales', 'muy buenos días', 'muy buenas tardes',
  ]) mgr.addDocument('es', u, 'greeting');

  // ── Pedidos (general + colombiano) ───────────────────────────
  for (const u of [
    // Castellano estándar
    'quiero pedir', 'quiero un pedido', 'necesito pedir', 'quiero hacer un pedido',
    'me puede mandar', 'mándame', 'me envía', 'quiero que me manden',
    'necesito que me envíen', 'por favor mándame', 'me hace el favor de mandar',
    'quiero comprar', 'voy a llevar', 'voy a pedir', 'solicito', 'requiero',
    // Colombiano informal
    'me traes', 'me trae', 'me traes un bulto', 'me puedes traer',
    'me llevas', 'me lleva', 'me puedes llevar', 'me puede llevar',
    'me manda', 'me mandas', 'me haces el favor', 'me hace el favor',
    'me colabora', 'me colaboras', 'me regala', 'me regalas',
    'me despacha', 'de una mándame', 'de una me manda', 'ahoritica me envía',
    'ya me manda', 'me puede hacer el favor', 'me haría el favor',
    'ome me manda', 'parce me envía', 'llave me trae',
    'me puedes mandar', 'podrías mandarme', 'me podrías traer',
    'me harías el favor de traerme', 'le cuadro después',
    // Con dirección al final (común en Colombia)
    'traerme a donde', 'mandarme para donde', 'llevame a donde',
    'quiero que me lleven a donde', 'me mandan para donde',
    'hola me traes', 'buenas me manda', 'hola quiero', 'buenas quiero',
    'buenos días quiero pedir', 'hola necesito', 'buenas tardes necesito',
    // Con cantidades
    'quiero dos bultos', 'necesito cinco sacos', 'quiero un costal',
    'me manda tres kilos', 'quiero diez libras', 'necesito una arroba',
    'un bulto de', 'dos sacos de', 'media carga de', 'una tonelada de',
    // Para negocio / finca
    'quiero pedir para mi negocio', 'para mi finca necesito',
    'para el ganado necesito', 'para mis gallinas', 'para los cerdos',
    'para mis animales', 'para la granja', 'necesito para la finca',
    // Repetir pedido anterior
    'lo mismo de la semana pasada', 'igual que el anterior',
    'lo de siempre', 'el pedido de siempre', 'como siempre',
    'repítame el pedido', 'lo mismo de antes',
    // Con precio / fiado incluido en el mensaje
    'mándame que ya le pago', 'me manda que de contado',
    'de contado me manda', 'le pago al momento', 'pago inmediato',
    'podría traerme un bulto', 'podría mandarme algo',
    'tiene disponible', 'hay disponible', 'me puede vender',
  ]) mgr.addDocument('es', u, 'order.add');

  // ── Consulta de productos / precios ──────────────────────────
  for (const u of [
    'qué productos tienen', 'qué venden', 'cuáles son sus productos',
    'qué tienen disponible', 'me manda la lista', 'lista de productos',
    'qué hay disponible', 'cuánto vale', 'cuánto cuesta', 'qué precio tiene',
    'me puede dar los precios', 'cuáles son los precios', 'catálogo',
    'qué manejan', 'qué trabajan', 'me manda el menú', 'menú de productos',
    'qué tienen hoy', 'qué alimentos manejan', 'qué concentrados tienen',
    'información sobre sus productos', 'qué referencias manejan',
    'tienen concentrado para', 'qué tienen para',
    'cuánto me sale', 'a cómo está', 'a cómo tienen',
  ]) mgr.addDocument('es', u, 'product.list');

  // ── Quejas / reclamos ─────────────────────────────────────────
  for (const u of [
    'no llegó mi pedido', 'no ha llegado nada', 'nunca llegó',
    'lleva mucho tiempo', 'tengo un problema', 'quiero hacer una queja',
    'quiero reclamar algo', 'mal servicio', 'me cobraron de más',
    'error en el pedido', 'producto dañado', 'llegó incompleto',
    'no sirve', 'está en mal estado', 'me engañaron',
    'no me han atendido', 'el producto llegó dañado',
    'no coincide con lo pedido', 'me mandaron lo incorrecto',
    'pésimo servicio', 'están fallando', 'no cumplen', 'me fallaron',
    'lleva días y no llega', 'ya van dos días', 'no han despachado',
  ]) mgr.addDocument('es', u, 'complaint');

  // ── Confirmación ─────────────────────────────────────────────
  for (const u of [
    'sí', 'si', 'yes', 'claro', 'correcto', 'eso es',
    'exacto', 'afirmativo', 'dale', 'ok', 'okay', 'está bien',
    'de acuerdo', 'sí señor', 'sí señora', 'claro que sí', 'por supuesto',
    'eso mismo', 'sí es ese', 'perfecto', 'listo', 'sí confirmo',
    'confirmo', 'acepto', 'así es', 'así mismo', 'eso quiero',
    'eso es lo que quiero', 'con ese', 'con esa', 'ese mismo',
    // Colombian confirms
    'listo pues', 'dale pues', 'claro pues', 'sí pues', 'oiga sí',
    'ese mismo pues', 'eso es pues', 'ajá sí', 'ajá ese',
  ]) mgr.addDocument('es', u, 'confirmation');

  // ── Negación / cancelación ────────────────────────────────────
  for (const u of [
    'no', 'nope', 'negativo', 'no gracias', 'cancela', 'cancelar',
    'no quiero', 'otro', 'otra cosa', 'diferente', 'incorrecto',
    'no es ese', 'no eso no', 'no me interesa', 'no por el momento',
    'más tarde', 'déjalo', 'olvídalo', 'no es lo que quiero',
    'no ese no', 'equivocado', 'ese no', 'no ese producto',
    // Colombian
    'nel', 'nel pastel', 'nanay', 'no gracias',
    'no ese no pues', 'ese no pues', 'no pues',
  ]) mgr.addDocument('es', u, 'denial');

  // ── Despedida ─────────────────────────────────────────────────
  for (const u of [
    'gracias', 'muchas gracias', 'gracias señora', 'gracias señor',
    'hasta luego', 'nos vemos', 'chao', 'bye', 'adiós', 'adios',
    'listo gracias', 'ok gracias', 'bien gracias', 'hasta mañana',
    'que les vaya bien', 'hasta pronto', 'que pasen bien',
    'chao chao', 'gracias que dios les pague', 'muy amables gracias',
    'listo pues gracias', 'bueno gracias pues',
  ]) mgr.addDocument('es', u, 'farewell');

  // ── Entidades: Unidades ──────────────────────────────────────
  mgr.addNamedEntityText('unit', 'bulto',    ['es'], ['bulto', 'bultos', 'saco', 'sacos', 'costal', 'costales', 'lote', 'lotes']);
  mgr.addNamedEntityText('unit', 'kg',       ['es'], ['kg', 'kilo', 'kilos', 'kilogramo', 'kilogramos']);
  mgr.addNamedEntityText('unit', 'arroba',   ['es'], ['arroba', 'arrobas']);
  mgr.addNamedEntityText('unit', 'libra',    ['es'], ['libra', 'libras']);
  mgr.addNamedEntityText('unit', 'tonelada', ['es'], ['tonelada', 'toneladas', 'ton', 'toneladas']);
  mgr.addNamedEntityText('unit', 'carga',    ['es'], ['carga', 'cargas', 'media carga', 'cuarto de carga']);
  mgr.addNamedEntityText('unit', 'paquete',  ['es'], ['paquete', 'paquetes', 'bolsa', 'bolsas', 'caja', 'cajas']);
  mgr.addNamedEntityText('unit', 'unidad',   ['es'], ['unidad', 'unidades', 'pieza', 'piezas']);

  // ── Entidades: Cantidad (regex) ──────────────────────────────
  mgr.addRegexEntity('quantity', 'es', /\b(\d{1,5})\b/);

  // ── Entidades: Productos desde DB ───────────────────────────
  for (const prod of products) {
    const aliases = JSON.parse(prod.aliases || '[]').filter(Boolean);
    const terms   = [prod.name, ...aliases];
    mgr.addNamedEntityText('product', String(prod.id), ['es'], terms);
  }

  // ── Respuestas automáticas ───────────────────────────────────
  mgr.addAnswer('es', 'greeting',     '¡Hola! Bienvenido a Concentrados Monserrath. ¿En qué le podemos ayudar?');
  mgr.addAnswer('es', 'farewell',     '¡Hasta luego! Gracias por contactarnos.');
  mgr.addAnswer('es', 'product.list', 'Con gusto le informamos sobre nuestros productos.');

  await mgr.train();
  return mgr;
}

function _getManager() {
  const db       = getDB();
  const products = db.prepare('SELECT id, name, aliases FROM products WHERE available=1').all();
  const hash     = _hashProducts(products);

  if (_manager && hash === _productHash) return Promise.resolve(_manager);

  if (!_trainingPromise || hash !== _productHash) {
    _productHash     = hash; // set early to prevent parallel retrains
    _trainingPromise = _buildManager(products).then(mgr => {
      _manager = mgr;
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
    product_id:            fuzzy?.product?.id   ?? null,
    product_name:          fuzzy?.product?.name ?? null,
    delivery_address:      addr,
    is_fiado,
    customer_name:         null,
    confidence:            fuzzy ? (fuzzy.score === 0 ? 'high' : 'medium') : 'low',
    needs_confirmation:    fuzzy ? (fuzzy.score > 0 && fuzzy.score < 0.6) : false,
    needs_clarification:   false,
    ambiguous_keyword:     null,
    ambiguous_candidates:  null,
    source:                'rules',
    intent:                null,
    quantity:              null,
    unit:                  null,
  };

  // Detectar categoría ambigua ANTES del LLM
  // Aplica cuando fuzzy no encontró nada O encontró match parcial
  const shouldCheckAmbiguity = !result.product_id || result.needs_confirmation;
  if (shouldCheckAmbiguity) {
    const ambiguous = findAmbiguousCategory(waMessage, products);
    if (ambiguous && ambiguous.candidates.length >= 2) {
      result.needs_clarification  = true;
      result.ambiguous_keyword    = ambiguous.keyword;
      result.ambiguous_candidates = ambiguous.candidates;
      // Limpiar producto parcial — el usuario debe especificar
      result.product_id          = null;
      result.product_name        = null;
      result.needs_confirmation  = false;
    }
  }

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

    // Producto desde NER (si fuzzy y ambiguity no encontraron nada)
    if (!result.product_id && !result.needs_clarification) {
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

    // Aumentar confianza si NLP confirma pedido
    if (nlp.intent === 'order.add' && result.product_id && nlp.score > 0.7) {
      result.confidence = 'high';
      if (fuzzy && fuzzy.score === 0) result.needs_confirmation = false;
    }

    result.source = 'nlpjs';
  } catch { /* usa resultado de reglas */ }

  return result;
}

// ── parseMultiItems (sin cambios) ──────────────────────────────
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
        product_id:         match.product.id,
        product_name:       match.product.name,
        product_price:      match.product.price,
        quantity:           qty,
        confidence:         match.score === 0 ? 'high' : match.score < 0.5 ? 'medium' : 'low',
        needs_confirmation: match.score > 0.3,
      });
    }
  }
  return items.length >= 2 ? items : null;
}

// ── getIntent ──────────────────────────────────────────────────
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
  isGreeting, isComplaint, isConfirmation, isDenial,
  hasOrderContent, findAmbiguousCategory, getIntent,
};
