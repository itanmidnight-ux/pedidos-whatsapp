'use strict';
const { getRedisClient, isRedisReady } = require('./redisClient');

// Store para express-rate-limit que usa Redis cuando esta disponible
// (compartido entre multiples instancias del server) y cae a un Map en
// memoria del proceso si Redis no esta configurado o falla a mitad de
// operacion -- asi una caida de Redis nunca tumba las rutas de la API.
class HybridRateLimitStore {
  constructor(prefix, windowMs) {
    this.prefix = prefix;
    this.windowMs = windowMs;
    this.memory = new Map(); // key -> { count, resetAt }
  }

  _memIncrement(key) {
    const now = Date.now();
    let rec = this.memory.get(key);
    if (!rec || rec.resetAt <= now) {
      rec = { count: 0, resetAt: now + this.windowMs };
      this.memory.set(key, rec);
    }
    rec.count += 1;
    return { totalHits: rec.count, resetTime: new Date(rec.resetAt) };
  }

  async increment(key) {
    const redis = getRedisClient();
    if (redis && isRedisReady()) {
      try {
        const rkey = this.prefix + key;
        const count = await redis.incr(rkey);
        if (count === 1) await redis.pexpire(rkey, this.windowMs);
        const ttl = await redis.pttl(rkey);
        return { totalHits: count, resetTime: new Date(Date.now() + (ttl > 0 ? ttl : this.windowMs)) };
      } catch (_e) {
        // Redis fallo a mitad de operacion -- cae a memoria para esta request.
      }
    }
    return this._memIncrement(key);
  }

  async decrement(key) {
    const redis = getRedisClient();
    if (redis && isRedisReady()) {
      try { await redis.decr(this.prefix + key); return; } catch (_e) { /* cae a memoria abajo */ }
    }
    const rec = this.memory.get(key);
    if (rec) rec.count = Math.max(0, rec.count - 1);
  }

  async resetKey(key) {
    const redis = getRedisClient();
    if (redis && isRedisReady()) {
      try { await redis.del(this.prefix + key); } catch (_e) { /* noop */ }
    }
    this.memory.delete(key);
  }
}

module.exports = HybridRateLimitStore;
