# Build Brief for Another App

## Purpose

Use this document to design and build a new app with the same visual discipline and product feel as Oasis without copying its name, logo, exact colors, property-specific content, or screens.

The result should feel warm, trustworthy, modern, and quietly premium. It should be minimal without feeling empty, friendly without becoming playful, and polished without relying on excessive decoration.

Replace the placeholders below before starting:

- **App name:** `[APP_NAME]`
- **What the app helps people do:** `[CORE_JOB]`
- **Primary audience:** `[AUDIENCE]`
- **Main objects in the product:** `[OBJECTS]`
- **Three to five primary destinations:** `[DESTINATIONS]`
- **Primary action users take:** `[PRIMARY_ACTION]`

## Project context agents need

Fill this in before asking an implementation agent to build features. Missing context here is where agents are most likely to make locally reasonable but product-wrong decisions.

- **MVP outcome:** `[THE ONE END-TO-END RESULT THE FIRST RELEASE MUST DELIVER]`
- **Explicit non-goals:** `[FEATURES OR PLATFORMS NOT IN THIS RELEASE]`
- **Supported platforms and minimum versions:** `[IOS / ANDROID / WEB / DESKTOP]`
- **Framework and language:** `[FOR THIS ARCHITECTURE: FLUTTER + DART]`
- **State management:** `[FOR THIS ARCHITECTURE: PROVIDER + CHANGENOTIFIER]`
- **User roles and permissions:** `[ROLE → ALLOWED DESTINATIONS AND ACTIONS]`
- **Authentication method:** `[TOKEN TYPE, REFRESH BEHAVIOR, LOGOUT RULES]`
- **Backend contract location:** `[LINK OR REPOSITORY PATH]`
- **Environment configuration:** `[LOCAL / STAGING / PRODUCTION, WITHOUT COMMITTED SECRETS]`
- **Source of truth for each major object:** `[BACKEND / DEVICE / DERIVED]`
- **Real-time events:** `[EVENT NAME → OWNER CONTROLLER → UI EFFECT]`
- **Offline expectations:** `[READ CACHE / QUEUE WRITES / RETRY ONLY]`
- **Sensitive data handled:** `[PII, PAYMENTS, LOCATION, MEDIA, ETC.]`
- **Locale rules:** `[LANGUAGE, TIME ZONE, CURRENCY, DATE AND NUMBER FORMATS]`
- **Analytics and crash reporting policy:** `[WHAT MAY AND MAY NOT BE RECORDED]`
- **Accessibility target:** `[WCAG AA AND PLATFORM REQUIREMENTS]`
- **Release acceptance tests:** `[CRITICAL USER FLOWS]`

Maintain a short product vocabulary beside the requirements: the official name of each role, object, status, and action. Reuse those terms in models, service methods, UI copy, tests, analytics, and backend discussions. Do not let synonyms create different concepts in different layers.

For every endpoint or external capability, document:

```text
Purpose:
Who may call it:
Method and path:
Request fields:
Success payload:
Known error codes and recovery:
Idempotency behavior:
Cache/refresh expectations:
Real-time event emitted afterward:
```

Agents should not invent missing backend behavior in the client. If the contract is incomplete, isolate the assumption at the service or parsing boundary, document it, and keep the UI truthful about what is actually supported.

## Core design character

Build around these five qualities:

1. **Quiet confidence** — clear hierarchy, generous breathing room, and very little visual noise.
2. **Warm utility** — practical screens softened with human copy, rounded geometry, subtle warmth, and real imagery.
3. **Product-first storytelling** — show miniature versions of the actual product instead of generic decorative illustrations.
4. **Semantic color** — every accent has a job; color is not added merely to make a screen look busy.
5. **Tactile restraint** — short transitions, shallow press states, soft depth, and useful haptics make the interface feel responsive.

## Visual hierarchy

Every screen should make these levels obvious at a glance:

1. The screen purpose
2. The most important current value, object, or status
3. The next useful action
4. Supporting details and metadata

Do not give headings, values, links, icons, and status labels the same visual weight. Most of the interface should be neutral. Reserve stronger color and weight for the small number of things that deserve attention.

## Layout and spacing

Use an 8-point spacing rhythm, with 4-point half-steps for compact relationships.

- Standard phone gutter: **20–24 px**
- Small internal gap: **4–8 px**
- Related-item gap: **10–16 px**
- Card padding: **16–20 px**
- Section gap: **24–32 px**
- Large breathing space: **36–48 px**
- Minimum comfortable touch target: **44 px**
- Keep auth and narrow form content centered with a maximum width around **440 px** on larger screens.

Prefer one strong vertical flow. Avoid dense two-column layouts on phones unless the content is naturally comparative. Keep related labels close to their values and use larger gaps between unrelated groups.

Respect safe areas and the keyboard. A floating bottom navigation bar must not cover the final card or action. A sheet footer must remain visible above the keyboard.

## Shape language

Use only three main corner radii so the interface looks designed as one system:

- **8 px:** chips, badges, tiny controls, and compact inline actions
- **16 px:** buttons, inputs, segmented controls, and inner tiles
- **24 px:** primary cards, sheets, dialogs, and floating navigation

