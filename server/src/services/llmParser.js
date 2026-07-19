const { NlpManager } = require('@nlpjs/basic');
const { getDB } = require('../db/database');

// ── Constantes ─────────────────────────────────────────────────
const FIADO_WORDS = [
  // Tiempo futuro explícito
  'mañana', 'manana', 'pasado mañana', 'después', 'despues',
  'el lunes', 'el martes', 'el miércoles', 'el jueves', 'el viernes',
  'el sábado', 'el domingo', 'la semana', 'próxima semana', 'proxima semana',
  'la otra semana', 'el próximo', 'el proximo', 'el mes que', 'el otro mes',
  // Pago diferido directo
  'fiado', 'me fía', 'me fia', 'al fío', 'al fio', 'a crédito', 'a credito',
  'le pago', 'luego pago', 'le debo', 'le cancelo', 'le cuadro', 'cuadro después',
  'cuando pueda', 'ya le cancelo', 'ya le pago', 'le mando lo que le debo',
  // Colombiano informal — pago diferido
  'horita', 'ahoritica', 'ahorita', 'ya le mando', 'le mando la plata',
  'cuando me manden', 'cuando cobre', 'cuando me paguen', 'cuando llegue',
  'cuando salga', 'cuando tenga', 'le consigo', 'me presta', 'me colabora',
  'pa la proxima', 'pa la próxima', 'horita que', 'ahorita que',
  'cuando me den', 'cuando me caiga', 'al rato le mando',
  'apenas cobre', 'apenas me paguen', 'apenas llegue la plata',
  'le mando por nequi', 'le mando por daviplata', 'le transfiero',
  'le giro', 'ya le giro', 'apenas tenga',
];

const GREETING_WORDS = [
  'hola', 'ola', 'buenos días', 'buenos dias', 'buenas tardes', 'buenas noches',
  'buenas', 'benas', 'buen dia', 'buen día', 'hey', 'saludos',
  'que tal', 'qué tal', 'que mas', 'qué más', 'como esta', 'cómo está',
  'como están', 'cómo están', 'ome', 'parce', 'llave', 'epa', 'epale',
];

// Cierre/agradecimiento tras un pedido ya confirmado -- sin esto, "gracias"
// no matcheaba ningun producto y el bot reabría el flujo preguntando de
// nuevo "¿cuál deseas pedir?" como si fuera un intento de pedido fallido.
const CLOSING_WORDS = [
  'gracias', 'muchas gracias', 'mil gracias', 'grasias', 'muy amable',
  'listo', 'listo gracias', 'vale', 'perfecto', 'genial', 'excelente',
  'de acuerdo', 'entendido', 'todo bien', 'esta bien', 'está bien',
  'ok gracias', 'oka gracias', 'bien gracias', 'de una', 'eso es',
];

const COMPLAINT_WORDS = [
  'no me han pagado', 'no han llegado', 'no llegó', 'no llego', 'nunca llegó',
  'problema', 'reclamo', 'queja', 'me cobraron', 'me engañaron', 'mal servicio',
  'no funcionó', 'no funciono', 'devolver', 'devolución', 'devolucion',
  'incompleto', 'dañado', 'dañada', 'no sirve', 'pésimo', 'pesimo',
  'no cumplieron', 'me fallaron', 'están fallando', 'no han despachado',
  'lleva días', 'lleva dias', 'equivocado el pedido', 'mandaron mal',
];

const YES_WORDS = [
  'si', 'sí', 'yes', 'claro', 'exacto', 'correcto', 'eso', 'ese', 'esa',
  'afirmativo', 'dale', 'ok', 'oka', 'okey', 'listo', 'bueno', 'así es',
  'así', 'eso mismo', 'ese mismo', 'con ese', 'con esa', 'ajá', 'aja',
  'jum', 'eah', 'mhm', 'mmm sí', 'claro pues', 'listo pues', 'dale pues',
  'sí pues', 'por su puesto', 'por supuesto',
];

const NO_WORDS = [
  'no', 'nope', 'negativo', 'otro', 'otra', 'diferente', 'incorrecto',
  'nel', 'nanay', 'nada', 'para nada',
];

