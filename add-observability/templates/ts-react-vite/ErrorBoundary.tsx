/**
 * ObservabilityErrorBoundary — AgenticApps spec §10.4 #3 for React.
 *
 * Wraps the React tree to catch render-time and lifecycle errors and
 * report them via captureError. Use as the outermost component inside
 * <StrictMode>:
 *
 *   import { ObservabilityErrorBoundary } from "./lib/observability/ErrorBoundary"
 *
 *   createRoot(document.getElementById("root")!).render(
 *     <StrictMode>
 *       <ObservabilityErrorBoundary>
 *         <App />
 *       </ObservabilityErrorBoundary>
 *     </StrictMode>
 *   )
 *
 * Async errors inside event handlers and effects are NOT caught by React
 * error boundaries — for those, call captureError directly in the catch
 * block, or use the withSpan helper which wires it automatically.
 */

import { Component, type ErrorInfo, type ReactNode } from "react";
import { captureError } from "./index";

interface Props {
  children: ReactNode;
  /**
   * Fallback UI shown when an error is caught. Defaults to a minimal
   * "Something went wrong" message; override in production projects with
   * a branded error screen.
   */
  fallback?: (error: Error, reset: () => void) => ReactNode;
}

interface State {
  error: Error | null;
}

export class ObservabilityErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    captureError(error, {
      event: "react_error_boundary",
      severity: "error",
      attrs: {
        component_stack: info.componentStack ?? "",
      },
    });
  }

  reset = (): void => {
    this.setState({ error: null });
  };

  render(): ReactNode {
    if (this.state.error) {
      if (this.props.fallback) {
        return this.props.fallback(this.state.error, this.reset);
      }
      return (
        <div role="alert" style={{ padding: "1rem", fontFamily: "sans-serif" }}>
          <h1>Something went wrong</h1>
          <p>The error has been reported. Try reloading the page.</p>
          <button onClick={this.reset}>Try again</button>
        </div>
      );
    }
    return this.props.children;
  }
}
