'use strict';

const chalk    = require('chalk');
const inquirer = require('inquirer');
const ora      = require('ora');
const { execSync, spawn } = require('child_process');
const fs       = require('fs');
const path     = require('path');
const https    = require('https');
const http     = require('http');
const os       = require('os');

// ── Rutas instalación ─────────────────────────────────────────
const INSTALL_DIR   = 'C:\\PedidosMonserrath';
const REPO_DIR      = path.join(INSTALL_DIR, 'app');
const SERVER_DIR    = path.join(REPO_DIR, 'server');
const SVC_NAME      = 'PedidosMonserrath';
const SVC_DESC      = 'Sistema de pedidos WhatsApp - Concentrados Monserrath';
const GITHUB_ZIP    = 'https://github.com/itanmidnight-ux/pedidos-whatsapp/archive/refs/heads/main.zip';
const NGROK_TOKEN   = '34G7biMjp4tdGcupxvySfJvYqrQ_6BEU8VntbCjSudDRWntdB';
const NGROK_DOMAIN  = 'francoise-subhumid-maire.ngrok-free.dev';
const NODE_REQUIRED = 20;
const NODE_VERSION  = '20.20.2';

// ── Credenciales pre-configuradas ────────────────────────────
const ENV_DEFAULTS = {
  PORT:        '3000',
  API_KEY:     '80721f27d4b9e6b1250ccf94f5356f1d9368993ffd0e51d1d9470754e85b9171',
  JWT_SECRET:  'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2',
  NGROK_DOMAIN: NGROK_DOMAIN,
  OLLAMA_MODEL: 'llama3.2:1b',
  WORKER_PIN:  '1234',
  BOT_ENABLED: 'true',
};

// ── Helpers ───────────────────────────────────────────────────
function header() {
  console.clear();
  const b = chalk.green('║'), l = chalk.green;
  console.log(l('╔══════════════════════════════════════════════════╗'));
  console.log(b + chalk.yellow.bold('       CONCENTRADOS MONSERRATH v2.0               ') + b);
  console.log(b + chalk.white('       Instalador del Sistema de Pedidos          ') + b);
  console.log(l('╚══════════════════════════════════════════════════╝\n'));
}

function run(cmd, opts = {}) {
  try { return execSync(cmd, { stdio: 'pipe', timeout: 180000, encoding: 'utf8', ...opts }).trim(); }
  catch { return null; }
}

function runOrThrow(cmd, opts = {}) {
  return execSync(cmd, { stdio: 'pipe', timeout: 300000, encoding: 'utf8', ...opts }).trim();
}

function write(p, content) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content, 'utf8');
}

function exists(p) { try { fs.accessSync(p); return true; } catch { return false; } }

function delay(ms) { return new Promise(r => setTimeout(r, ms)); }

function download(url, dest) {
  return new Promise((resolve, reject) => {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const file = fs.createWriteStream(dest);
    function get(u) {
      const mod = u.startsWith('https') ? https : http;
      mod.get(u, { headers: { 'User-Agent': 'Mozilla/5.0' } }, res => {
        if ([301, 302, 307, 308].includes(res.statusCode)) return get(res.headers.location);
        if (res.statusCode !== 200) { file.close(); return reject(new Error(`HTTP ${res.statusCode} para ${u}`)); }
        res.pipe(file);
        file.on('finish', () => { file.close(); resolve(); });
      }).on('error', e => { file.close(); reject(e); });
    }
    get(url);
  });
}

async function isAdmin() {
  try { execSync('net session', { stdio: 'pipe' }); return true; }
  catch { return false; }
}

function nodePATH() {
  const candidates = [
    'C:\\Program Files\\nodejs',
    path.join(process.env.ProgramFiles || '', 'nodejs'),
    path.join(INSTALL_DIR, 'node'),
  ];
  return process.env.PATH + ';' + candidates.join(';');
}

function ngrokPATH() { return nodePATH() + ';' + path.join(INSTALL_DIR, 'ngrok'); }