// Palabras que indican contenido de pedido (para detectar orden en saludo)
const ORDER_HINT_WORDS = [
  'traer', 'trae', 'traes', 'traerme', 'traiga', 'traigan',
  'llevar', 'lleva', 'llevas', 'llevarme', 'lleve', 'lleven',
  'mandar', 'manda', 'mandas', 'mandarme', 'mande', 'manden',
  'enviar', 'envía', 'envias', 'enviarme', 'envíe', 'envíen',
  'despachar', 'despacha', 'despachas', 'despácheme', 'despachen',
  'pedido', 'pedir', 'pido', 'pide', 'pedirme',
  'quiero', 'kiero', 'quero', 'queri', 'quiero pedir',
  'necesito', 'necesita', 'nesesito', 'nesecito', 'nececito',
  'requiero', 'solicito', 'comprar', 'compro', 'adquirir',
  'bulto', 'bultos', 'saco', 'sacos', 'costal', 'costales',
  'kilo', 'kilos', 'arroba', 'arrobas', 'libra', 'libras',
  'carga', 'tonelada', 'paquete',
  'concentrado', 'levante', 'engorde', 'ponedora', 'alimento',
  'colabora', 'regala', 'háganme', 'haganme', 'hágame', 'hagame',
];

// Palabras a ignorar en detección de ambigüedad
const AMBIGUITY_SKIP = new Set([
  'para', 'donde', 'como', 'todo', 'quiero', 'necesito', 'favor',
  'gracias', 'traer', 'trae', 'manda', 'lleva', 'envía', 'mandar',
  'puedo', 'puede', 'podría', 'podrias', 'hola', 'buenas', 'buenos',
  'dias', 'lunes', 'martes', 'jueves', 'viernes', 'esto', 'eso',
  'unos', 'unas', 'algo', 'todos', 'toda', 'kilo', 'kilos',
  'bulto', 'saco', 'costal', 'libra', 'arroba', 'carga',
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
  let bestProduct = null, bestScore = 1;
  for (const prod of products) {
    const aliases = JSON.parse(prod.aliases || '[]');
    for (const term of [prod.name, ...aliases]) {
      const normTerm  = normalize(term);
      const termWords = normTerm.split(' ').filter(w => w.length > 2);
      if (normText.includes(normTerm) || (termWords.length > 0 && termWords.every(w => normText.includes(w))))
        return { product: prod, score: 0 };
      if (!termWords.length) continue;
      let hits = 0;
      for (const tw of termWords) {
        if (msgWords.some(mw => {
          const mx = Math.max(tw.length, mw.length);
          return mx > 0 && levenshtein(tw, mw) / mx <= 0.3;
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
  const stop = '(mañana|manana|despues|después|le pago|fiado|me fía|horita|ahorita|\\.|,\\s*yo|,\\s*le|$)';
  const patterns = [
    new RegExp(`para donde (.+?)(?:${stop})`, 'i'),
    new RegExp(`a donde (.+?)(?:${stop})`, 'i'),
    new RegExp(`pa donde (.+?)(?:${stop})`, 'i'),
    new RegExp(`a lo de (.+?)(?:${stop})`, 'i'),
    new RegExp(`pa lo de (.+?)(?:${stop})`, 'i'),
    new RegExp(`donde (.+?)(?:${stop})`, 'i'),
    new RegExp(`para (.+?)(?:${stop})`, 'i'),
    new RegExp(`dirección:?\\s*(.+?)(?:${stop})`, 'i'),
    new RegExp(`entregar en (.+?)(?:${stop})`, 'i'),
    new RegExp(`llevar a (.+?)(?:${stop})`, 'i'),
    new RegExp(`al barrio (.+?)(?:${stop})`, 'i'),
    new RegExp(`a la finca (.+?)(?:${stop})`, 'i'),
    new RegExp(`en la finca (.+?)(?:${stop})`, 'i'),
    new RegExp(`vereda (.+?)(?:${stop})`, 'i'),
    new RegExp(`finca (.+?)(?:${stop})`, 'i'),
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

function isClosing(text) {
  const norm = normalize(text);
  return CLOSING_WORDS.some(w => norm === normalize(w) || norm.startsWith(normalize(w) + ' ') || norm.startsWith(normalize(w) + ','));
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

// Detecta categoría ambigua: "engorde" → hay "engorde cerdo" Y "engorde pollo"
function findAmbiguousCategory(text, products) {
  if (!products || products.length < 2) return null;
  const normText = normalize(text);
  const msgWords = normText.split(' ').filter(w => w.length >= 4 && !AMBIGUITY_SKIP.has(w));
  for (const word of msgWords) {
    const matching = [];
    for (const prod of products) {
      const aliases = JSON.parse(prod.aliases || '[]');
      const found = [prod.name, ...aliases].some(term => {
        const nt = normalize(term);
        if (nt.includes(word)) return true;
        return nt.split(' ').some(tw =>
          tw.length >= 4 && Math.abs(tw.length - word.length) <= 1 && levenshtein(tw, word) <= 1
        );
      });
      if (found) matching.push(prod);
    }
    if (matching.length >= 2 && matching.length < products.length)
      return { keyword: word, candidates: matching };
  }
  return null;
}

// ── NLP.js Manager ─────────────────────────────────────────────
let _manager = null, _productHash = '', _trainingPromise = null;

function _hashProducts(products) {
  return products.length + ':' + products.map(p => p.id + ':' + p.name).join('|');
}

async function _buildManager(products) {
  const mgr = new NlpManager({ languages: ['es'], forceNER: true, nlu: { log: false }, ner: { builtins: [] } });

  // ── SALUDOS ── (puro, sin pedido implícito)
  for (const u of [
    // Estándar
    'hola', 'hola!', 'hola!!', 'ola', 'buenos días', 'buenos dias', 'buenas tardes',
    'buenas noches', 'buenas', 'benas', 'buen día', 'buen dia', 'hey', 'hey!',
    'saludos', 'qué tal', 'que tal', 'qué más', 'que mas', 'qué más pues',
    // Con nombre / cortesía
    'hola señora', 'hola señor', 'hola señorita', 'buenas señor', 'buenas señora',
    'muy buenos días', 'muy buenas tardes', 'muy buenas noches',
    'buenas tardes señores', 'buenos días señores', 'buenas tardes señorita',
    // Colombiano
    'ome', 'ome qué más', 'parce buenas', 'llave qué más', 'epa buenas',
    'epale', 'qué más pues', 'quiubo', 'quiubo pues', 'quiubo señora',
    'hola cómo están', 'hola como estan', 'cómo están', 'como estan',
    'hola todo bien', 'hola qué más', 'hola hay alguien',
    'están disponibles', 'atienden', 'hay alguien', 'están',
    // WhatsApp informal
    'hla', 'hols', 'buenass', 'bueenas', 'holaa', 'holiii', 'buen diaa',
    // Consulta cortés sin pedido
    'hola buenas quería preguntar', 'hola buenas quería saber algo',
    'hola buenas quisiera información', 'hola están trabajando hoy',
    'buenas tardes me pueden atender', 'hola me atiende un momento',
  ]) mgr.addDocument('es', u, 'greeting');

  // ── PEDIDOS ── (Colombia + estándar + typos + contextos)
  for (const u of [
    // === VERBOS DE PEDIDO ESTÁNDAR ===
    'quiero pedir', 'quiero hacer un pedido', 'quiero comprar', 'voy a pedir',
    'necesito pedir', 'voy a llevar', 'solicito', 'requiero', 'necesito adquirir',
    // === FORMAS DIRECTAS CON ME ===
    'me puede mandar', 'me manda', 'me mandan', 'me mandas', 'mándame', 'mándeme',
    'me envía', 'me envían', 'me envías', 'envíame', 'envíeme',
    'me trae', 'me traes', 'me traen', 'tráeme', 'tráigame',
    'me lleva', 'me llevas', 'me llevan', 'llévame', 'lléveme',
    'me despacha', 'me despachan', 'despáchame', 'despácheme',
    'me entrega', 'me entregan', 'entrégueme',
    // === COLOMBIANO INFORMAL ===
    'me hace el favor', 'me hace el favor de mandarme',
    'me haría el favor', 'me haría el favor de traerme',
    'me haces el favor', 'me harías el favor',
    'me colabora', 'me colaboras', 'me colaboran',
    'me regala', 'me regalas', 'me regalan',
    'me fía', 'me fian', 'me da fiado',
    'ome me manda', 'ome me trae', 'ome me envía', 'ome mándeme',
    'parce me envía', 'parce me manda', 'parce me trae',
    'llave me manda', 'llave me trae', 'llave me lleva',
    'de una mándeme', 'de una tráigame', 'de una me manda',
    'ahoritica me envía', 'ahoritica me trae', 'ahoritica me manda',
    'ya me manda', 'ya me trae', 'ya me envía',
    'hagame el favor', 'hágame el favor', 'hágame el favorcito',
    'me haría el favor de', 'me puede hacer el favor de',
    'me puede colaborar con', 'me puede regalar',
    // === CON CONDICIONAL (CORTESÍA) ===
    'me podría mandar', 'me podría traer', 'me podría enviar',
    'podría mandarme', 'podría traerme', 'podría enviarme',
    'podrían mandarme', 'podrían traerme',
    'me puede mandar', 'me puede traer', 'me puede enviar',
    'pueden mandarme', 'pueden traerme', 'pueden enviarme',
    'tiene para venderme', 'me vende', 'me vendería',
    // === CON DIRECCIÓN (PATRONES COMUNES) ===
    'me manda a donde', 'me trae a donde', 'me lleva a donde',
    'me manda para donde', 'me trae para donde',
    'mandarme a la finca', 'traerme a la vereda',
    'llevar a donde', 'enviar para donde',
    // === CON CANTIDAD ===
    'quiero un bulto', 'quiero dos bultos', 'quiero tres bultos',
    'necesito un saco', 'necesito dos sacos', 'necesito cinco sacos',
    'quiero un costal', 'me manda un costal', 'me trae dos costales',
    'quiero un kilo', 'quiero cinco kilos', 'me manda diez kilos',
    'quiero una arroba', 'necesito dos arrobas', 'quiero media carga',
    'quiero una tonelada', 'necesito media tonelada',
    'un bulto de', 'dos bultos de', 'tres sacos de', 'un costal de',
    // === PARA NEGOCIO / FINCA / ANIMALES ===
    'quiero para mis cerdos', 'necesito para mis gallinas',
    'quiero para mi finca', 'para mi negocio necesito',
    'para el ganado necesito', 'para mis animales quiero',
    'para la granja necesito', 'para mis aves quiero',
    'para los pollos necesito', 'quiero para mis conejos',
    'para mi rancho', 'para la porqueriza', 'para el galpón',
    // === REPETIR PEDIDO ===
    'lo mismo de siempre', 'lo de siempre', 'el pedido de siempre',
    'lo mismo de la semana pasada', 'igual que antes', 'como siempre',
    'repítame el pedido', 'igual que el anterior', 'lo mismo',
    'lo mismo de la vez pasada', 'igual que la última vez',
    // === CON CONTEXTO AMISTOSO + ORDEN ===
    'hola me trae', 'hola me manda', 'hola me envía', 'hola me lleva',
    'buenas me manda', 'buenas me trae', 'buenas me envía',
    'hola quiero', 'buenas quiero', 'hola necesito', 'buenas necesito',
    'buenos días quiero pedir', 'buenas tardes necesito',
    'hola señora me manda', 'buenas señor me trae',
    // === TYPOS / ABREVIACIONES WHATSAPP ===
    'kiero pedir', 'kiero un bulto', 'kiero q me manden',
    'nesesito', 'nececito', 'necesito', 'nesecito',
    'mandeme', 'q me mandes', 'me mandas xfa',
    'mndame un saco', 'traeme un bulto', 'llvame',
    'bno necesito', 'bna me manda', 'xfavor mándeme',
    'porfavor mándeme', 'xfa mándeme', 'pliss mándeme',
    'necesito pedirles', 'les quiero pedir', 'quería pedirles',
    'quisiera pedir', 'quisiera que me mandaran',
    // === PAGO AL CONTADO (NO FIADO) ===
    'de contado', 'pago inmediato', 'le pago al momento',
    'pago ahorita', 'te pago ya', 'cancelo ya',
    'le consigno', 'le nequeo', 'le daviplata',
    'me manda que le pago ya', 'de contado me manda',
    // === URGENTE ===
    'urgente necesito', 'con urgencia necesito', 'me urge',
    'lo necesito hoy', 'para hoy necesito', 'me lo trae hoy',
    'lo necesito ya', 'para ya necesito',
  ]) mgr.addDocument('es', u, 'order.add');

  // ── CONSULTA DE PRODUCTOS / PRECIOS ──
  for (const u of [
    'qué productos tienen', 'qué venden', 'cuáles son sus productos',
    'qué tienen disponible', 'me manda la lista', 'la lista de precios',
    'lista de productos', 'qué hay disponible', 'qué tienen hoy',
    'cuánto vale', 'cuánto cuesta', 'qué precio tiene', 'a cómo está',
    'a cómo tienen', 'cuánto me sale', 'me puede dar los precios',
    'cuáles son los precios', 'catálogo de productos', 'el catálogo',
    'qué manejan', 'qué trabajan', 'me manda el menú', 'el menú',
    'qué referencias manejan', 'qué concentrados tienen',
    'tienen para gallinas', 'tienen para cerdos', 'tienen para pollos',
    'tienen para conejos', 'tienen para ganado', 'tienen para aves',
    'hay concentrado de', 'manejan sal mineralizada', 'tienen melaza',
    'información sobre sus productos', 'me puede informar sobre',
    'qué tipos de concentrado', 'cuánto vale el bulto',
    'a cuánto el kilo', 'a cuánto el saco',
    'qué tienen en existencia', 'qué está disponible',
    'hay stock', 'tienen existencias', 'hay disponibilidad',
    'me puede cotizar', 'cotización por favor', 'me hace una cotización',
    'quiero información', 'información de precios', 'lista de precios por favor',
  ]) mgr.addDocument('es', u, 'product.list');

  // ── QUEJAS / RECLAMOS ──
  for (const u of [
    'no llegó mi pedido', 'no ha llegado nada', 'nunca llegó', 'no ha llegado',
    'lleva mucho tiempo', 'llevan días y no aparece', 'ya van dos días',
    'tengo un problema', 'quiero hacer una queja', 'quiero reclamar',
    'mal servicio', 'me cobraron de más', 'me cobraron mal',
    'error en el pedido', 'pedido equivocado', 'me mandaron mal',
    'producto dañado', 'llegó incompleto', 'llegó abierto', 'llegó roto',
    'no sirve', 'está en mal estado', 'está dañado',
    'me engañaron', 'no me han atendido', 'pésimo servicio',
    'no cumplen', 'me fallaron', 'están fallando', 'no han despachado',
    'el producto llegó dañado', 'no coincide con lo pedido',
    'me mandaron lo incorrecto', 'mandaron otra cosa',
    'el bulto llegó vacío', 'llegó con menos',
    'cobro adicional no autorizado', 'precio diferente al acordado',
    'lleva tres días esperando', 'no dan razón del pedido',
    'quiero devolver', 'quiero que me devuelvan', 'quiero la devolución',
    'no estoy conforme', 'insatisfecho con el servicio',
  ]) mgr.addDocument('es', u, 'complaint');

  // ── CONFIRMACIÓN ──
  for (const u of [
    // Universal
    'sí', 'si', 'yes', 'claro', 'correcto', 'exacto', 'afirmativo',
    'de acuerdo', 'está bien', 'ok', 'okay', 'okey', 'oka', 'okis',
    'por supuesto', 'por su puesto', 'obvio', 'obvio que sí',
    // Colombiano
    'dale', 'dale pues', 'listo', 'listo pues', 'claro pues', 'sí pues',
    'eso mismo', 'eso es', 'eso mismo pues', 'ajá', 'aja', 'ajá sí',
    'jum', 'jum sí', 'eah', 'eah sí', 'mhm', 'mmm sí', 'eso',
    'con ese', 'con esa', 'ese mismo', 'esa misma', 'ese', 'esa',
    // Con sujeto
    'sí señor', 'sí señora', 'sí señorita', 'claro que sí', 'claro señor',
    'así es', 'así mismo', 'así es pues', 'sí claro', 'sí correcto',
    'confirmo', 'sí confirmo', 'acepto', 'eso quiero',
    'eso es lo que quiero', 'perfecto', 'perfecto así',
    'listo con eso', 'listo con ese', 'sí con ese',
    'sí ese es', 'sí esa es', 'ese es el que quiero',
    // WhatsApp
    'sii', 'siii', 'siiii', 'si si', 'sí sí', 'claro claro',
    'oks', 'okk', 'dale dale', 'listo listo', 'ya ya',
    // Entendió + confirma
    'entendido sí', 'recibido', 'recibido sí', 'ya entendí',
    'sí así', 'así mismo', 'correcto así',
  ]) mgr.addDocument('es', u, 'confirmation');

  // ── NEGACIÓN / CANCELACIÓN ──
  for (const u of [
    // Universal
    'no', 'nope', 'negativo', 'no gracias', 'para nada',
    // Colombiano
    'nel', 'nel pastel', 'nanay', 'nada', 'jamás',
    'no pues', 'no ese no', 'ese no', 'esa no',
    'no ese producto', 'no ese', 'no esa',
    // Con contexto
    'cancela', 'cancelar', 'cancelo', 'cancela el pedido',
    'no quiero', 'ya no quiero', 'no me interesa',
    'no por el momento', 'más tarde', 'después',
    'otro', 'otra', 'otra cosa', 'diferente', 'incorrecto',
    'equivocado', 'equivocada', 'eso no es', 'no es lo que quiero',
    'no es ese', 'no es esa', 'no me trae eso',
    'dejelo', 'déjelo', 'déjelo así', 'olvídelo', 'olvidelo',
    'no me lo traiga', 'no me lo mande', 'no gracias cancelar',
    'no sigo', 'me arrepentí', 'ya no', 'ya no quiero',
    // WhatsApp
    'nooo', 'noo', 'no no no', 'de ninguna manera',
    'jum no', 'nel pues',
  ]) mgr.addDocument('es', u, 'denial');

  // ── DESPEDIDA ──
  for (const u of [
    // Gracias + chao
    'gracias', 'muchas gracias', 'gracias señora', 'gracias señor',
    'gracias señorita', 'mil gracias', 'muchísimas gracias',
    'que dios les pague', 'que dios los bendiga',
    'muy amables', 'muy amable', 'muy amables gracias',
    'listo gracias', 'ok gracias', 'bien gracias', 'perfecto gracias',
    'listo pues gracias', 'bueno gracias pues', 'dale gracias',
    // Chao
    'hasta luego', 'hasta pronto', 'nos vemos', 'chao', 'chao chao',
    'bye', 'bye bye', 'adiós', 'adios', 'hasta mañana', 'hasta el lunes',
    'que estén bien', 'que les vaya bien', 'que pasen bien',
    'cuídense', 'cuidese', 'cuídese mucho', 'que le vaya bien',
    // Combinadas
    'listo hasta luego', 'ok chao', 'gracias chao', 'ok bye',
    'que pasen buena tarde', 'que tengan buen día',
  ]) mgr.addDocument('es', u, 'farewell');

  // ── ENTIDADES: Unidades ──
  mgr.addNamedEntityText('unit', 'bulto',    ['es'], ['bulto', 'bultos', 'saco', 'sacos', 'costal', 'costales', 'lote', 'lotes', 'talego', 'talegos']);
  mgr.addNamedEntityText('unit', 'kg',       ['es'], ['kg', 'kilo', 'kilos', 'kilogramo', 'kilogramos', 'kgs']);
  mgr.addNamedEntityText('unit', 'arroba',   ['es'], ['arroba', 'arrobas']);
  mgr.addNamedEntityText('unit', 'libra',    ['es'], ['libra', 'libras']);
  mgr.addNamedEntityText('unit', 'tonelada', ['es'], ['tonelada', 'toneladas', 'ton', 'tonelada metrica']);
  mgr.addNamedEntityText('unit', 'carga',    ['es'], ['carga', 'cargas', 'media carga', 'cuarto de carga', 'carga completa']);
  mgr.addNamedEntityText('unit', 'paquete',  ['es'], ['paquete', 'paquetes', 'bolsa', 'bolsas', 'caja', 'cajas', 'morral', 'morrales']);

  // ── ENTIDADES: Cantidad (regex) ──
  mgr.addRegexEntity('quantity', 'es', /\b(\d{1,5})\b/);

  // ── ENTIDADES: Productos desde DB ──
  for (const prod of products) {
    const aliases = JSON.parse(prod.aliases || '[]').filter(Boolean);
    mgr.addNamedEntityText('product', String(prod.id), ['es'], [prod.name, ...aliases]);
  }

  // ── Respuestas ──
  mgr.addAnswer('es', 'greeting',     '¡Hola! Bienvenido a Supermercado GO. ¿En qué le podemos ayudar?');
  mgr.addAnswer('es', 'farewell',     '¡Hasta luego! Gracias por contactarnos.');
  mgr.addAnswer('es', 'product.list', 'Con gusto le informamos sobre nuestros productos disponibles.');

  await mgr.train();
  return mgr;
}

async function _getManager() {
  const db       = getDB();
  const { rows: products } = await db.query('SELECT id, name, aliases FROM products WHERE available=1');
  const hash     = _hashProducts(products);
  if (_manager && hash === _productHash) return _manager;
  if (!_trainingPromise || hash !== _productHash) {
    _productHash     = hash;
    _trainingPromise = _buildManager(products).then(mgr => { _manager = mgr; return mgr; })
      .catch(err => { _trainingPromise = null; throw err; });
  }
  return _trainingPromise;
}

setImmediate(() => _getManager().catch(() => {}));

// ── parseOrderMessage ──────────────────────────────────────────
async function parseOrderMessage(waMessage) {
  const db       = getDB();
  const { rows: products } = await db.query('SELECT * FROM products WHERE available=1');
  const is_fiado = FIADO_WORDS.some(w => waMessage.toLowerCase().includes(w));
  const addr     = extractAddress(waMessage);
  const fuzzy    = fuzzyProductMatch(waMessage, products);

  let result = {
    product_id: fuzzy?.product?.id ?? null, product_name: fuzzy?.product?.name ?? null,
    delivery_address: addr, is_fiado, customer_name: null,
    confidence:          fuzzy ? (fuzzy.score === 0 ? 'high' : 'medium') : 'low',
    needs_confirmation:  fuzzy ? (fuzzy.score > 0 && fuzzy.score < 0.6) : false,
    needs_clarification: false, ambiguous_keyword: null, ambiguous_candidates: null,
    source: 'rules', intent: null, quantity: null, unit: null,
  };

  // Detectar categoría ambigua (ej: "engorde" → cerdo Y pollo)
  if (!result.product_id || result.needs_confirmation) {
    const ambiguous = findAmbiguousCategory(waMessage, products);
    if (ambiguous && ambiguous.candidates.length >= 2) {
      result.needs_clarification = true;
      result.ambiguous_keyword   = ambiguous.keyword;
      result.ambiguous_candidates = ambiguous.candidates;
      result.product_id = null; result.product_name = null;
      result.needs_confirmation = false;
    }
  }

  try {
    const mgr = await _getManager();
    const nlp = await mgr.process('es', waMessage);
    result.intent = nlp.intent;
    const qtyEnt  = nlp.entities?.find(e => e.entity === 'quantity');
    if (qtyEnt)  result.quantity = parseInt(qtyEnt.sourceText, 10) || null;
    const unitEnt = nlp.entities?.find(e => e.entity === 'unit');
    if (unitEnt) result.unit = unitEnt.option;
    if (!result.product_id && !result.needs_clarification) {
      const prodEnt = nlp.entities?.find(e => e.entity === 'product');
      if (prodEnt) {
        const prod = products.find(p => String(p.id) === prodEnt.option);
        if (prod) { result.product_id = prod.id; result.product_name = prod.name; result.confidence = 'high'; result.needs_confirmation = false; }
      }
    }
    if (nlp.intent === 'order.add' && result.product_id && nlp.score > 0.7) {
      result.confidence = 'high';
      if (fuzzy?.score === 0) result.needs_confirmation = false;
    }
    result.source = 'nlpjs';
  } catch { /* usa reglas */ }

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
    const qm  = seg.match(/^(\d+)\s*/);
    const qty = qm ? parseInt(qm[1]) : 1;
    const cl  = seg.replace(/^(\d+)\s*(bultos?|sacos?|kilos?|kg|unidades?|bolsas?|paquetes?)?\s*(?:de\s+|del?\s+)?/i, '').trim();
    const m   = fuzzyProductMatch(cl, products);
    if (m) items.push({ product_id: m.product.id, product_name: m.product.name, product_price: m.product.price, quantity: qty, confidence: m.score === 0 ? 'high' : m.score < 0.5 ? 'medium' : 'low', needs_confirmation: m.score > 0.3 });
  }
  return items.length >= 2 ? items : null;
}

async function getIntent(text) {
  try { const r = await (await _getManager()).process('es', text); return { intent: r.intent, score: r.score }; }
  catch { return { intent: 'unknown', score: 0 }; }
}

module.exports = {
  parseOrderMessage, parseMultiItems, fuzzyProductMatch, extractAddress,
  isGreeting, isClosing, isComplaint, isConfirmation, isDenial,
  hasOrderContent, findAmbiguousCategory, getIntent,
};
