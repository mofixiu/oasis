import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/core/widgets/oasis_media_hero.dart';
import 'package:oasis_app/core/widgets/oasis_network_image.dart';
import 'package:oasis_app/core/widgets/oasis_video_player.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/core/widgets/oasis_shimmer.dart';
import 'package:oasis_app/features/properties/controllers/landlord_controller.dart';
import 'package:oasis_app/features/properties/models/property_model.dart';
import 'package:oasis_app/features/properties/services/property_service.dart';
import 'package:oasis_app/features/properties/views/widgets/property_media_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How photos arrive is most of what a listing screen feels like, and the two
/// rules that matter are both invisible in a screenshot of the finished
/// state: a photo must *fill* the frame it was given, and nothing may spin
/// while it loads. One was a real bug, the other the complaint that started
/// the rework, so both are pinned here.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );

  group('OasisNetworkImage', () {
    testWidgets('hands the photo the full box, not a loose one', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 300,
            height: 150,
            child: OasisNetworkImage(url: 'https://example.test/photo.jpg'),
          ),
        ),
      );

      // The bug this catches, and the reason the cache package is not left to
      // lay itself out: handed a loose box, `BoxFit.cover` has nothing to
      // cover, and a portrait photo renders as a thin strip with bars down
      // both sides inside a card that was the right shape all along.
      //
      // Asserted by building what the package would build on decode, because
      // a widget test has no network and never decodes one for real.
      final cached = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(
        cached.imageBuilder,
        isNotNull,
        reason: 'the image must be built by hand, not laid out by the package',
      );
      final decoded = cached.imageBuilder!(
        tester.element(find.byType(CachedNetworkImage)),
        MemoryImage(_onePixelPng),
      );
      await tester.pumpWidget(
        wrap(SizedBox(width: 300, height: 150, child: decoded)),
      );

      expect(tester.getSize(find.byType(Image)), const Size(300, 150));
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    });

    testWidgets('shows no spinner while the photo loads', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 300,
            height: 150,
            child: OasisNetworkImage(
              url: 'https://example.test/photo.jpg',
              placeholderIcon: Icons.home_work_outlined,
            ),
          ),
        ),
      );
      await tester.pump();

      // The whole point of the rework. A wheel over a photograph reports on
      // the software rather than the room, and a grid of them is what made
      // the app read as unfinished. A still block stands in for it instead.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a missing url is the same quiet block, not an error', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 120,
            height: 90,
            child: OasisNetworkImage(
              url: null,
              placeholderIcon: Icons.meeting_room_outlined,
            ),
          ),
        ),
      );

      // No photo, a failed photo and a loading photo are one event from the
      // viewer's side: there is no picture here. Never a broken-image glyph.
      expect(find.byIcon(Icons.meeting_room_outlined), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('OasisVideoPlayer', () {
    testWidgets('offers a play button, never a spinner, and stays quiet '
        'about a poster nobody asked for', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 320,
            height: 180,
            child: OasisVideoPlayer(url: 'https://example.test/tour.mp4'),
          ),
        ),
      );
      // There is no video plugin under a widget test, so preparing the poster
      // fails, which is exactly the state being checked.
      await tester.pumpAndSettle();

      // A walkthrough that would not open is not a reason to turn a listing
      // into a black error panel. The block and the play button stay, and
      // the tap is the retry; the failure is only spelled out to somebody who
      // actually asked to watch.
      expect(find.byType(OasisVideoPlayButton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('could not be played'), findsNothing);
    });
  });

  group('OasisMediaHero', () {
    testWidgets('counts the walkthrough as a page of its own', (tester) async {
      await tester.pumpWidget(
        wrap(
          const OasisMediaHero(
            photoUrls: [
              'https://example.test/1.jpg',
              'https://example.test/2.jpg',
            ],
            videoUrl: 'https://example.test/tour.mp4',
            height: 300,
          ),
        ),
      );

      // Two photos and a video read as three pages, and the counter says so.
      // A guest deciding whether to keep swiping is owed the total.
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('a listing with nothing to show still renders', (tester) async {
      await tester.pumpWidget(
        wrap(
          const OasisMediaHero(
            photoUrls: [],
            height: 300,
            emptyIcon: Icons.holiday_village_outlined,
          ),
        ),
      );

      // No counter on a single page, and no crash on an empty list: a
      // property still awaiting its photos is one somebody has opened.
      expect(find.byIcon(Icons.holiday_village_outlined), findsOneWidget);
      expect(find.textContaining('/'), findsNothing);
    });
  });

  group("a property's listing photos", () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AuthTokenStorage.clear();
      await AuthTokenStorage.saveTokens(
        access: 'test-access-token',
        refresh: 'test-refresh-token',
      );
      ApiConstants.baseUrl = 'https://api.example.test/api/users';
    });

    Widget wrapManager(LandlordController controller) =>
        ChangeNotifierProvider<LandlordController>.value(
          value: controller,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: PropertyMediaManager(
                property: PropertyModel(
                  id: 'prop-1',
                  name: 'Sunset House',
                  address: 'Ikeja',
                  city: 'Lagos',
                  state: 'Lagos',
                  createdAt: '2026-01-01',
                ),
              ),
            ),
          ),
        );

    LandlordController controllerAnswering(
      List<Map<String, dynamic>> photos, {
      Completer<void>? heldUntil,
    }) => LandlordController(
      propertyService: PropertyService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (heldUntil != null) await heldUntil.future;
            if (request.url.path.endsWith('/video/')) {
              return _jsonBody({'video_url': null});
            }
            return _jsonBody(photos);
          }),
        ),
      ),
    );

    testWidgets('are a skeleton while they load, never "none yet"', (
      tester,
    ) async {
      // The request is held open so the frame *before* the response, the
      // one the bug lived in, can be inspected rather than raced past.
      final release = Completer<void>();
      final controller = controllerAnswering([
        {'id': 'photo-1', 'image_url': 'https://example.test/a.jpg'},
      ], heldUntil: release);

      await tester.pumpWidget(wrapManager(controller));
      await tester.pump();

      // The bug: an unfetched photo list and an empty one are both `[]`, so
      // the page announced "No listing photos yet" to a landlord with four
      // of them and swapped to the grid a moment later, which reads as the
      // app having lost their photos and found them again.
      expect(find.textContaining('No listing photos yet'), findsNothing);
      expect(find.byType(ShimmerBox), findsWidgets);
      // No count is claimed before there is one to claim.
      expect(find.text('0/10'), findsNothing);

      release.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining('No listing photos yet'), findsNothing);
      expect(find.text('1/10'), findsOneWidget);
    });

    testWidgets('say so once the fetch comes back genuinely empty', (
      tester,
    ) async {
      await tester.pumpWidget(wrapManager(controllerAnswering(const [])));
      await tester.pumpAndSettle();

      // The other half of the rule: once the question has been answered the
      // empty state is the truth and has to be offered, because it carries
      // the only way to add a first photo.
      expect(find.textContaining('No listing photos yet'), findsOneWidget);
      expect(find.text('0/10'), findsOneWidget);
    });
  });
}

/// A 1×1 transparent PNG. Real bytes, so building an `Image` around it in the
/// layout test above never throws mid-decode.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQot'
  'tAAAAABJRU5ErkJggg==',
);

http.Response _jsonBody(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