// ── PASO 1: Node.js ───────────────────────────────────────────
async function ensureNode(sp) {
  sp.text = 'Verificando Node.js...';
  const fullPath = nodePATH();

  const v = run('node --version', { env: { ...process.env, PATH: fullPath } });
  const major = v ? parseInt(v.replace(/[^0-9]/, '')) : 0;

  if (major >= NODE_REQUIRED) {
    sp.succeed(chalk.green(`Node.js ${v} ✓`));
    return fullPath;
  }

  sp.text = `Descargando Node.js ${NODE_VERSION} LTS...`;
  const msi = path.join(os.tmpdir(), 'node-setup.msi');

  try {
    if (!exists(msi)) {
      await download(
        `https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-x64.msi`,
        msi
      );
    }
    sp.text = 'Instalando Node.js (puede tardar 2 min)...';
    runOrThrow(
      `msiexec /i "${msi}" /quiet /norestart ADDLOCAL=ALL`,
      { timeout: 300000 }
    );
    try { fs.unlinkSync(msi); } catch { /* ignore */ }

    const v2 = run('node --version', { env: { ...process.env, PATH: fullPath } });
    if (v2) { sp.succeed(chalk.green(`Node.js ${v2} instalado ✓`)); return fullPath; }
    sp.warn(chalk.yellow('Node.js instalado — reinicia el instalador'));
    process.exit(0);
  } catch (e) {
    sp.fail(chalk.red('Error instalando Node.js: ' + e.message));
    throw e;
  }
}

// ── PASO 2: Git ───────────────────────────────────────────────
async function ensureGit(sp) {
  sp.text = 'Verificando Git...';
  const v = run('git --version');
  if (v) { sp.succeed(chalk.green(`${v} ✓`)); return; }

  sp.text = 'Descargando Git para Windows...';
  const exe = path.join(os.tmpdir(), 'git-setup.exe');
  try {
    if (!exists(exe)) {
      await download(
        'https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.1/Git-2.47.0-64-bit.exe',
        exe
      );
    }
    sp.text = 'Instalando Git...';
    runOrThrow(`"${exe}" /VERYSILENT /NORESTART /NOCANCEL /SP-`);
    try { fs.unlinkSync(exe); } catch { /* ignore */ }
    sp.succeed(chalk.green('Git instalado ✓'));
  } catch (e) {
    sp.warn(chalk.yellow('Git: ' + e.message + ' (continuando sin él)'));
  }
}

// ── PASO 3: ngrok ─────────────────────────────────────────────
async function ensureNgrok(sp, envPath) {
  sp.text = 'Verificando ngrok...';
  const v = run('ngrok version', { env: { ...process.env, PATH: envPath } });
  if (v) { sp.succeed(chalk.green(`ngrok ${v} ✓`)); return; }

  sp.text = 'Descargando ngrok...';
  const zip = path.join(os.tmpdir(), 'ngrok.zip');
  const dir = path.join(INSTALL_DIR, 'ngrok');
  fs.mkdirSync(dir, { recursive: true });

  try {
    if (!exists(zip)) {
      await download(
        'https://bin.ngrok.com/a/971cHyC98V7/ngrok-v3-3.39.6-windows-amd64.zip',
        zip
      );
    }
    // usar PowerShell para extraer (no depende de 7zip)
    runOrThrow(`powershell -Command "Expand-Archive -Path '${zip}' -DestinationPath '${dir}' -Force"`);
    try { fs.unlinkSync(zip); } catch { /* ignore */ }
    sp.succeed(chalk.green('ngrok instalado ✓'));
  } catch (e) {
    sp.warn(chalk.yellow('ngrok: ' + e.message));
  }
}

