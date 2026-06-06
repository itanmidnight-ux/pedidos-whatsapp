# Mega Upgrade — Concentrados Monserrath Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add client user role with product catalog + cart + Nequi payment, WhatsApp-style estados/stories, product images, admin settings, delete user, fix bugs, new color scheme, optimize APK script.

**Architecture:** Extend existing Node.js/SQLite backend with 5 new tables and 4 new route files. Flutter gets a separate client navigation stack (ClientHomeScreen) that branches from main.dart based on role='client'. Admin gets 2 new screens (Estados, Settings). Existing screens get targeted fixes.

**Tech Stack:** Node.js 20 + better-sqlite3 + multer | Flutter 3.44 + Provider + http | audioplayers, cached_network_image, image_picker, flutter_slidable, url_launcher

---

## FILE MAP

### Backend — new/modified
| File | Action | What |
|------|--------|------|
| `server/src/db/database.js` | Modify | +5 migrations: product_images, estados, cart_items, settings, client_orders |
| `server/src/middleware/auth.js` | Modify | +clientAuth middleware |
| `server/src/routes/users.js` | Modify | Allow role='client'; hard DELETE instead of soft |
| `server/src/routes/products.js` | Modify | +image upload/delete endpoints |
| `server/src/routes/estados.js` | Create | CRUD estados with 32h TTL |
| `server/src/routes/cart.js` | Create | Cart + checkout + Nequi ref |
| `server/src/routes/settings.js` | Create | GET/PUT app settings (nequi_phone, etc) |
| `server/src/index.js` | Modify | Register 3 new routes |

### Flutter — new screens
| File | Action | What |
|------|--------|------|
| `lib/main.dart` | Modify | Route to ClientHomeScreen if role='client' |
| `lib/models/product.dart` | Modify | +images: List<String> |
| `lib/models/estado.dart` | Create | Estado model |
| `lib/models/cart_item.dart` | Create | CartItem + ClientOrder models |
| `lib/services/api_service.dart` | Modify | +20 new API calls |
| `lib/screens/login_screen.dart` | Modify | Error → 'Error al iniciar sesión' + new colors |
| `lib/screens/dashboard_screen.dart` | Modify | Products tab admin-only; +Estados +Settings tabs |
| `lib/screens/messages_screen.dart` | Modify | Long-press bottom sheet; profile pic fallback |
| `lib/screens/chat_screen.dart` | Modify | Audio ext fix; date separators |
| `lib/screens/products_screen.dart` | Modify | Image upload in create/edit dialog |
| `lib/screens/users_screen.dart` | Modify | Hard delete button; show client role badge |
| `lib/screens/admin_estados_screen.dart` | Create | Upload photo/video; list with expiry; delete |
| `lib/screens/admin_settings_screen.dart` | Create | Nequi phone; app settings |
| `lib/screens/client_home_screen.dart` | Create | Client nav: Productos, Carrito, Estados |
| `lib/screens/client_products_screen.dart` | Create | Grid with product images + tap → detail |
| `lib/screens/client_product_detail_screen.dart` | Create | Quantity, delivery date, add to cart |
| `lib/screens/client_cart_screen.dart` | Create | Cart list + Pagar (Nequi/Contra entrega) |
| `lib/screens/client_estados_screen.dart` | Create | View states like WhatsApp (swipe) |
| `android/app/src/main/AndroidManifest.xml` | Modify | +INTERNET (already present; verify) |
| `pubspec.yaml` | Modify | +video_player, +file_picker |
| `compilar-apk.ps1` | Modify | Optimize: parallel gradle, skip if unchanged |

---

## PHASE 1 — Backend DB + Routes

### Task 1: DB migrations — 5 new tables

**Files:** Modify `server/src/db/database.js`

- [ ] Add 5 migrations after existing ones:

```javascript
// After existing migrations array, add:
'CREATE TABLE IF NOT EXISTS product_images (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, filename TEXT NOT NULL, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE)',
'CREATE TABLE IF NOT EXISTS estados (id INTEGER PRIMARY KEY AUTOINCREMENT, admin_username TEXT NOT NULL, filename TEXT NOT NULL, media_type TEXT NOT NULL DEFAULT \'image\', caption TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, expires_at DATETIME NOT NULL)',
'CREATE TABLE IF NOT EXISTS cart_items (id INTEGER PRIMARY KEY AUTOINCREMENT, client_username TEXT NOT NULL, product_id INTEGER NOT NULL, quantity INTEGER NOT NULL DEFAULT 1, delivery_date TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)',
'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)',
'CREATE TABLE IF NOT EXISTS client_orders (id INTEGER PRIMARY KEY AUTOINCREMENT, client_username TEXT NOT NULL, items_json TEXT NOT NULL, total REAL NOT NULL, payment_method TEXT NOT NULL, nequi_reference TEXT, status TEXT DEFAULT \'pending\', delivery_date TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)',
```

- [ ] Insert default settings after migrations run:
```javascript
// In initDB() after runMigrations():
db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('nequi_phone', '3001234567')`).run();
db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('nequi_name', 'Concentrados Monserrath')`).run();
```

- [ ] Commit: `git commit -m "feat(db): add product_images, estados, cart, settings, client_orders tables"`

### Task 2: Auth — allow client role + clientAuth middleware

**Files:** Modify `server/src/middleware/auth.js`, `server/src/routes/users.js`, `server/src/routes/auth.js`

- [ ] Add `clientAuth` to auth.js (allows admin, worker, client):
```javascript
function clientAuth(req, res, next) {
  jwtAuth(req, res, () => {
    if (!['admin', 'worker', 'client'].includes(req.user?.role))
      return res.status(403).json({ error: 'Acceso denegado' });
    next();
  });
}
module.exports = { apiKeyAuth, jwtAuth, adminAuth, clientAuth };
```

- [ ] In `users.js` line 26, change role validation:
```javascript
if (!['admin', 'worker', 'client'].includes(role))
  return res.status(400).json({ error: 'role debe ser admin, worker o client' });
```

- [ ] In `users.js` DELETE route, change soft delete to hard delete:
```javascript
router.delete('/:id', adminAuth, (req, res) => {
  const id = parseInt(req.params.id);
  if (req.user.id === id) return res.status(400).json({ error: 'No puedes eliminarte a ti mismo' });
  const db = getDB();
  const r  = db.prepare('DELETE FROM users WHERE id=?').run(id);
  if (!r.changes) return res.status(404).json({ error: 'Usuario no encontrado' });
  res.json({ ok: true });
});
```

- [ ] Commit: `git commit -m "feat(auth): add clientAuth, client role, hard delete user"`

### Task 3: Products route — image upload/serve/delete

**Files:** Modify `server/src/routes/products.js`

- [ ] Add at top after existing imports:
```javascript
const multer = require('multer');
const PRODUCT_IMG_DIR = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot', 'product-images');
if (!fs.existsSync(PRODUCT_IMG_DIR)) fs.mkdirSync(PRODUCT_IMG_DIR, { recursive: true });
const imgUpload = multer({ dest: PRODUCT_IMG_DIR, limits: { fileSize: 10 * 1024 * 1024 }, fileFilter: (_, f, cb) => cb(null, f.mimetype.startsWith('image/')) });
```

- [ ] Add after existing routes (before module.exports):
```javascript
// POST /api/products/:id/images — upload product image (admin)
router.post('/:id/images', adminAuth, imgUpload.single('image'), (req, res) => {
  const productId = parseInt(req.params.id);
  if (!req.file) return res.status(400).json({ error: 'Imagen requerida' });
  const ext = req.file.originalname.split('.').pop().toLowerCase() || 'jpg';
  const newFilename = `product_${productId}_${Date.now()}.${ext}`;
  const destPath = path.join(PRODUCT_IMG_DIR, newFilename);
  try { fs.renameSync(req.file.path, destPath); } catch { fs.copyFileSync(req.file.path, destPath); fs.unlinkSync(req.file.path); }
  const db = getDB();
  const result = db.prepare('INSERT INTO product_images (product_id, filename) VALUES (?, ?)').run(productId, newFilename);
  res.json({ id: result.lastInsertRowid, filename: newFilename });
});

// GET /api/products/images/:filename — serve image (any authenticated user)
router.get('/images/:filename', jwtAuth, (req, res) => {
  const filename = path.basename(req.params.filename);
  const filepath = path.join(PRODUCT_IMG_DIR, filename);
  if (!fs.existsSync(filepath)) return res.status(404).json({ error: 'Imagen no encontrada' });
  res.sendFile(filepath);
});

// DELETE /api/products/images/:id — delete image (admin)
router.delete('/images/:id', adminAuth, (req, res) => {
  const id = parseInt(req.params.id);
  const db = getDB();
  const img = db.prepare('SELECT * FROM product_images WHERE id=?').get(id);
  if (!img) return res.status(404).json({ error: 'Imagen no encontrada' });
  try { fs.unlinkSync(path.join(PRODUCT_IMG_DIR, img.filename)); } catch (_) {}
  db.prepare('DELETE FROM product_images WHERE id=?').run(id);
  res.json({ ok: true });
});
```

