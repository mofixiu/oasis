# Oasis — Marketing Website Brief

Everything a designer or developer needs to build the Oasis website without opening the
Flutter project. Written for a **minimal** site: a lot of white space, few colours,
big screenshots, short sentences.

---

## 1. What Oasis is

Oasis is a Nigerian **shortlet** app. Guests book verified short stays by the night;
hosts list their places. (The old yearly-rentals product with landlords, tenants,
agreements and rent is switched off. Do not mention it.)

| Role | What they do in Oasis |
|---|---|
| **Guest** | Searches shortlets, requests dates, pays Oasis once the host approves, checks in and out, reviews the stay |
| **Host** | Lists a place step by step, approves every request, hosts the stay, gets paid into their Oasis vault, withdraws to a bank |

Nobody books or hosts before their identity is verified. That is the product's premise,
and the site should say it early.

**Wording:** "shortlets" for the product (not "stays" as a noun), "guest" and "host"
(never tenant or landlord). Never write "escrow" — it is a regulated term. Say the money
is "held by Oasis until…".

**One-line positioning:** *Feel at home. Wherever you stay.* Verified shortlets across
Nigeria, paid for through Oasis and released to the host after the stay.

---

## 2. The four promises (the site's promise strip)

| Promise | What it means |
|---|---|
| **ID-verified hosts & guests** | Everyone verifies with their NIN and a selfie before booking or hosting. Oasis never stores the raw NIN. |
| **Paid after your stay** | The guest pays Oasis, not the host. The host's payout lands in their Oasis vault 24 hours after checkout, unless the guest reports a problem first. |
| **Refundable caution fee** | Optional, set by the host. Returned after checkout unless the host reports damage within a short inspection window. |
| **Clear cancellation terms** | Each host picks one of four policies — Flexible, Moderate, Strict, Non-refundable — shown to guests before they request. |

---

## 3. Product surface (what the site may truthfully claim)

**Identity & trust**
- NIN + selfie verification for every guest and host before booking or hosting. The raw
  NIN is never stored.
- A listing's map pin is checked against the address the host gives.
- Reviews only come from real, completed stays.

**Guests**
- Search by location, dates and number of guests; filter by price, bedrooms, type of
  place and amenities.
- Request dates → host approves → guest pays → check in → check out.
- The cancellation policy is shown before the guest requests.

**Hosts**
- A step-by-step listing flow: the place and its map pin, type of place, amenities, what
  it is best for, at least 3 photos and a required tour video, nightly price, house
  rules, check-in and check-out times.
- "Best for" options: staycation, birthdays, baecation, parties, weekend getaway, work
  trip, family time, friends' trip, photoshoots, weddings & owambe, holidays, long stays,
  airport stopover.
- Hosts approve every request, and can pause or remove a place.

**Money**
- Guests pay Oasis. Host payouts land in the host's Oasis **vault** 24 hours after
  checkout unless the guest reports a problem first; hosts withdraw to their bank with a
  vault PIN.
- Optional refundable caution fee, returned after checkout unless the host reports damage
  within a short inspection window.
- **Fees are not final.** Do not state any fee amounts; say fees will be shown before you
  pay.

**Status**
- The app is not in the App Store or Google Play yet. There are no user numbers,
  testimonials, ratings or press. Do not invent any.

---

## 4. Colour scheme

Light only. The earlier terracotta palette and warm-brown dark mode are retired.

| Token | Hex | Role |
|---|---|---|
| Cream | `#F8F1E5` | Page background |
| Deep cream | `#F1E8D8` | Alternate section bands |
| Black | `#171717` | Type, nav, phone frame, strong contrast bands |
| Orange | `#EE6309` | The logo orange. Primary buttons, CTAs, highlights |
| Orange ink | `#B34700` | Orange text and links on cream (4.9:1) |
| Orange hover | `#DD5B06` | Button hover, still with black text (4.8:1) |
| Lime | `#C9F52A` | Small accents, selected states, special labels |
| White | `#FFFFFF` | Cards, forms, content surfaces |
| Muted text | `#5F5A52` | Secondary copy (6.1:1 on cream) |
| Line | `#E8DFD0` | Borders and dividers |

**Contrast rules**
- Orange buttons use **black** text (`#171717` on `#EE6309` = 5.5:1). White on orange is
  only 3.3:1 — never use it.