Use circles for avatars, icon medallions, notification dots, and close buttons. Do not introduce random radii for individual screens. Nested shapes should use concentric corners: the inner radius should reduce by the same amount as the inset.

## Typography

Use a geometric sans-serif with a warm, modern personality. **Montserrat** is the closest match; a similar geometric family is acceptable if it better fits the new brand.

Use one family throughout the product. Build hierarchy through size, weight, spacing, and color instead of mixing fonts.

| Role | Size | Weight | Tracking and use |
|---|---:|---:|---|
| Screen title | 28 px | 700 | Slightly tight tracking; one per screen |
| Major value | 22–28 px | 700–800 | Tight tracking; currency, balances, or primary metrics |
| Section title | 17–19 px | 700 | Slightly tight; introduces a group |
| Card or row title | 15 px | 600 | Compact and easy to scan |
| Body | 13–15 px | 500 | Line height around 1.45–1.55 |
| Small label | 11 px | 700 | Slight positive tracking; metadata and pills |
| Navigation label | 10 px | 600–700 | Uppercase and short |

### Text casing

- Use **sentence case** for screen titles, section titles, buttons, instructions, and messages.
- Use **UPPERCASE** only for compact eyebrows, field labels, status labels, card metadata, and bottom-navigation labels.
- Keep uppercase labels short and add letter spacing so they do not feel cramped.
- Use tabular figures for changing balances, counters, and financial values when the selected font supports them.

### Type hierarchy rules

- Large headings use negative tracking so they feel intentional rather than loose.
- Body copy uses a relaxed line height and a neutral readable color.
- Key numbers may use the primary brand accent; long paragraphs may not.
- Important legal, medical, financial, or consent copy must use the highest-contrast neutral text, never a decorative brand color.
- Muted text is for secondary context, not essential instructions.

## Writing style

The voice should be calm, direct, human, and specific.

- Lead with what the user can do or what just happened.
- Prefer familiar words over internal product terminology.
- Use short headings that make a useful promise: “Find your next class,” “Your plan is ready,” or “Payment received.”
- Supporting copy should explain the practical benefit in one or two sentences.
- Button labels should name the action: “Create account,” “Send request,” “Review plan,” or “Try again.”
- Status messages should explain both the state and the next step.
- Empty states should never be dead ends; give the user a relevant action whenever one exists.
- Error messages should distinguish an empty result, an offline state, validation failure, and a server failure.
- Avoid hype, vague reassurance, exclamation marks, and robotic phrases such as “Operation completed successfully.”

Example pattern:

> **Nothing matches that search**  
> Try a different category or widen your filters to see more results.  
> **Clear filters**

## Color system — roles, not exact colors

Choose a new palette for the new brand, but preserve this relationship between colors.

| Role | Purpose | Usage rule |
|---|---|---|
| Page background | Quiet canvas behind content | Soft neutral; avoid stark white or pure black |
| Surface | Cards and primary containers | Clearly separated from the page by a border and soft depth |
| Elevated surface | Sheets, selected segments, floating controls | One visual step above a standard card |
| Recessed surface | Inputs, segmented tracks, quoted blocks | One visual step below a standard card |
| Primary brand/action | Main CTA, selected navigation, key links, selected states | Use consistently; do not change it per screen |
| Secondary accent | Success, completion, or positive confirmation | Use only where its meaning is clear |
| Warm neutral accent | Pending, caution, availability, or gentle highlights | It should feel noticeable but not alarming |
| Cool neutral accent | Profile, informational, or secondary system states | Supports the primary without competing with it |
| Danger accent | Destructive actions, disputes, and failures | Use sparingly and never for ordinary decoration |
| Attention dot | Time-sensitive unread activity | Brighter than the brand accent so it remains visible at tiny sizes |

### How to use color

- Let neutral backgrounds and surfaces occupy most of the interface.
- Use the primary accent for actions and selected states, not for every icon or paragraph.
- A screen may have one ambient accent, but its primary action keeps the app-wide action color.
- Use pale tinted surfaces behind status messages in light mode and deep tinted surfaces in dark mode.
- Pair every tinted surface with a tested foreground color; do not place theme-aware text on a fixed pale fill.
- Never communicate status by color alone. Add a label, icon, shape, or position cue.
- A bright alert dot is reserved for something genuinely waiting on the user.
- Photographs may supply visual richness. The interface around them should remain restrained.

Aim for an approximate **70/20/10** balance: 70% background and neutral space, 20% surfaces and supporting neutrals, and no more than 10% brand or semantic accents.

## Light and dark surfaces

### Light mode

- Use a soft neutral page rather than a clinical white canvas.
- Place light cards on it with a hairline border and very subtle shadow.
- Use dark neutral text for reading and the brand accent for selected headings or key values.
- Status surfaces should be low-saturation washes, not solid blocks.

### Dark mode

- Use a warm off-black page, never pure black.
- Create a small stepped surface ramp: page, recessed, card, and raised.
- Keep the steps subtle enough to be felt as depth rather than seen as stripes.
- Add a faint edge to raised elements because shadows alone disappear on dark surfaces.
- Use deep, opaque semantic tints rather than translucent light-mode fills.
- Confirm contrast independently in both themes; do not assume reversing text to white solves every pairing.