- [ ] In GET `/` and `/:id` routes, LEFT JOIN product_images and return images array:
```javascript
// Replace GET / query:
const products = db.prepare(`
  SELECT p.*, GROUP_CONCAT(pi.filename) as images_csv
  FROM products p
  LEFT JOIN product_images pi ON pi.product_id = p.id
  GROUP BY p.id ORDER BY p.favorite DESC, p.name ASC
`).all();
const result = products.map(p => ({
  ...p,
  images: p.images_csv ? p.images_csv.split(',') : []
}));
res.json(result);
```

- [ ] Commit: `git commit -m "feat(products): add image upload/serve/delete endpoints"`

### Task 4: Estados route (WhatsApp stories)

**Files:** Create `server/src/routes/estados.js`

- [ ] Create full file:
```javascript
'use strict';
const express = require('express');
const router  = express.Router();
const path    = require('path');
const fs      = require('fs');
const multer  = require('multer');
const { adminAuth, jwtAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

const ESTADOS_DIR = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot', 'estados');
if (!fs.existsSync(ESTADOS_DIR)) fs.mkdirSync(ESTADOS_DIR, { recursive: true });

const upload = multer({
  dest: ESTADOS_DIR,
  limits: { fileSize: 50 * 1024 * 1024 },
  fileFilter: (_, f, cb) => cb(null, f.mimetype.startsWith('image/') || f.mimetype.startsWith('video/')),
});

// GET /api/estados — list active (not expired)
router.get('/', jwtAuth, (req, res) => {
  const estados = getDB().prepare(
    `SELECT * FROM estados WHERE expires_at > datetime('now') ORDER BY created_at DESC`
  ).all();
  res.json(estados);
});

// POST /api/estados — create estado (admin only)
router.post('/', adminAuth, upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Archivo requerido' });
  const mediaType = req.file.mimetype.startsWith('video/') ? 'video' : 'image';
  const ext = req.file.originalname.split('.').pop().toLowerCase() || (mediaType === 'video' ? 'mp4' : 'jpg');
  const newFilename = `estado_${Date.now()}.${ext}`;
  const destPath = path.join(ESTADOS_DIR, newFilename);
  try { fs.renameSync(req.file.path, destPath); } catch { fs.copyFileSync(req.file.path, destPath); fs.unlinkSync(req.file.path); }
  const expiresAt = new Date(Date.now() + 32 * 60 * 60 * 1000).toISOString().replace('T', ' ').slice(0, 19);
  const db = getDB();
  const result = db.prepare(
    `INSERT INTO estados (admin_username, filename, media_type, caption, expires_at) VALUES (?, ?, ?, ?, ?)`
  ).run(req.user.username, newFilename, mediaType, req.body.caption || null, expiresAt);
  res.json({ id: result.lastInsertRowid, filename: newFilename, expires_at: expiresAt });
});

// GET /api/estados/media/:filename — serve media
router.get('/media/:filename', jwtAuth, (req, res) => {
  const filename = path.basename(req.params.filename);
  const filepath = path.join(ESTADOS_DIR, filename);
  if (!fs.existsSync(filepath)) return res.status(404).json({ error: 'Media no encontrada' });
  res.sendFile(filepath);
});

// DELETE /api/estados/:id — delete estado (admin only)
router.delete('/:id', adminAuth, (req, res) => {
  const id = parseInt(req.params.id);
  const db = getDB();
  const estado = db.prepare('SELECT * FROM estados WHERE id=?').get(id);
  if (!estado) return res.status(404).json({ error: 'Estado no encontrado' });
  try { fs.unlinkSync(path.join(ESTADOS_DIR, estado.filename)); } catch (_) {}
  db.prepare('DELETE FROM estados WHERE id=?').run(id);
  res.json({ ok: true });
});

module.exports = router;
```

- [ ] Commit: `git commit -m "feat(estados): WhatsApp-style stories with 32h TTL"`

### Task 5: Cart + Checkout route

**Files:** Create `server/src/routes/cart.js`

- [ ] Create full file:
```javascript
'use strict';
const express = require('express');
const router  = express.Router();
const { clientAuth, adminAuth, jwtAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

// GET /api/cart — get cart items for logged-in client
router.get('/', clientAuth, (req, res) => {
  const items = getDB().prepare(`
    SELECT ci.*, p.name as product_name, p.price as product_price,
           GROUP_CONCAT(pi.filename) as images_csv
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    LEFT JOIN product_images pi ON pi.product_id = ci.product_id
    WHERE ci.client_username = ?
    GROUP BY ci.id ORDER BY ci.created_at ASC
  `).all(req.user.username);
  const result = items.map(i => ({ ...i, images: i.images_csv ? i.images_csv.split(',') : [] }));
  res.json(result);
});

// POST /api/cart — add or update item
router.post('/', clientAuth, (req, res) => {
  const { product_id, quantity = 1, delivery_date } = req.body;
  if (!product_id || quantity < 1) return res.status(400).json({ error: 'product_id y quantity requeridos' });
  const db = getDB();
  const existing = db.prepare('SELECT * FROM cart_items WHERE client_username=? AND product_id=?').get(req.user.username, product_id);
  if (existing) {
    db.prepare('UPDATE cart_items SET quantity=?, delivery_date=? WHERE id=?').run(quantity, delivery_date || null, existing.id);
  } else {
    db.prepare('INSERT INTO cart_items (client_username, product_id, quantity, delivery_date) VALUES (?,?,?,?)').run(req.user.username, product_id, quantity, delivery_date || null);
  }
  res.json({ ok: true });
});

// DELETE /api/cart/:id — remove item from cart
router.delete('/:id', clientAuth, (req, res) => {
  const id = parseInt(req.params.id);
  const db = getDB();
  const item = db.prepare('SELECT * FROM cart_items WHERE id=? AND client_username=?').get(id, req.user.username);
  if (!item) return res.status(404).json({ error: 'Item no encontrado' });
  db.prepare('DELETE FROM cart_items WHERE id=?').run(id);
  res.json({ ok: true });
});

// DELETE /api/cart — clear entire cart
router.delete('/', clientAuth, (req, res) => {
  getDB().prepare('DELETE FROM cart_items WHERE client_username=?').run(req.user.username);
  res.json({ ok: true });
});

// POST /api/cart/checkout — place order
router.post('/checkout', clientAuth, (req, res) => {
  const { payment_method, nequi_reference, delivery_date } = req.body;
  if (!['nequi', 'contraentrega'].includes(payment_method))
    return res.status(400).json({ error: 'payment_method debe ser nequi o contraentrega' });
  if (payment_method === 'nequi' && !nequi_reference?.trim())
    return res.status(400).json({ error: 'nequi_reference requerido para pago Nequi' });

  const db = getDB();
  const items = db.prepare(`
    SELECT ci.*, p.name, p.price
    FROM cart_items ci JOIN products p ON p.id = ci.product_id
    WHERE ci.client_username = ?
  `).all(req.user.username);

  if (!items.length) return res.status(400).json({ error: 'Carrito vacío' });

  const total = items.reduce((sum, i) => sum + i.price * i.quantity, 0);
  const itemsJson = JSON.stringify(items.map(i => ({ product_id: i.product_id, name: i.name, price: i.price, quantity: i.quantity })));

  const result = db.prepare(
    `INSERT INTO client_orders (client_username, items_json, total, payment_method, nequi_reference, delivery_date) VALUES (?,?,?,?,?,?)`
  ).run(req.user.username, itemsJson, total, payment_method, nequi_reference?.trim() || null, delivery_date || null);

  db.prepare('DELETE FROM cart_items WHERE client_username=?').run(req.user.username);
  res.json({ ok: true, order_id: result.lastInsertRowid, total });
});

// GET /api/cart/orders — admin: list all client orders
router.get('/orders', adminAuth, (req, res) => {
  const orders = getDB().prepare(`SELECT * FROM client_orders ORDER BY created_at DESC LIMIT 100`).all();
  res.json(orders.map(o => ({ ...o, items: JSON.parse(o.items_json) })));
});

module.exports = router;
```

