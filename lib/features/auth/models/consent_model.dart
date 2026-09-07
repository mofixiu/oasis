/// The single consent type currently required before identity verification.
/// Bump [version] whenever the backend guide documents a new one: sending a
/// stale version does not satisfy the gate.
class VerificationConsent {
  static const String type = 'VERIFICATION_PRIVACY';
  static const String version = '2026-08-15';
}

class ConsentModel {
  final String id;
  final String consentType;
  final String version;
  final String acceptedAt;

  ConsentModel({
    required this.id,
    required this.consentType,
    required this.version,
    required this.acceptedAt,
  });

  factory ConsentModel.fromJson(Map<String, dynamic> json) {
    return ConsentModel(
      id: json['id'] ?? '',
      consentType: json['consent_type'] ?? '',
      version: json['version'] ?? '',
      acceptedAt: json['accepted_at'] ?? '',
    );
  }
}
