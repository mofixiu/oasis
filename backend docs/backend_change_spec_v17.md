# Oasis Backend Change Specification — v17: Stay and Review Photos

> **Audience:** Backend and Flutter developers working on the short-stay app.
>
> **Date:** 2026-10-26
>
> **Status:** Stay photos are already supported by the unit-media API and the Flutter app. Review photos are a proposed API addition; they are not supported by the current review endpoint.
>
> **Companion docs:** `flutter_api_guide (20).md` §Unit Media documents the existing unit-photo contract. `backend_change_spec_v7.md` §4 describes the current review contract.

## Summary

| Capability | Status | API |
| --- | --- | --- |
| Add and manage photos of a short-let stay | Available | `GET/POST /api/users/units/{unit_id}/photos/`, `DELETE /api/users/units/{unit_id}/photos/{photo_id}/` |
| Attach photos to a review | Not available yet | Proposed extension to `POST /api/users/reviews/` below |

Stay photos belong to the **unit** guests book. Review photos belong to one **completed booking review**. They are separate media records and must not be mixed into the listing's photo gallery.

## 1. Stay photos: existing support

### 1.1 Host flow in the app

In the v2 app, hosts can add or manage stay photos from:

- **Home → Your places → Add photos / Manage**.
- **Shortlets → My places → photo control**.
- Immediately after creating a short-let listing, which opens the unit's photo manager.

The photo action opens the existing unit media sheet. It loads the current unit photos, uploads selected images, and supports deleting an image. A newly created listing may be visible before photos are added, so the app handles an empty photo list and prompts the host to add pictures.

Guests see the unit photos on the stay card, listing details and booking details. The listing payload supplies `photo_urls` and, when selected, `cover_photo_url`.

### 1.2 Existing API contract

All unit-media endpoints require an authenticated, verified `OWNER`. The unit must belong to a property owned by that account.

```text
GET    /api/users/units/{unit_id}/photos/
POST   /api/users/units/{unit_id}/photos/
DELETE /api/users/units/{unit_id}/photos/{photo_id}/
```

Upload one or more images as `multipart/form-data`, using a repeated `photos` field:

```text
photos=<image file>
photos=<another image file>
```

Current limits are 12 photos per unit, 5 MB per image, and JPG/JPEG, PNG or WEBP. The response contains photo records:

```json
[
  {
    "id": "PHOTO_UUID",
    "image_url": "https://example.supabase.co/storage/v1/object/public/...",
    "created_at": "2026-10-26T10:00:00Z"
  }
]
```

The unit serializers used by short-let listings expose:

```json
{
  "photo_urls": ["https://…/living-room.jpg", "https://…/bedroom.jpg"],
  "cover_photo_url": "https://…/living-room.jpg"
}
```

Keep unit photos distinct from property photos. Property photos describe the building or compound and use `/properties/{property_id}/photos/`; unit photos show the specific apartment or room a guest will book.

## 2. Review photos: proposed API addition

### 2.1 Current limitation

`POST /api/users/reviews/` currently accepts JSON fields for `subject_type`, `subject_id`, `transaction_id`, `rating` and `comment`. It has no file field, and review responses contain no image records. A guest cannot attach photos to a review today.

### 2.2 Create a review with photos

Extend `POST /api/users/reviews/` to accept both existing JSON requests and `multipart/form-data` requests. JSON requests without photos must continue to work unchanged. Multipart requests use the same review fields plus zero or more repeated `photos` fields:

```text
subject_type=SHORT_LET
subject_id=LISTING_UUID
transaction_id=BOOKING_UUID
rating=5
comment=The place looked just like the photos.
photos=<image file>
photos=<another image file>
```

Example request:

```bash
curl -X POST "$API_BASE/users/reviews/" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "subject_type=SHORT_LET" \
  -F "subject_id=LISTING_UUID" \
  -F "transaction_id=BOOKING_UUID" \
  -F "rating=5" \
  -F "comment=The place looked just like the photos." \
  -F "photos=@living-room.jpg" \
  -F "photos=@balcony.jpg"
```

Return `201 Created` with the saved review and its photo records:

```json
{
  "id": "REVIEW_UUID",
  "subject_type": "SHORT_LET",
  "subject_id": "LISTING_UUID",
  "rating": 5,
  "comment": "The place looked just like the photos.",
  "author_name": "Ada O.",
  "author_role": "TENANT",
  "photos": [
    {
      "id": "REVIEW_PHOTO_UUID",
      "image_url": "https://example.supabase.co/storage/v1/object/public/...",
      "created_at": "2026-10-26T10:00:00Z"
    }
  ],
  "created_at": "2026-10-26T10:00:00Z"
}
```

`GET /api/users/reviews/?subject_type=SHORT_LET&subject_id=…` must include the same `photos` array on each review. Return an empty array when a review has no photos. `GET /api/users/reviews/summary/` does not need to include photos.

### 2.3 Validation and ownership

Use the existing review authorization and transaction checks without weakening them:

- The author must be the guest on the supplied booking.
- The booking must be paid and checked out.
- `subject_id` must be the listing for that booking.
- The author may submit only one review for that booking.
- Rating stays within 1–5 stars; comment stays within the existing 1,000-character limit.
- Photos are optional. A review without photos remains valid.
- Proposed limit: up to 5 photos per review, 5 MB per image, and JPG/JPEG, PNG or WEBP only.
- Validate detected file type and decoded image content server-side; do not trust the filename or client MIME type.
- Reject the entire submission if any photo is invalid. Do not leave a review with only some of the files the guest selected.
- If database or object-storage writes fail, clean up any orphaned uploads and return a retryable error. Preserve the existing duplicate-review response for a retried booking.

Photo URLs inherit the review's visibility: signed-in users who can read a public review can read its attached photos. Do not include uploader email, local file paths or other private metadata in the response.

Reviews cannot currently be edited after posting. Treat attached photos as immutable after creation too; any removal or moderation should follow the existing review-removal and moderation process rather than adding an unscoped delete endpoint.

### 2.4 Flutter acceptance criteria

When the backend contract is implemented, the review form should:

1. Offer an optional **Add photos** control and allow up to 5 selected images.
2. Show selected-image previews and allow a guest to remove a selection before posting.
3. Submit the rating, comment and selected files together as multipart form data. Keep JSON submission for reviews without photos if that is simpler for compatibility.
4. Show uploaded review photos in the review card and open them in a gallery viewer.
5. Keep review submission tied to the same completed booking and display upload failures without losing the guest's typed comment or selected photos.

Until the backend accepts and returns review photos, do not show a photo picker that appears to publish images. Stay-photo uploads are already usable through the host flows in §1.