## Borders and depth

Minimal does not mean flat. Use depth gently to explain containment and importance.

- Default card: one-pixel low-contrast border plus a two-layer shadow.
- First shadow: tight, faint contact shadow close to the surface.
- Second shadow: wider, softer shadow with a downward offset and negative spread.
- Raised sheets and dialogs may use a broader version of the same pair.
- Avoid dark, heavy drop shadows, glowing every card, or using shadow as the only boundary.
- Image-led cards may use a border without a shadow when the media already gives them sufficient weight.

## Core components

### App bar

- Height around 64 px with no visible elevation.
- Match the page background so it feels integrated rather than like a colored strip.
- Use a personal anchor such as an avatar on the left when relevant.
- Keep only frequent utilities on the right, such as notifications and messages.
- Root screens do not show a back button; pushed screens do.
- Avoid decorative logos when the screen title already explains where the user is.

### Screen header

- Begin with one strong sentence-case title.
- Add a one-line description only when it improves orientation.
- Keep title and subtitle left-aligned on task-oriented screens.
- Place search, filters, or primary context directly below the header.

### Cards

- Use one card to express one object or decision.
- Put the title and current status first, the main value second, and metadata last.
- Keep card padding generous and dividers rare.
- Make the whole card tappable when it has one destination; preserve separate tap targets when it contains its own actions.
- Use a shallow scale dip on press instead of a heavy ripple or dramatic bounce.

### Image-led cards

- Use a strong media band at the top and information below it.
- Crop imagery consistently and fade it in over a correctly shaped placeholder.
- Place verification or media badges on the image only when needed.
- Add a dark scrim beneath light text or badges when the image may reduce contrast.
- Keep overlays compact so the photograph remains the hero.

### Buttons

- Primary buttons are filled, normally full width, 52–56 px tall, with a medium radius.
- Secondary buttons are outlined or text-only and should not compete with the primary action.
- Use one primary action color across the app.
- Show an icon only when it improves recognition; keep it small and place it before the label.
- Disabled buttons use a recessed neutral fill, border, muted label, and no colored shadow.
- A loading button must not jump in size. Keep its label in place with a subtle progress treatment, or replace it with same-weight animated dots.

### Inputs and search

- Put a small uppercase label above form fields.
- Use a soft filled or recessed field with a hairline border.
- The focus state uses a 1.4–1.5 px primary-accent ring.
- Use subdued prefix icons and visible clear/password controls where relevant.
- Give hints realistic examples, not generic “Enter text” copy.
- Debounce remote search, but clear and submit immediately.

### Pills and badges

- Use compact rounded pills for short statuses and metadata.
- Use an icon plus label for important status.
- A selected state may use the accent directly; an informational state should use a tinted surface.
- Counts should be short and capped, such as `99+`.

### Segmented controls

- Use a recessed rounded track with a raised inner thumb.
- The thumb should slide with the gesture instead of snapping after it.
- Change label color, but avoid changing weight during the animation because text will visibly reflow.
- Selection must remain understandable from shape and elevation, not only color.

### Bottom navigation

- Use only three to five true top-level destinations.
- Float the bar above the bottom edge with side margins, a large radius, soft shadow, and subtle translucency or blur.
- Use outlined icons and short uppercase labels.
- The selected item uses the primary action accent; unselected items remain neutral but readable.
- Do not add a destination that only opens an empty or rarely useful screen.
- Hide the bar when there is only one destination.

### Sheets and dialogs

- Prefer a bottom sheet for a focused detour from the current task.
- Give every sheet the same grab handle, icon badge, title, subtitle, close button, body spacing, and top radius.
- Let the body scroll while the commit action stays pinned in a footer.
- Keep the sheet visible above the keyboard and device inset.
- Use a full page only when the task needs its own navigation, deep browsing, or extensive context.

### Feedback and system states

- Use compact top-floating messages with an icon, tinted surface, border, short text, and dismiss control.
- Differentiate success, information, warning, and failure semantically.
- Preserve useful cached content when a refresh fails; show a slim inline banner instead of replacing the whole page.
- A full-page error state should include a recognizable icon, plain-language title, explanation, and retry action.
- An empty state should match the reason it is empty and offer the most useful next step.

### Loading states

- Build skeletons with the same silhouette as the content that will replace them.
- Shimmer only the placeholder bars and media blocks, not the entire card surface.
- Use uneven line widths so skeleton text feels natural.
- Cross-fade skeleton, empty, error, and loaded states instead of swapping them abruptly.
- Use three small animated dots for inline waits and a thin sweep for a button-level operation. Avoid generic centered spinners where context can be preserved.

## Art direction

### Product miniatures

Onboarding and educational art should look like handcrafted miniature product scenes:

- Recreate recognizable app objects using native shapes, icons, small labels, skeleton lines, and simplified data.
- Show the actual promise being explained: a completed plan, approved request, protected payment, verified profile, live route, or other domain-specific result.
- Layer two or three rounded panels, with the rear panel slightly rotated and quieter than the main panel.
- Use one elevated hero panel, one supporting panel, and at most one floating confirmation chip.
- Keep miniature data believable and specific to the new app.
- Add one subtle loop only when it explains a process, such as a moving payment, progress pulse, or connecting route.
- Scale the entire composition from a fixed canvas so it remains stable across screen sizes.

