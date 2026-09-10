# Agent Context for Oasis

## Project Overview
Oasis is a Nigerian prop-tech platform focused on secure, fraud-free rentals.
Two roles share one app: **landlords** list verified properties, invite tenants
and approve applications; **tenants** browse the marketplace, apply for units,
sign agreements and pay rent into escrow.

## Core Rules & Constraints

1. **Architecture & State Management:**
   - Strictly modular, "Feature-First" MVCS architecture.
   - Use `provider` for state management and DI.
   - Do NOT organize by file types globally; organize by feature
     (`lib/features/<feature>/{controllers,models,services,views}`).
   - Cross-feature building blocks live in `lib/core/`
     (`network`, `session`, `theme`, `utils`, `widgets`).

2. **Backend Integration:**
   - The app talks to a **real Django backend**, not mocks. Base URL is
     `ApiConstants.stagingBaseUrl`; every endpoint path is declared in
     `lib/core/network/api_constants.dart` rather than inline at call sites.
   - All HTTP goes through `ApiClient`, which owns auth headers, token refresh,
     timeouts and multipart uploads.
   - Error handling is typed, and screens are expected to branch on the type:
     - `NetworkException` — never reached the server. Offer **Try again**.
     - `ConsentRequiredException` — `403 CONSENT_REQUIRED`. Route to consent.
     - `ApiException` — the server rejected it; `.message` is already
       user-presentable. Never surface the raw debug string in a toast.
   - Money arrives as decimal strings (`"450000.00"`). Format with
     `OasisCurrency`, which groups digits textually — never parse to `double`.
   - Money is *typed* through `OasisThousandsFormatter`
     (`core/utils/oasis_input_formatters.dart`), which groups digits as they
     are entered. Every money field carries it. The separators are display
     only: read the field back with `OasisThousandsFormatter.digitsOf(...)`
     before it goes anywhere near the wire, and seed a field from a backend
     amount with `groupAmount(...)`. A raw `text.trim()` on one of these
     fields sends `"450,000"`, which a serializer rejects and a query
     parameter silently matches against nothing.
   - Historical note: `IAuthService`/`IDashboardService` and their mock
     implementations survive from the pre-API phase. Auth and dashboard still
     depend on those interfaces; every feature added since (marketplace,
     properties, payments, agreements, notifications) uses a concrete service
     directly. Do not introduce new mock services — follow the concrete pattern.

3. **Session Hygiene:**
   - Providers are created once at startup and live for the whole process, so
     any controller caching per-user data MUST implement
     `SessionScopedController` and be registered in the composition root
     (`main.dart`). Without it, one user's data is rendered to whoever signs in
     next. `resetSessionState()` must not make network calls.

4. **Theme & UI Guidelines:**
   - The palette is warm and earthy, defined in `AppTheme`. Use the semantic
     aliases (`primaryColor`, `actionColor`, …), not raw hex, and never
     hardcode `Colors.grey` for text or borders — light and dark both ship.
     - **Terracotta** `#B65F3C` — primary/action: headings, primary buttons, CTAs.
     - **Sage green** `#6F8F72` — success, paid states, completed evidence.
     - **Sand** `#D6B98C` — vacant units, warnings, pending states.
     - **Slate grey** `#64748B` — profile surfaces, secondary chrome.
     - **Brick red** `#A44A3F` — escrow disputes, sign-out, destructive actions.
   - Read theme-aware colors through the helpers — `surfaceColor(context)`,
     `subtleSurfaceColor(context)`, `borderColor(context)`,
     `secondaryTextColor(context)`, `mutedTextColor(context)`.
   - **Three radii only** — `radiusSm` 8, `radiusMd` 16, `radiusLg` 24. Pick the
     nearest; inventing a fourth is what made the UI read as hand-assembled.
   - **One type ramp** — `screenTitle`, `sectionTitle`, `cardTitle`, `bodyText`,
     `labelText`. Headings carry negative tracking by design.
   - Elevation comes from `cardShadow`/`raisedShadow` (a tight contact shadow
     plus a wide soft one). A single blurred shadow reads muddy or flat.

