import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_constants.dart';
import 'auth_token_storage.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic errors;

  ApiException(this.message, {this.statusCode, this.errors});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thrown when the backend rejects a request with `403 {"code":
/// "CONSENT_REQUIRED"}`. A distinct type lets callers route straight to the
/// consent flow instead of pattern-matching the raw error body.
class ConsentRequiredException extends ApiException {
  ConsentRequiredException(super.message, {super.statusCode, super.errors});
}

/// Thrown when the backend rejects a request with `403 {"code":
/// "PAYOUT_ACCOUNT_REQUIRED"}`: the landlord must add and verify payout
/// details before executing an agreement or releasing escrow.
///
/// A distinct type lets the caller offer payout setup and retry the original
/// action, rather than surfacing it as a dead-end error.
class PayoutAccountRequiredException extends ApiException {
  PayoutAccountRequiredException(
    super.message, {
    super.statusCode,
    super.errors,
  });
}

/// Thrown when the backend rejects a money-out request with
/// `{"code": "INSUFFICIENT_VAULT_BALANCE"}`. The vault does not hold enough
/// to cover a withdrawal or a rent payment.
///
/// A distinct type because this is the one rejection with an obvious next
/// step: top up by [shortfall] and try again. Everything else can only be
/// reported.
class InsufficientVaultBalanceException extends ApiException {
  /// How much more is needed, as the decimal string the API speaks, when the
  /// backend quotes one. Null when it did not: callers then work the gap out
  /// from the balance they already hold rather than inventing a figure.
  final String? shortfall;

  InsufficientVaultBalanceException(
    super.message, {
    this.shortfall,
    super.statusCode,
    super.errors,
  });
}

/// Thrown when the request never reached the backend: no internet, DNS
/// failure, TLS handshake failure or timeout. Distinct from [ApiException] so
/// screens can offer "Try again" instead of showing a server-side message the
/// user cannot act on.
class NetworkException extends ApiException {
  NetworkException([
    super.message = 'No internet connection. Check your network and try again.',
  ]);
}

/// True when [error] means "we could not reach the server", as opposed to the
/// server answering with a rejection. Drives the retry-able error state.
bool isConnectionError(Object error) =>
    error is NetworkException ||
    error is SocketException ||
    error is TimeoutException ||
    error is HandshakeException ||
    error is http.ClientException;

/// Extracts a clean, user-presentable message from a caught error.
///
/// [ApiException.message] is already the backend's human-readable detail
/// (e.g. "Invalid email or password."); this avoids ever surfacing the raw
/// `ApiException(403): ...` debug string in toasts/banners.
String friendlyErrorMessage(Object error) {
  if (error is ApiException) return error.message;
  // Raw transport failures stringify to things like "SocketException: Failed
  // host lookup": never show that to a user.
  if (isConnectionError(error)) return NetworkException().message;
  return error.toString();
}

class MultipartUpload {
  final String fieldName;
  final File file;

  const MultipartUpload({required this.fieldName, required this.file});
}

class ApiClient {
  final http.Client _client;

  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  /// Ordinary requests give up after this long *once the backend is awake*.
  /// Without a ceiling a dropped connection leaves the caller's spinner
  /// running indefinitely instead of surfacing a retry-able error.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Uploads carry file bytes, so they get a far longer leash.
  static const Duration uploadTimeout = Duration(minutes: 3);

  /// Extra budget granted while the backend may still be asleep.
  ///
  /// Staging runs on Render, which spins a service down after roughly fifteen
  /// minutes without traffic and then takes the better part of a minute to
  /// cold-start it again. A flat 30s ceiling turns that ordinary, expected
  /// wait into "the server took too long to respond" on the very first screen
  /// after launch, which is when it matters most.
  ///
  /// Added on top of the call's own budget rather than replacing it, so an
  /// upload that begins during a cold start still gets its full three minutes
  /// to move the bytes afterwards.
  static const Duration coldStartBudget = Duration(seconds: 60);

  /// How long a successful response is taken as proof the service is awake.
  /// Deliberately shorter than Render's ~15 minute idle window, so the app
  /// errs towards granting the longer timeout rather than towards failing.
  static const Duration warmFor = Duration(minutes: 10);

  /// When the backend last answered anything at all. Static because it
  /// describes the *server*, not this client instance: several ApiClients
  /// exist across the app and they are all talking to the same box.
  static DateTime? _lastResponseAt;