Do not use generic people waving, floating 3D shapes, random blobs, or stock illustrations that could belong to any product.

### Photography

- Prefer believable, high-quality editorial photography with clean composition and natural or warm controlled light.
- Show spaces, objects, and people as users would realistically encounter them.
- Portraits should feel capable and approachable, with uncluttered backgrounds and authentic work details.
- Keep image treatment consistent in crop, contrast, warmth, and subject distance.
- Avoid oversaturated stock imagery, obvious lifestyle clichés, or images with embedded text.

### Ambient decoration

- A large soft radial wash may sit partly off-canvas behind onboarding art.
- The wash may change with the story slide while the main CTA color remains fixed.
- Decorative color fields should have no hard edge and should never reduce text contrast.
- Do not add gradients to every button, card, or heading. The ambient field and occasional image scrim are enough.

## Motion and tactile behavior

Motion should clarify cause and effect rather than advertise itself.

- Press state: scale to roughly **97%** over about **110 ms**.
- Small state change: fade or resize over **160–220 ms**.
- Content-state cross-fade: about **280 ms**.
- List entrance: fade and rise about **14 px** over **380 ms**, staggered by roughly **45 ms**, capped after the first several items.
- Page or onboarding advance: smooth ease-out around **400–420 ms**.
- Page indicators should interpolate with the swipe, not update only after the page settles.
- Use the same horizontal push transition across the app and retain the platform back-swipe gesture.
- Give ordinary taps a light haptic, selections a selection tick, commits a stronger haptic, and outcomes success/warning feedback.
- Honor reduced-motion settings by removing parallax, loops, and entrance travel while keeping state changes understandable.

## Recommended screen patterns

### Onboarding

Use three or four slides. Each slide contains:

1. A product miniature occupying roughly the upper half
2. A compact uppercase eyebrow in a tinted pill
3. A short benefit-led title
4. One concise explanatory paragraph
5. A gesture-linked page indicator
6. One persistent primary CTA and a quiet sign-in path

Change the ambient accent and artwork per slide, not the overall navigation or button system.

### Authentication

- Center the logo or wordmark above one short trust-building sentence.
- Put the form in a single bordered surface with generous padding.
- Use no more than the fields required for the current step.
- Make the main action full width and keep secondary account navigation below the card.

### Dashboard

- Start with the current user context, a short greeting only if useful, and the most important current state.
- Prefer one primary summary card plus a few task-oriented sections over a wall of equal metric tiles.
- Use color on key values and actionable status, not on every card.
- Put pending actions near the object they affect.

### Browse or list screen

- Use a clear title and useful one-line description.
- Place search first, then filters, then the result list.
- Use image-led cards when recognition matters; use compact rows when comparison speed matters.
- Preserve scroll position and already loaded content when switching top-level tabs.

### Detail screen

- Lead with media or the object identity, followed by the primary value and status.
- Group related information into a few clear sections.
- Keep the main action visible without repeating it throughout the page.

### Forms and commit flows

- Break long work into meaningful sections, not arbitrary step counts.
- Explain why sensitive information is needed close to the field.
- Keep validation local and specific.
- Use a pinned action in a sheet or a stable footer on a full page.
- Confirm completion with a clear outcome and the next relevant destination.

## Accessibility and responsive behavior

- Meet at least WCAG AA contrast for text and essential controls.
- Do not use small accent-colored text on tinted backgrounds without testing the exact pair.
- Support system text scaling without clipping buttons, pills, or sheet headers.
- Allow body copy and long labels to wrap; truncate only nonessential metadata.
- Add semantic labels and tooltips to icon-only controls.
- Keep status understandable without color.
- Preserve keyboard focus, screen-reader order, and logical back behavior.
- On tablets and desktop, constrain reading width and add outer space rather than simply stretching phone cards edge to edge.

## Application architecture

Use a **feature-first MVCS structure**: Model, View, Controller, and Service. Organize code by the user-facing capability it belongs to, not by putting every model or every screen in one app-wide folder.

The intended data flow is:

```text
View → Controller → Service → Shared API client → Backend
  ↑         │           │              │
  └─ state ─┘           └─ Models ─────┘
```

- The **view** renders state, collects input, and triggers controller methods.
- The **controller** owns feature state and coordinates user workflows.
- The **service** owns endpoint calls and wire-level request construction.
- The **model** parses, validates, and represents domain data.
- The **shared API client** owns transport behavior such as authentication, timeouts, token refresh, and response errors.
- The **composition root** creates long-lived dependencies and connects cross-cutting systems.

Keep each layer replaceable and testable. A view should not make HTTP requests, a service should not know about widgets, and a model should not depend on a screen.

### Recommended project tree

