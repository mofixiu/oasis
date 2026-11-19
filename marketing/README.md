# Oasis marketing

React, TypeScript and Vite. Built from `website-brief.md`: a guest-first shortlets story on the v2 palette (cream, black, orange, lime, white; light only) with the app’s exact guest bottom-navigation icons.

## Run

```sh
cd marketing
npm install
npm run dev
npm run build
npm run preview
```

`build` type-checks, builds the client, renders React to complete static HTML, generates deployment-specific crawler files, and checks the final output. No server or headless browser is needed in production. JavaScript hydrates analytics and the waitlist. Content, links and FAQ accordions work without it. `dev` uses normal Vite rendering; use `preview` to inspect the static production output.

`npm run check` rechecks an existing build. `node scripts/check-analytics.mjs` tests analytics gating and event delivery against local mocks without sending traffic.

## Configuration

For Vercel's GitHub import, select **oasis (root)** as the Root Directory and **Other** as the framework. The repository's root `vercel.json` installs dependencies in `marketing`, runs its static build, and publishes only `marketing/dist`. This avoids needing to select the marketing folder in Vercel's directory picker. Leave build/output overrides unset so the committed configuration applies.

Copy `.env.example` to `.env.local`. All values are public and embedded at build time; rebuild after changes. Never put secrets in them.

| Variable                                                 | Purpose                                                                                                        |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `SITE_URL`                                               | Public HTTPS origin for canonical, OG URLs, robots and sitemap; on Vercel defaults to the project’s production domain; required elsewhere. |
| `VITE_WAITLIST_ENDPOINT`                                 | JSON POST endpoint accepting `{ "email": "person@example.com" }`.                                              |
| `VITE_PRIVACY_URL`, `VITE_TERMS_URL`, `VITE_CONTACT_URL` | Approved legal and contact destinations.                                                                       |
| `VITE_PLAUSIBLE_SCRIPT_URL`                              | Exact unique HTTPS script URL from your Plausible site installation snippet.                                   |

Without an endpoint the waitlist shows “Sign-ups open soon” instead of a form, so there is no dead input. With `VITE_PRIVACY_URL` set, the consent line links to it. Even when configured, the form stays disabled until hydration, so disabling JavaScript cannot accidentally submit email addresses via a GET URL. The backend must validate, rate-limit, persist submissions, configure CORS, and return 2xx only after accepting the signup. Emails are not stored locally or sent to analytics.

Fees are **not final**; the FAQ says fees will be shown before you pay. Payout timing (24 hours after checkout unless the guest reports a problem), the caution fee and the four cancellation policies are described only as the app enforces them. Never call the held payment “escrow”. No fee amount, guaranteed refund, launch date, user number, rating or testimonial is invented, and the store badges say “Coming soon” rather than linking.

## Performance and sharing

- Display-sized WebP photos: about 74 KiB combined; below-fold media is lazy-loaded. All content images have dimensions, and the hero image has high fetch priority.
- The lossless wordmark and favicon use the orange Oasis lettering and lime palm. The palm-only mark on black is the app icon. Full-size PNGs remain in the parent app’s `assets/images/`. (`oasis-wordmark-dark.webp` is no longer referenced.)
- Four Latin-only Montserrat WOFF2 weights (400–700), about 73 KiB combined. No Cyrillic/Vietnamese/WOFF copies.
- `public/og.jpg`: 1200×630 sharing card on cream (wordmark, “Verified shortlets across Nigeria.”, “Paid after your stay. Hosts checked.”), generated with Pillow; it is metadata-only and does not download as page content.
- Complete Open Graph and Twitter metadata, absolute canonical, `robots.txt`, and a one-page sitemap. Section anchors are not separate sitemap pages.
- The deployment must be publicly reachable at `SITE_URL` for WhatsApp/search crawlers to read the page and image. A private Sites preview cannot provide public unfurls. This task does not change access or publish to the public domain.

`src/entry-server.tsx` and `scripts/prerender.mjs` produce static HTML from the same React component tree used for hydration. Browser-only state is read in effects, and native `details` handles FAQs without JavaScript. Mock app labels use divs rather than headings.

## Analytics

Analytics is prepared but **inactive until a real script URL is supplied**. No account has been created. The integration follows [Plausible’s current unique-script setup](https://plausible.io/docs/script-update-guide) and [custom event API](https://plausible.io/docs/custom-event-goals).

The configured script records pageviews. Custom events distinguish `Guest interest`/`Host interest`, waitlist interest, submitted/accepted/failed signups, and FAQ opens. Set these event names up as goals in the provider dashboard. Events contain only fixed labels and section identifiers, never email addresses, form values, identities or listing data. DNT/GPC preferences, development mode and script-load failure disable tracking. Validate receipt in the provider dashboard once connected; the current checks use local mocks.

## Assets and product previews

The phone and host listing visuals are labelled examples, not actual app captures (the phone is one `role="img"` with its contents hidden from screen readers). Replace them with seeded, populated app screenshots when available.

The five navigation glyphs are the exact Flutter MaterialIcons from the guest bar in `lib/core/widgets/v2_main_scaffold.dart`: `home_outlined`, `explore_outlined`, `luggage_outlined`, `chat_bubble_outline_rounded` and `payments_outlined`. Their 1.5 KB subset (made with `pyftsubset`) and upstream license are in `public/fonts/`.