  /// Whether the backend is known to be awake right now.
  static bool get isServerWarm {
    final last = _lastResponseAt;
    return last != null && DateTime.now().difference(last) < warmFor;
  }

  /// The real ceiling for a call: its own budget, plus the cold-start
  /// allowance while the service might still be waking up.
  static Duration _effectiveTimeout(Duration base) =>
      isServerWarm ? base : base + coldStartBudget;

  /// Forgets that the server was warm. For tests, so one case cannot leak a
  /// warm clock into the next.
  @visibleForTesting
  static void resetWarmState() => _lastResponseAt = null;

  /// Runs an HTTP call, converting every "never reached the server" failure
  /// into a [NetworkException] so callers get one type to test for.
  Future<T> _guard<T>(
    Future<T> Function() send, {
    Duration timeout = requestTimeout,
  }) async {
    final budget = _effectiveTimeout(timeout);
    final wasCold = !isServerWarm;
    try {
      final result = await send().timeout(budget);
      // Any answer at all proves the service is up: including a 4xx or 5xx,
      // which still means the container is running and the next call can use
      // the short timeout.
      _lastResponseAt = DateTime.now();
      return result;
    } on TimeoutException {
      debugPrint(
        '⌛ [API TIMEOUT] No response within ${budget.inSeconds}s '
        '(${wasCold ? 'cold start allowance included' : 'server was warm'}).',
      );
      throw NetworkException(
        wasCold
            // Naming the cause beats a generic apology: this is a sleeping
            // free-tier service, it is recoverable, and trying again in a
            // moment genuinely works.
            ? 'The server is waking up and took too long to answer. Give it a '
                  'moment and try again.'
            : 'The server took too long to respond. Please try again.',
      );
    } on SocketException catch (e) {
      debugPrint('[API OFFLINE] $e');
      throw NetworkException();
    } on HandshakeException catch (e) {
      debugPrint('[API TLS FAILURE] $e');
      throw NetworkException(
        'Could not establish a secure connection. Please try again.',
      );
    } on http.ClientException catch (e) {
      debugPrint('[API CLIENT FAILURE] $e');
      throw NetworkException();
    }
  }

  /// Fired whenever any request hits the backend's verification gate (403
  /// "Complete identity verification before accessing this feature."),
  /// even if the locally cached verification status was stale/VERIFIED.
  /// Wired in main.dart to re-check verification status and route the user
  /// back to the verification screen.
  static void Function()? onVerificationRequired;

  /// Fired when the session is definitively over: the access token was
  /// rejected and the refresh token was rejected too, so there is nothing
  /// left to authenticate with.
  ///
  /// Without this, an expired session was invisible. `_attemptRefreshToken`
  /// cleared storage and returned false, the original 401 surfaced as an
  /// ordinary API error, and the app carried on believing it was signed in,
  /// so the user sat on a screen showing "Given token not valid for any token
  /// type" while every subsequent request failed the same way, with no way
  /// back to the sign-in screen short of force-quitting.
  ///
  /// Deliberately not fired when the refresh could not be *reached*. Offline
  /// is not "your session expired", and signing someone out every time the
  /// network blips is worse than the bug this fixes.
  static void Function()? onSessionExpired;

