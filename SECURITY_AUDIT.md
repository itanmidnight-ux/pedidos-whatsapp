# Auditoría de seguridad

Estado: revisado el 2026-08-11. El repositorio no contiene secretos reales ni archivos privados detectables.

## Corregido

- JWT restringido a `HS256` con `issuer` y `audience` configurables; evita aceptar tokens firmados con algoritmos o destinos inesperados.
- `TRUST_PROXY` y `CORS_ALLOW_CREDENTIALS` quedan desactivados por defecto.
- CORS usa una allowlist de dominios configurados, sin comodín.
- Body URL-encoded limitado a 2 MB y 100 parámetros.
- Consultas SQL parametrizadas, API key y firma HMAC del webhook con comparación constante.

## Riesgos residuales

- Algunas cargas multimedia validan MIME declarado; producción debe añadir inspección de contenido/magic bytes antes de publicar archivos.
- `SERVER_DOMAIN`, `JWT_SECRET`, `API_KEY`, `WEBHOOK_SECRET` y credenciales de base de datos deben existir solo en el entorno de despliegue.
- Usar HTTPS detrás de un proxy confiable y activar `TRUST_PROXY=true` únicamente allí.

Validación realizada: sintaxis JavaScript y revisión de rutas, middleware, almacenamiento y entradas del webhook.