```text
lib/
  main.dart                         # composition root only
  core/
    network/
      api_client.dart               # HTTP, auth headers, retry, errors
      api_constants.dart            # base URL and endpoint paths
      auth_token_storage.dart       # secure local credentials
      load_failure.dart             # shared error/loaded-state helpers
    session/
      session_scope.dart            # reset per-user cached state
      realtime_hub.dart             # route socket events to features
    theme/
      app_theme.dart                # semantic tokens and ThemeData
      theme_controller.dart         # persisted light/dark/system choice
    utils/                          # small cross-feature behavior
    widgets/                        # truly reusable design-system widgets
  features/
    feature_name/
      models/
      services/
      controllers/
      views/
        widgets/                    # widgets private to this feature
test/
  feature_flow_test.dart
  component_test.dart
  regression_test.dart
```

Not every feature must contain every directory. Create only the folders the feature needs. Keep a widget inside the feature until it is genuinely shared by several features; then promote it to `core/widgets`.

### Dependency direction

Dependencies should point inward in this order:

```text
core primitives ← feature models/services/controllers ← feature views
```

Apply these rules:

- `core` must not import feature screens or feature controllers, except for a deliberate application-level coordinator such as a real-time event hub.
- Models must not import views or controllers.
- Services may depend on the shared network layer and their feature’s models.
- Controllers may depend on their feature’s services and models plus small shared utilities.
- Views may depend on their feature controller, models, shared theme, and shared widgets.
- One feature should not reach into another feature’s private view widgets.
- Cross-feature workflows belong in a clearly named coordinator or the composition root, not in circular controller dependencies.

## Layer responsibilities

### Models

Models should be mostly immutable value objects:

- Prefer `final` fields and `const` constructors.
- Put JSON parsing and serialization beside the model.
- Add computed properties for presentation-independent domain facts, such as `isPending`, `canMessage`, or `lowestPrice`.
- Use `copyWith` for controlled immutable updates.
- Parse enums defensively and include an `unknown` state rather than silently treating an unfamiliar backend value as an actionable status.
- Accept known backend variations at the parsing boundary when contracts are in transition, but do not spread fallback key logic through the UI.
- Mark optimistic records explicitly so actions requiring a server-issued ID remain unavailable until confirmation.

Models should not format colors, show dialogs, call the network, or hold a `BuildContext`.

### Services

Services are the boundary between domain code and external systems:

- Give each service a narrow feature-specific API.
- Construct paths, query parameters, request bodies, file uploads, and response mapping here.
- Return typed models or small typed result objects, not raw response maps when a stable model exists.
- Inject the shared API client through the constructor, with a sensible production default.
- Introduce an abstract service interface when multiple implementations are expected, such as live, mock, local, or test versions.
- Keep mock implementations realistic: include latency, believable records, empty results, and failures.
- Make retried financial or destructive requests idempotent whenever the backend supports an idempotency key.
- Log request method, route, duration, and safe identifiers in development, but never tokens, passwords, full identity documents, or other sensitive payloads.

Services must not call `notifyListeners`, navigate, show UI feedback, or choose colors and copy for screens.

### Controllers

Controllers are feature-level state machines, not miscellaneous utility classes:

- Use one controller per cohesive feature or workflow, not one giant application controller.
- Keep mutable state private and expose read-only getters.
- Inject the service so controller tests can provide a fake or mock implementation.
- Provide intention-revealing methods such as `loadBookings`, `applyFilters`, `submitApplication`, or `approveRequest`.
- Own loading, loaded-once, failure, filters, pagination, selected state, and operation-in-flight identifiers.
- Convert caught exceptions into stable state through a shared failure mechanism.
- Notify listeners at meaningful state boundaries, avoiding redundant notifications that cause visible flicker.
- Never store `BuildContext` or build widgets.
- Clear user-specific state on logout or before a new login.

Do not use one global `isLoading` flag for everything. Keep background list loading separate from row-level actions. When a user acts on one record, store the ID of that record so only its controls become busy.

### Views

Views should stay declarative and task-focused:

- Read state with a watching selector only where that state affects rendering.
- Use non-watching reads for one-off controller calls.
- Keep networking and business rules out of widgets.
- Own temporary presentation state such as text controllers, tab controllers, animation controllers, and local disclosure toggles.
- Split a large screen into private widgets named after meaningful UI regions.
- Move a widget into the feature’s `views/widgets` directory when it is reused within that feature.
- Move it into `core/widgets` only after it becomes cross-feature design-system behavior.
- Keep navigation and user feedback close to the interaction that triggers them, while the controller owns the underlying result.
- Handle loading, loaded content, loaded empty, offline, server error, stale-content refresh failure, and disabled states explicitly.

Views must not decode JSON, assemble endpoint URLs, manually refresh tokens, or duplicate domain rules already available from a model or controller.

### Composition root

Keep dependency construction in `main.dart` or one dedicated bootstrap module:

- Initialize framework bindings and global error handling first.
- Create theme, auth, feature controllers, and application coordinators in one visible place.
- Register providers there rather than scattering process-wide singletons through screens.
- Connect authentication changes to session-bound systems such as sockets.
- Connect global network signals, such as expired credentials, back to the authentication controller there.
- Start real-time systems early enough that events cannot arrive before listeners exist.
- Observe application lifecycle at the root for global systems.
- Keep feature-specific business logic out of the composition root.

This makes ownership obvious and prevents hidden global state from accumulating across tests or user sessions.

## State and data lifecycle

