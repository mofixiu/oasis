# v1 is switched off

**Date:** 2026-10-17

Oasis now ships only **v2**, the short-stay app (shortlets for guests and hosts). The original **v1** app (long-term rentals: marketplace and applications, tenancy agreements, rent and escrow, the landlord dashboard, Fix and artisans) is switched off, but none of it has been deleted.

## What was changed

| File | Change |
| --- | --- |
| `lib/core/app_variant.dart` | `APP_VARIANT` now defaults to `v2` (it used to default to `v1`). |
| `lib/core/widgets/main_scaffold.dart` | `MainScaffold` always returns `V2MainScaffold`. The whole v1 shell (tabs, role switch, bottom bar) is kept underneath, **commented out line by line**. |
| `lib/features/auth/views/sign_up_screen.dart` | In v2, sign-up opens on Guest, lists Guest before Host, and hides the "Register your trade" artisan route (artisans belong to v1's Fix). |
| `lib/features/auth/views/welcome_screen.dart` | v2 has its own three-slide tour about shortlets; the four v1 slides are kept as `_v1Slides`. |
| Copy across the app | v2 says *guest/host* and *shortlets*. Each change is written as `isOasisV2 ? 'v2 text' : 'v1 text'`, so the v1 wording is still there. |

Everything under `lib/features` that v1 used (dashboard, marketplace, agreements, payments, properties, fix, and so on) is untouched. It still compiles, and the test suite still runs against it.

## What still depends on v1 code

* **Hosts listing a shortlet.** `create_shortlet_sheet.dart` lets a host pick one of their existing units, loaded through `LandlordController` (`/properties/`). Adding properties and units was a v1 dashboard feature, so **a brand-new host in v2 has no way to create the unit they want to list.** This needs a v2 "add a place" flow before hosts can onboard. It is listed as a follow-up in `backend docs/backend_change_spec_v16.md`.
* **The vault.** The v2 Payments tab uses the same vault screens and endpoints as v1 (top-up, withdraw, PIN, ledger, bank account). Nothing about the vault was switched off.

## How to bring v1 back

1. In `lib/core/widgets/main_scaffold.dart`, delete the small v2-only `MainScaffold` class at the top, then uncomment the block under `V1 SHELL (switched off 2026-10-17)` (remove the leading `// ` from each line).
2. Build with `--dart-define=APP_VARIANT=v1`, or change the default in `lib/core/app_variant.dart` back to `v1`.
3. Run `flutter analyze` and `flutter test`.

With `APP_VARIANT=v1`, every `isOasisV2` branch falls back to the original behaviour: the white and slate palette, landlord/tenant wording, the four-slide welcome tour, the artisan sign-up route, and the v1 bottom bar.

## Previewing v2 without a backend

`tool/v2_preview_main.dart` runs the v2 shell signed in as a sample guest, with every API call answered from sample data:

```bash
flutter run -t tool/v2_preview_main.dart --dart-define=PREVIEW_PHOTOS=/absolute/path/to/photos
```

Photos are optional. Without them, listings fall back to the bundled interior photo.
