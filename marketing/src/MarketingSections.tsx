import {
  ArrowRight,
  ArrowUpRight,
  ShieldCheck,
  House,
  FileCheck2,
  LockKeyhole,
  Fingerprint,
  Wallet,
  Landmark,
  CalendarDays,
  Check,
  ChevronDown,
} from "lucide-react";
import { track } from "./analytics";

export function Landlords() {
  return (
    <section className="landlords-section section container" id="landlords">
      <div className="landlord-copy">
        <span className="eyebrow">For landlords</span>
        <h2>
          Your property.
          <br />
          One clear view.
        </h2>
        <p>
          List units, choose verified tenants and sign in-app. Track rent
          through to your bank.
        </p>
        <ol className="owner-steps">
          <li>
            <span>01</span>Verify your identity
          </li>
          <li>
            <span>02</span>Add your property and units
          </li>
          <li>
            <span>03</span>Choose a tenant and sign
          </li>
        </ol>
        <a
          className="button"
          href="#waitlist"
          onClick={() => track("Landlord interest", { source: "landlords" })}
        >
          Join as a landlord <ArrowUpRight size={18} />
        </a>
      </div>
      <figure className="portfolio-preview">
        <div className="portfolio-top">
          <span>
            <House size={20} /> Your portfolio
          </span>
          <span className="badge">Preview</span>
        </div>
        <div className="portfolio-summary">
          <strong>
            Every unit.
            <br />
            Accounted for.
          </strong>
          <span>Yearly rent + short stays</span>
        </div>
        <div className="unit-row">
          <span className="unit-mark">A1</span>
          <span>
            <b>Two-bedroom apartment</b>
            <small>Annual tenancy</small>
          </span>
          <span className="badge">Occupied</span>
        </div>
        <div className="unit-row">
          <span className="unit-mark">A2</span>
          <span>
            <b>One-bedroom apartment</b>
            <small>Open for applications</small>
          </span>
          <span className="badge vacant">Available</span>
        </div>
        <div className="unit-row">
          <span className="unit-mark">B1</span>
          <span>
            <b>Furnished studio</b>
            <small>Nightly stays</small>
          </span>
          <span className="badge reserved">Reserved</span>
        </div>
        <div className="portfolio-bottom">
          <FileCheck2 size={17} />
          <span>Applications → agreements → rent → payouts</span>
        </div>
      </figure>
    </section>
  );
}
const promises = [
  {
    icon: House,
    title: "Homes you can trust",
    body: "Real photos, clear prices and a checked landlord. Find your area and apply in-app.",
  },
  {
    icon: FileCheck2,
    title: "Sign the lease right here",
    body: "Both parties review and sign one agreement. Your copy stays in your vault.",
  },
  {
    icon: LockKeyhole,
    title: "Rent that stays protected",
    body: "Pay into escrow and follow the release status in-app. Read the money FAQs below.",
  },
  {
    icon: Fingerprint,
    title: "Everyone here is verified",
    body: "Landlords and tenants complete identity checks before they can transact.",
  },
];
export function ProductPromises() {
  return (
    <section className="product-section section" id="product">
      <div className="container">
        <div className="compact-heading">
          <span className="eyebrow">For tenants · The Oasis way</span>
          <h2>
            From first search
            <br />
            to your own front door.
          </h2>
        </div>
        <div className="compact-promises">
          {promises.map(({ icon: Icon, title, body }, i) => (
            <article key={title}>
              <span className="promise-index">
                0{i + 1}
                <Icon size={23} />
              </span>
              <h3>{title}</h3>
              <p>{body}</p>
            </article>
          ))}
        </div>
        <a
          className="text-link"
          href="#waitlist"
          onClick={() => track("Tenant interest", { source: "product" })}
        >
          Find your place with Oasis <ArrowRight size={17} />
        </a>
      </div>
    </section>
  );
}
export function MoneyAndStays() {
  return (
    <section className="section container" id="money-and-stays">
      <div className="compact-heading">
        <span className="eyebrow">More than the yearly rent</span>
        <h2>
          A year. A night.
          <br />
          Every naira.
        </h2>
      </div>
      <div className="services-grid">
        <article className="service-card">
          <img
            src="/images/short-stay.webp"
            alt="Furnished living room used to illustrate a short stay"
            width={768}
            height={480}
            loading="lazy"
            decoding="async"
          />
          <div className="service-copy">
            <span className="service-label">
              <CalendarDays size={18} /> Stays
            </span>
            <h3>Same units. Shorter stays.</h3>
            <p>
              Offer nightly listings alongside annual rentals, with check-in and
              check-out in one place.
            </p>
            <details
              onToggle={(e) => {
                if (e.currentTarget.open)
                  track("Product detail", { section: "stays" });
              }}
            >
              <summary>
                The booking flow <ChevronDown size={16} />
              </summary>
              <p>
                Request → host approval → a 24-hour payment window → check-in.
                Host payout is held until check-in; caution-fee claims and
                disputes stay attached to the booking.
              </p>
            </details>
          </div>
        </article>
        <article className="service-card">
          <div
            className="money-illustration"
            aria-label="Illustrative vault ledger"
          >
            <div className="ledger-top">
              <Wallet size={25} />
              <span>YOUR VAULT</span>
            </div>
            <div className="ledger-row">
              <span>Top-up</span>
              <b>+ ₦300,000</b>
            </div>
            <div className="ledger-row">
              <span>Rent payment</span>
              <b>− ₦250,000</b>
            </div>
            <div className="ledger-balance">
              <span>Running balance</span>
              <strong>₦50,000</strong>
            </div>
          </div>
          <div className="service-copy">
            <span className="service-label">
              <Wallet size={18} /> Vault
            </span>
            <h3>A record of every naira.</h3>
            <p>
              Top-ups, withdrawals and receipts, with a running balance and a
              PIN to protect your wallet.
            </p>
          </div>
        </article>
        <article className="service-card">
          <div className="money-illustration payout-illustration">
            <Landmark size={34} />
            <div className="payout-step">
              <Check size={15} /> Save your Nigerian bank account
            </div>
            <div className="payout-step">
              <LockKeyhole size={15} /> Follow the release status
            </div>
            <div className="payout-step">
              <ArrowUpRight size={15} /> Receive your payout
            </div>
          </div>
          <div className="service-copy">
            <span className="service-label">
              <Landmark size={18} /> Payouts
            </span>
            <h3>From rent to your bank.</h3>
            <p>
              Landlord payouts reach your saved bank account automatically. The
              app shows the applicable release schedule.
            </p>
          </div>
        </article>
      </div>
    </section>
  );
}
export function CraftAndTrust() {
  return (
    <section className="craft-trust section">
      <div className="container">
        <div className="trust-line" id="trust">
          <ShieldCheck size={29} />
          <div>
            <h2>Trust, built into the details.</h2>
            <p>
              NIN + selfie checks. We store only a tokenised fingerprint,
              never your raw NIN. Reviews follow actual transactions.
            </p>
          </div>
        </div>
        <div id="how-we-build" className="build-principles">
          <div>
            <span className="eyebrow">How we build</span>
            <h3>
              Less friction.
              <br />
              More certainty.
            </h3>
          </div>
          <div>
            <h3>Places, picked correctly.</h3>
            <p>One shared list of Nigerian states and towns.</p>
          </div>
          <div>
            <h3>Your records stay put.</h3>
            <p>
              Property removal has a seven-day cooling-off period. Agreements
              and receipts remain accessible.
            </p>
          </div>
          <div>
            <h3>Comfort after hours.</h3>
            <p>Warm dark mode when you want it. Light mode by default.</p>
          </div>
        </div>
        <p className="fix-caption">
          Need a hand? <b>Oasis Fix</b> helps you find and call verified
          artisans. Arrange repairs directly.
        </p>
      </div>
    </section>
  );
}
export const faqs = [
  {
    question: "Who holds my money?",
    answer:
      "Rent is paid into escrow rather than directly to the landlord. The escrow provider and custody arrangements have not yet been confirmed for publication. Those details will need to be available before you pay.",
  },
  {
    question: "What does Oasis cost?",
    answer:
      "Fees are still being finalized. We cannot quote listing, booking, payment or withdrawal charges yet. Do not assume a service is free; review the final charges before using it.",
  },
  {
    question: "What if the landlord does not hand over the keys?",
    answer:
      "Escrow is intended to protect rent until handover. The failed-handover process, dispute rules and refund timelines are still being finalized. A refund outcome or timeline cannot be confirmed until that policy is published.",
  },
  {
    question: "Can I offer both yearly rentals and short stays?",
    answer:
      "Yes. Oasis supports annual tenancies and nightly listings on the same property units. Short-stay requests need host approval, then payment within the booking window.",
  },
];
export function FAQ() {
  return (
    <section className="faq-section section container" id="faq">
      <div className="compact-heading">
        <span className="eyebrow">Before you commit</span>
        <h2>
          Fair questions.
          <br />
          Clear answers.
        </h2>
        <p>What is confirmed and what is still being finalized.</p>
      </div>
      <div className="faq-list">
        {faqs.map(({ question, answer }, i) => (
          <details
            key={question}
            onToggle={(e) => {
              if (e.currentTarget.open)
                track("FAQ opened", { question: String(i + 1) });
            }}
          >
            <summary>
              {question}
              <ChevronDown size={20} />
            </summary>
            <p>{answer}</p>
          </details>
        ))}
      </div>
    </section>
  );
}
