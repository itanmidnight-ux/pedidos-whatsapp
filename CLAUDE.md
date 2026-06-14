# CLAUDE.md — Instrucciones para Claude Code

## Token Optimization (SIEMPRE)
- Responder en caveman ultra mode por defecto
- Usar grep/glob antes de read para localizar código
- Leer solo secciones relevantes (offset+limit)
- Delegar búsquedas amplias a subagentes (cavecrew-investigator)
- Preferir Edit sobre Write para archivos existentes
- No añadir comentarios salvo WHY no obvio

## Herramientas a usar
- caveman ultra: toda respuesta
- cavecrew-investigator: búsquedas en codebase amplias
- cavecrew-builder: edits de 1-2 archivos
- ui-ux-pro-max: cambios de UI/Flutter
- claude-mem: memoria del proyecto entre sesiones
- Firecrawl MCP: scraping docs externos
- Playwright MCP: testing UI browser

## Stack del proyecto
- Backend: Node.js 20 + Express + better-sqlite3 (WAL)
- Bot: @whiskeysockets/baileys v6.7.9 (no Puppeteer)
- LLM: Ollama llama3.2:1b (parser híbrido + reglas fuzzy) + @nlpjs/basic
- Tunnel: ngrok dominio fijo
- App: Flutter 3.44 (Android + Web/PWA)
- OS dev: Linux Kali (build APK vía compilar-apk.ps1 en Windows)

## Reglas de código
- Sin error handling para casos imposibles
- Sin backwards-compatibility shims
- Validar solo en boundaries (input usuario, APIs externas)
- DB siempre async (better-sqlite3 WAL mode)
- Nombres de empleados desde DB, no hardcoded
