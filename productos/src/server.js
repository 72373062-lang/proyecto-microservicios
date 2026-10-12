require('dotenv').config();
const app = require('./app');

const PORT = process.env.PORT || 3002;

app.listen(PORT, () => {
  console.log(`Servicio de Productos ejecutándose en http://localhost:${PORT}`);
});