  /// Build standard headers with Bearer access token
  Future<Map<String, String>> _getHeaders({
    bool isJson = true,
    bool requiresAuth = true,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};

    if (isJson) {
      headers['Content-Type'] = 'application/json; charset=UTF-8';
    }

    if (requiresAuth) {
      final token = await AuthTokenStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  /// Perform GET request.
  ///
  /// [queryParameters] entries with a null value are dropped, so callers can
  /// pass optional filters without building the query string themselves.
  Future<dynamic> get(
    String path, {
    bool requiresAuth = true,
    Map<String, String?>? queryParameters,
  }) async {
    var url = Uri.parse('${ApiConstants.baseUrl}$path');
    final filters = <String, String>{
      for (final entry
          in (queryParameters ?? const <String, String?>{}).entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    if (filters.isNotEmpty) {
      url = url.replace(queryParameters: {...url.queryParameters, ...filters});
    }
    final headers = await _getHeaders(
      isJson: false,
      requiresAuth: requiresAuth,
    );

    debugPrint(
      '[API GET REQUEST] -> URL: $url | Auth: ${headers.containsKey('Authorization')}',
    );

    final stopwatch = Stopwatch()..start();
    var response = await _guard(() => _client.get(url, headers: headers));
    stopwatch.stop();

    debugPrint(
      '[API GET RESPONSE] <- URL: $url | Status: ${response.statusCode} | Duration: ${stopwatch.elapsedMilliseconds}ms',
    );

    if (response.statusCode == 401 && requiresAuth) {
      debugPrint('[API GET 401 UNAUTHORIZED] Attempting token refresh...');
      final refreshed = await _attemptRefreshToken();
      if (refreshed) {
        final newHeaders = await _getHeaders(
          isJson: false,
          requiresAuth: requiresAuth,
        );
        debugPrint('[API GET RETRY WITH NEW TOKEN] -> URL: $url');
        response = await _guard(() => _client.get(url, headers: newHeaders));
        debugPrint(
          '[API GET RETRY RESPONSE] <- Status: ${response.statusCode}',
        );
      }
    }

    return _processResponse(response, path: path);
  }

  /// Perform POST request
  /// Perform POST request.
  ///
  /// [extraHeaders] carries per-request headers the endpoint needs: an
  /// `Idempotency-Key` on anything that moves money, so a retry over a flaky
  /// connection cannot withdraw twice. They are re-sent on the token-refresh
  /// retry below, which is the whole point: the retry must reuse the *same*
  /// key rather than looking like a second request.
  Future<dynamic> post(
    String path, {
    dynamic body,
    bool requiresAuth = true,
    Map<String, String>? extraHeaders,
  }) async {
    final url = Uri.parse('${ApiConstants.baseUrl}$path');
    final headers = await _getHeaders(isJson: true, requiresAuth: requiresAuth)
      ..addAll(extraHeaders ?? const {});
    final encodedBody = body != null ? jsonEncode(body) : null;

    debugPrint(
      '[API POST REQUEST] -> URL: $url | Auth: ${headers.containsKey('Authorization')}',
    );

    final stopwatch = Stopwatch()..start();
    var response = await _guard(
      () => _client.post(url, headers: headers, body: encodedBody),
    );
    stopwatch.stop();

    debugPrint(
      '[API POST RESPONSE] <- URL: $url | Status: ${response.statusCode} | Duration: ${stopwatch.elapsedMilliseconds}ms',
    );

    if (response.statusCode == 401 && requiresAuth) {
      debugPrint('[API POST 401 UNAUTHORIZED] Attempting token refresh...');
      final refreshed = await _attemptRefreshToken();
      if (refreshed) {
        final newHeaders =
            await _getHeaders(isJson: true, requiresAuth: requiresAuth)
              ..addAll(extraHeaders ?? const {});
        debugPrint('[API POST RETRY WITH NEW TOKEN] -> URL: $url');
        response = await _guard(
          () => _client.post(url, headers: newHeaders, body: encodedBody),
        );
        debugPrint(
          '[API POST RETRY RESPONSE] <- Status: ${response.statusCode}',
        );
      }
    }

    return _processResponse(response, path: path);
  }

  /// Perform PATCH request
  Future<dynamic> patch(
    String path, {
    dynamic body,
    bool requiresAuth = true,
  }) async {
    final url = Uri.parse('${ApiConstants.baseUrl}$path');
    final headers = await _getHeaders(isJson: true, requiresAuth: requiresAuth);
    final encodedBody = body != null ? jsonEncode(body) : null;

    debugPrint(
      '[API PATCH REQUEST] -> URL: $url | Auth: ${headers.containsKey('Authorization')}',
    );

    final stopwatch = Stopwatch()..start();
    var response = await _guard(
      () => _client.patch(url, headers: headers, body: encodedBody),
    );
    stopwatch.stop();

    debugPrint(
      '[API PATCH RESPONSE] <- URL: $url | Status: ${response.statusCode} | Duration: ${stopwatch.elapsedMilliseconds}ms',
    );

    if (response.statusCode == 401 && requiresAuth) {
      debugPrint('[API PATCH 401 UNAUTHORIZED] Attempting token refresh...');
      final refreshed = await _attemptRefreshToken();
      if (refreshed) {
        final newHeaders = await _getHeaders(
          isJson: true,
          requiresAuth: requiresAuth,
        );
        debugPrint('[API PATCH RETRY WITH NEW TOKEN] -> URL: $url');
        response = await _guard(
          () => _client.patch(url, headers: newHeaders, body: encodedBody),
        );
        debugPrint(
          '[API PATCH RETRY RESPONSE] <- Status: ${response.statusCode}',
        );
      }
    }

    return _processResponse(response, path: path);
  }

  /// Perform DELETE request.
  ///
  /// Deletion endpoints answer `204 No Content`, so an empty body here is a
  /// success rather than a parse failure.
  ///
  /// [body] is unusual on a DELETE but two endpoints need it: the one that
  /// removes a unit's artisan recommendation names the category to drop in
  /// the body rather than the URL, because a unit holds one recommendation
  /// per category and the path identifies only the unit.
  Future<dynamic> delete(
    String path, {
    dynamic body,
    bool requiresAuth = true,

    /// Query string, for the few DELETEs that address a row by something
    /// other than its id: removing a push device by its token, for one.
    /// Built through [Uri.replace] rather than concatenated, so a value
    /// carrying a `&` or a `+` cannot silently change the request.
    Map<String, String?>? queryParameters,
  }) async {
    var url = Uri.parse('${ApiConstants.baseUrl}$path');
    final filters = <String, String>{
      for (final entry
          in (queryParameters ?? const <String, String?>{}).entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    if (filters.isNotEmpty) {
      url = url.replace(queryParameters: {...url.queryParameters, ...filters});
    }
    final headers = await _getHeaders(
      isJson: body != null,
      requiresAuth: requiresAuth,
    );
    final encodedBody = body != null ? jsonEncode(body) : null;

    debugPrint(
      '[API DELETE REQUEST] -> URL: $url | Auth: ${headers.containsKey('Authorization')}',
    );

    final stopwatch = Stopwatch()..start();
    var response = await _guard(
      () => _client.delete(url, headers: headers, body: encodedBody),
    );
    stopwatch.stop();

    debugPrint(
      '[API DELETE RESPONSE] <- URL: $url | Status: ${response.statusCode} | Duration: ${stopwatch.elapsedMilliseconds}ms',
    );

    if (response.statusCode == 401 && requiresAuth) {
      debugPrint('[API DELETE 401 UNAUTHORIZED] Attempting token refresh...');
      final refreshed = await _attemptRefreshToken();
      if (refreshed) {
        final newHeaders = await _getHeaders(
          isJson: body != null,
          requiresAuth: requiresAuth,
        );
        debugPrint('[API DELETE RETRY WITH NEW TOKEN] -> URL: $url');
        response = await _guard(
          () => _client.delete(url, headers: newHeaders, body: encodedBody),
        );
        debugPrint(
          '[API DELETE RETRY RESPONSE] <- Status: ${response.statusCode}',
        );
      }
    }

    return _processResponse(response, path: path);
  }

  /// Perform Multipart POST request (for identity selfie verification)
  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    bool requiresAuth = true,
  }) async {
    final url = Uri.parse('${ApiConstants.baseUrl}$path');
    var request = http.MultipartRequest('POST', url);

    if (requiresAuth) {
      final token = await AuthTokenStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
    }

    request.headers['Accept'] = 'application/json';
    request.fields.addAll(fields);

    final ext = file.path.toLowerCase();
    final subType = ext.endsWith('.png')
        ? 'png'
        : ext.endsWith('.webp')
        ? 'webp'
        : 'jpeg';
    final mediaType = MediaType('image', subType);

    debugPrint('[API MULTIPART POST REQUEST] -> URL: $url');
    debugPrint(
      'Auth: ${request.headers.containsKey('Authorization')} | '
      'File field: $fileField | Content type: $mediaType | '
      'Size: ${await file.length()} bytes',
    );

    final multipartFile = await http.MultipartFile.fromPath(
      fileField,
      file.path,
      contentType: mediaType,
    );
    request.files.add(multipartFile);

    final stopwatch = Stopwatch()..start();
    // Send via `_client`, not `request.send()`: BaseRequest.send() spins up
    // its own throwaway http.Client() and would silently ignore any client
    // injected into this ApiClient (e.g. a MockClient in tests), always
    // hitting the real network instead.
    final streamedResponse = await _guard(
      () => _client.send(request),
      timeout: uploadTimeout,
    );
    final response = await http.Response.fromStream(streamedResponse);
    stopwatch.stop();

    debugPrint(
      '[API MULTIPART POST RESPONSE] <- URL: $url | Status: ${response.statusCode} | Duration: ${stopwatch.elapsedMilliseconds}ms',
    );

    if (response.statusCode == 401 && requiresAuth) {
      debugPrint(
        '[API MULTIPART 401 UNAUTHORIZED] Attempting token refresh...',
      );
      final refreshed = await _attemptRefreshToken();
      if (refreshed) {
        var retryRequest = http.MultipartRequest('POST', url);
        final token = await AuthTokenStorage.getAccessToken();
        if (token != null) {
          retryRequest.headers['Authorization'] = 'Bearer $token';
        }
        retryRequest.headers['Accept'] = 'application/json';
        retryRequest.fields.addAll(fields);
        retryRequest.files.add(
          await http.MultipartFile.fromPath(
            fileField,
            file.path,
            contentType: mediaType,
          ),
        );
        final retryStreamed = await _guard(
          () => _client.send(retryRequest),
          timeout: uploadTimeout,
        );
        final retryResponse = await http.Response.fromStream(retryStreamed);
        debugPrint(
          '[API MULTIPART RETRY RESPONSE] <- Status: ${retryResponse.statusCode}',
        );
        return _processResponse(retryResponse, path: path);
      }
    }

    return _processResponse(response, path: path);
  }

  /// POST multiple files with ordinary fields. Used for verified property submissions.
  Future<dynamic> postMultipartFiles(
    String path, {
    required Map<String, String> fields,
    required List<MultipartUpload> files,
    bool requiresAuth = true,
  }) async {
    final url = Uri.parse('${ApiConstants.baseUrl}$path');

    Future<http.MultipartRequest> buildRequest() async {
      final request = http.MultipartRequest('POST', url)
        ..headers['Accept'] = 'application/json'
        ..fields.addAll(fields);
      if (requiresAuth) {
        final token = await AuthTokenStorage.getAccessToken();
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
      }
      for (final upload in files) {
        request.files.add(
          await http.MultipartFile.fromPath(
            upload.fieldName,
            upload.file.path,
            contentType: _mediaTypeFor(upload.file.path),
          ),
        );
      }
      return request;
    }

    debugPrint(
      '[API MULTIPART POST REQUEST] -> URL: $url | Files: ${files.length}',
    );
    var response = await http.Response.fromStream(
      await _guard(
        () async => _client.send(await buildRequest()),
        timeout: uploadTimeout,
      ),
    );
    if (response.statusCode == 401 &&
        requiresAuth &&
        await _attemptRefreshToken()) {
      response = await http.Response.fromStream(
        await _guard(
          () async => _client.send(await buildRequest()),
          timeout: uploadTimeout,
        ),
      );
    }
    return _processResponse(response, path: path);
  }

  MediaType _mediaTypeFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'mov':
        return MediaType('video', 'quicktime');
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'pdf':
        return MediaType('application', 'pdf');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  /// Attempt token refresh via POST /token/refresh/
  Future<bool> _attemptRefreshToken() async {
    try {
      final refreshToken = await AuthTokenStorage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.refreshTokenEndpoint}',
      );
      final response = await _guard(
        () => _client.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'refresh': refreshToken}),
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data.containsKey('access')) {
          await AuthTokenStorage.saveAccessToken(data['access']);
          debugPrint('[TOKEN REFRESH SUCCESS] New access token saved.');
          return true;
        }
      }
      // Logged explicitly. A refresh that came back non-200 used to fall
      // straight through to `clear()` without a word, so the log showed the
      // attempt starting and never finishing, which read as the refresh
      // having silently done nothing.
      debugPrint(
        '[TOKEN REFRESH REJECTED] Status: ${response.statusCode} | '
        'Body: ${response.body}',
      );
    } on NetworkException catch (e) {
      // Offline is not "your session expired": dropping the tokens here
      // would sign the user out every time the network blips.
      debugPrint('[TOKEN REFRESH UNREACHABLE] ${e.message}');
      return false;
    } catch (e) {
      // Nor is anything else that went wrong on the way. Only the server
      // saying no is evidence the credentials are dead; an exception is
      // evidence that we do not know, and the safe reading of "do not know"
      // is to leave the session alone and let the caller surface the error.
      debugPrint('[TOKEN REFRESH FAILED] Error: $e');
      return false;
    }

