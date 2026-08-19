# Agent Context for Landa OS

## Project Overview
Landa OS is a Nigerian prop-tech platform focused on secure, fraud-free rentals.
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
     `LandaCurrency`, which groups digits textually — never parse to `double`.
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

5. **Shared UI Components — reach for these before writing new chrome:**
   - `LandaSheet` — the one bottom-sheet chrome: grab handle, header block,
     scrolling body, pinned keyboard-aware footer. Pair with
     `landaInputDecoration()`, `LandaFieldLabel`, `LandaSheetButton`,
     `LandaSheetChipButton`. Present it with
     `backgroundColor: Colors.transparent` — the sheet paints its own surface.
   - `LandaStateViews` (`LandaEmptyState`, `LandaErrorState`,
     `LandaErrorBanner`) — every list needs empty, error and offline states,
     and a failure with content already on screen is a banner, not a takeover.
   - `LandaShimmer` family (`LandaCardSkeleton`, `LandaSkeletonList`,
     `LandaListingSkeleton`) for loading, not a bare `CircularProgressIndicator`.
   - `LandaPressable` for tap feedback (scale dip + haptic), `LandaToast` for
     transient messages, `LandaEntrance` for staggered list reveals.

6. **Coding Standards:**
   - Meticulously comment every class, complex method, and UI feature.
     Explain *why*, not what — the codebase's existing comments are the model.
   - Keep `build` methods small. Extract UI into private stateless widgets.
   - Avoid duplicating logic. Read the surrounding code before adding new code.
   - `flutter analyze` must be clean before a change is considered done.

7. **Testing:**
   - Tests live in `test/` and cover contracts and states rather than golden
     pixels: backend lifecycle contracts, session reset, connection-error
     branching, application decision state, currency formatting, and widget
     smoke tests for state views and skeleton layout.
   - When a UI bug is structural (a layout that throws rather than renders),
     pin it with a widget test — see `shimmer_layout_smoke_test.dart`.
