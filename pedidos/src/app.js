const express = require('express');
const pool = require('./db');

const app = express();

app.use(express.json());

const USUARIOS_URL = process.env.USUARIOS_URL || 'http://usuarios:3001';
const PRODUCTOS_URL = process.env.PRODUCTOS_URL || 'http://productos:3002';

app.get('/health', (req, res) => {
  res.json({ estado: 'ok', servicio: 'pedidos' });
});

app.get('/pedidos', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM pedidos');
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al consultar pedidos' });
  }
});

// Consulta a otro microservicio si existe un registro con ese id
async function existeEn(url, id) {
  const respuesta = await fetch(url);
  if (!respuesta.ok) {
    throw new Error(`No se pudo consultar ${url}`);
  }
  const datos = await respuesta.json();
  return datos.some((item) => item.id === id);
}

app.post('/pedidos', async (req, res) => {
  const usuarioId = Number(req.body.usuario_id);
  const productoId = Number(req.body.producto_id);
  const cantidad = Number(req.body.cantidad);

  if (!Number.isInteger(usuarioId) || !Number.isInteger(productoId) ||
      !Number.isInteger(cantidad) || cantidad <= 0) {
    return res.status(400).json({
      estado: 'rechazado',
      error: 'usuario_id, producto_id y cantidad deben ser números enteros válidos'
    });
  }

  try {
    if (!(await existeEn(`${USUARIOS_URL}/usuarios`, usuarioId))) {
      return res.status(404).json({ estado: 'rechazado', error: `El usuario ${usuarioId} no existe` });
    }
    if (!(await existeEn(`${PRODUCTOS_URL}/productos`, productoId))) {
      return res.status(404).json({ estado: 'rechazado', error: `El producto ${productoId} no existe` });
    }

    const result = await pool.query(
      'INSERT INTO pedidos (usuario_id, producto_id, cantidad) VALUES ($1, $2, $3) RETURNING *',
      [usuarioId, productoId, cantidad]
    );
    res.status(201).json({ estado: 'aceptado', pedido: result.rows[0] });
  } catch (error) {
    console.error(error);
    res.status(503).json({
      estado: 'error',
      error: 'No se pudo validar el pedido con los servicios de usuarios o productos'
    });
  }
});

module.exports = app;
