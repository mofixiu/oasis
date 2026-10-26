# Oasis v2, every screen (2026-10-26)

Taken on an iPhone 18 Pro Max simulator (1320 × 2868), light mode, from `tool/v2_preview_main.dart`.

The preview answers every API call with sample data shaped the way staging answers today (API guide 20): `/app-config/` with every value blank, saved shortlets on the server, a host payout due 24 hours after checkout, one new place that is live before it has photos, and one booking with an open caution-fee claim. **Names, prices, bookings, messages and photos are placeholders.**

## Signed out

| # | Screen |
| --- | --- |
| 01–03 | Welcome tour |
| 04 | Sign in |
| 05 | Sign up, Guest selected |

## Guest

| # | Screen |
| --- | --- |
| 06–07 | Home: search, occasions, Plan your trip, Featured shortlets (the new place shows "No photos yet") |
| 08 | Discover |
| 09 | Discover filters: dates, price, bedrooms |
| 10 | My trips, Upcoming: caution fee held, comes back 24 hours after checkout |
| 11 | My trips: the host claimed part of the caution fee, with Respond |
| 12 | My trips, Past: caution fee back in the vault |
| 13–14 | Inbox: Messages and Updates |
| 15–16 | Payments: vault, Save for this trip, vault activity |
| 17 | Search |
| 18–19 | Shortlet listing |
| 20 | Shortlet listing for a place with no photos yet |
| 21 | Booking details |
| 22 | Booking details with an open caution-fee claim |
| 23–24 | Chat, and chat details with Call host, Report an issue, Block host |
| 25 | Profile |
| 26 | Edit profile: name read-only for verified users |
| 27 | Saved shortlets |
| 28 | Help & support: only "Send us a message" while no contacts are set |
| 29 | Terms & policies: Terms and Privacy "Coming soon" until the links are set |
| 30 | Payments opened from Profile's Vault tile |

## Host

| # | Screen |
| --- | --- |
| 31 | Host home: "1 checkout to inspect" |
| 32–33 | Shortlets, Requests: checkout inspection, payout release time, a claim waiting on the guest |
| 34 | Shortlets, My places: photo prompts |
| 35 | List a place (one request to `POST /host/listings/`) |
| 36 | Inbox |
| 37–38 | Payments: vault, and payouts with their release times |
| 39 | Profile |
