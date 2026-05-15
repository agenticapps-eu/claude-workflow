import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
// agenticapps:observability:start
import { init, ObservabilityErrorBoundary } from "./lib/observability";
// agenticapps:observability:end
import App from "./App";
import "./index.css";

// agenticapps:observability:start
init();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ObservabilityErrorBoundary>
      <App />
    </ObservabilityErrorBoundary>
  </StrictMode>,
);
// agenticapps:observability:end
