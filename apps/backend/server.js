const path = require('path');
const express = require('express');
const client = require('prom-client');

const app = express();
const port = process.env.PORT || 3000;

client.collectDefaultMetrics();

const httpRequestDurationMicroseconds = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'code'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5]
});

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'code']
});

app.get('/api/hello', (req, res) => {
  const end = httpRequestDurationMicroseconds.startTimer();

  const isError = Math.random() < 0.02;
  setTimeout(() => {
    const code = isError ? 500 : 200;
    if (isError) {
      res.status(500).json({ error: 'Internal Server Error' });
    } else {
      res.json({ message: 'Hello World from the backend!' });
    }
    end({ method: 'GET', route: '/api/hello', code });
    httpRequestsTotal.inc({ method: 'GET', route: '/api/hello', code });
  }, Math.random() * 200);
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

const frontendDist = path.join(__dirname, '..', 'frontend', 'dist');
app.use(express.static(frontendDist));
app.get(/^(?!\/api|\/metrics).*/, (req, res) => {
  res.sendFile(path.join(frontendDist, 'index.html'), (err) => {
    if (err) {
      res
        .status(404)
        .send('Frontend build not found — run `npm run build --workspace=frontend` first.');
    }
  });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
