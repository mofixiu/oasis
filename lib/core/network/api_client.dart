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

/// Extracts a clean, user-presentable message from a caught error.
///
/// [ApiException.message] is already the backend's human-readable detail
/// (e.g. "Invalid email or password."); this avoids ever surfacing the raw
/// `ApiException(403): ...` debug string in toasts/banners.
String friendlyErrorMessage(Object error) {
  if (error is ApiException) return error.message;
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

  /// Fired whenever any request hits the backend's verification gate (403
  /// "Complete identity verification before accessing this feature."),
  /// even if the locally cached verification status was stale/VERIFIED.
  /// Wired in main.dart to re-check verification status and route the user
  /// back to the verification screen.
  static void Function()? onVerificationRequired;

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

  /// Perform GET request
  Future<dynamic> get(String path, {bool requiresAuth = true}) async {
    final url = Uri.parse('${ApiConstants.baseUrl}$path');
    final headers = await _getHeaders(
      isJson: false,
      requiresAuth: requiresAuth,
    );

    debugPrint(
      '🌐 [API GET REQUEST] -> URL: $url | Auth: ${headers.containsKey('Authorization')}',
    );

    final stopwatch = Stopwatch()..start();
    var response = await _client.get(url, headers: headers);
    stopwatch.stop();

    debugPrint(
      '📩 [API GET RESPONSE] <- URL: $url | Status: ${response.statusCode} | Duration: ${stopwatch.elapsedMilliseconds}ms',
    );

    if (response.statusCode == 401 && requiresAuth) {
      debugPrint('⚠️ [API GET 401 UNAUTHORIZED] Attempting token refresh...');
      final refreshed = await _attemptRefreshToken();
      if (refreshed) {
        final newHeaders = await _getHeaders(
          isJson: false,
          requiresAuth: requiresAuth,
        );
        debugPrint('🔄 [API GET RETRY WITH NEW TOKEN] -> URL: $url');
        response = await _client.get(url, headers: newHeaders);
        debugPrint(
          '📩 [API GET RETRY RESPONSE] <- Status: ${response.statusCode}',
        );
      }
    }

    return _processResponse(response, path: path);
  }

  /// Perform POST request
  Future<dynamic> post(
    String path, {
    dynamic body,
    bool requiresAuth = true,
  }) async {
    final url = Uri.parse('${ApiConstants.baseUrl}$path');
    final headers = await _getHeaders(isJson: true, requiresAuth: requiresAuth);
    final encodedBody = body != null ? jsonEncode(body) : null;

    debugPrint(
      '🌐 [API POST REQUEST] -> URL: $url | Auth: ${headers.containsKey('Authorization')}',
    );

    final stopwatch = Stopwatch()..start();
    var response = await _client.post(url, headers: headers, body: encodedBody);
    stopwatch.stop();

    debugPrint(
      '📩 [API POST RESPONSE] <- URL: $url | Status: ${response.statusCode} | Duration: ${stopwatch.elapsedMilliseconds}ms',
    );

    if (response.statusCode == 401 && requiresAuth) {
      debugPrint('⚠️ [API POST 401 UNAUTHORIZED] Attempting token refresh...');
      final refreshed = await _attemptRefreshToken();
      if (refreshed) {
        final newHeaders = await _getHeaders(
          isJson: true,
          requiresAuth: requiresAuth,
        );
        debugPrint('🔄 [API POST RETRY WITH NEW TOKEN] -> URL: $url');
        response = await _client.post(
          url,
          headers: newHeaders,
          body: encodedBody,
        );
        debugPrint(
          '📩 [API POST RETRY RESPONSE] <- Status: ${response.statusCode}',
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
      '🌐 [API PATCH REQUEST] -> URL: $url | Auth: ${headers.containsKey('Authorization')}',
    );

    final stopwatch = Stopwatch()..start();
    var response = await _client.patch(
      url,
      headers: headers,
      body: encodedBody,
    );
    stopwatch.stop();

    debugPrint(
      '📩 [API PATCH RESPONSE] <- URL: $url | Status: ${response.statusCode} | Duration: ${stopwatch.elapsedMilliseconds}ms',
    );

    if (response.statusCode == 401 && requiresAuth) {
      debugPrint('⚠️ [API PATCH 401 UNAUTHORIZED] Attempting token refresh...');
      final refreshed = await _attemptRefreshToken();
      if (refreshed) {
        final newHeaders = await _getHeaders(
          isJson: true,
          requiresAuth: requiresAuth,
        );
        debugPrint('🔄 [API PATCH RETRY WITH NEW TOKEN] -> URL: $url');
        response = await _client.patch(
          url,
          headers: newHeaders,
          body: encodedBody,
        );
        debugPrint(
          '📩 [API PATCH RETRY RESPONSE] <- Status: ${response.statusCode}',
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

    debugPrint('🌐 [API MULTIPART POST REQUEST] -> URL: $url');
    debugPrint(
      '   Auth: ${request.headers.containsKey('Authorization')} | '
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
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    stopwatch.stop();

    debugPrint(
      '📩 [API MULTIPART POST RESPONSE] <- URL: $url | Status: ${response.statusCode} | Duration: ${stopwatch.elapsedMilliseconds}ms',
    );

    if (response.statusCode == 401 && requiresAuth) {
      debugPrint(
        '⚠️ [API MULTIPART 401 UNAUTHORIZED] Attempting token refresh...',
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
        final retryStreamed = await retryRequest.send();
        final retryResponse = await http.Response.fromStream(retryStreamed);
        debugPrint(
          '📩 [API MULTIPART RETRY RESPONSE] <- Status: ${retryResponse.statusCode}',
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
      '🌐 [API MULTIPART POST REQUEST] -> URL: $url | Files: ${files.length}',
    );
    var response = await http.Response.fromStream(
      await (await buildRequest()).send(),
    );
    if (response.statusCode == 401 &&
        requiresAuth &&
        await _attemptRefreshToken()) {
      response = await http.Response.fromStream(
        await (await buildRequest()).send(),
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
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'refresh': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data.containsKey('access')) {
          await AuthTokenStorage.saveAccessToken(data['access']);
          debugPrint('✅ [TOKEN REFRESH SUCCESS] New access token saved.');
          return true;
        }
      }
    } catch (e) {
      debugPrint('❌ [TOKEN REFRESH FAILED] Error: $e');
    }
    await AuthTokenStorage.clear();
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
      debugPrint('✅ [API SUCCESS ($path)] Status: $statusCode');
      return body;
    }

    String errorMessage = 'An error occurred. Please try again.';
    if (body is Map<String, dynamic>) {
      if (body.containsKey('detail')) {
        errorMessage = body['detail'].toString();
      } else if (body.containsKey('error')) {
        errorMessage = body['error'].toString();
      } else if (body.containsKey('errors')) {
        // Nested per-row validation errors, e.g. batch unit creation:
        // {"errors": {"units": {"units.1": {"unit_number": ["Already exists."]}}}}
        final flattened = _flattenErrors(body['errors']);
        errorMessage = flattened.isNotEmpty
            ? flattened
            : 'One or more entries are invalid.';
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
      '❌ [API ERROR ($path)] Status: $statusCode | Error Message: $errorMessage',
    );

    if (statusCode == 403 &&
        errorMessage.toLowerCase().contains('identity verification')) {
      debugPrint(
        '🛡️ [API VERIFICATION GATE] Backend rejected request due to unverified '
        'status. Notifying app to re-check verification.',
      );
      onVerificationRequired?.call();
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