// ── PASO 4: Descargar código del servidor ─────────────────────
async function ensureServerCode(sp) {
  sp.text = 'Verificando código del servidor...';
  const indexFile = path.join(SERVER_DIR, 'src', 'index.js');

  if (exists(indexFile)) {
    sp.succeed(chalk.green('Código del servidor ya presente ✓'));
    return;
  }

  // Intentar git clone primero
  const gitAvailable = !!run('git --version');
  fs.mkdirSync(INSTALL_DIR, { recursive: true });

  if (gitAvailable) {
    sp.text = 'Clonando repositorio...';
    try {
      if (exists(REPO_DIR)) run(`rmdir /s /q "${REPO_DIR}"`, { shell: true });
      runOrThrow(
        `git clone --depth 1 https://github.com/itanmidnight-ux/pedidos-whatsapp.git "${REPO_DIR}"`,
        { timeout: 120000 }
      );
      sp.succeed(chalk.green('Repositorio clonado ✓'));
      return;
    } catch { /* fallback to ZIP */ }
  }

  // Fallback: descargar ZIP de GitHub
  sp.text = 'Descargando código (ZIP)...';
  const zip = path.join(os.tmpdir(), 'pedidos-app.zip');
  const tmp = path.join(os.tmpdir(), 'pedidos-extract');

  try {
    await download(GITHUB_ZIP, zip);
    sp.text = 'Extrayendo código...';
    if (exists(tmp)) run(`rmdir /s /q "${tmp}"`, { shell: true });
    fs.mkdirSync(tmp, { recursive: true });
    runOrThrow(`powershell -Command "Expand-Archive -Path '${zip}' -DestinationPath '${tmp}' -Force"`);

    // La carpeta extraída tiene nombre pedidos-whatsapp-main
    const extracted = fs.readdirSync(tmp).find(d => d.startsWith('pedidos-whatsapp'));
    if (!extracted) throw new Error('Estructura de ZIP inesperada');

    if (exists(REPO_DIR)) run(`rmdir /s /q "${REPO_DIR}"`, { shell: true });
    runOrThrow(`xcopy /e /i /q "${path.join(tmp, extracted)}" "${REPO_DIR}"`);
    run(`rmdir /s /q "${tmp}"`, { shell: true });
    try { fs.unlinkSync(zip); } catch { /* ignore */ }
    sp.succeed(chalk.green('Código descargado ✓'));
  } catch (e) {
    sp.fail(chalk.red('No se pudo obtener el código: ' + e.message));
    throw e;
  }
}

// ── PASO 5: npm install ───────────────────────────────────────
async function ensureNpmDeps(sp, envPath) {
  sp.text = 'Verificando dependencias npm...';
  const nodeModules = path.join(SERVER_DIR, 'node_modules', 'express');

  if (exists(nodeModules)) {
    sp.succeed(chalk.green('Dependencias npm ya instaladas ✓'));
    return;
  }

  sp.text = 'Instalando dependencias npm (puede tardar 3-5 min)...';
  const env = { ...process.env, PATH: envPath, npm_config_cache: path.join(INSTALL_DIR, '.npm-cache') };

  try {
    runOrThrow('npm install --production --legacy-peer-deps --no-audit', { cwd: SERVER_DIR, env });
    sp.succeed(chalk.green('Dependencias instaladas ✓'));
  } catch (e) {
    sp.fail(chalk.red('Error npm install: ' + e.message.split('\n')[0]));
    throw e;
  }
}

// ── PASO 6: Escribir .env ─────────────────────────────────────
function writeEnv(phone) {
  const envPath = path.join(SERVER_DIR, '.env');
  const lines = Object.entries({ ...ENV_DEFAULTS, BOT_PHONE: phone }).map(([k, v]) => `${k}=${v}`);
  // No sobreescribir si ya existe con mismo teléfono (idempotente)
  if (exists(envPath)) {
    const current = fs.readFileSync(envPath, 'utf8');
    if (current.includes(`BOT_PHONE=${phone}`)) return; // ya configurado
  }
  write(envPath, lines.join('\n') + '\n');
}

// ── PASO 7: Configurar ngrok ──────────────────────────────────
function configureNgrok(sp, envPath) {
  sp.text = 'Configurando ngrok...';
  try {
    runOrThrow(
      `ngrok config add-authtoken ${NGROK_TOKEN}`,
      { env: { ...process.env, PATH: envPath } }
    );
    sp.succeed(chalk.green('ngrok configurado ✓'));
  } catch (e) {
    sp.warn(chalk.yellow('ngrok config: ' + e.message));
  }
}

