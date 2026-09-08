import { useEffect, useState } from "react";
import {
  Landlords,
  ProductPromises,
  MoneyAndStays,
  CraftAndTrust,
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
  Bath,
  Search,
  SlidersHorizontal,
  Heart,
  Sun,
  Moon,
  FileCheck2,
  LockKeyhole,
  ChevronRight,
  Bell,
  Wifi,
  BatteryFull,
  Signal,
  KeyRound,
} from "lucide-react";

// Exact MaterialIcons codepoints from Flutter's CustomBottomNavbar.
const appNavigationIcons = {
  dashboard: "\uf0d7", // Icons.grid_view_outlined
  discover: "\uf037", // Icons.explore_outlined
  stays: "\uf104", // Icons.holiday_village_outlined
  payments: "\uf266", // Icons.payments_outlined
};

function AppNavigationIcon({
  name,
}: {
  name: keyof typeof appNavigationIcons;
}) {
  return (
    <i className="app-nav-icon" aria-hidden="true">
      {appNavigationIcons[name]}
    </i>
  );
}

function Wordmark({ className = "" }: { className?: string }) {
  return (
    <span className={`logo ${className}`} role="img" aria-label="Landa OS">
      <span className="logo-base" />
      <span className="logo-os" />
    </span>
  );
}
function Logo() {
  return (
    <a href="#" aria-label="Landa OS home">
      <Wordmark />
    </a>
  );
}
function AppPreview() {
  return (
    <figure className="app-figure" aria-label="Landa Discover preview">
      <div className="phone">
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
            <Wordmark className="preview-logo" />
            <Bell size={19} />
          </div>
          <div className="app-greeting">A place to call yours.</div>
          <div className="app-screen-title">Find your next home</div>
          <div className="app-search">
            <Search size={16} />
            <span>Lekki, Lagos</span>
            <SlidersHorizontal size={17} />
          </div>
          <div className="app-chips">
            <span className="selected">For rent</span>
            <span>Short stays</span>
          </div>
          <div className="app-section-label">
            <b>Homes for you</b>
            <span>View all</span>
          </div>
          <div className="listing">
            <div className="listing-photo">
              <img
                src="/images/room-interior.webp"
                width={560}
                height={560}
                fetchPriority="high"
                alt="Bright living room with large windows and a blue sofa"
              />
              <span className="verified-label">
                <ShieldCheck size={12} /> Verified landlord
              </span>
              <span className="listing-heart">
                <Heart size={15} />
              </span>
            </div>
            <div className="listing-info">
              <div className="app-listing-title">
                A little more room to live.
              </div>
              <span className="location">
                <MapPin size={12} /> Lekki Phase 1, Lagos
              </span>
              <div className="amenities">
                <span>
                  <BedDouble size={14} /> 2 beds
                </span>
                <span>
                  <Bath size={14} /> 2 baths
                </span>
              </div>
              <div className="listing-bottom">
                <strong>
                  ₦2,500,000<span> / year</span>
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
              <b>Your next chapter, here.</b>
              <span>Explore verified homes</span>
            </div>
            <ChevronRight size={15} />
          </div>
        </div>
        <div className="app-bottom-nav">
          <span>
            <AppNavigationIcon name="dashboard" />
            Dashboard
          </span>
          <span className="active">
            <AppNavigationIcon name="discover" />
            Discover
          </span>
          <span>
            <AppNavigationIcon name="stays" />
            Stays
          </span>
          <span>
            <AppNavigationIcon name="payments" />
            Payments
          </span>
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
          <span className="eyebrow hero-eyebrow">
            <span className="live-dot" /> A better way to rent in Nigeria
          </span>
          <h1>
            Feel at home.
            <br />
            <span>
              Before you
              <br className="desktop-break" /> move in.
            </span>
          </h1>
          <p>
            Verified homes. Agreements signed in the app. Rent held in escrow
            until the keys change hands.
          </p>
          <div className="hero-ctas">
            <a
              className="button"
              href="#landlords"
              onClick={() => track("Landlord interest", { source: "hero" })}
            >
              Bring your property to Landa <ArrowUpRight size={19} />
            </a>
            <a
              className="text-link"
              href="#product"
              onClick={() => track("Tenant interest", { source: "hero" })}
            >
              Looking for a home? <ArrowRight size={16} />
            </a>
          </div>
          <div className="hero-note">
            <ShieldCheck size={17} />
            <span>Real people. Verified from day one.</span>
          </div>
        </div>
        <div className="hero-visual">
          <div className="visual-heading">
            <span>YOUR NEXT CHAPTER</span>
            <span>01 / DISCOVER</span>
          </div>
          <AppPreview />
        </div>
      </section>
      <div className="promise-strip container">
        <span>
          <ShieldCheck />
          Verified people
        </span>
        <span>
          <FileCheck2 />
          Agreements in-app
        </span>
        <span>
          <LockKeyhole />
          Rent in escrow
        </span>
        <span>
          <KeyRound />
          Peace of mind
        </span>
      </div>
    </>
  );
}
function App() {
  const [theme, setTheme] = useState("light");
  useEffect(() => {
    setTheme(
      document.documentElement.dataset.theme === "dark" ? "dark" : "light",
    );
  }, []);
  function toggleTheme() {
    const next = theme === "light" ? "dark" : "light";
    setTheme(next);
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem("landa-theme", next);
    } catch {}
  }
  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <header className="header">
        <div className="container nav">
          <Logo />
          <div className="nav-actions">
            <button
              className="icon-button theme-toggle"
              onClick={toggleTheme}
              aria-label={`Switch to ${theme === "light" ? "dark" : "light"} mode`}
            >
              {theme === "light" ? <Moon size={19} /> : <Sun size={19} />}
            </button>
            <a
              className="button button-small"
              href="#waitlist"
              onClick={() => track("Waitlist interest", { source: "header" })}
            >
              Join the waitlist <ArrowUpRight size={16} />
            </a>
          </div>
        </div>
      </header>
      <main id="main">
        <Hero />
        <Landlords />
        <ProductPromises />
        <MoneyAndStays />
        <CraftAndTrust />
        <FAQ />
        <Waitlist />
      </main>
      <Footer />
    </>
  );
}
function Waitlist() {
  return (
    <section className="waitlist section container" id="waitlist">
      <span className="eyebrow">Make yourself at home</span>
      <h2>
        A better way to rent
        <br />
        is on its way.
      </h2>
      <p>Be first to hear when Landa is ready for you.</p>
      <WaitlistForm />
      <noscript>
        <p>
          JavaScript is needed to submit the waitlist form when registration
          opens.
        </p>
      </noscript>
      <span className="waitlist-note">
        Built for Nigeria. Made for your peace of mind.
      </span>
    </section>
  );
}
function WaitlistForm() {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<
    "idle" | "loading" | "success" | "error"
  >("idle");
  const endpoint = import.meta.env.VITE_WAITLIST_ENDPOINT;
  const [ready, setReady] = useState(false);
  useEffect(() => setReady(true), []);
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
          disabled={
            !ready || !endpoint || status === "loading" || status === "success"
          }
        />
        <button
          className="button"
          type="submit"
          disabled={
            !ready || !endpoint || status === "loading" || status === "success"
          }
        >
          {status === "loading"
            ? "Joining…"
            : status === "success"
              ? "You’re on the list"
              : "Join the waitlist"}
          {status === "success" ? (
            <Check size={18} />
          ) : (
            <ArrowUpRight size={18} />
          )}
        </button>
      </form>
      <p className={`form-status ${status}`} aria-live="polite">
        {!endpoint
          ? "Waitlist registration is opening soon."
          : status === "success"
            ? "You’re on the list. We’ll email you when Landa is ready."
            : status === "error"
              ? "We couldn’t save your email. Please try again."
              : "By joining, you agree to receive Landa launch updates."}
      </p>
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
    <footer className="footer container">
      <div>
        <Logo />
        <span>Home starts with trust.</span>
      </div>
      <nav className="footer-sections" aria-label="Explore Landa">
        <a href="#landlords">For landlords</a>
        <a href="#product">For tenants</a>
        <a href="#money-and-stays">Stays & money</a>
        <a href="#how-we-build">How we build</a>
        <a href="#trust">Trust</a>
        <a href="#faq">FAQs & fees</a>
      </nav>
      <div className="footer-bottom">
        <span>© {new Date().getFullYear()} Landa OS</span>
        <nav aria-label="Footer">
          {links.map(([label, url]) =>
            url ? (
              <a key={label} href={url}>
                {label}
              </a>
            ) : (
              <span
                key={label}
                title={`${label} information will be available before launch`}
              >
                {label}{" "}
                <span className="sr-only">(available before launch)</span>
              </span>
            ),
          )}
        </nav>
        <span>
          Made for life in Nigeria{" "}
          <span className="nigeria-mark" aria-hidden="true" />
        </span>
      </div>
    </footer>
  );
}
export default App;