5. **Freshness — the app re-reads rather than waiting to be dragged:**
   - Screens that fetch mix in `AutoRefreshMixin` (`core/utils/oasis_refresh.dart`)
     and implement `onAutoRefresh()`. It fetches on mount, again when a pushed
     route pops (`oasisRouteObserver`, registered on the `MaterialApp`), again
     when its **tab becomes visible**, and again on app resume. Do NOT
     hand-roll `addPostFrameCallback` for a first load any more.
   - The tab trigger is `OasisTabVisibility`, which `MainScaffold` wraps each
     tab in. It exists because the bottom bar is an `IndexedStack`: switching
     tabs mounts nothing, disposes nothing and pushes no route, so every
     screen used to sit on whatever it loaded when it was first built and
     pull-to-refresh was the only way out. It also *defers* the opening fetch
     of a tab nobody has opened — an `IndexedStack` builds all its children at
     once, and without it four screens fetched on the first frame.
   - Set `autoRefreshInterval => kOasisPollInterval` only where the user is
     waiting on somebody else: booking requests, applications, the messaging
     inbox. Polling a screen nobody is waiting on is battery — which is why
     Fix stopped polling when it stopped being a marketplace.
   - After a mutation the screen owns, call `refreshNow()` rather than trusting
     the value the mutation echoed back.
   - Controllers mix in `LoadedOnceState` and call `markLoaded(key)` in the
     `finally` of each loader. Every list branches on
     `!controller.hasLoaded(key) || (isLoading && list.isEmpty)` before it may
     render an empty state — `isLoading` is false both *before* a load starts
     and after it ends, and the old check made every screen flash "nothing
     here" before its data arrived. `resetSessionState()` must call
     `resetLoadedState()`.

6. **Shared UI Components — reach for these before writing new chrome:**
   - `OasisPickerField` + `openStatePicker` / `openCityPicker`
     (`core/widgets/oasis_place_picker.dart`) over `NigeriaLocations`
     (`core/utils/nigeria_locations.dart`) — states and cities are **picked,
     never typed**. Both sides of the marketplace filter compare the landlord's
     string against the tenant's, so "Lagos" and "lagos state" were two
     different places and neither user was told why. `canonicalState` is also
     what the geocoder's answer is normalised through, so a pin that resolves
     "Federal Capital Territory" fills the box with the one spelling the
     picker offers.
   - `OasisSheet` — the one bottom-sheet chrome: grab handle, header block,
     scrolling body, pinned keyboard-aware footer. Pair with
     `oasisInputDecoration()`, `OasisFieldLabel`, `OasisSheetButton`,
     `OasisSheetChipButton`. Present it with
     `backgroundColor: Colors.transparent` — the sheet paints its own surface.
   - `OasisStateViews` (`OasisEmptyState`, `OasisErrorState`,
     `OasisErrorBanner`) — every list needs empty, error and offline states,
     and a failure with content already on screen is a banner, not a takeover.
   - `OasisShimmer` family (`OasisCardSkeleton`, `OasisSkeletonList`,
     `OasisListingSkeleton`) for loading, not a bare `CircularProgressIndicator`.
   - `OasisPressable` for tap feedback (scale dip + haptic), `OasisToast` for
     transient messages, `OasisEntrance` for staggered list reveals.

7. **Coding Standards:**
   - Meticulously comment every class, complex method, and UI feature.
     Explain *why*, not what — the codebase's existing comments are the model.
   - Keep `build` methods small. Extract UI into private stateless widgets.
   - Avoid duplicating logic. Read the surrounding code before adding new code.
   - `flutter analyze` must be clean before a change is considered done.

