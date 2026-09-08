// Only fixed event names and non-personal props are sent. Never pass form values.
type EventName =
  | "Landlord interest"
  | "Tenant interest"
  | "Waitlist interest"
  | "Waitlist submit"
  | "Waitlist success"
  | "Waitlist error"
  | "FAQ opened"
  | "Product detail";
type Plausible = {
  (event: EventName, options?: { props?: Record<string, string> }): void;
  q?: unknown[][];
  init?: (options?: object) => void;
  o?: object;
};
declare global {
  interface Window {
    plausible?: Plausible;
  }
}
let enabled = false;
export function initializeAnalytics() {
  const scriptUrl = import.meta.env.VITE_PLAUSIBLE_SCRIPT_URL;
  if (
    !scriptUrl ||
    import.meta.env.DEV ||
    navigator.doNotTrack === "1" ||
    (navigator as Navigator & { globalPrivacyControl?: boolean })
      .globalPrivacyControl
  )
    return;
  let url: URL;
  try {
    url = new URL(scriptUrl);
  } catch {
    return;
  }
  if (url.protocol !== "https:") return;
  const queue: Plausible = function (...args) {
    (queue.q ??= []).push(args);
  };
  queue.init = (options) => {
    queue.o = options || {};
  };
  window.plausible = window.plausible || queue;
  window.plausible.init?.();
  const script = document.createElement("script");
  script.src = url.href;
  script.async = true;
  script.onerror = () => {
    enabled = false;
  };
  document.head.append(script);
  enabled = true;
}
export function track(event: EventName, props?: Record<string, string>) {
  if (!enabled || typeof window === "undefined") return;
  try {
    window.plausible?.(event, props ? { props } : undefined);
  } catch {
    /* Analytics never blocks the page or signup. */
  }
}