### Use a complete load-state model

An empty list and a list that has never been loaded are different states. Every remotely loaded collection should distinguish:

1. **Never loaded** — show a content-shaped skeleton.
2. **First load in progress** — keep showing the skeleton.
3. **Loaded with content** — show the content.
4. **Loaded empty** — show a truthful empty state and useful action.
5. **Initial load failed** — show a full error or offline state.
6. **Background refresh in progress** — preserve the existing content.
7. **Background refresh failed** — preserve content and show a slim banner.

Set the loaded-once marker in `finally`, including after failure, so an unsuccessful request does not leave a skeleton running forever.

### Refresh behavior

Use one refresh method per screen and call it from all relevant triggers:

- first visible mount
- pull to refresh
- returning from a pushed screen where data may have changed
- returning to a preserved bottom-navigation tab
- resuming the app from the background
- an opt-in interval only when the user is visibly waiting for another person or system

Do not refresh on every build. Drop overlapping refreshes rather than queueing them. Pause polling while a screen is hidden. Defer the first fetch for tabs that were constructed but have never been viewed.

Preserve tab state with an indexed/persistent stack when appropriate so scroll position, filters, and already loaded content survive navigation. Refresh silently when a preserved tab becomes visible again.

### Mutations and optimistic UI

Use optimistic updates only when the expected result is highly predictable and immediate feedback materially improves the workflow.

For every optimistic mutation:

1. Save enough previous state to undo the change.
2. Apply a clearly identifiable provisional record or local status.
3. Disable only the action that is actually in flight.
4. Replace the provisional state with the server response on success.
5. Roll back completely on failure.
6. Re-fetch authoritative server state when the mutation may affect related records.
7. Test the mid-flight state, success replacement, and failure rollback.

Never leave a user-facing success state in place after the backend refused the action.

### Session boundaries

Long-lived providers cache user data, so every controller holding per-user state must implement an explicit reset contract.

- Reset all session-scoped controllers on logout.
- Also reset before login or registration so an expired prior session cannot leak into the next one.
- Clear lists, selected records, filters, operation IDs, errors, loaded-once markers, and local unread counts.
- A reset must not trigger authenticated network calls because credentials may already be gone.
- Clear real-time popup queues and disconnect sockets when the session ends.

Treat this as a privacy boundary, not merely a convenience for refreshing the UI.

## Network and reliability architecture

Centralize transport behavior in one API client:

- base URL and endpoint composition
- auth headers
- JSON encoding and decoding
- query parameter filtering and URI encoding
- upload handling
- request and upload timeouts
- access-token refresh and one retry of the original request
- typed API, validation, authentication, and connection exceptions
- human-readable error extraction
- session-expiry signaling
- verification or consent gate signaling where relevant

Differentiate “the server rejected this” from “the request never reached the server.” Offline, DNS, TLS, client, and timeout failures should resolve to one connection-error family the UI can recognize.

Do not sign a user out because the network is temporarily unavailable. End the session only when credentials are definitively rejected and cannot be refreshed.

For staging systems that sleep, model cold-start time separately from ordinary request time. For money movement and destructive retries, preserve the same idempotency key across authentication refresh and network retry.

## Real-time architecture

When the app has live messages or notifications, use one application-level real-time hub rather than letting every screen create its own socket.

- Connect only while authenticated and in the foreground.
- Route each event type to the controller that owns that data.
- Reconcile unread counts or critical lists after reconnect because events may have been missed.
- Use a slow fallback poll only while the socket is disconnected.
- Collapse bursts of related popups so a backlog does not interrupt the user repeatedly.
- Do not show a popup for an event already visible on the active screen.
- Treat unknown event types as safe no-ops with development logging.
- Stop timers, subscriptions, sockets, and listeners when their owner is disposed or the session ends.

Use global navigation only for genuinely external events that must open a destination without a screen context. Ordinary navigation should remain local to the initiating view.

## Performance rules

- Preserve top-level tab state instead of rebuilding and refetching it on every switch.
- Debounce remote text search; submit and clear immediately.
- Cache network images and fade them into correctly shaped placeholders.
- Prefetch detail images when intent is clear, such as on opening a listing.
- Keep existing content visible during silent refreshes.
- Avoid rebuilding an entire screen for a small unread count or row update; select the smallest state slice possible.
- Cap entrance-animation staggering so long lists do not feel delayed.
- Avoid polling hidden screens and avoid running real-time polling while the socket is healthy.
- Dispose text, page, tab, and animation controllers, timers, stream subscriptions, and listeners.

## Security and privacy rules

- Store access and refresh credentials in secure platform storage.
- Never log credentials, passwords, identity numbers, uploaded documents, or full sensitive request bodies.
- Treat session reset as mandatory before a different account can use cached controllers.
- Validate sensitive actions on the backend even when the client disables them.
- Use explicit typed states for consent, verification, payout setup, insufficient balance, and other recoverable gates so the UI can offer the right next step.
- Reuse idempotency keys for retried money-moving requests.
- Do not infer authorization from a hidden button; the server remains the authority.
- Keep secrets, environment-specific URLs, and signing material out of committed source.

## Testing strategy

Test behavior at the layer where it is owned.