- [ ] Commit: `git commit -m "feat(cart): client cart + Nequi/contra-entrega checkout"`

### Task 6: Settings route

**Files:** Create `server/src/routes/settings.js`

- [ ] Create full file:
```javascript
'use strict';
const express = require('express');
const router  = express.Router();
const { adminAuth, jwtAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

// GET /api/settings — public settings for clients
router.get('/', jwtAuth, (req, res) => {
  const rows = getDB().prepare('SELECT key, value FROM settings').all();
  const settings = Object.fromEntries(rows.map(r => [r.key, r.value]));
  res.json(settings);
});

// PUT /api/settings — update settings (admin only)
router.put('/', adminAuth, (req, res) => {
  const db = getDB();
  const allowed = ['nequi_phone', 'nequi_name'];
  const stmt = db.prepare(`INSERT INTO settings (key, value, updated_at) VALUES (?, ?, datetime('now'))
    ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at`);
  for (const key of allowed) {
    if (req.body[key] !== undefined) stmt.run(key, String(req.body[key]).trim());
  }
  const rows = db.prepare('SELECT key, value FROM settings').all();
  res.json(Object.fromEntries(rows.map(r => [r.key, r.value])));
});

module.exports = router;
```

- [ ] Commit: `git commit -m "feat(settings): Nequi phone + app settings endpoint"`

### Task 7: Register new routes in index.js

**Files:** Modify `server/src/index.js`

- [ ] Add 3 new route registrations after existing ones:
```javascript
const estadosRoutes   = require('./routes/estados');
const cartRoutes      = require('./routes/cart');
const settingsRoutes  = require('./routes/settings');
// ...
app.use('/api/estados',  estadosRoutes);
app.use('/api/cart',     cartRoutes);
app.use('/api/settings', settingsRoutes);
```

- [ ] Commit: `git commit -m "feat(server): register estados, cart, settings routes"`

---

## PHASE 2 — Flutter Foundation Fixes

### Task 8: Models update

**Files:** Modify `lib/models/product.dart`, create `lib/models/estado.dart`, create `lib/models/cart_item.dart`

- [ ] Update `product.dart` — add images field:
```dart
class Product {
  final int? id;
  final String name;
  final List<String> aliases;
  final double price;
  final bool available;
  final bool favorite;
  final bool noFiado;
  final List<String> images;  // NEW

  Product({
    this.id, required this.name, required this.aliases,
    required this.price, this.available = true,
    this.favorite = false, this.noFiado = false,
    this.images = const [],  // NEW
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: j['id'], name: j['name'],
    aliases: (j['aliases'] is List) ? List<String>.from(j['aliases']) : [],
    price: (j['price'] as num).toDouble(),
    available: j['available'] == 1 || j['available'] == true,
    favorite: j['favorite'] == 1 || j['favorite'] == true,
    noFiado: j['no_fiado'] == 1 || j['no_fiado'] == true,
    images: (j['images'] is List) ? List<String>.from(j['images']) : [],  // NEW
  );

  Map<String, dynamic> toJson() => {
    'name': name, 'price': price, 'aliases': aliases,
    'available': available ? 1 : 0,
    'favorite': favorite ? 1 : 0,
    'no_fiado': noFiado ? 1 : 0,
  };
}
```

- [ ] Create `lib/models/estado.dart`:
```dart
class Estado {
  final int     id;
  final String  adminUsername;
  final String  filename;
  final String  mediaType; // 'image' | 'video'
  final String? caption;
  final String  createdAt;
  final String  expiresAt;

  Estado({
    required this.id, required this.adminUsername, required this.filename,
    required this.mediaType, this.caption, required this.createdAt, required this.expiresAt,
  });

  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';

  factory Estado.fromJson(Map<String, dynamic> j) => Estado(
    id:            j['id'],
    adminUsername: j['admin_username'] ?? '',
    filename:      j['filename'] ?? '',
    mediaType:     j['media_type'] ?? 'image',
    caption:       j['caption'],
    createdAt:     j['created_at'] ?? '',
    expiresAt:     j['expires_at'] ?? '',
  );
}
```

- [ ] Create `lib/models/cart_item.dart`:
```dart
class CartItem {
  final int     id;
  final int     productId;
  final String  productName;
  final double  productPrice;
  final int     quantity;
  final String? deliveryDate;
  final List<String> images;

  CartItem({
    required this.id, required this.productId, required this.productName,
    required this.productPrice, required this.quantity, this.deliveryDate,
    this.images = const [],
  });

  double get subtotal => productPrice * quantity;

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
    id:           j['id'],
    productId:    j['product_id'],
    productName:  j['product_name'] ?? '',
    productPrice: (j['product_price'] as num).toDouble(),
    quantity:     j['quantity'] ?? 1,
    deliveryDate: j['delivery_date'],
    images:       (j['images'] is List) ? List<String>.from(j['images']) : [],
  );
}
```

- [ ] Commit: `git commit -m "feat(models): add images to Product; add Estado, CartItem models"`

### Task 9: ApiService — add all new calls

**Files:** Modify `lib/services/api_service.dart`

- [ ] Add to ApiService class:
```dart
// ── Product images ───────────────────────────────────────
static Future<Map<String, dynamic>> uploadProductImage(int productId, String filePath) async {
  final uri     = Uri.parse('$_serverUrl/api/products/$productId/images');
  final request = http.MultipartRequest('POST', uri);
  request.headers.addAll(_headersNoContent);
  request.files.add(await http.MultipartFile.fromPath('image', filePath));
  final streamed = await request.send().timeout(const Duration(seconds: 30));
  final body = jsonDecode(await streamed.stream.bytesToString());
  if (streamed.statusCode != 200) throw Exception(body['error'] ?? 'Error subiendo imagen');
  return body as Map<String, dynamic>;
}

static Future<void> deleteProductImage(int imageId) async {
  await http.delete(Uri.parse('$_serverUrl/api/products/images/$imageId'), headers: _headers).timeout(const Duration(seconds: 10));
}

static Future<Uint8List?> downloadProductImage(String filename) async {
  try {
    final res = await http.get(
      Uri.parse('$_serverUrl/api/products/images/${Uri.encodeComponent(filename)}'),
      headers: _headers,
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode == 200) return res.bodyBytes;
    return null;
  } catch (_) { return null; }
}

// ── Estados ──────────────────────────────────────────────
static Future<List<Estado>> getEstados() async {
  final res = await http.get(Uri.parse('$_serverUrl/api/estados'), headers: _headers).timeout(const Duration(seconds: 10));
  if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Estado.fromJson(j)).toList();
  throw Exception('Error estados');
}

static Future<Estado> uploadEstado(String filePath, {String? caption}) async {
  final uri     = Uri.parse('$_serverUrl/api/estados');
  final request = http.MultipartRequest('POST', uri);
  request.headers.addAll(_headersNoContent);
  if (caption != null) request.fields['caption'] = caption;
  request.files.add(await http.MultipartFile.fromPath('file', filePath));
  final streamed = await request.send().timeout(const Duration(seconds: 60));
  final body = jsonDecode(await streamed.stream.bytesToString());
  if (streamed.statusCode != 200) throw Exception(body['error'] ?? 'Error subiendo estado');
  return Estado.fromJson(body);
}

static Future<void> deleteEstado(int id) async {
  await http.delete(Uri.parse('$_serverUrl/api/estados/$id'), headers: _headers).timeout(const Duration(seconds: 10));
}

static Future<Uint8List?> downloadEstadoMedia(String filename) async {
  try {
    final res = await http.get(
      Uri.parse('$_serverUrl/api/estados/media/${Uri.encodeComponent(filename)}'),
      headers: _headers,
    ).timeout(const Duration(seconds: 60));
    if (res.statusCode == 200) return res.bodyBytes;
    return null;
  } catch (_) { return null; }
}

// ── Cart ─────────────────────────────────────────────────
static Future<List<CartItem>> getCart() async {
  final res = await http.get(Uri.parse('$_serverUrl/api/cart'), headers: _headers).timeout(const Duration(seconds: 10));
  if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => CartItem.fromJson(j)).toList();
  throw Exception('Error carrito');
}

static Future<void> addToCart(int productId, int quantity, {String? deliveryDate}) async {
  await http.post(Uri.parse('$_serverUrl/api/cart'), headers: _headers,
    body: jsonEncode({'product_id': productId, 'quantity': quantity, 'delivery_date': deliveryDate})).timeout(const Duration(seconds: 10));
}

static Future<void> removeFromCart(int cartItemId) async {
  await http.delete(Uri.parse('$_serverUrl/api/cart/$cartItemId'), headers: _headers).timeout(const Duration(seconds: 10));
}

static Future<Map<String, dynamic>> checkout({
  required String paymentMethod,
  String? nequiReference,
  String? deliveryDate,
}) async {
  final res = await http.post(Uri.parse('$_serverUrl/api/cart/checkout'), headers: _headers,
    body: jsonEncode({
      'payment_method': paymentMethod,
      if (nequiReference != null) 'nequi_reference': nequiReference,
      if (deliveryDate != null) 'delivery_date': deliveryDate,
    })).timeout(const Duration(seconds: 15));
  final body = jsonDecode(res.body);
  if (res.statusCode != 200) throw Exception(body['error'] ?? 'Error al realizar pedido');
  return body as Map<String, dynamic>;
}

// ── Settings ─────────────────────────────────────────────
static Future<Map<String, String>> getSettings() async {
  final res = await http.get(Uri.parse('$_serverUrl/api/settings'), headers: _headers).timeout(const Duration(seconds: 10));
  if (res.statusCode == 200) return Map<String, String>.from(jsonDecode(res.body).map((k, v) => MapEntry(k as String, v as String)));
  throw Exception('Error settings');
}

static Future<Map<String, String>> updateSettings(Map<String, String> data) async {
  final res = await http.put(Uri.parse('$_serverUrl/api/settings'), headers: _headers,
    body: jsonEncode(data)).timeout(const Duration(seconds: 10));
  if (res.statusCode == 200) return Map<String, String>.from(jsonDecode(res.body).map((k, v) => MapEntry(k as String, v as String)));
  throw Exception('Error actualizando settings');
}

// ── Delete user ───────────────────────────────────────────
static Future<void> deleteUser(int id) async {
  final res = await http.delete(Uri.parse('$_serverUrl/api/users/$id'), headers: _headers).timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error borrando usuario');
}
```

