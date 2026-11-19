import { useEffect, useState } from "react";
import {
  HowItWorks,
  ForHosts,
  Safety,
  Occasions,
  FAQ,
} from "./MarketingSections";
import { track } from "./analytics";
import {
  ArrowUpRight,
  ArrowRight,
  Check,
  ShieldCheck,
  MapPin,
  BedDouble,
  Users,
  Search,
  SlidersHorizontal,
  Heart,
  ChevronRight,
  Bell,
  Wifi,
  BatteryFull,
  Signal,
  Wallet,
  KeyRound,
  CalendarCheck,
  Smartphone,
} from "lucide-react";

// Exact MaterialIcons codepoints from the guest bottom bar in
// lib/core/widgets/v2_main_scaffold.dart.
const appNavigationIcons = {
  home: "", // Icons.home_outlined
  discover: "", // Icons.explore_outlined
  trips: "", // Icons.luggage_outlined
  inbox: "", // Icons.chat_bubble_outline_rounded
  payments: "", // Icons.payments_outlined
};
const appNavigation: [keyof typeof appNavigationIcons, string][] = [
  ["home", "Home"],
  ["discover", "Discover"],
  ["trips", "Trips"],
  ["inbox", "Inbox"],
  ["payments", "Payments"],
];

function Wordmark({ className = "" }: { className?: string }) {
  return (
    <span className={`logo ${className}`}>
      <img
        src="/images/oasis-wordmark.webp"
        width={382}
        height={118}
        alt="Oasis"
      />
    </span>
  );
}
function Logo() {
  return (
    <a className="logo-link" href="/" aria-label="Oasis home">
      <Wordmark />
    </a>
  );
}
export function StoreBadges() {
  return (
    <ul className="store-badges" aria-label="App availability">
      <li>
        <Smartphone size={18} aria-hidden="true" />
        <span>
          <small>Coming soon to the</small>App Store
        </span>
      </li>
      <li>
        <Smartphone size={18} aria-hidden="true" />
        <span>
          <small>Coming soon to</small>Google Play
        </span>
      </li>
    </ul>
  );
}
function AppPreview() {
  return (
    <figure
      className="app-figure"
      role="img"
      aria-label="Example Oasis app screen: a two-bedroom shortlet in Lekki Phase 1, Lagos, from a verified host at ₦85,000 a night."
    >
      <div className="phone" aria-hidden="true">
        <div className="phone-status">
          <span>9:41</span>
          <span className="phone-island" />
          <span>
            <Signal size={13} />
            <Wifi size={13} />
            <BatteryFull size={17} />
          </span>
        </div>
        <div className="phone-content">
          <div className="app-top">
            <span className="logo preview-logo">
              <img
                src="/images/oasis-wordmark.webp"
                width={382}
                height={118}
                alt=""
              />
            </span>
            <Bell size={19} />
          </div>
          <div className="app-greeting">Good evening</div>
          <div className="app-screen-title">Where to next?</div>
          <div className="app-search">
            <Search size={16} />
            <span>Lekki, Lagos · 2 guests</span>
            <SlidersHorizontal size={17} />
          </div>
          <div className="app-chips">
            <span className="selected">Staycation</span>
            <span>Baecation</span>
            <span>Work trip</span>
          </div>
          <div className="app-section-label">
            <b>Shortlets near you</b>
            <span>View all</span>
          </div>
          <div className="listing">
            <div className="listing-photo">
              <img
                src="/images/room-interior.webp"
                width={560}
                height={560}
                fetchPriority="high"
                alt=""
              />
              <span className="verified-label">
                <ShieldCheck size={12} /> Verified host
              </span>
              <span className="listing-heart">
                <Heart size={15} />
              </span>
            </div>
            <div className="listing-info">
              <div className="app-listing-title">Bright two-bed apartment</div>
              <span className="location">
                <MapPin size={12} /> Lekki Phase 1, Lagos
              </span>
              <div className="amenities">
                <span>
                  <BedDouble size={14} /> 2 bedrooms
                </span>
                <span>
                  <Users size={14} /> 4 guests
                </span>
              </div>
              <div className="listing-bottom">
                <strong>
                  ₦85,000<span> / night</span>
                </strong>
                <ArrowUpRight size={18} />
              </div>
            </div>
          </div>
          <div className="app-next">
            <img
              src="/images/interior-thumb.webp"
              alt=""
              width={80}
              height={80}
              loading="lazy"
              decoding="async"
            />
            <div>
              <b>Weekend getaway</b>
              <span>Request sent · waiting for host</span>
            </div>
            <ChevronRight size={15} />
          </div>
        </div>
        <div className="app-bottom-nav">
          {appNavigation.map(([icon, label]) => (
            <span key={icon} className={icon === "discover" ? "active" : ""}>
              <i className="app-nav-icon">{appNavigationIcons[icon]}</i>
              {label}
            </span>
          ))}
        </div>
        <div className="phone-home" />
      </div>
    </figure>
  );
}
function Hero() {
  return (
    <>
      <section className="hero container">
        <div className="hero-copy">
          <span className="label-lime">Shortlets across Nigeria</span>
          <h1>
            Feel at home.
            <br />
            <span>Wherever you stay.</span>
          </h1>
          <p>
            Book verified shortlets by the night. Every host and guest checks
            their ID, and your payment is held by Oasis until after your stay.
          </p>
          <div className="hero-ctas">
            <a
              className="button"
              href="#waitlist"
              onClick={() => track("Guest interest", { source: "hero" })}
            >
              Be first to book <ArrowUpRight size={19} aria-hidden="true" />
            </a>
            <a
              className="button button-secondary"
              href="#hosts"
              onClick={() => track("Host interest", { source: "hero" })}
            >
              List your place <ArrowRight size={18} aria-hidden="true" />
            </a>
          </div>
          <StoreBadges />
        </div>
        <div className="hero-visual">
          <AppPreview />
        </div>
      </section>
      <ul className="promise-strip container" aria-label="The Oasis promise">
        <li>
          <ShieldCheck aria-hidden="true" />
          ID-verified hosts &amp; guests
        </li>
        <li>
          <Wallet aria-hidden="true" />
          Paid after your stay
        </li>
        <li>
          <KeyRound aria-hidden="true" />
          Refundable caution fee
        </li>
        <li>
          <CalendarCheck aria-hidden="true" />
          Clear cancellation terms
        </li>
      </ul>
    </>
  );
}
function App() {
  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <header className="header">
        <div className="container nav">
          <Logo />
          <nav className="nav-links" aria-label="Main">
            <a href="#how-it-works">How it works</a>
            <a href="#hosts">For hosts</a>
            <a href="#safety">Safety</a>
            <a href="#faq">FAQ</a>
          </nav>
          <a
            className="button button-small"
            href="#waitlist"
            onClick={() => track("Waitlist interest", { source: "header" })}
          >
            Join the waitlist <ArrowUpRight size={16} aria-hidden="true" />
          </a>
        </div>
      </header>
      <main id="main">
        <Hero />
        <HowItWorks />
        <ForHosts />
        <Safety />
        <Occasions />
        <FAQ />
        <Waitlist />
      </main>
      <Footer />
    </>
  );
}
function Waitlist() {
  return (
    <section
      className="waitlist section"
      id="waitlist"
      aria-labelledby="waitlist-title"
    >
      <div className="container">
        <span className="label-lime">Coming soon</span>
        <h2 id="waitlist-title">
          Better short stays
          <br />
          are on their way.
        </h2>
        <p>
          Oasis isn’t in the App Store or Google Play yet. Be first to hear when
          it opens for guests and hosts.
        </p>
        <WaitlistForm />
        <StoreBadges />
      </div>
    </section>
  );
}
function WaitlistForm() {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<
    "idle" | "loading" | "success" | "error"
  >("idle");
  const endpoint = import.meta.env.VITE_WAITLIST_ENDPOINT;
  const privacyUrl = import.meta.env.VITE_PRIVACY_URL;
  const [ready, setReady] = useState(false);
  useEffect(() => setReady(true), []);
  if (!endpoint)
    return (
      <p className="waitlist-closed" role="status">
        Sign-ups open soon. Check back here shortly.
      </p>
    );
  async function submit(event: React.SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!endpoint || status === "loading") return;
    setStatus("loading");
    track("Waitlist submit");
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim() }),
        signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) throw new Error("Request failed");
      setStatus("success");
      track("Waitlist success");
      setEmail("");
    } catch {
      setStatus("error");
      track("Waitlist error");
    }
  }
  const locked = !ready || status === "loading" || status === "success";
  return (
    <div className="waitlist-form-wrapper">
      <form
        className={`waitlist-form ${status === "loading" ? "submitting" : ""}`}
        onSubmit={submit}
      >
        <label className="sr-only" htmlFor="email">
          Email address
        </label>
        <input
          id="email"
          name="email"
          type="email"
          placeholder="Your email address"
          autoComplete="email"
          required
          maxLength={254}
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          disabled={locked}
        />
        <button className="button" type="submit" disabled={locked}>
          {status === "loading"
            ? "Joining…"
            : status === "success"
              ? "You’re on the list"
              : "Join the waitlist"}
          {status === "success" ? (
            <Check size={18} aria-hidden="true" />
          ) : (
            <ArrowUpRight size={18} aria-hidden="true" />
          )}
        </button>
      </form>
      <p className={`form-status ${status}`} aria-live="polite">
        {status === "success" ? (
          "You’re on the list. We’ll email you when Oasis is ready."
        ) : status === "error" ? (
          "We couldn’t save your email. Please try again."
        ) : (
          <>
            By joining, you agree to receive Oasis launch updates.
            {privacyUrl ? (
              <>
                {" "}
                Read our <a href={privacyUrl}>Privacy policy</a>.
              </>
            ) : null}
          </>
        )}
      </p>
      <noscript>
        <p className="form-status">
          JavaScript is needed to join the waitlist.
        </p>
      </noscript>
    </div>
  );
}
function Footer() {
  const links = [
    ["Privacy", import.meta.env.VITE_PRIVACY_URL],
    ["Terms", import.meta.env.VITE_TERMS_URL],
    ["Contact", import.meta.env.VITE_CONTACT_URL],
  ];
  return (
    <footer className="footer">
      <div className="container">
        <div className="footer-top">
          <Logo />
          <span>Feel at home. Wherever you stay.</span>
        </div>
        <nav className="footer-sections" aria-label="Explore Oasis">
          <a href="#guests">For guests</a>
          <a href="#hosts">For hosts</a>
          <a href="#safety">Safety</a>
          <a href="#faq">FAQ</a>
        </nav>
        <div className="footer-bottom">
          <span>© {new Date().getFullYear()} Oasis</span>
          <nav aria-label="Legal and contact">
            {links.map(([label, url]) =>
              url ? (
                <a key={label} href={url}>
                  {label}
                </a>
              ) : (
                <span key={label}>
                  {label}{" "}
                  <span className="sr-only">(available before launch)</span>
                </span>
              ),
            )}
          </nav>
          <span>Made for life in Nigeria</span>
        </div>
      </div>
    </footer>
  );
}
export default App;