8. **Fix is a directory, not a marketplace:**
   - Oasis used to broker repairs — request, accept, quote, pay into escrow,
     confirm, release. API guide 18 (§7B) removed every endpoint behind that,
     and `FixJob`, `FixJobStatus`, `FixUrgency`, the artisan job queue, the
     request sheet and seven notification types went with them. Do not
     reintroduce any of it without a backend change to point at.
   - What is left: find a verified artisan, see their phone number, ring them.
     The number used to be released only once a job was accepted — that gate
     was most of why the workflow existed — and is now always present.
   - **An artisan's whole app is one screen**, `ArtisanHomeScreen`: the
     listing others find them by. They take no jobs through Oasis and are paid
     no money through it, so they have no bottom bar (`MainScaffold` renders
     one only for a role with more than one destination) and no Messages
     button (threads hang off an application or a tenancy; an artisan has
     neither).
   - A landlord browses the directory from `/landlord/artisans/`, a tenant
     from `/tenant/fix/artisans/`. They are not interchangeable: a landlord
     calling the tenant route is refused with a 403.

9. **Realtime — the app is told, it does not only ask:**
   - One WebSocket for the whole app (`core/network/realtime_socket.dart`),
     opened on sign-in and while the app is in the foreground, authenticated
     with the access token in the `Authorization` header — never in the query
     string, which is a credential in every proxy log between here and Render.
     The heartbeat is **server-first**: it sends `ping` every 25 seconds and
     the app answers `pong`. Silence is the only symptom a dead socket has, so
     70 seconds of it tears the connection down and rebuilds. Pinned end to
     end against a real WebSocket server in `realtime_socket_test.dart`.
   - `core/session/realtime_hub.dart` is the only place that knows what a
     socket frame *means*. Feature controllers expose `applyIncoming…`
     methods and know nothing about sockets; the hub decides where an event
     goes and whether it is worth interrupting the user for.
   - **The socket is never load-bearing.** Every screen behind it still
     fetches over REST, and messaging keeps its poll timer armed, skipping
     the request while the socket is up. A backend with no `/ws/realtime/`
     gives you exactly the old behaviour, more slowly. New live features must
     keep that property.
   - `OasisPopups` (`core/widgets/oasis_popup_notification.dart`) is the
     in-app banner for things that happen *to* the user. It is not
     `OasisToast`: a toast reports the result of something the user just did
     and is shown with that screen's context; a popup is an interruption with
     no screen in the call stack, so it reaches the overlay through
     `oasisRootOverlay`. A screen that would be reporting news the user can
     already see calls `OasisPopups.suppress()` / `resume()`.
   - `oasisNavigatorKey` (`core/utils/oasis_navigator.dart`) is the only
     sanctioned global navigator, and only for callers with no context of
     their own. Do not reach for it from a screen.