- [ ] Also add imports at top: `import 'models/estado.dart';` `import 'models/cart_item.dart';` (adjust relative paths)

- [ ] Commit: `git commit -m "feat(api): add product images, estados, cart, settings, deleteUser"`

### Task 10: pubspec.yaml — add video_player + file_picker

**Files:** Modify `android-app/pubspec.yaml`

- [ ] Add to dependencies section:
```yaml
  video_player: ^2.8.3
  file_picker: ^8.0.0+1
```

- [ ] Run: `flutter pub get` from android-app directory

- [ ] Commit: `git commit -m "chore(deps): add video_player, file_picker"`

---

## PHASE 3 — Flutter Bug Fixes (Original Design)

### Task 11: dashboard_screen.dart — Products tab admin-only

**Files:** Modify `lib/screens/dashboard_screen.dart`

- [ ] Change line 31: `_titlesWorker = ['Pedidos Activos', 'Mensajes'];`
- [ ] In IndexedStack, wrap ProductsScreen: `if (provider.isAdmin) const ProductsScreen(),`
- [ ] In NavigationBar destinations, wrap Products: `if (provider.isAdmin) const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded, color: Color(0xFF2D5016)), label: 'Productos'),`
- [ ] In dashboard titles: add `_titlesAdmin = ['Pedidos Activos', 'Productos', 'Mensajes', 'Usuarios'];` (unchanged)
- [ ] Commit: `git commit -m "fix(dashboard): hide Products tab from non-admin users"`

### Task 12: messages_screen.dart — long-press + profile pic fallback

**Files:** Modify `lib/screens/messages_screen.dart`

- [ ] Replace `_buildAvatar` to use `CachedNetworkImage` with error handling:
```dart
Widget _buildAvatar(Conversation c) {
  final flagColor = _flagColor(c.flagReason);
  final initial = c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?';
  final bgColor  = c.hasFlaggedMessages ? flagColor : const Color(0xFF2D5016);

  Widget avatar = Container(
    width: 48, height: 48,
    decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
    child: ClipOval(
      child: c.profilePicUrl != null && c.profilePicUrl!.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: c.profilePicUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) => Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
            errorWidget: (_, __, ___) => Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
          )
        : Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
    ),
  );

  if (!c.hasFlaggedMessages) return avatar;
  return Stack(children: [
    avatar,
    Positioned(right: 0, top: 0,
      child: Container(
        width: 14, height: 14,
        decoration: BoxDecoration(color: flagColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
        child: const Icon(Icons.priority_high, size: 9, color: Colors.white),
      )),
  ]);
}
```

- [ ] Add `_showOptions` method before `_buildConvTile`:
```dart
void _showOptions(Conversation c, {bool isArchived = false}) {
  final initial = c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?';
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
      ListTile(
        leading: CircleAvatar(backgroundColor: const Color(0xFF2D5016).withOpacity(0.1),
          child: Text(initial, style: const TextStyle(color: Color(0xFF2D5016), fontWeight: FontWeight.bold))),
        title: Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('+57${c.phone}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ),
      const Divider(height: 1),
      ListTile(
        leading: Icon(isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, color: Colors.amber.shade700),
        title: Text(isArchived ? 'Restaurar conversación' : 'Archivar conversación'),
        onTap: () { Navigator.pop(context); _archive(c, archive: !isArchived); },
      ),
      ListTile(
        leading: const Icon(Icons.delete_outline, color: Colors.red),
        title: const Text('Borrar conversación', style: TextStyle(color: Colors.red)),
        onTap: () { Navigator.pop(context); _delete(c); },
      ),
      const SizedBox(height: 8),
    ])),
  );
}
```

- [ ] Add `onLongPress: () => _showOptions(c, isArchived: isArchived),` to the ListTile in `_buildConvTile`

- [ ] Commit: `git commit -m "fix(messages): long-press bottom sheet + profile pic fallback"`

### Task 13: chat_screen.dart — audio ext fix + date separators

**Files:** Modify `lib/screens/chat_screen.dart`

- [ ] Fix audio extension in `_toggleAudio` — replace hardcoded `.m4a`:
```dart
// Find: final file = File('${dir.path}/audio_$msgId.m4a');
// Replace with:
final ext = mediaUrl.split('.').last.toLowerCase();
final file = File('${dir.path}/audio_$msgId.$ext');
```

- [ ] Add date separator widget before `_buildBubble`:
```dart
Widget _buildDateSeparator(String dateStr) {
  return Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 4)],
      ),
      child: Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
    ),
  );
}

String _dateLabel(String iso) {
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(msgDay).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  if (diff < 7) return DateFormat('EEEE', 'es').format(dt);
  return DateFormat('d MMM yyyy', 'es').format(dt);
}
```

- [ ] Replace ListView.builder to show date separators:
```dart
// Replace:
itemBuilder: (ctx, i) => _buildBubble(_messages[i]),
// With:
itemBuilder: (ctx, i) {
  final msg = _messages[i];
  final showDate = i == 0 || _dateLabel(msg.createdAt) != _dateLabel(_messages[i-1].createdAt);
  return Column(mainAxisSize: MainAxisSize.min, children: [
    if (showDate) _buildDateSeparator(_dateLabel(msg.createdAt)),
    _buildBubble(msg),
  ]);
},
```

- [ ] Commit: `git commit -m "fix(chat): audio extension + date separators between messages"`

### Task 14: users_screen.dart — delete user + client badge

**Files:** Modify `lib/screens/users_screen.dart`

- [ ] Read the full file first, then add delete button to each user card. In the actions or trailing of each user card, add:
```dart
IconButton(
  icon: const Icon(Icons.delete_outline, color: Colors.red),
  tooltip: 'Eliminar usuario',
  onPressed: () async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar a ${user['display_name']}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ApiService.deleteUser(user['id']);
        // reload users
        setState(() {});
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  },
),
```

- [ ] Add client role badge — show different color for role=='client':
```dart
// In role chip/badge, add case for 'client':
Color _roleColor(String role) {
  if (role == 'admin') return Colors.red.shade100;
  if (role == 'client') return Colors.blue.shade100;
  return Colors.green.shade100;
}
```

