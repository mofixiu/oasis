# Landa OS — Marketing Website Brief

Everything a designer or developer needs to build landaos.com without opening the
Flutter project. Written for a **minimal** site: a lot of white space, few colours,
big screenshots, short sentences.

---

## 1. What Landa is

Landa OS is a Nigerian prop-tech app for **rentals without fraud**. Three roles share
one app:

| Role | What they do in Landa |
|---|---|
| **Landlord (owner)** | Lists verified properties and units, reviews applications, signs tenancies, collects rent, runs short lets, gets paid out to a bank account |
| **Tenant** | Browses the marketplace, applies for a unit, signs the agreement in-app, pays rent into escrow, books short stays, finds artisans |
| **Artisan** | One screen: a verified trade listing with a phone number, so landlords and tenants can find and call them |

Nobody transacts before their identity is verified. That is the product's whole premise,
and the site should say it early.

**One-line positioning:** *Verified homes, agreements signed in the app, rent held in
escrow until the keys change hands.*

---

## 2. The four promises (use these as the site's spine)

These are lifted verbatim from the app's own onboarding, so the site and the product say
the same thing:

| Eyebrow | Headline | Body |
|---|---|---|
| MARKETPLACE | **Homes you can trust** | Browse listings with real photos, real prices and a landlord who has been checked. Apply in a few taps. |
| AGREEMENTS | **Sign the lease right here** | Tenancy agreements are drafted, reviewed and signed inside Landa. No printing, no courier, no lost copies. |
| ESCROW | **Rent that stays protected** | Your payment sits in escrow and is only released when the keys change hands. Payouts reach the landlord automatically. |
| VERIFIED | **Everyone here is verified** | Landlords and tenants both pass identity checks, and every document you sign is filed away in your vault. |

---

## 3. Product surface (what the site may truthfully claim)

**Identity & trust**
- NIN + selfie verification through an identity provider. The raw NIN is never stored —
  only a tokenised fingerprint. Say this on the site; it is a real differentiator.
- Product APIs stay locked until verification reaches VERIFIED.
- Two-sided reviews, each tied to a real booking, tenancy or job, so they cannot be bought.

**Renting (yearly)**
- Marketplace of properties with available units; search by area, filter, or "near me"
  distance sorting.
- Apply to a unit in the app; the landlord approves or declines from an applications inbox.
- Tenancy agreement drafted, read and signed by both parties in-app.
- A signed tenancy sits at *awaiting first rent* until the money lands, with a
  backend-set deadline shown to the tenant.

**Money**
- Rent paid into **escrow**, released on a schedule with a visible countdown.
- **Vault**: an in-app wallet with a running-balance ledger, PIN, top-ups and withdrawals.
- **Payouts**: landlords resolve and save a Nigerian bank account; money reaches it
  automatically.
- Receipts for every payment.

**Short lets (nightly)**
- A second business on the same units: nightly listings, booking requests, a 24-hour
  payment window after approval, check-in / check-out, caution-fee claims and disputes,
  host payout held until check-in.

**Fix (artisan directory)**
- Find a verified electrician, plumber, carpenter and so on, and call them. Landlords can
  vouch for artisans, whose recommendations surface per unit for their tenants.
- Landa does **not** broker or take payment for repairs. Do not imply it does.

**Communication**
- Threaded messaging hung off a real relationship (an application or a tenancy) — no cold DMs.
- In-app notifications and landlord broadcasts, delivered live over a WebSocket.

**Property lifecycle**
- Batch unit creation, occupancy states (available / reserved / occupied), and a
  seven-day cooling-off **removal request** rather than a delete — nothing is ever hard
  deleted, so old agreements and receipts keep resolving.

---

## 4. Colour scheme

The app's palette is **warm and earthy**, deliberately not the blue-and-white default
every fintech ships with. Use it for the website too.

### Core palette

| Token | Hex | Role |
|---|---|---|
| Terracotta | `#B65F3C` | Primary. Headings, primary buttons, every CTA |
| Sage green | `#6F8F72` | Success, paid, completed |
| Sand | `#D6B98C` | Vacant units, warnings, pending |
| Slate grey | `#64748B` | Profile surfaces, secondary chrome |
| Brick red | `#A44A3F` | Disputes, sign-out, destructive |
| Black | `#101010` | High-contrast reading copy |
| White | `#FFFFFF` | Light surfaces |

### Light mode

| Token | Hex |
|---|---|
| Page background | `#F1F4F8` |
| Card / surface | `#FFFFFF` |
| Border | `#E5E7EB` |
| Secondary text | `#6B7280` |
| Muted text | `#9CA3AF` |
| Success surface | `#E8F3EA` |
| Vacant surface | `#F4E8D9` |
| Slate surface | `#F1F4F8` |
| Dispute / logout surface | `#F7E9E6` |

### Dark mode (warm, stepped — never pure black)

| Token | Hex |
|---|---|
| Page background | `#121110` |
| Card | `#1C1A19` |
| Raised (sheets, headers) | `#262322` |
| Recessed (inputs, quotes) | `#171514` |
| Input fill | `#262626` |
| Success surface | `#17281A` |
| Vacant surface | `#2A2117` |
| Dispute surface | `#21100E` |
| Alert dot | `#E5484D` |

**Why it looks like this:** every dark surface carries a few points of red and green over
blue, so terracotta reads as printed on the surface rather than stuck to it. Pure black
gives a card no edge to be seen against, which makes every plane sit at the same depth.
Status fills are opaque tints, never alpha overlays, so a pill reads identically on a
card and on the page.

### The wordmark needs recolouring