### Model tests

- JSON variants and missing optional fields
- unknown enum values
- computed domain properties
- immutable update methods
- optimistic/provisional record markers

### Service and network tests

- method, endpoint, query, headers, and body shape
- success response mapping
- backend validation errors
- timeouts and connection failures
- access-token refresh and request retry
- idempotency key reuse
- empty and malformed payload handling

### Controller tests

- never-loaded, loading, content, empty, and error transitions
- feature-specific filters and derived counts
- row-level operation IDs
- optimistic mid-flight state, success replacement, and failure rollback
- loaded-once markers
- session reset
- refresh deduplication where applicable

### Widget and flow tests

- light and dark mode rendering
- small-screen, keyboard, and large-text layouts
- shared buttons, fields, sheets, state views, cards, and navigation
- action availability for every domain status
- loading controls stay stable in size
- cached content remains visible after refresh failure
- skeletons match final content shape
- complete high-risk flows such as authentication, payment, approval, upload, and sign-out

### Regression tests

Every fixed bug should receive a focused test that fails for the original behavior. Give regression tests names that describe the user-visible contract, not the private method used to implement it.

Before handoff, run the formatter, static analysis, targeted tests for changed features, and the full test suite when the change affects shared core code.

For a Flutter implementation, the default verification sequence is:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test test/<changed_feature_test>.dart
flutter test
```

Use the project’s documented equivalents when it adopts custom scripts, code generation, flavors, integration tests, or golden tests. Never regenerate or upgrade dependencies incidentally during an unrelated feature task.

## Agent working agreement

An implementation agent should follow this sequence for each feature:

1. Read this brief, the current product requirements, the backend/API contract, and neighboring feature code before editing.
2. State any assumptions where product or backend behavior is ambiguous.
3. Identify the smallest complete vertical slice: model, service, controller, view, state handling, and tests.
4. Reuse existing tokens, widgets, network behavior, and controller mixins before creating new abstractions.
5. Add new shared code only when the behavior is cross-feature and the shared API is clear.
6. Implement the success path and every relevant loading, empty, offline, validation, failure, disabled, retry, and dark-mode state.
7. Check session reset, refresh-on-return, operation-level loading, and real-time effects for the feature.
8. Add focused tests before declaring the work complete.
9. Run formatting, analysis, and the appropriate test scope.
10. Report changed files, behavior delivered, tests run, assumptions, and any backend dependency still outstanding.

Agents must preserve unrelated user changes, avoid broad rewrites without a clear need, and never hide failures by deleting or weakening tests.

### Questions an agent must answer before coding

- Who is allowed to see and perform this action?
- What is the backend source of truth?
- What does the screen show before the first response?
- What does a genuinely empty result mean?
- What remains visible during refresh?
- Which exact control becomes busy during a mutation?
- Can the change be optimistic, and how is it rolled back?
- What happens after returning from the next screen or resuming the app?
- Does this state contain user-specific data that must reset on sign-out?
- Can a real-time event change it while the user is looking?
- What happens offline, on timeout, and after expired credentials?
- Does the layout work in dark mode, on a small device, with the keyboard open, and with larger text?
- Which tests prove the user-visible contract?

### Agent handoff format

Use this compact format when an agent finishes a task:

```text
Outcome
- What now works for the user

Implementation
- Important architectural or design decisions
- Shared components or contracts reused/added

Verification
- Formatter/static analysis result
- Targeted tests run
- Full-suite result, if run

