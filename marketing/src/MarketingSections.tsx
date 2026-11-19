import {
  ArrowRight,
  ArrowUpRight,
  ShieldCheck,
  MapPin,
  Wallet,
  KeyRound,
  CalendarCheck,
  Star,
  Check,
  ChevronDown,
  Camera,
  Landmark,
} from "lucide-react";
import { track } from "./analytics";

const guestSteps = [
  {
    title: "Verify your ID",
    body: "Your NIN and a selfie, once, before your first booking.",
  },
  {
    title: "Search",
    body: "Pick a location, dates and guests. Filter by price, bedrooms, type of place and amenities.",
  },
  {
    title: "Request your dates",
    body: "See the cancellation policy first, then send a request. The host approves it.",
  },
  {
    title: "Pay Oasis",
    body: "Once approved, you pay Oasis, not the host. We hold the money until after your stay.",
  },
  {
    title: "Check in, check out",
    body: "Enjoy the stay. If something’s wrong, report it before the host is paid.",
  },
];
const hostSteps = [
  {
    title: "Verify your ID",
    body: "Your NIN and a selfie, once, before you list.",
  },
  {
    title: "List your place",
    body: "A step-by-step flow: map pin, photos, a tour video, your price and house rules.",
  },
  {
    title: "Approve requests",
    body: "Every booking starts as a request. You decide who stays.",
  },
  {
    title: "Host the stay",
    body: "Guests check in and out at the times you set.",
  },
  {
    title: "Get paid",
    body: "Your payout lands in your Oasis vault 24 hours after checkout.",
  },
];
function Steps({
  id,
  label,
  steps,
}: {
  id?: string;
  label: string;
  steps: { title: string; body: string }[];
}) {
  return (
    <article className="track" id={id} aria-labelledby={`${label}-title`}>
      <h3 id={`${label}-title`}>
        <span className="label-lime">For {label}</span>
      </h3>
      <ol className="steps">
        {steps.map(({ title, body }, i) => (
          <li key={title}>
            <span className="step-number" aria-hidden="true">
              {String(i + 1).padStart(2, "0")}
            </span>
            <span>
              <b>{title}</b>
              <span>{body}</span>
            </span>
          </li>
        ))}
      </ol>
    </article>
  );
}
export function HowItWorks() {
  return (
    <section
      className="section container"
      id="how-it-works"
      aria-labelledby="how-title"
    >
      <div className="compact-heading">
        <span className="eyebrow">How it works</span>
        <h2 id="how-title">
          From first search
          <br />
          to checkout.
        </h2>
      </div>
      <div className="tracks">
        <Steps id="guests" label="guests" steps={guestSteps} />
        <Steps label="hosts" steps={hostSteps} />
      </div>
      <a
        className="text-link"
        href="#waitlist"
        onClick={() => track("Guest interest", { source: "how-it-works" })}
      >
        Be first to book a shortlet <ArrowRight size={17} aria-hidden="true" />
      </a>
    </section>
  );
}
const hostPoints = [
  {
    title: "Pin it on the map",
    body: "Drop a pin for your place. We check it against the address you give.",
  },
  {
    title: "Show it properly",
    body: "At least three photos and a tour video, so guests know what they’re booking.",
  },
  {
    title: "Set your terms",
    body: "Your nightly price, house rules, check-in and check-out times, and one of four cancellation policies.",
  },
  {
    title: "Add a caution fee",
    body: "Optional and refundable. Report damage in the short inspection window after checkout.",
  },
  {
    title: "Stay in control",
    body: "Approve every request yourself. Pause your place or remove it when you need to.",
  },
  {
    title: "Withdraw to your bank",
    body: "Payouts land in your Oasis vault. Withdraw to your bank with your vault PIN.",
  },
];
export function ForHosts() {
  return (
    <section className="hosts-section section" id="hosts" aria-labelledby="hosts-title">
      <div className="container hosts-grid">
        <div className="hosts-copy">
          <span className="label-lime">For hosts</span>
          <h2 id="hosts-title">
            Your place. Your rules.
            <br />
            Paid after every stay.
          </h2>
          <p>
            List your place in a few clear steps and approve every guest
            yourself. Guests pay Oasis, and your payout lands 24 hours after
            checkout.
          </p>
          <ul className="host-points">
            {hostPoints.map(({ title, body }) => (
              <li key={title}>
                <Check size={18} aria-hidden="true" />
                <span>
                  <b>{title}</b>
                  {body}
                </span>
              </li>
            ))}
          </ul>
          <a
            className="button"
            href="#waitlist"
            onClick={() => track("Host interest", { source: "hosts" })}
          >
            List your place <ArrowUpRight size={18} aria-hidden="true" />
          </a>
        </div>
        <figure className="listing-preview">
          <figcaption>
            <span>Example listing</span>
            <span className="badge">Ready to publish</span>
          </figcaption>
          <dl>
            <div>
              <dt>
                <MapPin size={17} aria-hidden="true" /> Place
              </dt>
              <dd>Two-bed apartment · Lekki Phase 1, Lagos</dd>
            </div>
            <div>
              <dt>
                <Camera size={17} aria-hidden="true" /> Media
              </dt>
              <dd>8 photos · tour video</dd>
            </div>
            <div>
              <dt>
                <Star size={17} aria-hidden="true" /> Best for
              </dt>
              <dd className="chip-row">
                <span>Staycation</span>
                <span>Baecation</span>
                <span>Work trip</span>
              </dd>
            </div>
            <div>
              <dt>
                <CalendarCheck size={17} aria-hidden="true" /> Cancellation
              </dt>
              <dd>Moderate</dd>
            </div>
            <div>
              <dt>
                <Wallet size={17} aria-hidden="true" /> Nightly price
              </dt>
              <dd>
                <strong>₦85,000</strong> / night
              </dd>
            </div>
          </dl>
          <p className="listing-preview-foot">
            <Landmark size={17} aria-hidden="true" />
            Payout to your vault 24 hours after checkout
          </p>
        </figure>
      </div>
    </section>
  );
}
const safety = [
  {
    icon: ShieldCheck,
    title: "ID checks for everyone",
    body: "Hosts and guests verify with their NIN and a selfie before booking or hosting. Oasis never stores your raw NIN.",
  },
  {
    icon: MapPin,
    title: "Pins checked against addresses",
    body: "When hosts list a place, its map pin is checked against the address they give.",
  },
  {
    icon: Wallet,
    title: "Money held until after the stay",
    body: "Guests pay Oasis, not the host. The host is paid 24 hours after checkout, unless the guest reports a problem first.",
  },
  {
    icon: KeyRound,
    title: "A refundable caution fee",
    body: "If a host asks for one, it comes back after checkout unless the host reports damage in a short inspection window.",
  },
  {
    icon: CalendarCheck,
    title: "Cancellation terms up front",
    body: "Flexible, Moderate, Strict or Non-refundable. You see the host’s policy before you request.",
  },
  {
    icon: Star,
    title: "Reviews from real stays",
    body: "Reviews only come from real, completed stays.",
  },
];
export function Safety() {
  return (
    <section className="safety-section section" id="safety" aria-labelledby="safety-title">
      <div className="container">
        <div className="compact-heading">
          <span className="eyebrow">Safety</span>
          <h2 id="safety-title">
            Trust, built into
            <br />
            every booking.
          </h2>
        </div>
        <ul className="safety-grid">
          {safety.map(({ icon: Icon, title, body }) => (
            <li key={title}>
              <span className="safety-icon">
                <Icon size={22} aria-hidden="true" />
              </span>
              <h3>{title}</h3>
              <p>{body}</p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
const occasions = [
  "Staycation",
  "Birthdays",
  "Baecation",
  "Parties",
  "Weekend getaway",
  "Work trip",
  "Family time",
  "Friends’ trip",
  "Photoshoots",
  "Weddings & owambe",
  "Holidays",
  "Long stays",
  "Airport stopover",
];
export function Occasions() {
  return (
    <section
      className="occasions-section section container"
      id="occasions"
      aria-labelledby="occasions-title"
    >
      <img
        src="/images/short-stay.webp"
        alt="Furnished living room with a sofa and soft daylight"
        width={768}
        height={480}
        loading="lazy"
        decoding="async"
      />
      <div>
        <span className="eyebrow">Best for</span>
        <h2 id="occasions-title">A place for every occasion.</h2>
        <p>Hosts say what their place is best for, so you can find the right one.</p>
        <ul className="occasion-chips">
          {occasions.map((name) => (
            <li key={name}>{name}</li>
          ))}
        </ul>
      </div>
    </section>
  );
}
export const faqs = [
  {
    question: "When does the host get paid?",
    answer:
      "Guests pay Oasis, not the host. The host’s payout lands in their Oasis vault 24 hours after checkout, unless the guest reports a problem first. Hosts then withdraw to their bank with their vault PIN.",
  },
  {
    question: "What is the caution fee?",
    answer:
      "An optional, refundable fee some hosts add to their place. It comes back to the guest after checkout, unless the host reports damage during a short inspection window.",
  },
  {
    question: "What if I cancel?",
    answer:
      "Each host chooses one of four cancellation policies: Flexible, Moderate, Strict or Non-refundable. You see the policy before you request, so you know the terms before you commit.",
  },
  {
    question: "How are hosts and guests verified?",
    answer:
      "Everyone verifies their ID with their NIN and a selfie before they can book or host. Oasis never stores your raw NIN.",
  },
  {
    question: "What if the place isn’t as listed?",
    answer:
      "Report the problem in the app. The host isn’t paid until 24 hours after checkout, and a problem reported before then stops the payout going through automatically. Every listing also needs real photos and a tour video, and its map pin is checked against its address.",
  },
  {
    question: "What does Oasis cost?",
    answer:
      "Fees aren’t final yet. Any fees will be shown before you pay.",
  },
];
export function FAQ() {
  return (
    <section className="faq-section section container" id="faq" aria-labelledby="faq-title">
      <div className="compact-heading">
        <span className="eyebrow">FAQ</span>
        <h2 id="faq-title">
          Fair questions.
          <br />
          Clear answers.
        </h2>
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
              <ChevronDown size={20} aria-hidden="true" />
            </summary>
            <p>{answer}</p>
          </details>
        ))}
      </div>
    </section>
  );
}
