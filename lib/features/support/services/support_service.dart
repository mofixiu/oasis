import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';

/// How to reach Oasis, and where its legal documents live.
///
/// Served by the backend (spec v16 §3, live in API guide 20) so it can change
/// without an app release. A value the server sends empty is not offered:
/// the business has not supplied it yet, and that is a deliberate state, not
/// a gap to fill from elsewhere. Build-time values
/// (`--dart-define=SUPPORT_EMAIL=…`) are only used when the server cannot be
/// reached at all.
class AppConfig {
  final String supportEmail;
  final String supportPhone;
  final String supportWhatsApp;
  final String supportHours;
  final String termsUrl;
  final String privacyUrl;

  const AppConfig({
    this.supportEmail = '',
    this.supportPhone = '',
    this.supportWhatsApp = '',
    this.supportHours = '',
    this.termsUrl = '',
    this.privacyUrl = '',
  });

  static const AppConfig buildTime = AppConfig(
    supportEmail: String.fromEnvironment('SUPPORT_EMAIL'),
    supportPhone: String.fromEnvironment('SUPPORT_PHONE'),
    supportWhatsApp: String.fromEnvironment('SUPPORT_WHATSAPP'),
    supportHours: String.fromEnvironment('SUPPORT_HOURS'),
    termsUrl: String.fromEnvironment('TERMS_URL'),
    privacyUrl: String.fromEnvironment('PRIVACY_URL'),
  );

  /// Exactly what the server sent. Blank stays blank: the backend asks the
  /// app to hide empty values rather than substitute its own.
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    String read(String key) => json[key]?.toString().trim() ?? '';

    return AppConfig(
      supportEmail: read('support_email'),
      supportPhone: read('support_phone'),
      supportWhatsApp: read('support_whatsapp'),
      supportHours: read('support_hours'),
      termsUrl: read('terms_url'),
      privacyUrl: read('privacy_url'),
    );
  }

  bool get hasDirectContact =>
      supportEmail.isNotEmpty ||
      supportPhone.isNotEmpty ||
      supportWhatsApp.isNotEmpty;
}

enum SupportCategory {
  booking('BOOKING', 'Booking'),
  payment('PAYMENT', 'Payment'),
  vault('VAULT', 'Vault'),
  account('ACCOUNT', 'Account'),
  safety('SAFETY', 'Safety'),
  other('OTHER', 'Other');

  final String wireValue;
  final String label;

  const SupportCategory(this.wireValue, this.label);
}

class SupportService {
  final ApiClient _apiClient;

  SupportService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// The current config, or the build-time values when the endpoint cannot
  /// be reached.
  Future<AppConfig> getAppConfig() async {
    try {
      final response = await _apiClient.get(
        ApiConstants.appConfigEndpoint,
        requiresAuth: false,
      );
      if (response is Map<String, dynamic>) {
        return AppConfig.fromJson(response);
      }
    } catch (_) {}
    return AppConfig.buildTime;
  }

  /// Sends a message to the support team and returns its reference, when the
  /// server gives one.
  Future<String?> createTicket({
    required SupportCategory category,
    required String message,
    String? shortLetBookingId,
    String? conversationId,
  }) async {
    final response = await _apiClient.post(
      ApiConstants.supportTicketsEndpoint,
      body: {
        'category': category.wireValue,
        'message': message,
        'short_let_booking_id': ?shortLetBookingId,
        'conversation_id': ?conversationId,
      },
    );
    if (response is Map<String, dynamic>) {
      return (response['reference'] ?? response['id'])?.toString();
    }
    return null;
  }
}
