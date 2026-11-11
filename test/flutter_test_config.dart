import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Runs before every test file. Tests have no Keychain or Keystore, so the
/// secure store is swapped for the package's in-memory fake.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FlutterSecureStorage.setMockInitialValues({});
  await testMain();
}
