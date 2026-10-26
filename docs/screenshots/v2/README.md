# Oasis v2 screenshots

Taken on 2026-10-17 on an iPhone 18 Pro simulator (1206 × 2622), light mode, from `tool/v2_preview_main.dart`.

The preview signs in a sample guest and answers every API call with sample data, so **names, prices, bookings, messages and the support contacts on the Help screen are placeholders**. Listing photos are free Unsplash images used for the preview only; they are not bundled with the app.

| # | Screen |
| --- | --- |
| 01–02 | Home: photo hero and search, occasions, Plan your trip, Featured shortlets |
| 03–04 | Discover: photo grid and Trending now |
| 05 | Discover filters sheet (dates, price, bedrooms), opened from the floating Filters button |
| 06 | Search |
| 07–08 | Shortlet listing: photos, amenities, About, policies, Request to book |
| 09–10 | My trips: Upcoming and Past |
| 11–12 | Booking details |
| 13–14 | Inbox: Messages and Updates |
| 15 | Chat |
| 16 | Chat details: booking, Call host, Report an issue, Block host |
| 17 | Report an issue |
| 18–19 | Payments: vault balance, quick actions, Save for this trip, vault activity |
| 20 | Profile |
| 21 | Edit profile |
| 22 | Saved shortlets |
| 23 | Help & support |
| 24–25 | Terms & policies, and the cancellation policies sheet |
| 26–28 | Welcome tour |
| 29 | Sign in |
| 30 | Sign up (Guest selected) |

## Caution fee (`caution-fee/`)

Taken on 2026-10-21 on an iPhone 18 Pro Max simulator (1320 × 2868), same preview and sample data.

| # | Screen |
| --- | --- |
| 01 | Guest, My trips: caution fee held on an upcoming trip |
| 02 | Guest, My trips: the host claimed part of the caution fee, with Respond |
| 03 | Guest, booking details for the claimed trip |
| 04 | Host home: "1 checkout to inspect" with time left |
| 05 | Host Shortlets, Requests: checkout inspection card with the 24-hour countdown |
| 06 | Host Shortlets, Requests: a claim waiting on the guest |
| 07 | Host: "Refund the caution fee now?" confirmation |

## Live v16 backend (`v16/`)

Taken on 2026-10-23 on an iPhone 18 Pro Max simulator, same preview, with the sample server answering the way staging does since API guide 20 (`/app-config/` all blank, saved shortlets live, payouts held until a day after checkout).

| # | Screen |
| --- | --- |
| 01 | New host, Shortlets: nothing listed yet, payout timing in the header |
| 02–04 | List a place: name, address, state and city filled from the map pin, flat or unit, bedrooms, bathrooms, price |
| 05 | Straight after listing: add photos of the new place |
| 06 | Host payout line: "Releases 24 Oct, 1:28 AM, a day after checkout…" |
| 07 | Help & support with no contacts set yet: only "Send us a message" |
| 08 | Chat details before payment: "Call host · Shared once the booking is paid" |
| 09 | Guest Home: a new place that is live before its photos, shown with a plain "No photos yet" tile |
| 10 | Guest, that place's listing page with no photos |
| 11 | Host, My places: "No photos yet. Add some so guests can see it." on the new place, "3 photos · Manage" on the others |