10. **BuildContext lifetime — the app's most common crash:**
   - Never store a `BuildContext` in a widget field or pass one down the tree.
     An ancestor lookup on a deactivated element does not return null, it
     trips an assertion (*"Looking up a deactivated widget's ancestor is
     unsafe"*), which is a hard stop in debug.
   - When something has to outlive the widget that started it — a sheet that
     pops itself and then opens another — capture the *objects* first
     (`Navigator.of(context)`, `context.read<Controller>()`) and use those.
     `NavigatorState` and a controller both outlive every sheet.
   - **A flow that awaits more than one sheet takes a `NavigatorState`, not a
     `BuildContext`.** `openAddPropertyFlow` is the model: capture the
     navigator once, present every sheet from `navigator.context`, and guard
     between steps on `navigator.mounted`. The screen that opened such a flow
     is not guaranteed to survive it — `MainScaffold` swaps its whole body
     for the verification screen whenever a request returns
     `403 VERIFICATION_REQUIRED` — and the next sheet then dies inside
     `debugCheckHasMediaQuery` on a context whose element has left the tree.
     `context.mounted` does not prevent it: it is checked before an `await`
     and the swap happens during one.
   - `OasisErrorGuard` (`core/utils/oasis_error_guard.dart`), installed first
     thing in `main()`, logs every framework and async error under
     `[OASIS ERROR]` and replaces the release-mode red box with a small card,
     so one broken widget no longer takes a page with it. It makes these bugs
     legible; it does not make them acceptable.

11. **Signed is not the same as moved in** (API guide 19 §1):
   - A tenancy signed by both parties sits at `AWAITING_FIRST_RENT` until the
     money reaches escrow, and the backend **voids it after 72 hours** if it
     does not. `first_rent_due_by` is the deadline and it is always the
     backend's: never compute one here, a client clock a day fast would show
     a live tenancy as lapsed.
   - **`canPayRent` must accept `AWAITING_FIRST_RENT`.** It reads
     `payRentUnlocked && isBothSigned`. Writing it as `isExecuted && …`, which
     is what it said before guide 19, leaves the tenant with no way to pay
     during the only window in which paying matters, and the backend then
     voids the tenancy for a non-payment the app made impossible. Any check
     that means "signing is done" is `isBothSigned`, not `isExecuted`.
   - `awaitingFirstRent` prefers the backend's own answer (`status`, then
     `first_rent_settled`) and only falls back to reading the rent block for a
     deployment that predates guide 19. Keep that fallback conservative:
     `NOT_DUE` and a missing `rent_payment` both mean "settled", because that
     is how a tenancy the landlord imported with rent already collected
     arrives, and accusing a paid-up tenant of owing money is the worse
     failure.
   - Units carry `availability` (`AVAILABLE | RESERVED | OCCUPIED`).
     `is_occupied` alone was two ideas in one boolean; `UnitModel.occupancyLabel`
     is the single place that turns the three states into words.
   - A unit also carries `active_agreement` (id, status, `conversation_id`),
     which is what the landlord's **Message tenant** button hangs off. Do not
     go back to scanning `AgreementController.agreements` for a matching
     `unit`: that held every agreement in memory to draw one button, and was
     wrong whenever that list had not been fetched.

12. **Removing a property is a request, not a delete** (API guide 19 §6):
   - Three calls: `POST …/removal-request/` (refused `409` with per-unit
     reasons while a tenancy, escrow, booking or application is live),
     `confirm` with the account password, `DELETE` to cancel. Seven days of
     cooling off, and **nothing is ever hard-deleted** — an archived property
     still resolves, so the agreements and payments pointing at it keep
     working. That is what makes offering the button acceptable at all.
   - `PropertyRemovalBlocked` carries the reasons per unit rather than one
     flattened sentence: the landlord's next move is on a specific flat.

13. **Phone push is out of scope for the MVP** (API guide 19 §2):
   - The backend endpoints are live and the paths are catalogued in
     `ApiConstants`, but the app registers no device token and shows no push
     setting. Do not add one: a switch over a preference the app cannot act
     on promises alerts that never arrive.
   - What it would take, when it comes back: a Firebase project (one for both
     platforms, plus an APNs key before iOS works at all), then
     `firebase_messaging` + a `google-services.json` — **the dependency
     without that file fails the Android build** — then register on sign-in
     and, more importantly, unregister on sign-out. Registering late costs
     somebody a notification; failing to unregister keeps sending a tenancy's
     rent reminders to a phone whose owner signed out weeks ago.
   - In-app notifications, the WebSocket and the 45-second fallback poll all
     work and are unaffected. The gap is only what reaches a closed app.

14. **Testing:**
   - Tests live in `test/` and cover contracts and states rather than golden
     pixels: backend lifecycle contracts, session reset, connection-error
     branching, application decision state, currency formatting, and widget
     smoke tests for state views and skeleton layout.
   - When a UI bug is structural (a layout that throws rather than renders),
     pin it with a widget test — see `shimmer_layout_smoke_test.dart`.
