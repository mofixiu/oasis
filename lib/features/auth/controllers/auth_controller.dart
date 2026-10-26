import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/load_failure.dart';
import '../../../core/network/auth_token_storage.dart';
import '../../../core/session/session_scope.dart';
import '../models/consent_model.dart';
import '../models/user_model.dart';
import '../services/i_auth_service.dart';

class AuthController extends ChangeNotifier with LoadFailureState {
  final IAuthService _authService;

  AuthController({required IAuthService authService})
    : _authService = authService;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  UserRole get currentRole => _currentUser?.role ?? UserRole.owner;

  /// True right after `verifyIdentity` fails because the backend requires
  /// privacy/verification consent first. The verification screen watches
  /// this to show a consent step, then retries automatically.
  bool _consentRequired = false;
  bool get consentRequired => _consentRequired;

  /// Check initial auth state on app launch
  Future<void> checkAuthStatus() async {
    _setLoading(true);
    try {
      final token = await AuthTokenStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        _currentUser = await _authService.getProfile();
        _isAuthenticated = true;
        clearFailure();
      } else {
        _currentUser = null;
        _isAuthenticated = false;
      }
    } catch (_) {
      final cachedUser = await AuthTokenStorage.getCachedUserProfile();
      if (cachedUser != null) {
        _currentUser = cachedUser;
        _isAuthenticated = true;
        clearFailure();
      } else {
        _currentUser = null;
        _isAuthenticated = false;
      }
    } finally {
      _setLoading(false);
    }
  }

  /// User Sign In
  Future<bool> login(String email, String password) async {
    _setLoading(true);
    clearFailure();
    // A session can end without `logout()` running: an expired refresh token
    // clears storage from inside ApiClient and drops the user here. Clearing
    // on the way in guarantees a signed-in user never inherits cached data,
    // however the previous session ended.
    SessionScope.resetAll();
    // The same goes for the stored token and cached profile: left in place, a
    // sign-in that fails part-way would fall back to the previous account.
    await AuthTokenStorage.clear();

    try {
      _currentUser = await _authService.login(email: email, password: password);
      _isAuthenticated = true;
      notifyListeners();
      return true;
    } catch (e) {
      _isAuthenticated = false;
      captureFailure(e);
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Request a password reset email without changing the signed-in state.
  Future<bool> requestPasswordReset(String email) async {
    _setLoading(true);
    clearFailure();
    try {
      await _authService.requestPasswordReset(email: email);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Completes a password reset using the token from the reset email/link.
  Future<bool> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    _setLoading(true);
    clearFailure();
    try {
      await _authService.confirmPasswordReset(
        token: token,
        newPassword: newPassword,
      );
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// User Registration
  ///
  /// The trade fields are artisan-only and are forwarded as given; the service
  /// decides whether they reach the wire, so this never has to know the shape
  /// of the registration body.
  Future<bool> register({
    required String email,
    required String password,
    required String phone,
    required UserRole role,
    String? category,
    String? location,
    String? bio,
    int? yearsOfExperience,
  }) async {
    _setLoading(true);
    clearFailure();
    SessionScope.resetAll();
    // Without this a sign-up whose automatic sign-in fails leaves the previous
    // account's token in storage, and the next launch restores that account.
    await AuthTokenStorage.clear();

    try {
      _currentUser = await _authService.register(
        email: email,
        password: password,
        phone: phone,
        role: role,
        category: category,
        location: location,
        bio: bio,
        yearsOfExperience: yearsOfExperience,
      );
      _isAuthenticated = true;
      notifyListeners();
      return true;
    } catch (e) {
      _isAuthenticated = false;
      captureFailure(e);
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Identity Verification Submission (Selfie + NIN)
  ///
  /// [givenNames]/[lastName]/[email] are optional and only needed to match
  /// Smile ID sandbox test identities once the backend is switched off the
  /// mock verification provider.
  Future<VerificationStatus?> verifyIdentity({
    required File selfie,
    required String nin,
    String? givenNames,
    String? lastName,
    String? email,
  }) async {
    _setLoading(true);
    clearFailure();
    _consentRequired = false;

    try {
      final response = await _authService.verifyIdentity(
        selfie: selfie,
        nin: nin,
        givenNames: givenNames,
        lastName: lastName,
        email: email,
      );
      final status = _applyVerificationResponse(response);
      notifyListeners();
      return status;
    } on ConsentRequiredException {
      // Not a generic failure: the caller should show the consent step and
      // retry this same call, not display an error toast.
      _consentRequired = true;
      notifyListeners();
      return null;
    } catch (e) {
      captureFailure(e);
      notifyListeners();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Records the current verification/privacy consent. Must succeed before
  /// retrying `verifyIdentity` after a [ConsentRequiredException].
  Future<bool> acceptVerificationConsent() async {
    try {
      await _authService.acceptConsent(
        consentType: VerificationConsent.type,
        version: VerificationConsent.version,
      );
      _consentRequired = false;
      return true;
    } catch (e) {
      captureFailure(e);
      notifyListeners();
      return false;
    }
  }

  /// Checks the backend-owned asynchronous verification state. Flutter only
  /// polls this endpoint; it must never call a provider webhook directly.
  Future<VerificationStatus?> checkVerificationStatus({
    bool reportErrors = false,
  }) async {
    try {
      final response = await _authService.getVerificationStatus();
      final status = _applyVerificationResponse(response);
      clearFailure();
      notifyListeners();
      return status;
    } catch (e) {
      if (reportErrors) {
        captureFailure(e);
        notifyListeners();
      }
      return null;
    }
  }

  VerificationStatus _applyVerificationResponse(Map<String, dynamic> response) {
    final responseUser = response['user'];
    if (responseUser is Map<String, dynamic>) {
      _currentUser = UserModel.fromJson(responseUser);
    }

    final rawStatus =
        response['verification_status'] ??
        response['status'] ??
        (responseUser is Map<String, dynamic>
            ? responseUser['verification_status']
            : null);
    final status = VerificationStatus.fromString(rawStatus?.toString());

    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(verificationStatus: status);
      AuthTokenStorage.saveUserProfile(_currentUser!);
    }
    return status;
  }

  /// Reacts to a live 403 "Complete identity verification..." response from
  /// any gated endpoint by re-checking the authoritative backend status, even
  /// if the locally cached status was (incorrectly) VERIFIED. Screens that
  /// watch [currentUser]/[VerificationStatus] (e.g. MainScaffold) will then
  /// redirect back to the verification flow automatically.
  Future<void> handleVerificationRequiredSignal() async {
    await checkVerificationStatus(reportErrors: false);
  }

  /// The session ended without anybody pressing sign out.
  ///
  /// Fired by [ApiClient] when a refresh token is rejected. Tokens are already
  /// gone by then; what is left is to stop the app claiming to be signed in
  /// and to wipe the previous user's data out of the process-lifetime
  /// controllers, exactly as [logout] does.
  ///
  /// No network call: the server has already told us the credentials are
  /// dead, and posting a logout with them would only fail.
  void handleSessionExpired() {
    if (!_isAuthenticated && _currentUser == null) return;
    _currentUser = null;
    _isAuthenticated = false;
    _consentRequired = false;
    clearFailure();
    SessionScope.resetAll();
    notifyListeners();
  }

  /// Refresh user profile
  Future<void> refreshProfile() async {
    try {
      _currentUser = await _authService.getProfile();
      notifyListeners();
    } catch (_) {}
  }

  /// Sign Out
  Future<void> logout() async {
    _setLoading(true);
    await _authService.logout();
    _currentUser = null;
    _isAuthenticated = false;
    _consentRequired = false;
    clearFailure();
    // Feature controllers are process-lifetime singletons, so without this
    // the previous user's properties, agreements, payments, and notification
    // badge stay in memory and are rendered to whoever signs in next.
    SessionScope.resetAll();
    _setLoading(false);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void clearError() {
    clearFailure();
    notifyListeners();
  }
}
