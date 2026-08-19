import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/core/theme/app_theme.dart';
import 'package:landa_app/core/widgets/landa_entrance.dart';
import 'package:landa_app/core/widgets/landa_shimmer.dart';
import 'package:landa_app/core/widgets/landa_state_views.dart';

/// Render cover for the shared state views. These sit on every fetching
/// screen, so a layout error in one of them breaks the whole app at once.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.lightTheme
            : AppTheme.darkTheme,
        home: Scaffold(body: child),
      );

  for (final brightness in Brightness.values) {
    testWidgets('error state offers retry in ${brightness.name}', (
      tester,
    ) async {
      var retries = 0;

      await tester.pumpWidget(
        host(
          LandaErrorState(
            isConnectionError: true,
            onRetry: () async => retries++,
          ),
          brightness: brightness,
        ),
      );

      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(retries, 1);
    });
  }

  testWidgets('a server failure reads as a failure, not as offline', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const LandaErrorState(message: 'Server said no.')),
    );

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Server said no.'), findsOneWidget);
    // No retry callback supplied: no dead button offered.
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('empty state runs its action', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      host(
        LandaEmptyState(
          icon: Icons.inbox_outlined,
          title: 'No applications yet',
          message: 'They will show up here.',
          actionLabel: 'Refresh',
          onAction: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('the banner keeps content visible while reporting failure', (
    tester,
  ) async {
    var retries = 0;

    await tester.pumpWidget(
      host(
        Column(
          children: [
            LandaErrorBanner(
              message: 'Could not refresh.',
              isConnectionError: true,
              onRetry: () => retries++,
            ),
            const Expanded(child: Text('cached content')),
          ],
        ),
      ),
    );

    expect(find.text('cached content'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('the switcher cross-fades a skeleton into a filled list', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const LandaContentSwitcher(
          stateKey: 'loading',
          child: LandaSkeletonList(count: 2, hasAvatar: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LandaCardSkeleton), findsNWidgets(2));

    // An Expanded child inside the switcher is the shape every list screen
    // uses; it must not overflow when the switcher stacks both states.
    await tester.pumpWidget(
      host(
        LandaContentSwitcher(
          stateKey: 'content',
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: const [
                    LandaEntrance(index: 0, child: Text('first')),
                    LandaEntrance(index: 1, child: Text('second')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
