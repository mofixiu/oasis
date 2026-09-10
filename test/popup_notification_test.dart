import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/core/utils/oasis_navigator.dart';
import 'package:oasis_app/core/widgets/oasis_popup_notification.dart';

/// In-app popups are the one piece of chrome nobody asks for, so the rules
/// about when *not* to show one matter more than the rendering does.
///
/// Three of them are pinned here: a popup must find its way onto any screen
/// without being handed a context; it must not interrupt somebody with news
/// about the thread they are already reading; and a burst of them must be one
/// banner rather than a column of them.
void main() {
  setUp(OasisPopups.resetForTest);
  tearDown(OasisPopups.resetForTest);

  /// The app shell, with the global navigator key attached exactly as
  /// `main.dart` attaches it, that key is how a popup reaches an overlay
  /// from outside the widget tree.
  Widget shell({Widget? home}) => MaterialApp(
    theme: AppTheme.lightTheme,
    navigatorKey: oasisNavigatorKey,
    home: home ?? const Scaffold(body: Center(child: Text('Dashboard'))),
  );

  testWidgets('a popup reaches the screen with no context handed in', (
    tester,
  ) async {
    await tester.pumpWidget(shell());

    OasisPopups.show(
      const OasisPopup(
        title: 'Ada Okafor',
        body: 'Can I see it Saturday?',
        icon: Icons.forum_rounded,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ada Okafor'), findsOneWidget);
    expect(find.text('Can I see it Saturday?'), findsOneWidget);
    // The screen underneath is untouched: a popup is a banner, not a route.
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('tapping one runs its action and takes the banner away', (
    tester,
  ) async {
    await tester.pumpWidget(shell());
    var opened = false;

    OasisPopups.show(
      OasisPopup(
        title: 'Booking request',
        body: 'Ada asked for 12–14 March.',
        icon: Icons.event_available_outlined,
        onTap: () => opened = true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Booking request'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(find.text('Booking request'), findsNothing);
  });

  testWidgets('a second message in the same thread replaces the first', (
    tester,
  ) async {
    await tester.pumpWidget(shell());

    OasisPopups.show(
      const OasisPopup(
        title: 'Ada Okafor',
        body: 'Can I see it Saturday?',
        icon: Icons.forum_rounded,
        collapseKey: 'conversation:conv-1',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    OasisPopups.show(
      const OasisPopup(
        title: 'Ada Okafor',
        body: 'Or Sunday, if that is easier.',
        icon: Icons.forum_rounded,
        collapseKey: 'conversation:conv-1',
      ),
    );
    await tester.pump();

    // Somebody answering three questions in a row is one interruption, not
    // three, and the newest line is the one worth showing.
    expect(find.text('Ada Okafor'), findsOneWidget);
    expect(find.text('Or Sunday, if that is easier.'), findsOneWidget);
    expect(find.text('Can I see it Saturday?'), findsNothing);
  });

  testWidgets('a suppressed screen is not interrupted', (tester) async {
    await tester.pumpWidget(shell());

    // What an open conversation does: a banner announcing a message arriving
    // in the thread on screen is noise about something already visible.
    OasisPopups.suppress();
    OasisPopups.show(
      const OasisPopup(
        title: 'Ada Okafor',
        body: 'Can I see it Saturday?',
        icon: Icons.forum_rounded,
      ),
    );
    await tester.pump();
    expect(find.text('Ada Okafor'), findsNothing);

    // Nested, because a popup can push a conversation over a conversation.
    // The inner screen closing must not un-silence the outer one.
    OasisPopups.suppress();
    OasisPopups.resume();
    OasisPopups.show(
      const OasisPopup(
        title: 'Ada Okafor',
        body: 'Can I see it Saturday?',
        icon: Icons.forum_rounded,
      ),
    );
    await tester.pump();
    expect(find.text('Ada Okafor'), findsNothing);

    OasisPopups.resume();
    OasisPopups.show(
      const OasisPopup(
        title: 'Ada Okafor',
        body: 'Can I see it Saturday?',
        icon: Icons.forum_rounded,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ada Okafor'), findsOneWidget);
  });

  testWidgets('it withdraws on its own', (tester) async {
    await tester.pumpWidget(shell());

    OasisPopups.show(
      const OasisPopup(
        title: 'Rent confirmed',
        body: 'March rent is in escrow.',
        icon: Icons.verified_outlined,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Rent confirmed'), findsOneWidget);

    await tester.pump(OasisPopups.visibleFor);
    await tester.pumpAndSettle();

    expect(find.text('Rent confirmed'), findsNothing);
    expect(OasisPopups.isShowing, isFalse);
  });
}