- Orange small text on cream fails (2.9:1). Use orange ink `#B34700` or plain black.
- Lime is only a fill behind black text. Never lime text, never a thin lime line on cream.
- Black `#171717` bands with white text are on-brand; the app's splash is black with the
  orange-and-lime logo.

### The logo

The orange **Oasis** wordmark with a lime palm. Use `oasis-wordmark.webp` on cream, white
and black. The palm alone on black is the app icon.

---

## 5. Type

- **Typeface:** Montserrat throughout (Google Fonts). One family, no pairing.
- **Headings carry negative tracking** — `-0.4` to `-1.2` depending on size. Montserrat's
  default spacing is tuned for small text and reads slack at display sizes; this is most
  of what stops the app looking like a default template.

App type ramp, for reference and for sizing the website's own scale:

| Style | Size | Weight | Tracking |
|---|---|---|---|
| Screen title | 28 | Bold | −0.7 |
| Section title | 17 | 700 | −0.35 |
| Card title | 15 | 600 | −0.2 |
| Body | 13 | 500 | 0 |
| Label | 11 | 700 | +0.3 |

---

## 6. Shape, depth, motion

**Three radii only — 8 / 16 / 24.** Chips and small controls at 8, buttons, inputs and
inner tiles at 16, cards, sheets and modals at 24. Inventing a fourth is what made the UI
read as hand-assembled. The website should hold the same three.

**Two-layer shadows.** A tight contact shadow that anchors the card to the page, plus a
wide soft one that gives it height. A single blurred shadow always reads either muddy or
flat.

```
contact: rgba(0,0,0,.04)  0 1px 2px
lift:    rgba(0,0,0,.05)  0 8px 18px -4px
```

**Motion is short and functional.** Fade page transitions, a 3% scale dip plus a haptic
tick on press, a fade-and-rise entrance staggered per list index, numbers that crossfade
rather than snap, and list rows that collapse and fade out rather than disappearing.
Nothing runs long enough to be watched. The website should borrow the restraint, not the
count: one entrance per section, no parallax.

---

## 7. Design choices worth putting on the site

These are the opinions behind the interface. They are for the team and for screenshot
captions; the public site leads with guests and hosts, not engineering detail.

- **No spinners.** A circular progress indicator reports on the software, not on the work.
  Buttons get a two-pixel sweep along their own foot; rows get three dots beside them;
  images get a still tinted block the exact shape of what is coming.
- **Skeletons are shaped like the real card** — thumbnail, title bar, subtitle, status
  pill — not featureless grey slabs, and the sweep runs over the bars only, never the card.
- **Photos fade, never pop**, and anything already cached draws instantly with no fade:
  animating something that was never absent is the other way to look cheap.
- **Listings are sold by their pictures**, so a detail page opens with a full-bleed,
  swipeable, pinch-zoomable photo hero. Everything else starts below it.
- **Places are picked, never typed.** Nigerian states and towns come from a shared,
  searchable list, because "Lagos" and "lagos state" were two different places to search
  and neither side was told why.
- **Every list has an empty, error and offline state**, and a failure with content already
  on screen is a quiet banner, not a takeover.
- **The app re-reads rather than waiting to be dragged.** Screens refetch on mount, when a
  pushed route pops, when their tab becomes visible, and on app resume. Only screens where
  you are waiting on another person poll.
- **Live, but never load-bearing.** One WebSocket delivers messages and notifications
  instantly; every screen behind it still works over plain HTTP if the socket is down.

---

## 8. Tech stack (for an "under the hood" line, if the site wants one)

| Layer | Choice |
|---|---|
| App | Flutter (Dart SDK 3.11), iOS + Android from one codebase |
| Architecture | Feature-first MVCS — each feature owns its models, views, controllers, services |
| State | `provider` |
| Backend | Django REST API, hosted on Render |
| Realtime | One authenticated WebSocket, server-first heartbeat |
| Maps & location | `flutter_map` + `geolocator` for "near me" search |
| Media | `cached_network_image`, `video_player` + `chewie` for listing walkthroughs |
| Storage | `flutter_secure_storage` for tokens, `shared_preferences` for settings |
| Type | Montserrat via `google_fonts` |
| Tests | Contract, session-reset, state and widget smoke tests |

---

## 9. Screenshots

**None exist in the repo yet — they have to be captured.** Below is the shot list and how
to take them.