Assumptions or follow-ups
- Backend dependency, known limitation, or “None”
```

## Suggested build order

Build the app in this sequence so foundations settle before feature screens multiply:

1. Product roles, permissions, main objects, statuses, and backend contract
2. Semantic theme, typography, spacing, shapes, shadows, motion, and dark mode
3. Shared API client, typed failures, secure token storage, and auth lifecycle
4. Shared app shell, route behavior, app bar, and role-aware navigation
5. Shared inputs, buttons, sheets, state views, loading treatments, and feedback
6. Authentication and session reset
7. One end-to-end vertical feature slice proving the architecture
8. Remaining features, one complete slice at a time
9. Real-time coordination and reconnect reconciliation
10. Cross-feature performance, accessibility, responsive, and regression pass

Do not build all models first, then all services, then all screens. Complete and test one user-visible slice before expanding the pattern.

## Implementation rules

Create semantic design tokens before building feature screens:

- `pageBackground`
- `surface`
- `elevatedSurface`
- `recessedSurface`
- `border`
- `textPrimary`
- `textSecondary`
- `textMuted`
- `textReading`
- `action`
- `success`
- `warning`
- `danger`
- `info`
- a matching surface token for every semantic accent
- three radius tokens
- a spacing scale
- one type ramp
- card and raised shadow recipes
- motion duration and easing tokens

Build shared components for buttons, press behavior, app bars, sheets, field labels, inputs, search, segmented controls, cards, pills, toasts, skeletons, empty states, error states, and content transitions. Feature screens should compose these components instead of recreating styling locally.

Do not scatter raw colors, radii, shadows, text sizes, or transition durations through feature code. If a visual choice is repeated, make it a token or shared component.

Keep code comments focused on **why** a choice or invariant exists, especially when it prevents a subtle lifecycle, accessibility, API-contract, or state-consistency bug. Do not narrate obvious syntax.

## Non-negotiable constraints

- Do not copy Oasis’s exact palette, logo, name, assets, or property-specific wording.
- Do not use more than one primary CTA in the same visual region.
- Do not put every section inside a card.
- Do not use pure black as the dark-mode page background.
- Do not use uppercase for long headings or paragraphs.
- Do not rely on color alone for selection or status.
- Do not mix several corner-radius systems.
- Do not use generic spinners when a contextual loading treatment is possible.
- Do not add animation unless it explains navigation, hierarchy, progress, selection, or feedback.
- Do not let minimalism remove necessary labels, instructions, feedback, or next steps.
- Do not make network calls directly from views.
- Do not let services navigate, show feedback, or own widget state.
- Do not put every feature into one global controller.
- Do not treat “not loaded yet” as “loaded and empty.”
- Do not blank useful content during a background refresh.
- Do not use optimistic UI without a complete rollback path.
- Do not let per-user controller state survive logout or a new login.
- Do not duplicate transport, token-refresh, timeout, or error parsing logic in feature services.
- Do not weaken existing tests or bypass architecture merely to make a feature compile.

## Final quality checklist

Before considering the app ready, confirm that:

- A user can identify the purpose and next action on every screen within a few seconds.
- The same typography, spacing, shape, and interaction rules appear across all features.
- Most screens use neutral space, with accent color reserved for meaning.
- Light and dark modes both have clear surface depth and readable semantic states.
- Every loading, empty, error, disabled, success, and offline state is designed.
- Onboarding art depicts the real product rather than generic decoration.
- Cards and skeletons have matching silhouettes.
- Pressed, selected, loading, and completed controls all give immediate feedback.
- Navigation contains only true top-level destinations.
- Long text, large text settings, keyboard display, and small screens do not break the layout.
- Every feature follows the Model → Service → Controller → View boundary.
- Dependencies are created in one visible composition root and are injectable in tests.
- Per-user controllers reset fully at session boundaries.
- Never-loaded, empty, offline, failed refresh, and row-level busy states are distinct.
- Optimistic changes have tested success and rollback paths.
- Hidden tabs do not fetch or poll unnecessarily, while returning screens refresh stale data.
- Network errors are typed and user-facing messages never expose raw transport details.
- Shared core changes pass the full test suite as well as focused feature tests.

## Copy-and-paste build instruction

Build `[APP_NAME]`, a `[TYPE_OF_APP]` for `[AUDIENCE]` that helps them `[CORE_JOB]`. Give it a warm, trustworthy, quietly premium visual language. Use a geometric sans-serif, tight bold headings, clear sentence-case copy, small tracked uppercase labels, generous 20–24 px gutters, an 8-point spacing rhythm, and a consistent 8/16/24 px radius system.

Choose an original palette rather than copying Oasis. Define colors semantically: a soft neutral page, standard and raised surfaces, a recessed input surface, one primary brand/action accent, and separate positive, caution, informational, danger, and attention roles. Keep most of each screen neutral and use accent color only for actions, selected states, important values, and meaningful status. Create a warm stepped dark-mode surface ramp instead of using pure black.

Use bordered cards with subtle two-layer depth, full-width primary buttons, soft filled inputs with a focused accent ring, raised-thumb segmented controls, compact status pills, consistent bottom sheets with pinned actions, contextual toasts, content-shaped skeletons, useful empty states, and specific error states. Keep navigation to three to five true destinations and use a floating rounded bottom bar only when multiple destinations exist.

For onboarding, create handcrafted miniature scenes of the real product using layered native UI panels, simplified believable data, slight rotations, soft shadows, one floating status chip, and at most one meaningful loop. Pair them with benefit-led titles and concise body copy. Use authentic, consistently treated photography where real people, places, or objects improve trust.

Add shallow press scaling, short fades, gesture-linked selection movement, restrained list entrances, one consistent page transition, and contextual haptics. Design every loading, empty, offline, error, disabled, success, and dark-mode state. Centralize all tokens and shared components before composing the final screens.

Structure the code feature-first using Model, View, Controller, and Service boundaries. Keep cross-feature networking, session lifecycle, theming, utilities, and reusable widgets in a small `core` layer. Build dependencies in one composition root. Inject services and the shared API client so controllers and network behavior can be tested without real requests. Keep domain state out of widgets, UI behavior out of services, and backend parsing out of screens.

Model never-loaded separately from loaded-empty, preserve content during silent refreshes, refresh visible screens on mount, return, tab re-entry, and app resume, and prevent overlapping loads. Use record-level busy identifiers for mutations. When using optimistic UI, mark provisional records, replace them with server data on success, and roll them back completely on failure. Reset every user-scoped controller and live connection at session boundaries.

Centralize authentication headers, secure token storage, token refresh, timeouts, typed connection errors, response parsing, and idempotency behavior in the network layer. Use one app-level hub for real-time events and reconcile state after reconnect. Add model, service, controller, widget, flow, dark-mode, layout, and regression tests. Before handoff, format the code, run static analysis, run focused tests, and run the full suite when shared core behavior changes.
