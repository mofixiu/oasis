import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sign-in tokens and the cached profile live in the Keychain / Keystore,
/// not in plain preferences that any backup or file browser can read.
void main() {
  const secure = FlutterSecureStorage();

  setUp(() {
    AuthTokenStorage.resetForTest();
  });

  test('saved tokens go to secure storage, not plain preferences', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    await AuthTokenStorage.saveTokens(access: 'a1', refresh: 'r1');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('oasis_access_token'), isNull);
    expect(prefs.getString('oasis_refresh_token'), isNull);
    expect(await secure.read(key: 'oasis_access_token'), 'a1');
    expect(await secure.read(key: 'oasis_refresh_token'), 'r1');
  });

  test('an upgrade moves the old plain session into secure storage', () async {
    SharedPreferences.setMockInitialValues({
      'oasis_access_token': 'old-access',
      'oasis_refresh_token': 'old-refresh',
      'oasis_user_role': 'TENANT',
      'oasis_user_profile': '{"email":"a@b.c"}',
      'oasis_onboarding_done': true,
    });
    FlutterSecureStorage.setMockInitialValues({});

    expect(await AuthTokenStorage.getAccessToken(), 'old-access');
    expect(await AuthTokenStorage.getRefreshToken(), 'old-refresh');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('oasis_access_token'), isNull);
    expect(prefs.getString('oasis_refresh_token'), isNull);
    expect(prefs.getString('oasis_user_profile'), isNull);
    expect(prefs.getString('oasis_user_role'), isNull);
    // Not sensitive, so it stays where it was.
    expect(prefs.getBool('oasis_onboarding_done'), isTrue);
    expect(await secure.read(key: 'oasis_user_profile'), '{"email":"a@b.c"}');
  });

  test('a reinstall does not pick up a Keychain session left behind', () async {
    // Plain preferences are wiped on uninstall; Keychain items are not.
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'oasis_access_token': 'previous-install',
      'oasis_refresh_token': 'previous-install',
    });

    expect(await AuthTokenStorage.getAccessToken(), isNull);
    expect(await AuthTokenStorage.getRefreshToken(), isNull);
    expect(await secure.read(key: 'oasis_access_token'), isNull);
  });

  test('after the move, a relaunch reads the secure session', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthTokenStorage.saveTokens(access: 'a2', refresh: 'r2');

    AuthTokenStorage.resetForTest(); // next launch

    expect(await AuthTokenStorage.getAccessToken(), 'a2');
    expect(await AuthTokenStorage.getRefreshToken(), 'r2');
  });

  test('sign-out removes the session from secure storage', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthTokenStorage.saveTokens(access: 'a3', refresh: 'r3');

    await AuthTokenStorage.clear();
    AuthTokenStorage.resetForTest();

    expect(await secure.read(key: 'oasis_access_token'), isNull);
    expect(await AuthTokenStorage.getAccessToken(), isNull);
  });
}