// ── PASO 8: Servicio Windows ──────────────────────────────────
const SVC_SCRIPT = (nodeExe, serverDir) => `
const { Service } = require('node-windows');
const svc = new Service({
  name: '${SVC_NAME}',
  description: '${SVC_DESC}',
  script: '${path.join(serverDir, 'src', 'index.js').replace(/\\/g, '\\\\')}',
  workingDirectory: '${serverDir.replace(/\\/g, '\\\\')}',
  nodeOptions: [],
  env: [{ name: 'NODE_ENV', value: 'production' }]
});
svc.on('install',          () => { console.log('installed'); svc.start(); });
svc.on('alreadyinstalled', () => { svc.restart(); console.log('restarted'); });
svc.on('error',             e => { console.error('svc-error:', e); process.exit(1); });
svc.install();
setTimeout(() => process.exit(0), 15000);
`.trim();

async function stopExistingService(sp) {
  sp.text = 'Verificando servicio existente...';
  const status = run(`sc query ${SVC_NAME}`);
  if (!status) { sp.succeed(chalk.green('Sin instalación previa ✓')); return; }

  sp.text = 'Deteniendo servicio anterior...';
  run(`sc stop ${SVC_NAME}`);
  await delay(4000);

  const uninstallScript = path.join(INSTALL_DIR, '_uninstall-svc.js');
  write(uninstallScript, `
const { Service } = require('node-windows');
const svc = new Service({ name: '${SVC_NAME}', script: '${path.join(SERVER_DIR, 'src', 'index.js').replace(/\\/g, '\\\\')}' });
svc.on('uninstall', () => { console.log('uninstalled'); process.exit(0); });
svc.on('error', () => process.exit(0));
svc.uninstall();
setTimeout(() => process.exit(0), 10000);
`.trim());

  try {
    runOrThrow(`node "${uninstallScript}"`, { cwd: SERVER_DIR, timeout: 15000 });
  } catch { /* ignorar */ }
  try { fs.unlinkSync(uninstallScript); } catch { /* ignore */ }
  await delay(3000);
  sp.succeed(chalk.green('Servicio anterior eliminado ✓'));
}

async function installService(sp, envPath) {
  sp.text = 'Instalando servicio Windows...';

  // node-windows debe estar instalado
  const nwPath = path.join(SERVER_DIR, 'node_modules', 'node-windows');
  if (!exists(nwPath)) {
    const env = { ...process.env, PATH: envPath };
    runOrThrow('npm install node-windows --save --legacy-peer-deps', { cwd: SERVER_DIR, env, timeout: 60000 });
  }

  const installScript = path.join(INSTALL_DIR, '_install-svc.js');
  write(installScript, SVC_SCRIPT(process.execPath, SERVER_DIR));

  try {
    runOrThrow(`node "${installScript}"`, { cwd: SERVER_DIR, timeout: 30000 });
    await delay(5000);
    try { fs.unlinkSync(installScript); } catch { /* ignore */ }
    sp.succeed(chalk.green('Servicio Windows instalado ✓'));
  } catch (e) {
    sp.warn(chalk.yellow('Servicio: ' + e.message));
  }
}

// ── PASO 9: Verificar servidor ────────────────────────────────
async function waitForServer(sp, port = 3000, maxWait = 30000) {
  sp.text = 'Esperando que el servidor inicie...';
  const start = Date.now();
  while (Date.now() - start < maxWait) {
    try {
      await new Promise((res, rej) => {
        const req = http.get(`http://localhost:${port}/health`, r => {
          let d = '';
          r.on('data', c => d += c);
          r.on('end', () => d.includes('ok') ? res() : rej(new Error('bad response')));
        });
        req.on('error', rej);
        req.setTimeout(2000, () => { req.destroy(); rej(new Error('timeout')); });
      });
      sp.succeed(chalk.green('Servidor en línea ✓'));
      return true;
    } catch { await delay(2000); }
  }
  sp.warn(chalk.yellow('Servidor no respondió en 30s (puede tardar un poco más)'));
  return false;
}

// ── PASO 10: Lanzar bot y mostrar pairing code ────────────────
function launchBotWindow() {
  const bat = path.join(INSTALL_DIR, 'ver-bot.bat');
  write(bat, [
    '@echo off',
    `title Bot WhatsApp - Concentrados Monserrath`,
    'color 0A',
    'mode con cols=80 lines=30',
    `cd /d "${SERVER_DIR}"`,
    'echo.',
    'echo  Monitoreo del bot WhatsApp',
    'echo  El codigo de vinculacion aparecera aqui abajo...',
    'echo.',
    `node src/index.js`,
    'pause',
  ].join('\r\n'));
  execSync(`start "Bot Monserrath" "${bat}"`, { shell: true, stdio: 'ignore' });
}

