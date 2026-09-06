import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:landa_app/core/utils/landa_refresh.dart';
import 'package:landa_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:landa_app/features/shortlets/services/shortlet_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Two bugs that were only visible for about a second each, which is why they
/// survived so long and why they are pinned here rather than left to the eye.
///
/// The first: every list in the app showed its empty state before it had
/// fetched anything. "No short stays yet" then, a beat later, eight stays.
/// The cause was that `isLoading` is false both *before* a load starts and
/// *after* it finishes, so an empty list could not tell those two apart.
///
/// The second: nothing re-fetched on its own. A screen you returned to still
/// described the world as it was when you left it, and the only fix was to
/// drag the list down.
void main() {
  late String originalBaseUrl;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(access: 'token', refresh: 'refresh');
    originalBaseUrl = ApiConstants.baseUrl;
    ApiConstants.baseUrl = 'https://api.example.test/api/users';
  });

  tearDown(() => ApiConstants.baseUrl = originalBaseUrl);

  group('loaded-once tracking', () {
    test('a controller has not loaded before anything is fetched', () {
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(client: MockClient((_) async => _json([]))),
        ),
      );

      // The state the old code could not see. Empty list, not loading, and
      // yet the truthful answer is "we have not looked".
      expect(controller.browseListings, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.hasLoaded(ShortLetController.kBrowseKey), isFalse);
    });

    test('an empty result still counts as loaded', () async {
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(client: MockClient((_) async => _json([]))),
        ),
      );

      await controller.loadBrowseListings();

      // Now the empty state is the truth and the screen may say so.
      expect(controller.hasLoaded(ShortLetController.kBrowseKey), isTrue);
      expect(controller.browseListings, isEmpty);
    });

    test(
      'a failed fetch counts as loaded, so the error state can show',
      () async {
        final controller = ShortLetController(
          service: ShortLetService(
            apiClient: ApiClient(
              client: MockClient(
                (_) async => http.Response('{"detail":"Nope."}', 400),
              ),
            ),
          ),
        );

        await controller.loadBrowseListings();

        // Marked in the `finally`, not on success: a skeleton that never
        // resolves is worse than an error the user can retry.
        expect(controller.hasLoaded(ShortLetController.kBrowseKey), isTrue);
        expect(controller.hasError, isTrue);
      },
    );

    test(
      'keys are independent, so one fetch never speaks for another',
      () async {
        final controller = ShortLetController(
          service: ShortLetService(
            apiClient: ApiClient(client: MockClient((_) async => _json([]))),
          ),
        );

        await controller.loadBrowseListings();

        expect(controller.hasLoaded(ShortLetController.kBrowseKey), isTrue);
        // The tenant's own bookings have not been asked for. Sharing one flag
        // would render "no bookings" on the strength of a browse call.
        expect(controller.hasLoaded(ShortLetController.kBookingsKey), isFalse);
      },
    );

    test('signing out forgets what was loaded', () async {
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(client: MockClient((_) async => _json([]))),
        ),
      );
      await controller.loadBrowseListings();
      expect(controller.hasLoaded(ShortLetController.kBrowseKey), isTrue);

      controller.resetSessionState();

      // The next user must get a skeleton, not the previous user's
      // "nothing here".
      expect(controller.hasLoaded(ShortLetController.kBrowseKey), isFalse);
    });
  });

  group('AutoRefreshMixin', () {
    testWidgets('fetches once on mount', (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [landaRouteObserver],
          home: _RefreshProbe(onRefresh: () => refreshes++),
        ),
      );
      await tester.pumpAndSettle();

      expect(refreshes, 1);
    });

    testWidgets('fetches again when a pushed route pops', (tester) async {
      var refreshes = 0;
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [landaRouteObserver],
          home: _RefreshProbe(onRefresh: () => refreshes++),
        ),
      );
      await tester.pumpAndSettle();
      expect(refreshes, 1);

      // Stand in for approving an application, paying for a stay, accepting a
      // job: anything done on a screen pushed over this one.
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      );
      await tester.pumpAndSettle();
      expect(refreshes, 1, reason: 'nothing to refresh while covered');

      key.currentState!.pop();
      await tester.pumpAndSettle();

      expect(refreshes, 2, reason: 'back on top, so the data is re-read');
    });

    testWidgets('a second refresh is dropped while one is in flight', (
      tester,
    ) async {
      var starts = 0;
      final gate = Completer<void>();
      late _RefreshProbeState state;

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [landaRouteObserver],
          home: _RefreshProbe(
            onRefresh: () => starts++,
            block: gate.future,
            onState: (s) => state = s,
          ),
        ),
      );
      await tester.pump();
      expect(starts, 1);

      // A poll tick landing on top of a slow request must not stack a second
      // one behind it.
      await state.refreshNow();
      expect(starts, 1);

      gate.complete();
      await tester.pumpAndSettle();
    });
  });
}

/// A screen that does nothing but count its refreshes.
class _RefreshProbe extends StatefulWidget {
  final VoidCallback onRefresh;

  /// Held open to simulate a slow request.
  final Future<void>? block;

  final void Function(_RefreshProbeState)? onState;

  const _RefreshProbe({required this.onRefresh, this.block, this.onState});

  @override
  State<_RefreshProbe> createState() => _RefreshProbeState();
}

class _RefreshProbeState extends State<_RefreshProbe>
    with AutoRefreshMixin<_RefreshProbe> {
  @override
  void initState() {
    super.initState();
    widget.onState?.call(this);
  }

  @override
  Future<void> onAutoRefresh() async {
    widget.onRefresh();
    if (widget.block != null) await widget.block;
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);