- [ ] Commit: `git commit -m "feat(users): hard delete + client role badge"`

### Task 15: login_screen.dart — error message + color refresh

**Files:** Modify `lib/screens/login_screen.dart`

- [ ] In `_login()` catch block, ensure error says 'Error al iniciar sesión':
```dart
} catch (e) {
  String msg = e.toString().replaceAll('Exception: ', '');
  if (msg.contains('401') || msg.contains('Credenciales') || msg.contains('invalid') || msg.contains('credentials')) {
    msg = 'Error al iniciar sesión: usuario o PIN incorrecto';
  } else if (msg.isEmpty) {
    msg = 'Error al iniciar sesión';
  }
  setState(() { _error = msg; });
}
```

- [ ] Update background to richer gradient and branding:
```dart
// Replace backgroundColor: const Color(0xFF1A3009), with:
body: Container(
  decoration: const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1A3009), Color(0xFF2D5016), Color(0xFF1A3009)],
    ),
  ),
  child: SafeArea(child: Center(...))
```

- [ ] Commit: `git commit -m "fix(login): better error messages + gradient background"`

---

## PHASE 4 — New Color Scheme

### Task 16: Global color theme update

**Files:** Modify `lib/main.dart`

- [ ] Define new Material 3 color scheme constants at top:
```dart
// Brand palette
const kPrimary   = Color(0xFF1E6B2E); // forest green
const kSecondary = Color(0xFF4CAF50); // leaf green  
const kAccent    = Color(0xFFFF8F00); // amber harvest
const kSurface   = Color(0xFFFFFFFF);
const kBg        = Color(0xFFF5F5F0); // warm off-white
const kDark      = Color(0xFF1A2E12); // very dark green
```

- [ ] Update MaterialApp theme:
```dart
theme: ThemeData(
  useMaterial3: true,
  colorSchemeSeed: const Color(0xFF1E6B2E),
  brightness: Brightness.light,
  scaffoldBackgroundColor: kBg,
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF1E6B2E),
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: false,
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: const Color(0xFFD4ECB8),
    labelTextStyle: WidgetStateProperty.all(
      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E6B2E)),
  ),
  cardTheme: CardThemeData(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    color: Colors.white,
  ),
),
```

- [ ] In `main.dart` `build` → route to `ClientHomeScreen` when role == 'client':
```dart
// In AppProvider/Consumer that decides which screen to show:
if (provider.isLoggedIn) {
  return provider.currentRole == 'client'
    ? const ClientHomeScreen()
    : const DashboardScreen();
}
return const LoginScreen();
```

- [ ] Commit: `git commit -m "feat(theme): Material 3 color scheme, route client role"`

---

## PHASE 5 — Admin Screens

### Task 17: admin_estados_screen.dart

**Files:** Create `lib/screens/admin_estados_screen.dart`

- [ ] Create full screen (~250 lines). Key features:
  - AppBar: "Mis Estados" + upload FAB (image_picker)
  - List of estados with thumbnail, caption, expiry timer, delete button
  - Upload: pick image/video → `ApiService.uploadEstado()` → reload
  - Delete: confirm dialog → `ApiService.deleteEstado(id)` → reload
  - Empty state: "No has publicado estados aún"
  - Each card shows time remaining (e.g., "Expira en 28h")

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/estado.dart';
import '../services/api_service.dart';

class AdminEstadosScreen extends StatefulWidget {
  const AdminEstadosScreen({super.key});
  @override State<AdminEstadosScreen> createState() => _AdminEstadosScreenState();
}

class _AdminEstadosScreenState extends State<AdminEstadosScreen> {
  List<Estado> _estados = [];
  bool _loading = true;
  final Map<String, Uint8List?> _cache = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final e = await ApiService.getEstados();
      if (mounted) setState(() => _estados = e);
      for (final est in e) {
        if (!_cache.containsKey(est.filename)) {
          ApiService.downloadEstadoMedia(est.filename).then((bytes) {
            if (mounted) setState(() => _cache[est.filename] = bytes);
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _upload() async {
    final captionCtrl = TextEditingController();
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !mounted) return;
    if (!mounted) return;
    final caption = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Agregar título (opcional)'),
        content: TextField(controller: captionCtrl, decoration: const InputDecoration(hintText: 'Ej: ¡Oferta del día!')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Omitir')),
          FilledButton(onPressed: () => Navigator.pop(context, captionCtrl.text.trim()), child: const Text('Publicar')),
        ],
      ),
    );
    try {
      await ApiService.uploadEstado(file.path, caption: caption?.isEmpty == true ? null : caption);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete(Estado e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar estado'),
        content: const Text('¿Eliminar este estado?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try { await ApiService.deleteEstado(e.id); _load(); } catch (_) {}
  }

  String _timeLeft(String expiresAt) {
    final exp = DateTime.tryParse(expiresAt);
    if (exp == null) return '';
    final diff = exp.toLocal().difference(DateTime.now());
    if (diff.isNegative) return 'Expirado';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return h > 0 ? 'Expira en ${h}h ${m}m' : 'Expira en ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _upload,
        backgroundColor: const Color(0xFF1E6B2E),
        icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
        label: const Text('Nuevo estado', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E6B2E)))
        : _estados.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('📸', style: TextStyle(fontSize: 56)),
              SizedBox(height: 12),
              Text('No has publicado estados aún', style: TextStyle(color: Colors.grey, fontSize: 15)),
              SizedBox(height: 4),
              Text('Toca el botón para publicar', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: _estados.length,
              itemBuilder: (ctx, i) {
                final e = _estados[i];
                final bytes = _cache[e.filename];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                      child: bytes != null
                        ? Image.memory(bytes, width: 80, height: 80, fit: BoxFit.cover)
                        : Container(width: 80, height: 80, color: Colors.grey.shade200,
                            child: const Icon(Icons.image_outlined, color: Colors.grey)),
                    ),
                    Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (e.caption != null)
                          Text(e.caption!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(DateFormat('d MMM, HH:mm', 'es').format(DateTime.tryParse(e.createdAt)?.toLocal() ?? DateTime.now()),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(height: 2),
                        Text(_timeLeft(e.expiresAt),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF1E6B2E), fontWeight: FontWeight.w600)),
                      ]),
                    )),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _delete(e),
                    ),
                    const SizedBox(width: 4),
                  ]),
                );
              },
            ),
    );
  }
}
```

- [ ] Commit: `git commit -m "feat(admin): Estados screen with upload/delete/expiry"`

### Task 18: admin_settings_screen.dart

**Files:** Create `lib/screens/admin_settings_screen.dart`

- [ ] Create full screen:
```dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _nequiPhoneCtrl = TextEditingController();
  final _nequiNameCtrl  = TextEditingController();
  bool _loading  = true;
  bool _saving   = false;
  String? _error;
  String? _success;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await ApiService.getSettings();
      _nequiPhoneCtrl.text = settings['nequi_phone'] ?? '';
      _nequiNameCtrl.text  = settings['nequi_name'] ?? '';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final phone = _nequiPhoneCtrl.text.trim();
    final name  = _nequiNameCtrl.text.trim();
    if (phone.isEmpty) { setState(() { _error = 'Número Nequi requerido'; _success = null; }); return; }
    setState(() { _saving = true; _error = null; _success = null; });
    try {
      await ApiService.updateSettings({'nequi_phone': phone, 'nequi_name': name});
      if (mounted) setState(() { _success = 'Configuración guardada'; _saving = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF1E6B2E)));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Configuración de pagos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Datos de Nequi para recibir pagos de clientes', style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Row(children: [
                CircleAvatar(backgroundColor: Color(0xFF5C068C), radius: 16,
                  child: Text('N', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                SizedBox(width: 10),
                Text('Nequi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _nequiPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Número de celular Nequi',
                  hintText: '3001234567',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nequiNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Nombre del titular',
                  hintText: 'Concentrados Monserrath',
                  prefixIcon: const Icon(Icons.business_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text(_error!, style: const TextStyle(color: Colors.red))),
        ],
        if (_success != null) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text(_success!, style: const TextStyle(color: Colors.green))),
        ],
        const SizedBox(height: 20),
        SizedBox(width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Guardando...' : 'Guardar configuración'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E6B2E), minimumSize: const Size(double.infinity, 50)),
          ),
        ),
        const SizedBox(height: 32),
        const Text('Información', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _infoRow(Icons.info_outline, 'Los clientes verán este número para realizar pagos por Nequi'),
        _infoRow(Icons.security_outlined, 'El cliente ingresa la referencia de la transacción como confirmación'),
        _infoRow(Icons.verified_outlined, 'Verifica las referencias en tu app Nequi antes de despachar pedidos'),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: Colors.grey),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey))),
    ]),
  );
}
```

- [ ] Commit: `git commit -m "feat(admin): Settings screen with Nequi config"`

### Task 19: Update dashboard_screen.dart — add Estados + Settings tabs for admin

**Files:** Modify `lib/screens/dashboard_screen.dart`

- [ ] Add imports: `import 'admin_estados_screen.dart';` `import 'admin_settings_screen.dart';`
- [ ] Update title arrays:
```dart
static const _titlesWorker = ['Pedidos Activos', 'Mensajes'];
static const _titlesAdmin  = ['Pedidos Activos', 'Productos', 'Mensajes', 'Estados', 'Usuarios', 'Config'];
```
- [ ] Add to IndexedStack (admin only): `if (provider.isAdmin) const AdminEstadosScreen(),` `if (provider.isAdmin) const UsersScreen(),` `if (provider.isAdmin) const AdminSettingsScreen(),`
- [ ] Add to NavigationBar (admin only):
```dart
if (provider.isAdmin) const NavigationDestination(
  icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories, color: Color(0xFF1E6B2E)),
  label: 'Estados'),
