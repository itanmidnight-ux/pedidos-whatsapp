const express = require('express');
const router  = express.Router();
const jwt     = require('jsonwebtoken');
const bcrypt  = require('bcrypt');
const { getDB } = require('../db/database');

function signToken(user) {
  const token = jwt.sign(
    { id: user.id, username: user.username, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: '30d' }
  );
  return { token, username: user.username, display_name: user.display_name || user.username, role: user.role };
}

// POST /api/auth/token — login por username+contraseña
router.post('/token', (req, res) => {
  const { username, password, pin } = req.body;
  if (!username || typeof username !== 'string' || !username.trim())
    return res.status(400).json({ error: 'Usuario requerido' });

  const credential = password !== undefined ? String(password) : (pin !== undefined ? String(pin) : '');
  if (!credential.length) return res.status(400).json({ error: 'Contraseña requerida' });

  const db   = getDB();
  const user = db.prepare('SELECT * FROM users WHERE username = ? AND active = 1').get(username.trim().toLowerCase());
  if (!user) return res.status(401).json({ error: 'Credenciales incorrectas' });

  bcrypt.compare(credential, user.pin || user.password_hash, (err, match) => {
    if (err || !match) return res.status(401).json({ error: 'Credenciales incorrectas' });
    res.json(signToken(user));
  });
});

module.exports = router;