    // Reached only on an explicit non-200 from the refresh endpoint: the
    // server has looked at the refresh token and rejected it. Nothing is left
    // to authenticate with, so clear, and then say so, because the clearing
    // alone left the UI still believing it was signed in.
    await AuthTokenStorage.clear();
    debugPrint('[SESSION EXPIRED] Tokens cleared; signing out.');
    onSessionExpired?.call();
    return false;
  }

  /// Helper method to process HTTP response status codes
  dynamic _processResponse(http.Response response, {required String path}) {
    final statusCode = response.statusCode;
    dynamic body;

    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = response.body;
    }

    if (statusCode >= 200 && statusCode < 300) {
      debugPrint('[API SUCCESS ($path)] Status: $statusCode');
      return body;
    }

    String errorMessage = 'An error occurred. Please try again.';
    if (body is Map<String, dynamic>) {
      // `errors` is read before `detail`, and the order matters. A validation
      // failure carries both:
      //
      //   {"code": "VALIDATION_ERROR",
      //    "detail": "Some details are missing or invalid.",
      //    "errors": {"city": ["This field may not be blank."]}}
      //
      // `detail` is a category and `errors` is the answer. Preferring `detail`
      // , as this did, showed the user a sentence that named no field and
      // suggested no fix, while the thing that did was sitting in the same
      // payload, discarded. Anything that flattens to nothing falls through to
      // `detail`, so endpoints that only send one are unaffected.
      final flattened = body.containsKey('errors')
          ? _flattenErrors(body['errors'])
          : '';
      if (flattened.isNotEmpty) {
        errorMessage = flattened;
      } else if (body.containsKey('detail')) {
        errorMessage = body['detail'].toString();
      } else if (body.containsKey('error')) {
        errorMessage = body['error'].toString();
      } else if (body.containsKey('errors')) {
        errorMessage = 'One or more entries are invalid.';
      } else if (body.isNotEmpty) {
        // Collect field error lists (e.g. {"email": ["user already exists."]})
        final firstEntry = body.entries.first;
        final key = firstEntry.key;
        final val = firstEntry.value;
        if (val is List && val.isNotEmpty) {
          errorMessage = '$key: ${val.first}';
        } else {
          errorMessage = '$key: $val';
        }
      }
    }

    debugPrint(
      '[API ERROR ($path)] Status: $statusCode | Error Message: $errorMessage',
    );

    if (statusCode == 403 &&
        errorMessage.toLowerCase().contains('identity verification')) {
      debugPrint(
        '[API VERIFICATION GATE] Backend rejected request due to unverified '
        'status. Notifying app to re-check verification.',
      );
      onVerificationRequired?.call();
    }

    if (statusCode == 403 &&
        body is Map<String, dynamic> &&
        body['code'] == 'CONSENT_REQUIRED') {
      throw ConsentRequiredException(
        errorMessage,
        statusCode: statusCode,
        errors: body,
      );
    }

    if (statusCode == 403 &&
        body is Map<String, dynamic> &&
        body['code'] == 'PAYOUT_ACCOUNT_REQUIRED') {
      throw PayoutAccountRequiredException(
        errorMessage,
        statusCode: statusCode,
        errors: body,
      );
    }

    if (body is Map<String, dynamic> &&
        body['code'] == 'INSUFFICIENT_VAULT_BALANCE') {
      throw InsufficientVaultBalanceException(
        errorMessage,
        // The backend names this field differently between the withdrawal and
        // the rent-payment rejection, so read either. A missing one is fine:
        // the exception is still the right type, and the caller falls back to
        // its own arithmetic.
        shortfall: (body['shortfall'] ?? body['shortfall_amount'])?.toString(),
        statusCode: statusCode,
        errors: body,
      );
    }

    throw ApiException(errorMessage, statusCode: statusCode, errors: body);
  }

  /// Flattens nested field-error maps/lists (as returned for batch validation
  /// failures) into a single readable "field: message" summary.
  String _flattenErrors(dynamic errors, {String label = ''}) {
    if (errors is Map) {
      final parts = <String>[];
      errors.forEach((key, value) {
        final childLabel = label.isEmpty ? key.toString() : '$label.$key';
        final flattened = _flattenErrors(value, label: childLabel);
        if (flattened.isNotEmpty) parts.add(flattened);
      });
      return parts.join('; ');
    }
    if (errors is List) {
      if (errors.isNotEmpty && errors.every((e) => e is String)) {
        return '$label: ${errors.join(', ')}';
      }
      final parts = <String>[];
      for (var i = 0; i < errors.length; i++) {
        final flattened = _flattenErrors(errors[i], label: '$label[$i]');
        if (flattened.isNotEmpty) parts.add(flattened);
      }
      return parts.join('; ');
    }
    return label.isEmpty ? errors.toString() : '$label: $errors';
  }
}
