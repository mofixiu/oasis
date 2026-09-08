import React from "react";
import { createRoot, hydrateRoot } from "react-dom/client";
import App from "./App";
import { initializeAnalytics } from "./analytics";
import "./fonts.css";
import "./styles.css";
const container = document.getElementById("root")!;
const app = (
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
if (container.hasChildNodes()) hydrateRoot(container, app);
else createRoot(container).render(app);
initializeAnalytics();