// ── Main ──────────────────────────────────────────────────────
async function main() {
  header();

  // ── Admin check ───────────────────────────────────────────
  if (!await isAdmin()) {
    console.log(chalk.red.bold('✗ Ejecutar como Administrador.'));
    console.log(chalk.yellow('  Clic derecho en el .exe → "Ejecutar como administrador"'));
    await inquirer.prompt([{ type: 'input', name: 'x', message: '\n  Presiona Enter para cerrar...' }]);
    process.exit(1);
  }
  console.log(chalk.green('  ✓ Administrador OK'));

  // ── Info del sistema ──────────────────────────────────────
  const totalRAM = Math.round(os.totalmem() / 1073741824);
  console.log(chalk.gray(`  Sistema: Windows ${os.release()} | RAM: ${totalRAM}GB`));
  if (totalRAM < 2) console.log(chalk.yellow('  ⚠ RAM < 2GB: el sistema puede ir lento'));
  console.log();

  // ── Detectar re-instalación ───────────────────────────────
  const yaInstalado = exists(path.join(SERVER_DIR, '.env'));
  if (yaInstalado) {
    console.log(chalk.yellow('  ⚡ Instalación existente detectada.'));
    const { accion } = await inquirer.prompt([{
      type: 'list', name: 'accion',
      message: '  ¿Qué deseas hacer?',
      choices: [
        { name: 'Actualizar y reiniciar', value: 'update' },
        { name: 'Reparar (reinstalar dependencias)', value: 'repair' },
        { name: 'Instalar desde cero', value: 'fresh' },
        { name: 'Salir', value: 'exit' },
      ]
    }]);
    if (accion === 'exit') process.exit(0);
    if (accion === 'fresh') {
      run(`rmdir /s /q "${REPO_DIR}"`, { shell: true });
      run(`rmdir /s /q "${path.join(SERVER_DIR, 'node_modules')}"`, { shell: true });
    }
    if (accion === 'repair') {
      run(`rmdir /s /q "${path.join(SERVER_DIR, 'node_modules')}"`, { shell: true });
    }
    console.log();
  }

  // ── Preguntar solo lo necesario ───────────────────────────
  console.log(chalk.cyan.bold('  Configuración'));
  console.log(chalk.gray('  ─────────────────────────────────────────────\n'));

  // Si ya hay .env, leer el teléfono existente
  let defaultPhone = '57';
  if (yaInstalado) {
    const envContent = fs.readFileSync(path.join(SERVER_DIR, '.env'), 'utf8');
    const match = envContent.match(/BOT_PHONE=(\d+)/);
    if (match) defaultPhone = match[1];
  }

  const { phone } = await inquirer.prompt([{
    type: 'input', name: 'phone',
    message: chalk.white('  Número WhatsApp del negocio (código país + número, sin +):'),
    default: defaultPhone,
    validate: v => /^\d{10,15}$/.test(v.trim()) || 'Formato inválido. Ejemplo: 573001234567',
    filter: v => v.trim(),
  }]);

  console.log(chalk.gray('\n  Resto de la configuración: pre-configurada automáticamente.'));
  console.log(chalk.gray(`  Servidor: https://${NGROK_DOMAIN}`));
  console.log(chalk.gray('  ngrok: configurado con authtoken oficial'));
  console.log();

  // ── Instalar herramientas ─────────────────────────────────
  let sp = ora({ color: 'green' }).start();

  const envPath = await ensureNode(sp);

  sp = ora({ color: 'green' }).start();
  await ensureGit(sp);

  sp = ora({ color: 'green' }).start();
  await ensureNgrok(sp, ngrokPATH());

  sp = ora({ color: 'green' }).start();
  await ensureServerCode(sp);

  sp = ora({ color: 'green' }).start();
  await ensureNpmDeps(sp, envPath);

  // ── Configurar .env ───────────────────────────────────────
  sp = ora({ text: 'Configurando variables de entorno...', color: 'green' }).start();
  writeEnv(phone);
  sp.succeed(chalk.green('.env configurado ✓'));

  // ── Configurar ngrok ──────────────────────────────────────
  sp = ora({ color: 'green' }).start();
  configureNgrok(sp, ngrokPATH());

  // ── Servicio Windows ──────────────────────────────────────
  sp = ora({ color: 'green' }).start();
  await stopExistingService(sp);

  sp = ora({ color: 'green' }).start();
  await installService(sp, envPath);

  // ── Esperar servidor ──────────────────────────────────────
  sp = ora({ color: 'green' }).start();
  await waitForServer(sp);

  // ── Pairing WhatsApp ──────────────────────────────────────
  console.log();
  console.log(chalk.yellow.bold('  ┌─────────────────────────────────────────────────┐'));
  console.log(chalk.yellow.bold('  │     VINCULAR WHATSAPP — LEE ESTO                │'));
  console.log(chalk.yellow.bold('  └─────────────────────────────────────────────────┘\n'));
  console.log(chalk.white('  Se abrirá una ventana con el CÓDIGO DE VINCULACIÓN.'));
  console.log(chalk.white('  Déjala abierta — el código aparece en ~10 segundos.\n'));
  console.log(chalk.cyan('  Pasos en tu teléfono:'));
  console.log(chalk.white('    1. Abre WhatsApp'));
  console.log(chalk.white('    2. Menú (⋮) → Dispositivos vinculados'));
  console.log(chalk.white('    3. Vincular un dispositivo'));
  console.log(chalk.white('    4. Vincular con número de teléfono'));
  console.log(chalk.white('    5. Ingresa el código que aparece en la ventana\n'));

  await inquirer.prompt([{
    type: 'input', name: 'x',
    message: chalk.cyan('  Presiona Enter para abrir la ventana del código...'),
  }]);

  launchBotWindow();

  await inquirer.prompt([{
    type: 'input', name: 'x',
    message: chalk.green('\n  ✓ Cuando la ventana diga "Bot WhatsApp CONECTADO", presiona Enter:'),
  }]);

  // ── Verificación final ────────────────────────────────────
  const serviceStatus = run(`sc query ${SVC_NAME}`);
  const running = serviceStatus && serviceStatus.includes('RUNNING');

  console.log();
  console.log(chalk.green('╔══════════════════════════════════════════════════╗'));
  if (running) {
    console.log(chalk.green('║') + chalk.green.bold('  ✅  SISTEMA INSTALADO Y ACTIVO                    ') + chalk.green('║'));
  } else {
    console.log(chalk.green('║') + chalk.yellow.bold('  ⚠️  INSTALADO — servicio iniciando                ') + chalk.green('║'));
  }
  console.log(chalk.green('╠══════════════════════════════════════════════════╣'));
  console.log(chalk.green('║') + chalk.white(`  App:     https://${NGROK_DOMAIN}/app/      `) + chalk.green('║'));
  console.log(chalk.green('║') + chalk.white(`  Estado:  https://${NGROK_DOMAIN}/health    `) + chalk.green('║'));
  console.log(chalk.green('║') + chalk.white('  El servicio inicia automáticamente con Windows   ') + chalk.green('║'));
  console.log(chalk.green('║') + chalk.white(`  Instalado en: ${INSTALL_DIR.padEnd(35)}`) + chalk.green('║'));
  console.log(chalk.green('╚══════════════════════════════════════════════════╝\n'));

  await inquirer.prompt([{ type: 'input', name: 'x', message: '  Presiona Enter para cerrar...' }]);
}

// ── Error handler global ──────────────────────────────────────
process.on('uncaughtException', async err => {
  console.error(chalk.red('\n  ✗ Error inesperado: ' + err.message));
  console.error(chalk.gray('  Detalle: ' + (err.stack?.split('\n')[1] || '')));
  console.log(chalk.yellow('\n  Si el error persiste, contacta al soporte.'));
  try { await inquirer.prompt([{ type: 'input', name: 'x', message: '  Presiona Enter para cerrar...' }]); } catch { /* */ }
  process.exit(1);
});

main().catch(async err => {
  console.error(chalk.red('\n  ✗ ' + err.message));
  try { await inquirer.prompt([{ type: 'input', name: 'x', message: '  Presiona Enter para cerrar...' }]); } catch { /* */ }
  process.exit(1);
});
