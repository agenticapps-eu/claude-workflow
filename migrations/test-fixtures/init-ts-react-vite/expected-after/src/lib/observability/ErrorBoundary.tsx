// agenticapps:observability:start
//
// React ErrorBoundary — materialised by `/add-observability init`.
// Source template: add-observability/templates/ts-react-vite/ErrorBoundary.tsx
//
// Fixture stub — the real init produces the full class-component
// implementation with componentDidCatch + captureError integration.

import { Component, type ReactNode } from "react";

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
}

export class ObservabilityErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(_error: Error, _info: unknown): void {
    // Real implementation: forwards to captureError() from ./index.ts
  }

  render() {
    if (this.state.hasError) return this.props.fallback ?? null;
    return this.props.children;
  }
}
// agenticapps:observability:end
