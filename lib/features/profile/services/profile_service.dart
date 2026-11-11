import 'dart:io';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';

/// Edits to the signed-in user's own profile (spec v16 §2).
class ProfileService {
  final ApiClient _apiClient;

  ProfileService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// Sends only the fields given. [dateOfBirth] is `YYYY-MM-DD`; an empty
  /// string clears an optional field. [brandName] is hosts only: the
  /// backend refuses it from guests, and an empty string clears it.
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? dateOfBirth,
    String? bio,
    String? brandName,
  }) => _apiClient.patch(
    ApiConstants.profileEndpoint,
    body: {
      'full_name': ?fullName,
      'phone': ?phone,
      'date_of_birth': ?dateOfBirth,
      'bio': ?bio,
      'brand_name': ?brandName,
    },
  );

  /// Uploads a new profile photo and returns its URL when the server sends
  /// one back.
  Future<String?> uploadAvatar(File photo) async {
    final response = await _apiClient.postMultipart(
      ApiConstants.profileAvatarEndpoint,
      fields: const {},
      fileField: 'avatar',
      file: photo,
    );
    if (response is Map<String, dynamic>) {
      return response['avatar_url']?.toString();
    }
    return null;
  }
}