if (provider.isAdmin) NavigationDestination(..., label: 'Usuarios'),
if (provider.isAdmin) const NavigationDestination(
  icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings, color: Color(0xFF1E6B2E)),
  label: 'Config'),
```
- [ ] Commit: `git commit -m "feat(dashboard): add Estados + Settings tabs for admins"`

---

## PHASE 6 — Client App

### Task 20: client_estados_screen.dart — view states like WhatsApp

**Files:** Create `lib/screens/client_estados_screen.dart`

- [ ] Create screen that fetches and displays states with PageView (full-screen swipe):
```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/estado.dart';
import '../services/api_service.dart';

class ClientEstadosScreen extends StatefulWidget {
  const ClientEstadosScreen({super.key});
  @override State<ClientEstadosScreen> createState() => _ClientEstadosScreenState();
}

class _ClientEstadosScreenState extends State<ClientEstadosScreen> {
  List<Estado>  _estados = [];
  bool _loading = true;
  final Map<String, Uint8List?> _cache = {};

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final e = await ApiService.getEstados();
      if (mounted) setState(() => _estados = e);
      for (final est in e) {
        ApiService.downloadEstadoMedia(est.filename).then((bytes) {
          if (mounted) setState(() => _cache[est.filename] = bytes);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _openViewer(int index) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _EstadoViewer(estados: _estados, initialIndex: index, cache: _cache),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF1E6B2E)));
    if (_estados.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('📸', style: TextStyle(fontSize: 56)),
      SizedBox(height: 12),
      Text('Sin estados por ahora', style: TextStyle(color: Colors.grey, fontSize: 15)),
    ]));
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF1E6B2E),
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.75),
        itemCount: _estados.length,
        itemBuilder: (ctx, i) {
          final e = _estados[i];
          final bytes = _cache[e.filename];
          return GestureDetector(
            onTap: () => _openViewer(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(children: [
                Positioned.fill(
                  child: bytes != null
                    ? Image.memory(bytes, fit: BoxFit.cover)
                    : Container(color: Colors.grey.shade200, child: const Center(child: CircularProgressIndicator(color: Color(0xFF1E6B2E)))),
                ),
                if (e.caption != null)
                  Positioned(bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.6)])),
                      child: Text(e.caption!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    )),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _EstadoViewer extends StatefulWidget {
  final List<Estado> estados;
  final int initialIndex;
  final Map<String, Uint8List?> cache;
  const _EstadoViewer({required this.estados, required this.initialIndex, required this.cache});
  @override State<_EstadoViewer> createState() => _EstadoViewerState();
}

class _EstadoViewerState extends State<_EstadoViewer> {
  late final PageController _pc;
  @override void initState() { super.initState(); _pc = PageController(initialPage: widget.initialIndex); }
  @override void dispose() { _pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: const BackButton(color: Colors.white),
        title: Text('Estados de Concentrados Monserrath', style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.estados.length,
        itemBuilder: (ctx, i) {
          final e = widget.estados[i];
          final bytes = widget.cache[e.filename];
          return Stack(children: [
            Center(
              child: bytes != null
                ? InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain))
                : const CircularProgressIndicator(color: Colors.white),
            ),
            if (e.caption != null)
              Positioned(bottom: 32, left: 20, right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                  child: Text(e.caption!, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
                )),
          ]);
        },
      ),
    );
  }
}
```

- [ ] Commit: `git commit -m "feat(client): Estados viewer with full-screen swipe"`

### Task 21: client_products_screen.dart — attractive product grid

**Files:** Create `lib/screens/client_products_screen.dart`

- [ ] Create grid screen with product images, search bar, attractive cards:
```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import 'client_product_detail_screen.dart';

class ClientProductsScreen extends StatefulWidget {
  const ClientProductsScreen({super.key});
  @override State<ClientProductsScreen> createState() => _ClientProductsScreenState();
}