Terracotta + sage is the palette, settled. The shipped wordmark
(`assets/images/newlogo.png`, `newlogonobackground.png`, `logo_wordmark_light.png`,
`iconlogo.png`) is still **deep navy + emerald** from the app's first palette and is now
the only thing in the brand that disagrees with everything else.

Recolour it before the site is built, keeping the artwork exactly as it is:

| Element | From (navy/emerald) | To |
|---|---|---|
| Shield + building mark | Deep navy | Terracotta `#B65F3C` |
| "Landa" wordmark | Deep navy | Terracotta `#B65F3C` |
| "OS" | Emerald | Sage green `#6F8F72` |
| Dark-background variant | White | White (unchanged) |

The shape is right — a shield with a building rising out of it reads as *protected
property* in one glance, which is the whole pitch. Only the colour is stale. Do not build
a navy website around a terracotta app, and do not introduce a third accent to bridge them.

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

These are the opinions behind the interface. A short "How we build" section, or captions
under screenshots, is a good home for them.

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
- **Removing a property is a request, not a delete.** Seven days of cooling off and nothing
  is ever hard-deleted, so agreements and receipts pointing at it keep working.
- **Dark mode is a first-class design, not an inversion** — see the warm stepped ramp above.

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
- **Light mode** for the main set. Optionally re-shoot 3–4 hero screens in dark mode for a
  light/dark toggle on the site — the dark theme is good enough to be a selling point.
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
| 01 | `01-marketplace.png` | Tenant Discover | Grid of listings with photos, a search term filled in |
| 02 | `02-listing.png` | Listing detail | Scrolled to top so the full-bleed photo hero leads |
| 03 | `03-apply.png` | Apply for unit sheet | Sheet open over a listing, fields filled |
| 04 | `04-agreement.png` | Tenancy agreement | Terms visible with the signature action at the foot |
| 05 | `05-escrow.png` | Payment / receipt | Rent in escrow with the release countdown showing |
| 06 | `06-vault.png` | Vault ledger | Balance card plus several ledger rows with running balance |
| 07 | `07-landlord-dashboard.png` | Landlord dashboard | Portfolio box with occupancy leading, units below |
| 08 | `08-applications.png` | Applications inbox | Two or three pending applications awaiting a decision |
| 09 | `09-stays.png` | Stays browse | Nightly listings with prices |
| 10 | `10-fix.png` | Fix directory | Artisan cards with trade, rating and phone number |
| 11 | `11-messages.png` | Conversation | A thread between landlord and tenant |
| 12 | `12-verification.png` | Identity verification | The NIN + selfie step, verified badge state |
| 13 | `13-dark.png` | Any hero screen | Same as 01 or 07, dark mode |

### How screenshots should appear on the site
- Big. One screen per section, not a collage of nine.
- In a plain device frame or no frame at all — no perspective tilt, no floating shadows
  stacked three deep, no gradient blobs behind them.
- Paired with one short line of copy each, taken from §2 or §7.
- Two or three per page maximum. The rest belong on a `/product` page or a lightbox.

---

## 10. Website design direction

**Look:** the app's palette on a lot of white. Terracotta is the only strong colour on
the page; sage and sand appear once or twice as accents. No gradients, no glassmorphism,
no illustration style that is not already in the app.

**Suggested page order**
1. **Hero** — wordmark, the positioning line, one primary CTA, one screenshot.
2. **The four promises** — §2, one row each with its screenshot, alternating side.
3. **For landlords / for tenants** — a two-column split, or a toggle. Keep to five bullets each.
4. **How we build** — three or four items from §7. This is what separates the site from
   every other prop-tech landing page; do not cut it.
5. **Trust** — verification, escrow, reviews tied to real transactions, nothing hard-deleted.
6. **Download / waitlist** — one form field.
7. **Footer** — legal, privacy, contact.

**Rules**
- Three radii: 8 / 16 / 24. Same as the app.
- Two-layer shadow, or no shadow. Never a single 40px blur.
- Montserrat, negative tracking on every heading above 24px.
- One entrance animation per section, ~200ms, fade and rise. Nothing on scroll-jack.
- Sentence case for headings. The app writes in plain English — "Rent that stays
  protected", not "Revolutionising Nigerian Real Estate".
- Ship a dark mode. The app has a good one; a site that ignores the visitor's preference
  next to an app that respects it is an odd first impression.

**Stack:** anything static — Next.js, Astro, or plain HTML with Tailwind. There is no
dynamic content beyond a waitlist form.

---

## 11. Available assets

`assets/images/` in this repo:

| File | Size | Use |
|---|---|---|
| `newlogo.png` | 1830×658 | Full wordmark, light background — **awaiting recolour**, see §4 |
| `newlogonobackground.png` | 833×299 | Wordmark, transparent |
| `logo_wordmark_light.png` | 833×299 | White wordmark, for dark backgrounds |
| `iconlogo.png` | 826×878 | Shield mark alone — use for the favicon and app icon |
| `room_interior.png`, `quality_hero.png` | 1024² | Interior imagery |
| `artisan_*.png` | 1024² | Artisan portraits (demo likenesses — check rights before public use) |

---

## 12. Claims to avoid

Accuracy matters more than reach, and the app is an MVP:

- **No push notifications yet.** Notifications are in-app and live while the app is open.
  Do not promise alerts to a closed phone.
- **Fix is a directory, not a repairs marketplace.** No job booking, no quotes, no escrow
  for repairs. "Find and call a verified artisan" is the whole claim.
- **The backend runs on staging.** Do not publish a launch date or user numbers that
  have not happened.
- Do not describe escrow release, payout timing or refund policy in more detail than the
  product actually enforces — those windows are set by the backend and change.
