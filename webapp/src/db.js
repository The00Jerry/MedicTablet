'use strict';
// MySQL-Pool (mysql2/promise). Ausschliesslich parametrisierte Queries.
const mysql = require('mysql2/promise');
const cfg = require('./config');

const pool = mysql.createPool({
  host: cfg.db.host,
  port: cfg.db.port,
  user: cfg.db.user,
  password: cfg.db.password,
  database: cfg.db.database,
  waitForConnections: true,
  connectionLimit: 10,
  namedPlaceholders: false,
  charset: 'utf8mb4',
});

async function query(sql, params) {
  const [rows] = await pool.execute(sql, params || []);
  return rows;
}
async function single(sql, params) {
  const rows = await query(sql, params);
  return rows[0] || null;
}
async function scalar(sql, params) {
  const row = await single(sql, params);
  if (!row) return null;
  return row[Object.keys(row)[0]];
}
async function insert(sql, params) {
  const [res] = await pool.execute(sql, params || []);
  return res.insertId;
}
async function update(sql, params) {
  const [res] = await pool.execute(sql, params || []);
  return res.affectedRows;
}

module.exports = { pool, query, single, scalar, insert, update };
