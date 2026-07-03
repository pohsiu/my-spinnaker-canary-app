import { Component, Suspense, type ReactNode } from 'react'

class RemoteErrorBoundary extends Component<
  { children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false }

  static getDerivedStateFromError() {
    return { failed: true }
  }

  render() {
    if (this.state.failed) {
      return (
        <p style={{ color: '#B5473F', fontFamily: 'monospace', fontSize: '0.85rem' }}>
          micro-frontend unavailable — remoteEntry.js failed to load
        </p>
      )
    }
    return this.props.children
  }
}

export default function RemoteBoundary({ children }: { children: ReactNode }) {
  return (
    <RemoteErrorBoundary>
      <Suspense fallback={<p style={{ fontFamily: 'monospace', fontSize: '0.85rem' }}>loading micro-frontend…</p>}>
        {children}
      </Suspense>
    </RemoteErrorBoundary>
  )
}
