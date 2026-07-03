import { useState } from 'react';

// Exposed via Module Federation as ./Widget — this is the only file the
// host (apps/frontend) imports. Anything not exported here (App.tsx,
// main.tsx, standalone dev shell) never ships to the host bundle.
export default function Widget() {
  const [count, setCount] = useState(0);
  const version = import.meta.env.VITE_MF_VERSION ?? 'dev';

  return (
    <div
      style={{
        border: '2px solid #B8860B',
        borderRadius: '10px',
        padding: '1rem 1.25rem',
        fontFamily: 'monospace',
        background: '#F1E1B4',
        color: '#1B231F',
        maxWidth: '360px',
      }}
    >
      <strong>micro-frontend/Widget</strong>
      <div style={{ fontSize: '0.8rem', opacity: 0.75, margin: '0.25rem 0 0.75rem' }}>
        loaded via remoteEntry.js · build {version}
      </div>
      <button type="button" onClick={() => setCount((c) => c + 1)}>
        clicked {count} times (state lives in the remote)
      </button>
    </div>
  );
}
