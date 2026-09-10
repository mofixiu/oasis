import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/widgets/oasis_app_bar.dart';
import 'package:oasis_app/features/auth/controllers/auth_controller.dart';
import 'package:oasis_app/features/auth/models/user_model.dart';
import 'package:oasis_app/features/auth/services/mock_auth_service.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/messaging/controllers/messaging_controller.dart';
import 'package:oasis_app/features/notifications/controllers/notification_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app bar lost its wordmark and moved the avatar to the left, and later
/// lost the Discover compass to a bottom-nav tab. These pin the three things a
/// future change could quietly undo: the avatar leading, the bell being the
/// first of the right-hand actions, and Discover *not* being back in the bar.
/// Putting it in both places is how a tenant ends up with two doors to one
/// screen and a back arrow that goes somewhere unexpected.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(access: 'token', refresh: 'refresh');
  });

  testWidgets('the avatar leads and the bell heads the actions', (
    tester,
  ) async {
    await _pumpBar(tester);

    // The avatar renders the signed-in user's initial, not a person glyph.
    final avatarX = tester.getCenter(find.text('A')).dx;
    final bellX = tester
        .getCenter(find.byIcon(Icons.notifications_none_rounded))
        .dx;
    final messagesX = tester.getCenter(find.byIcon(Icons.forum_outlined)).dx;

    final width = tester.getSize(find.byType(OasisAppBar)).width;
    expect(avatarX, lessThan(width / 2));
    expect(bellX, greaterThan(width / 2));

    // Bell, then messages.
    expect(bellX, lessThan(messagesX));
  });

  testWidgets('discover is not in the app bar, it is a tab', (tester) async {
    await _pumpBar(tester);
    expect(find.byIcon(Icons.explore_outlined), findsNothing);
  });

  testWidgets('no wordmark is rendered', (tester) async {
    await _pumpBar(tester);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a pushed route keeps the avatar beside the back arrow', (
    tester,
  ) async {
    await _pumpBar(tester, showBackButton: true);

    final backX = tester.getCenter(find.byIcon(Icons.arrow_back_rounded)).dx;
    final avatarX = tester.getCenter(find.text('A')).dx;

    // Both on the left, arrow first: the avatar must not be exiled to the
    // right on screens that can be navigated back from.
    expect(backX, lessThan(avatarX));
    expect(
      avatarX,
      lessThan(tester.getSize(find.byType(OasisAppBar)).width / 2),
    );
  });
}

/// A signed-in tenant: the role that would have carried the compass, so a
/// regression putting it back would be caught here rather than passing for
/// want of the right role.
class _TenantAuthService extends MockAuthService {
  @override
  Future<UserModel> getProfile() async => UserModel(
    id: 'tenant-1',
    email: 'ada@example.test',
    phone: '+2348012345678',
    role: UserRole.tenant,
    verificationStatus: VerificationStatus.verified,
  );
}

Future<void> _pumpBar(
  WidgetTester tester, {
  bool showBackButton = false,
}) async {
  final auth = AuthController(authService: _TenantAuthService());
  await auth.checkAuthStatus();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => NotificationController()),
        ChangeNotifierProvider(create: (_) => MessagingController()),
      ],
      child: MaterialApp(
        home: Scaffold(
          appBar: OasisAppBar(showBackButton: showBackButton),
          body: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pump();
}