class _ClientProductsScreenState extends State<ClientProductsScreen> {
  List<Product> _all = [], _filtered = [];
  bool _loading = true;
  String _search = '';
  final Map<String, Uint8List?> _imgCache = {};

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final products = await ApiService.getProducts();
      if (mounted) {
        setState(() { _all = products.where((p) => p.available).toList(); _filtered = _all; });
        for (final p in _all) {
          if (p.images.isNotEmpty && !_imgCache.containsKey(p.images.first)) {
            ApiService.downloadProductImage(p.images.first).then((bytes) {
              if (mounted) setState(() => _imgCache[p.images.first] = bytes);
            });
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _onSearch(String q) {
    setState(() {
      _search = q;
      _filtered = q.isEmpty ? _all : _all.where((p) => p.name.toLowerCase().contains(q.toLowerCase())).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: TextField(
          onChanged: _onSearch,
          decoration: InputDecoration(
            hintText: 'Buscar productos…',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          ),
        ),
      ),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E6B2E)))
        : _filtered.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('🔍', style: TextStyle(fontSize: 48)),
              SizedBox(height: 12),
              Text('Sin productos disponibles', style: TextStyle(color: Colors.grey)),
            ]))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF1E6B2E),
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.72),
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) => _buildCard(_filtered[i]),
              ),
            )),
    ]);
  }

  Widget _buildCard(Product p) {
    final bytes = p.images.isNotEmpty ? _imgCache[p.images.first] : null;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ClientProductDetailScreen(product: p, imageCache: _imgCache))),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 3,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 1.1,
              child: p.images.isNotEmpty && bytes != null
                ? Image.memory(bytes, fit: BoxFit.cover)
                : Container(
                    color: const Color(0xFFE8F5E9),
                    child: const Center(child: Icon(Icons.grain_rounded, size: 48, color: Color(0xFF1E6B2E)))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('\$${p.price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                style: const TextStyle(color: Color(0xFF1E6B2E), fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 6),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ClientProductDetailScreen(product: p, imageCache: _imgCache))),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                  label: const Text('Pedir', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6B2E), foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] Commit: `git commit -m "feat(client): product grid with images + search"`

### Task 22: client_product_detail_screen.dart

**Files:** Create `lib/screens/client_product_detail_screen.dart`

- [ ] Create product detail with quantity selector, delivery date, add to cart:
```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/api_service.dart';

class ClientProductDetailScreen extends StatefulWidget {
  final Product product;
  final Map<String, Uint8List?> imageCache;
  const ClientProductDetailScreen({super.key, required this.product, required this.imageCache});
  @override State<ClientProductDetailScreen> createState() => _ClientProductDetailScreenState();
}

class _ClientProductDetailScreenState extends State<ClientProductDetailScreen> {
  int _quantity = 1;
  DateTime? _deliveryDate;
  bool _adding = false;
  int _imageIndex = 0;

  String _formatPrice(double price) =>
    '\$${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      helpText: 'Selecciona la fecha de entrega',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF1E6B2E))),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _deliveryDate = picked);
  }

  Future<void> _addToCart() async {
    setState(() => _adding = true);
    try {
      await ApiService.addToCart(
        widget.product.id!,
        _quantity,
        deliveryDate: _deliveryDate?.toIso8601String().split('T').first,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('${widget.product.name} agregado al carrito'),
            ]),
            backgroundColor: const Color(0xFF1E6B2E),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final images = p.images;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF1E6B2E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image carousel
          if (images.isNotEmpty) ...[
            SizedBox(
              height: 260,
              child: PageView.builder(
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _imageIndex = i),
                itemBuilder: (ctx, i) {
                  final bytes = widget.imageCache[images[i]];
                  return bytes != null
                    ? Image.memory(bytes, fit: BoxFit.cover)
                    : Container(color: const Color(0xFFE8F5E9),
                        child: const Center(child: Icon(Icons.grain_rounded, size: 64, color: Color(0xFF1E6B2E))));
                },
              ),
            ),
            if (images.length > 1)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(images.length, (i) =>
                Container(margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8), width: 7, height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: i == _imageIndex ? const Color(0xFF1E6B2E) : Colors.grey.shade300)))),
          ] else
            Container(height: 200, color: const Color(0xFFE8F5E9),
              child: const Center(child: Icon(Icons.grain_rounded, size: 80, color: Color(0xFF1E6B2E)))),

          // Product info
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(_formatPrice(p.price), style: const TextStyle(fontSize: 28, color: Color(0xFF1E6B2E), fontWeight: FontWeight.w900)),
              const Divider(height: 28),

              // Quantity
              const Text('Cantidad', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(children: [
                IconButton.filled(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_rounded),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF1E6B2E), foregroundColor: Colors.white),
                ),
                const SizedBox(width: 16),
                Text('$_quantity', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(width: 16),
                IconButton.filled(
                  onPressed: () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_rounded),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF1E6B2E), foregroundColor: Colors.white),
                ),
                const Spacer(),
                Text('Total: ${_formatPrice(p.price * _quantity)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E6B2E))),
              ]),

              const SizedBox(height: 20),

              // Delivery date
              const Text('Fecha de entrega (opcional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('¿Para cuándo necesitas el producto?', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: _deliveryDate != null ? const Color(0xFF1E6B2E) : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                    color: _deliveryDate != null ? const Color(0xFFE8F5E9) : Colors.white,
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_rounded,
                      color: _deliveryDate != null ? const Color(0xFF1E6B2E) : Colors.grey, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      _deliveryDate != null
                        ? DateFormat('d MMMM yyyy', 'es').format(_deliveryDate!)
                        : 'Seleccionar fecha',
                      style: TextStyle(
                        color: _deliveryDate != null ? const Color(0xFF1E6B2E) : Colors.grey,
                        fontWeight: _deliveryDate != null ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    if (_deliveryDate != null) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _deliveryDate = null),
                        child: const Icon(Icons.close, size: 18, color: Colors.grey),
                      ),
                    ],
                  ]),
                ),
              ),

              const SizedBox(height: 28),
              SizedBox(width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _adding ? null : _addToCart,
                  icon: _adding
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_shopping_cart_rounded),
                  label: Text(_adding ? 'Agregando…' : 'Agregar al carrito',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6B2E),
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] Commit: `git commit -m "feat(client): product detail with quantity + delivery date + add to cart"`

### Task 23: client_cart_screen.dart — cart + Nequi/contra-entrega

**Files:** Create `lib/screens/client_cart_screen.dart`

- [ ] Create cart screen with item list, total, payment options:
```dart
import 'package:flutter/material.dart';
import '../models/cart_item.dart';
import '../services/api_service.dart';

class ClientCartScreen extends StatefulWidget {
  const ClientCartScreen({super.key});
  @override State<ClientCartScreen> createState() => _ClientCartScreenState();
}

class _ClientCartScreenState extends State<ClientCartScreen> {
  List<CartItem> _items = [];
  bool _loading = true;
  bool _paying  = false;
  Map<String, String> _settings = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([ApiService.getCart(), ApiService.getSettings()]);
      if (mounted) {
        setState(() {
          _items    = results[0] as List<CartItem>;
          _settings = results[1] as Map<String, String>;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  double get _total => _items.fold(0, (sum, i) => sum + i.subtotal);

  String _formatPrice(double p) =>
    '\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  Future<void> _remove(CartItem item) async {
    try {
      await ApiService.removeFromCart(item.id);
      _load();
    } catch (_) {}
  }

  Future<void> _checkout(String method) async {
    if (_items.isEmpty) return;
    if (method == 'nequi') {
      final refCtrl = TextEditingController();
      final nequiPhone = _settings['nequi_phone'] ?? 'N/A';
      final nequiName  = _settings['nequi_name']  ?? 'Concentrados Monserrath';
      final ref = await showDialog<String?>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(children: [
            CircleAvatar(backgroundColor: Color(0xFF5C068C), radius: 16,
              child: Text('N', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            SizedBox(width: 10),
            Text('Pagar con Nequi', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                const Text('Enviar pago a:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(nequiPhone, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF5C068C), letterSpacing: 2)),
                Text(nequiName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(_formatPrice(_total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E6B2E))),
              ]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: refCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Referencia de transferencia',
                hintText: 'Número de 6-10 dígitos',
                helperText: 'Encuéntrala en el comprobante Nequi',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.receipt_long_outlined),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (refCtrl.text.trim().length < 4) return;
                Navigator.pop(context, refCtrl.text.trim());
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5C068C)),
              child: const Text('Confirmar pago'),
            ),
          ],
        ),
      );
      if (ref == null || !mounted) return;
      setState(() => _paying = true);
      try {
        await ApiService.checkout(paymentMethod: 'nequi', nequiReference: ref);
        if (mounted) _showSuccess('¡Pedido realizado!\nReferencia Nequi: $ref\nNos pondremos en contacto pronto.');
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      } finally {
        if (mounted) setState(() => _paying = false);
      }
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.local_shipping_rounded, color: Color(0xFF1E6B2E)),
            SizedBox(width: 8),
            Text('Pago contraentrega'),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Pagarás cuando recibas tu pedido.', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 10),
            Text('Total a pagar: ${_formatPrice(_total)}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1E6B2E))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E6B2E)),
              child: const Text('Confirmar pedido'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _paying = true);
      try {
        await ApiService.checkout(paymentMethod: 'contraentrega');
        if (mounted) _showSuccess('¡Pedido realizado!\nPagarás cuando recibas tu pedido.\nNos pondremos en contacto pronto.');
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      } finally {
        if (mounted) setState(() => _paying = false);
      }
    }
  }

  void _showSuccess(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF1E6B2E), size: 64),
          const SizedBox(height: 16),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
        ]),
        actions: [
          FilledButton(
            onPressed: () { Navigator.pop(context); _load(); },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E6B2E)),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E6B2E)))
        : _items.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('🛒', style: TextStyle(fontSize: 64)),
              SizedBox(height: 12),
              Text('Tu carrito está vacío', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text('Agrega productos desde el catálogo', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ]))
          : Column(children: [
              // Pay button header
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_items.length} producto(s)', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    Text('Total: ${_formatPrice(_total)}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E6B2E))),
                  ])),
                  _paying
                    ? const CircularProgressIndicator(color: Color(0xFF1E6B2E))
                    : PopupMenuButton<String>(
                        onSelected: _checkout,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E6B2E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(children: [
                            Icon(Icons.payment_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text('Pagar pedido', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                          ]),
                        ),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'nequi',
                            child: Row(children: [
                              CircleAvatar(backgroundColor: Color(0xFF5C068C), radius: 14,
                                child: Text('N', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              SizedBox(width: 10),
                              Text('Pagar con Nequi'),
                            ])),
                          const PopupMenuItem(value: 'contraentrega',
                            child: Row(children: [
                              Icon(Icons.local_shipping_rounded, color: Color(0xFF1E6B2E)),
                              SizedBox(width: 10),
                              Text('Pago contraentrega'),
                            ])),
                        ],
                      ),
                ]),
              ),

              // Items list
              Expanded(child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _items.length,
                itemBuilder: (ctx, i) {
                  final item = _items[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(child: Icon(Icons.grain_rounded, color: Color(0xFF1E6B2E), size: 28)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('${_formatPrice(item.productPrice)} × ${item.quantity}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          if (item.deliveryDate != null) ...[
                            const SizedBox(height: 2),
                            Row(children: [
                              const Icon(Icons.calendar_today_rounded, size: 11, color: Color(0xFF1E6B2E)),
                              const SizedBox(width: 4),
                              Text('Entrega: ${item.deliveryDate}', style: const TextStyle(fontSize: 11, color: Color(0xFF1E6B2E))),
                            ]),
                          ],
                          Text(_formatPrice(item.subtotal),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1E6B2E), fontSize: 15)),
                        ])),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.red),
                          onPressed: () => _remove(item),
                          tooltip: 'Quitar del carrito',
                        ),
                      ]),
                    ),
                  );
                },
              )),
            ]),
    );
  }
}
```

- [ ] Commit: `git commit -m "feat(client): cart screen with Nequi + contra-entrega payment"`

### Task 24: client_home_screen.dart — client navigation shell

**Files:** Create `lib/screens/client_home_screen.dart`

- [ ] Create navigation shell for client role (Products, Cart, Estados, Profile):
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'client_products_screen.dart';
import 'client_cart_screen.dart';
import 'client_estados_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});
  @override State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  int _tab = 0;
  static const _titles = ['Catálogo', 'Mi Carrito', 'Estados'];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E6B2E),
        foregroundColor: Colors.white,
        title: Row(children: [
          const Text('🌾 ', style: TextStyle(fontSize: 18)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_titles[_tab], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Text('Concentrados Monserrath', style: TextStyle(fontSize: 10, color: Colors.white70)),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Cerrar sesión'),
                  content: const Text('¿Deseas cerrar sesión?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir')),
                  ],
                ),
              );
              if (ok == true && context.mounted) context.read<AppProvider>().logout();
            },
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: const [
        ClientProductsScreen(),
        ClientCartScreen(),
        ClientEstadosScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFD4ECB8),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded, color: Color(0xFF1E6B2E)),
            label: 'Catálogo'),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart_rounded, color: Color(0xFF1E6B2E)),
            label: 'Carrito'),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories_rounded, color: Color(0xFF1E6B2E)),
            label: 'Estados'),
        ],
      ),
    );
  }
}
```