### Capture settings
- One device size for the whole set: **iPhone 16 Pro (1206×2622)** or an Android equivalent.
- **Light mode** only; the site has no dark theme.
- Use a seeded demo account with realistic Nigerian data: real place names, real-looking
  naira amounts, at least one photo per listing. Empty screens sell nothing.
- Capture at full resolution, PNG, then export web versions at 2× the displayed size.

```bash
flutter run --release
# then, per screen:
xcrun simctl io booted screenshot marketing/screenshots/01-marketplace.png
```

### Shot list

| # | File | Screen | State to capture |
|---|---|---|---|
| 01 | `01-discover.png` | Guest Discover | Shortlet cards with photos, a location and dates filled in |
| 02 | `02-filters.png` | Search filters | Price, bedrooms, type of place and amenities |
| 03 | `03-listing.png` | Shortlet detail | Photo hero, verified host, nightly price, cancellation policy |
| 04 | `04-request.png` | Request dates | Dates and guests chosen, policy shown before sending |
| 05 | `05-trip.png` | Trips | A trip waiting for host approval, and one confirmed |
| 06 | `06-payment.png` | Payment | Amount held by Oasis until after the stay |
| 07 | `07-host-listing.png` | Host listing flow | The "best for" step or the map-pin step |
| 08 | `08-host-requests.png` | Host requests | Two or three requests awaiting approval |
| 09 | `09-vault.png` | Host vault | A payout landed after checkout, withdraw button |
| 10 | `10-verification.png` | Identity verification | The NIN + selfie step, verified badge state |

### How screenshots should appear on the site
- Big. One screen per section, not a collage of nine.
- In a plain device frame or no frame at all — no perspective tilt, no floating shadows
  stacked three deep, no gradient blobs behind them.
- Paired with one short line of copy each, taken from §2 or §3.
- Two or three per page maximum. The rest belong on a `/product` page or a lightbox.

---

## 10. Website design direction

**Look:** cream page, black type, orange for the actions, lime for small labels and
selected states, white cards. No gradients, no glassmorphism, no illustration style that is
not already in the app.

**Page order (guest-first, as built)**
1. **Hero** — wordmark, "Feel at home. Wherever you stay.", a guest CTA and "List your
   place" for hosts, "Coming soon" store badges (not links), the app preview.
2. **Promise strip** — the four promises in §2.
3. **How it works** — two numbered tracks: guests and hosts.
4. **For hosts** — the listing flow, approval, payouts and the vault.
5. **Safety** — ID checks, map pin checked against the address, money held until after
   the stay, caution fee, cancellation terms, reviews from real stays.
6. **Occasions** — the "best for" list as chips.
7. **FAQ**, then the **waitlist**, then the **footer** (For guests / For hosts / Safety /
   FAQ, plus legal and contact).

**Rules**
- Three radii: 8 / 16 / 24. Same as the app.
- Two-layer shadow, or no shadow. Never a single 40px blur.
- Montserrat, negative tracking on every heading above 24px.
- One entrance animation per section, ~200ms, fade and rise. Nothing on scroll-jack.
- Sentence case for headings, plain English.
- Light only. Minimum 12px text outside the phone preview; orange focus outlines.

**Stack:** anything static — Next.js, Astro, or plain HTML with Tailwind. There is no
dynamic content beyond a waitlist form.

---

## 11. Available assets

`assets/images/` in this repo:

| File | Size | Use |
|---|---|---|
| `oasis_wordmark.png` | 574×177 | Orange OASIS wordmark with lime palm — headers and splash |
| `oasis_mark.png` | 522×523 | Lime palm alone, transparent |
| `oasis_app_icon.png` | 1024×1024 | Lime palm on black — app icon |
| `room_interior.png`, `quality_hero.png` | 1024² | Interior imagery |

---

## 12. Claims to avoid

Accuracy matters more than reach, and the app is not launched:

- **Not in the stores yet.** "Coming soon" badges only; never link to a store listing that
  does not exist.
- **No numbers, testimonials, ratings or press.** None exist. Do not invent any.
- **No fee amounts.** Fees are not final; say fees will be shown before you pay.
- **No "escrow".** Say the payment is held by Oasis until after the stay.
- **No push notifications yet.** Do not promise alerts to a closed phone.
- Do not describe payouts, the caution fee or cancellations in more detail than §2 and
  §3 — no refund guarantees, no dispute outcomes.
