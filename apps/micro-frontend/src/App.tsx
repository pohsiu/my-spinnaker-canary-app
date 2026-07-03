import Widget from './Widget';

// Standalone dev shell — renders exactly what the host consumes via
// Module Federation, so `npm run dev` here previews the real thing.
function App() {
  return (
    <div style={{ padding: '2rem', fontFamily: 'system-ui' }}>
      <p style={{ color: '#4A554C', marginBottom: '1rem' }}>
        Standalone preview of <code>micro-frontend</code>. In apps/frontend this
        renders inside the host shell instead.
      </p>
      <Widget />
    </div>
  );
}

export default App;
