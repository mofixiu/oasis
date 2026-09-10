class ApiConstants {
  // Base URLs
  static const String stagingBaseUrl =
      'https://landa-os-staging.onrender.com/api/users';
  static const String localBaseUrl = 'http://127.0.0.1:8000/api/users';
  static const String androidEmulatorBaseUrl = 'http://10.0.2.2:8000/api/users';

  // Default Base URL (Staging per flutter_api_guide.md)
  static String baseUrl = stagingBaseUrl;

  // Endpoint Paths
  static const String registerEndpoint = '/register/';
  static const String loginEndpoint = '/login/';
  static const String refreshTokenEndpoint = '/token/refresh/';
  static const String profileEndpoint = '/profile/';
  static const String verifyEndpoint = '/verify/';
  static const String verificationStatusEndpoint = '/verify/status/';
  static const String passwordResetRequestEndpoint = '/password/reset/request/';
  static const String passwordResetConfirmEndpoint = '/password/reset/confirm/';
  static const String consentsEndpoint = '/consents/';

  // Landlord payout setup
  static const String banksEndpoint = '/banks/';
  static const String payoutAccountEndpoint = '/payout-account/';
  // Resolves a bank account with the provider without saving it, so the
  // landlord confirms the name the bank returns rather than typing their own.
  static const String payoutAccountResolveEndpoint = '/payout-account/resolve/';

  // Vault: every user has one. Rent released from escrow lands in the
  // landlord's; the tenant's is savings they top up ahead of a rent bill and
  // pay out of. Same balance, same ledger, same withdrawal route, so the two
  // roles share one set of endpoints rather than a parallel pair.
  //
  // A payout account is only required at withdrawal time.
  static const String vaultEndpoint = '/vault/';
  static const String vaultTransactionsEndpoint = '/vault/transactions/';

  // The 4-digit PIN guarding everything that moves money *out* of the vault:
  // withdrawals to a bank, and a tenant paying rent from their balance. One
  // path serves GET (status), POST (create) and PATCH (change).
  static const String vaultPinEndpoint = '/vault/pin/';
  static const String withdrawalsEndpoint = '/vault/withdrawals/';
  static String withdrawalDetailEndpoint(String withdrawalId) =>
      '/vault/withdrawals/$withdrawalId/';

  // Tenant top-ups: money into the vault through the same provider checkout
  // rent already uses.
  static const String vaultTopUpsEndpoint = '/vault/topups/';
  static String verifyTopUpEndpoint(String topUpId) =>
      '/vault/topups/$topUpId/verify/';

  // Short lets: nightly stays. A landlord lists a unit for daily booking; a
  // tenant requests dates, waits for approval, then pays. Deliberately a
  // parallel set of paths to the rental ones rather than a flag on them: a
  // booking is not an application and a nightly price is not rent.
  static const String landlordShortLetsEndpoint = '/landlord/short-lets/';

  /// One listing, for editing it.
  ///
  /// Creating and editing used to be the same `POST`: the backend keyed a
  /// listing to its unit and treated a second post as an edit. As of API
  /// guide 18 it does not: a second `POST` for a unit that already has a
  /// listing is refused with `409 LISTING_EXISTS`, and every edit comes here
  /// instead.
  static String landlordShortLetDetailEndpoint(String listingId) =>
      '/landlord/short-lets/$listingId/';
  static const String landlordShortLetBookingsEndpoint =
      '/landlord/short-let-bookings/';
  static String approveShortLetBookingEndpoint(String bookingId) =>
      '/landlord/short-let-bookings/$bookingId/approve/';
  static String rejectShortLetBookingEndpoint(String bookingId) =>
      '/landlord/short-let-bookings/$bookingId/reject/';

  static const String tenantShortLetsEndpoint = '/tenant/short-lets/';
  static const String tenantShortLetBookingsEndpoint =
      '/tenant/short-let-bookings/';
  static String cancelShortLetBookingEndpoint(String bookingId) =>
      '/tenant/short-let-bookings/$bookingId/cancel/';

  /// Quotes the current cancellation refund before the tenant commits to it.
  /// See `backend_change_spec_v7.md` §7: the response shape is not yet
  /// documented, so [ShortLetBooking.withCancelPreview] parses it
  /// defensively.
  static String tenantShortLetCancelPreviewEndpoint(String bookingId) =>
      '/tenant/short-let-bookings/$bookingId/cancel-preview/';

  /// The host's own withdrawal from a booking: an emergency, not the
  /// ordinary reject-a-request path. Requires a reason.
  static String landlordCancelShortLetBookingEndpoint(String bookingId) =>
      '/landlord/short-let-bookings/$bookingId/cancel/';
  static String payShortLetBookingEndpoint(String bookingId) =>
      '/tenant/short-let-bookings/$bookingId/pay/';
  static String verifyShortLetPaymentEndpoint(String paymentId) =>
      '/tenant/short-let-payments/$paymentId/verify/';
  // Raised while the refundable caution fee is still in escrow. Release runs
  // after checkout, so a dispute has to land before that job does: it makes
  // the job skip the caution-fee refund, not the landlord stay payout.
  static String disputeShortLetPaymentEndpoint(String paymentId) =>
      '/tenant/short-let-payments/$paymentId/dispute/';

  /// Tenant marks a payout-blocking dispute settled, so the host payout can
  /// release: immediately, if the release time has already passed.
  static String resolveShortLetDisputeEndpoint(String paymentId) =>
      '/tenant/short-let-payments/$paymentId/resolve-dispute/';

  /// Host opens a claim against the caution fee after checkout, within the
  /// 24-hour claim window the backend enforces.
  static String openShortLetCautionClaimEndpoint(String bookingId) =>
      '/landlord/short-let-bookings/$bookingId/caution-claims/';

  /// Tenant accepts, rejects, or counters a caution-fee claim.
  static String respondToShortLetCautionClaimEndpoint(String claimId) =>
      '/tenant/short-let-caution-claims/$claimId/respond/';

  // Artisan Fix: a directory, not a marketplace.
  //
  // Oasis used to broker the whole repair: a tenant raised a request, an
  // artisan accepted and quoted it, the tenant paid into escrow, and
  // confirming the work released the money. API guide 18 removed all of it
  // (§7B, "2026-09-06 simplification"). Every one of those endpoints is gone
  // from the backend.
  //
  // What is left is smaller and honest about what Oasis is for: a verified
  // artisan can be found, and their phone number is shown to whoever finds
  // them. The repair itself is arranged on the phone, outside the app. The
  // phone number used to be released only once a job was accepted, which is
  // why so much of the old workflow existed at all: it was the thing being
  // gated.
  static const String artisanCategoriesEndpoint = '/artisans/categories/';

  /// The signed-in artisan's own profile. GET reads it, PATCH edits it.
  ///
  /// Now the whole of an artisan's app: keeping this accurate is how they get
  /// found, and there is nothing else for them to do here.
  static const String artisanProfileEndpoint = '/artisans/me/';

  /// One landlord-recommended artisan per category on a unit. GET lists,
  /// POST creates or replaces, DELETE removes: all on the same path, with
  /// the category in the body rather than the URL.
  static String unitArtisanRecommendationsEndpoint(String unitId) =>
      '/units/$unitId/artisan-recommendations/';

  /// The artisan directory as a landlord sees it, for choosing who to
  /// recommend on a unit.
  ///
  /// The path moved: this was `/landlord/fix/artisans/`, guessed at in
  /// `backend_change_spec_v5.md` before the route existed. API guide 18
  /// documents it as `/landlord/artisans/`. The old guess 404s, and the app
  /// used to fall back to the tenant route on a 404, which a landlord is
  /// refused with a 403, so the picker came up empty and no landlord could
  /// recommend anybody.
  static const String landlordArtisansEndpoint = '/landlord/artisans/';

  /// The same directory as a tenant sees it. Takes `category`, an optional
  /// `unit` (which marks the landlord's recommendation), and a typed
  /// `location`.
  static const String tenantFixArtisansEndpoint = '/tenant/fix/artisans/';

  // Which optional emails a user wants, and whether phone push is on. Only
  // the early rent reminders are switchable among the emails; the ones that
  // matter are sent regardless.
  static const String notificationPreferencesEndpoint =
      '/notification-preferences/';

  // Phone push registration (API guide 19 §2) is **not wired up**. The
  // endpoints exist server-side and the paths are recorded below so this
  // file stays a complete catalogue of the API, but nothing calls them:
  // getting a token needs `firebase_messaging`, which needs a
  // `google-services.json`, which needs a Firebase project. Push is out of
  // MVP scope. When it comes back, the notes that matter are: post on every
  // launch (FCM reissues tokens, and the endpoint is idempotent on them),
  // and the `DELETE` on sign-out is the half to get right — without it,
  // "rent is due for Unit A1" keeps reaching a phone whose owner signed out
  // weeks ago. `backend docs/backend_change_spec_v15.md` §3 has the rest.
  static const String devicesEndpoint = '/devices/';
  static String deviceDetailEndpoint(String deviceId) =>
      '/devices/$deviceId/';

  /// The canonical 37 Nigerian states, server-side.
  ///
  /// The app ships its own list in `NigeriaLocations` and does not need
  /// this; it exists so a state added or respelled on the backend does not
  /// require an app release to stay in step.
  static const String statesEndpoint = '/locations/states/';

  static const String propertiesEndpoint = '/properties/';
  static String propertyDetailEndpoint(String propertyId) =>
      '/properties/$propertyId/';
  // Listing media (photos + one property-tour video)
  static String propertyPhotosEndpoint(String propertyId) =>
      '/properties/$propertyId/photos/';
  static String propertyPhotoDetailEndpoint(
    String propertyId,
    String photoId,
  ) => '/properties/$propertyId/photos/$photoId/';
  static String propertyVideoEndpoint(String propertyId) =>
      '/properties/$propertyId/video/';

  /// Taking a property off Oasis. Three calls, deliberately: a property is
  /// not a leaf, and a plain `DELETE` on one with a signed tenancy under it
  /// would delete somebody's home, their agreement and the record of the
  /// rent they paid into escrow.
  ///
  /// `POST` asks, and is refused with `409` and a per-unit list of reasons
  /// while anything is live on it. `confirm` re-enters the account password
  /// and starts a 7-day window in which the property is hidden from tenants
  /// but still the landlord's to change their mind about. `DELETE` cancels.
  /// Nothing is ever hard-deleted: an archived property still resolves, so
  /// an old agreement or payment pointing at it does not break.
  /// See API guide 19 §6.
  static String propertyRemovalRequestEndpoint(String propertyId) =>
      '/properties/$propertyId/removal-request/';
  static String propertyRemovalConfirmEndpoint(
    String propertyId,
    String requestId,
  ) => '/properties/$propertyId/removal-request/$requestId/confirm/';
  static String propertyRemovalCancelEndpoint(
    String propertyId,
    String requestId,
  ) => '/properties/$propertyId/removal-request/$requestId/';

  static String propertyUnitsEndpoint(String propertyId) =>
      '/properties/$propertyId/units/';
  static String propertyUnitsBatchEndpoint(String propertyId) =>
      '/properties/$propertyId/units/batch/';
  // Per-unit listing media. A tenant rents *a flat*, not a building, so the
  // photos and the walkthrough that decide whether they apply have to be of
  // the flat. Property-level media stays for the block itself: the gate, the
  // compound, the street, and these are what the marketplace and Stays lead
  // with. See `backend docs/backend_change_spec_v7.md`.
  static String unitPhotosEndpoint(String unitId) => '/units/$unitId/photos/';
  static String unitPhotoDetailEndpoint(String unitId, String photoId) =>
      '/units/$unitId/photos/$photoId/';
  static String unitVideoEndpoint(String unitId) => '/units/$unitId/video/';

  /// A unit's own record.
  ///
  /// `PATCH` is how a landlord changes what a flat costs after it has been
  /// listed. Until this existed, a rent typed once when the unit was created
  /// was the rent for ever: a landlord who mispriced a flat, or who wanted
  /// to drop it to fill a vacancy, had no way to say so from inside the app.
  /// See `backend docs/backend_change_spec_v12.md` §1.
  static String unitDetailEndpoint(String unitId) => '/units/$unitId/';

  static String assignTenantEndpoint(String unitId) => '/units/$unitId/assign/';
  static const String tenantAssignedUnitEndpoint = '/tenant/assigned-unit/';

  // Tenant marketplace & rental applications
  static const String tenantMarketplaceEndpoint = '/tenant/marketplace/';
  static const String tenantApplicationsEndpoint = '/tenant/applications/';
  static const String landlordApplicationsEndpoint = '/landlord/applications/';
  static String approveApplicationEndpoint(String applicationId) =>
      '/landlord/applications/$applicationId/approve/';
  static String rejectApplicationEndpoint(String applicationId) =>
      '/landlord/applications/$applicationId/reject/';

  static const String agreementsEndpoint = '/agreements/';

  /// Batch import of tenancies that predate Oasis. Proposed in
  /// `backend docs/backend_change_spec_v6.md` §1 and not live yet: the
  /// service falls back to one `POST /agreements/` per row until it is.
  static const String landlordTenancyImportEndpoint =
      '/landlord/tenancies/import/';
  static String signAgreementEndpoint(String agreementId) =>
      '/agreements/$agreementId/sign/';

  static const String paymentsEndpoint = '/payments/';
  static String paymentReceiptEndpoint(String paymentId) =>
      '/payments/$paymentId/';
  static String verifyPaymentEndpoint(String paymentId) =>
      '/payments/$paymentId/verify/';
  static String releaseEscrowEndpoint(String paymentId) =>
      '/payments/$paymentId/release/';
  static String escrowStatusEndpoint(String paymentId) =>
      '/payments/$paymentId/escrow/';
  static String disputePaymentEndpoint(String paymentId) =>
      '/payments/$paymentId/dispute/';

  // Messaging. A conversation exists because an application or a tenancy
  // exists; either party may open one, but only against a live relationship.
  static const String conversationsEndpoint = '/conversations/';
  static String conversationDetailEndpoint(String conversationId) =>
      '/conversations/$conversationId/';
  static String conversationMessagesEndpoint(String conversationId) =>
      '/conversations/$conversationId/messages/';
  static String conversationReadEndpoint(String conversationId) =>
      '/conversations/$conversationId/read/';
  static const String conversationsUnreadCountEndpoint =
      '/conversations/unread-count/';

  // Landlord announcements, fanned out into each tenant's notification list.
  static const String landlordBroadcastsEndpoint = '/landlord/broadcasts/';

  // Ratings and written reviews. One set of paths for every reviewable thing
  //  (a stay, an artisan, a landlord, a tenant) with `subject_type` in the
  // query or body saying which. See `backend docs/backend_change_spec_v7.md`.
  static const String reviewsEndpoint = '/reviews/';
  static const String reviewSummaryEndpoint = '/reviews/summary/';
  static String reviewResponseEndpoint(String reviewId) =>
      '/reviews/$reviewId/respond/';

  static const String notificationsEndpoint = '/notifications/';
  static String markNotificationReadEndpoint(String notificationId) =>
      '/notifications/$notificationId/read/';
  static const String notificationsUnreadCountEndpoint =
      '/notifications/unread-count/';

  // ------------------------------------------------------------- realtime

  /// The single WebSocket every live feature shares.
  ///
  /// One socket rather than one per feature: a phone on Nigerian mobile data
  /// pays for each connection in handshake latency and battery, and the two
  /// things that need to be live (a message arriving and a notification
  /// being raised) are both "something happened to you" and belong on the
  /// same wire. See `backend docs/backend_change_spec_v11.md` §1.
  static const String realtimePath = '/ws/realtime/';

  /// The socket lives on the same host as the REST API, so it is derived
  /// from [baseUrl] rather than configured twice and left to drift.
  ///
  /// `https` → `wss`, `http` → `ws`. The `/api/users` suffix is dropped: the
  /// socket is routed by Django Channels' own URL router, which sits at the
  /// project root rather than under the REST app's prefix.
  ///
  /// The access token is **not** put in the query string. A URL is logged by
  /// every proxy it passes through, and a JWT in one is a credential written
  /// to somebody else's disk; it travels in the `Authorization` header
  /// instead, which the socket sends on the opening HTTP request.
  static Uri realtimeUri() {
    final api = Uri.parse(baseUrl);
    return Uri(
      scheme: api.scheme == 'https' ? 'wss' : 'ws',
      host: api.host,
      port: api.hasPort ? api.port : null,
      path: realtimePath,
    );
  }
}