- [ ] Update `lib/main.dart` — add import + route logic:
```dart
import 'screens/client_home_screen.dart';
// In the Consumer<AppProvider> where screen is chosen:
if (provider.isLoggedIn) {
  return provider.currentRole == 'client'
    ? const ClientHomeScreen()
    : const DashboardScreen();
}
return const LoginScreen();
```

- [ ] Commit: `git commit -m "feat(client): ClientHomeScreen navigation shell + role routing"`

---

## PHASE 7 — Fixes + Optimization

### Task 25: products_screen.dart — image upload in create/edit

**Files:** Modify `lib/screens/products_screen.dart`

- [ ] Read current file, then in the product create/edit dialog, add image upload section:
```dart
// After price field, add:
const SizedBox(height: 12),
const Text('Foto del producto (opcional)', style: TextStyle(fontSize: 12, color: Colors.grey)),
const SizedBox(height: 6),
ElevatedButton.icon(
  onPressed: _uploadingImage ? null : () async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || productId == null) return;
    setState(() => _uploadingImage = true);
    try {
      await ApiService.uploadProductImage(productId, file.path);
      // reload product
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  },
  icon: const Icon(Icons.add_photo_alternate_outlined),
  label: const Text('Agregar foto'),
  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E6B2E), foregroundColor: Colors.white),
),
```

- [ ] Commit: `git commit -m "feat(products): image upload in admin product dialog"`

### Task 26: start-all.sh — NLP health + watchdog

**Files:** Modify `start-all.sh`

- [ ] Replace section 8 (NLP.js comment) with actual verification after server starts:
```bash
# ── 8. Verificar NLP.js entrenado ────────────────────────────────
info "Verificando parser NLP.js..."
NLP_OK=0
for i in $(seq 1 10); do
  NLP_STATUS=$(curl -sf "http://localhost:${PORT_VAL}/health" 2>/dev/null | grep -o '"nlp":[^,}]*' || echo "")
  if echo "$NLP_STATUS" | grep -q '"trained":true\|"ready":true\|true'; then
    NLP_OK=1; break
  fi
  sleep 1
done
[ "$NLP_OK" = "1" ] && ok "NLP.js entrenado con productos de DB" || warn "NLP.js: sin confirmar — verifica /health"
```

- [ ] Add bot watchdog AFTER section 11 (bot section):
```bash
# ── 11b. Watchdog bot WhatsApp ────────────────────────────────────
if [ "${BOT_ENABLED:-false}" = "true" ]; then
  (
    while true; do
      sleep 60
      kill -0 "$SERVER_PID" 2>/dev/null || exit 0
      if ! grep -q '\[bot\] ✅ Connected' "$LOG/server.log" 2>/dev/null; then
        LAST_CONN=$(grep '\[bot\]' "$LOG/server.log" 2>/dev/null | tail -1 || echo "")
        echo "[$(date '+%H:%M:%S')] watchdog: bot no conectado — $LAST_CONN" >> "$LOG/bot-watchdog.log"
      fi
    done
  ) &
  ok "Watchdog bot iniciado (monitoreo cada 60s)"
fi
```

- [ ] Remove hardcoded credentials from resumen (lines 435-436):
```bash
# Replace the users/PIN lines with:
printf "${GREEN}${BOLD}║${NC} Roles: admin | worker | client              ${GREEN}${BOLD}║${NC}\n"
printf "${GREEN}${BOLD}║${NC} Gestionar usuarios: app → tab Usuarios       ${GREEN}${BOLD}║${NC}\n"
```

- [ ] Commit: `git commit -m "feat(start): NLP.js health check + bot watchdog + remove hardcoded creds from output"`

### Task 27: compilar-apk.ps1 optimization

**Files:** Modify `compilar-apk.ps1`

- [ ] After pub get section, add Gradle optimization flags:
```powershell
# ── 7b. Set Gradle optimizations ─────────────────────────────
$gradleProps = Join-Path $APPDIR "android\gradle.properties"
$optimizations = @"

# Claude Code optimizations
org.gradle.daemon=true
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.jvmargs=-Xmx4g -XX:+UseParallelGC
android.enableR8.fullMode=false
android.bundle.enableUncompressedNativeLibs=false
"@
if (Test-Path $gradleProps) {
  $existing = Get-Content $gradleProps -Raw
  if (-not $existing.Contains('org.gradle.parallel=true')) {
    Add-Content $gradleProps $optimizations
    ok "Gradle optimizations applied"
  } else {
    ok "Gradle optimizations already set"
  }
}
```

- [ ] Change build command to use `--no-shrink` only if debug, keep release shrink:
```powershell
# Replace current build command with:
$buildOut = & $FLUTTER build apk --release --no-pub `
  --target-platform android-arm64 `
  --obfuscate `
  --split-debug-info="$APPDIR\debug-symbols" `
  --dart-define=FLUTTER_WEB_USE_SKIA=false 2>&1
```

- [ ] Add clean check: if last build was <5min ago and no source changed, skip:
```powershell
# Before build step, add:
$lastApk = Get-Item $apkSrc -ErrorAction SilentlyContinue
$sourceChanged = $false
if ($lastApk) {
  $lastBuild = $lastApk.LastWriteTime
  $newerSrc = Get-ChildItem "$APPDIR\lib" -Recurse -Filter "*.dart" |
    Where-Object { $_.LastWriteTime -gt $lastBuild } | Select-Object -First 1
  $sourceChanged = $null -ne $newerSrc
  if (-not $sourceChanged -and -not $Clean) {
    ok "APK reciente sin cambios — omitiendo compilación"
    Copy-Item $apkSrc $OUT -Force
    $size = [math]::Round((Get-Item $OUT).Length / 1MB, 1)
    Write-Host "`n${GREEN}${BOLD}APK ya actualizado: $size MB${NC}`n"
    exit 0
  }
}
```

- [ ] Commit: `git commit -m "feat(compile): Gradle parallel+cache optimizations + skip if unchanged"`

---

## FINAL CHECKLIST

- [ ] Run `flutter pub get` in android-app/
- [ ] Verify server starts: `npm start` in server/, check `/health`
- [ ] Verify all new routes registered in index.js
- [ ] Verify `role='client'` can login and sees ClientHomeScreen
- [ ] Verify `role='admin'` sees Estados + Config tabs
- [ ] Verify Products tab hidden from worker role
- [ ] Verify audio plays with correct extension (.ogg from bot)
- [ ] Verify long-press on conversation shows bottom sheet
- [ ] Push all changes: `git push origin main`
- [ ] Run `compilar-apk.ps1` manually and verify APK builds

---

*Total tasks: 27 | Estimated time: 4-6 hours*
