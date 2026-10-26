import '../../../core/app_variant.dart';
import '../../payouts/models/payout_models.dart';

enum UserRole {
  owner,
  tenant,

  /// A tradesperson who takes repair jobs through Fix. Registered as its own
  /// account rather than a flag on a tenant: an artisan owns no unit, signs no
  /// agreement and pays no rent, so almost nothing a tenant account carries
  /// applies to them.
  artisan;

  static UserRole fromString(String? role) {
    switch (role?.toUpperCase()) {
      case 'OWNER':
      case 'LANDLORD':
        return UserRole.owner;
      case 'ARTISAN':
        return UserRole.artisan;
      default:
        return UserRole.tenant;
    }
  }

  String toServerString() {
    switch (this) {
      case UserRole.owner:
        return 'OWNER';
      case UserRole.tenant:
        return 'TENANT';
      case UserRole.artisan:
        return 'ARTISAN';
    }
  }

  /// The short-stay app (v2) calls the two renting roles guest and host.
  String get displayName {
    switch (this) {
      case UserRole.owner:
        return isOasisV2 ? 'Host' : 'Landlord';
      case UserRole.tenant:
        return isOasisV2 ? 'Guest' : 'Tenant';
      case UserRole.artisan:
        return 'Artisan';
    }
  }

  /// Tested explicitly rather than as `!= owner`, which is how an artisan
  /// would inherit every tenant-only affordance in the app (Discover, rent,
  /// vault top-ups) none of which the backend would serve them.
  bool get isTenant => this == UserRole.tenant;

  bool get isArtisan => this == UserRole.artisan;
}

enum VerificationStatus {
  unverified,
  pending,
  verified,
  failed;

  static VerificationStatus fromString(String? status) {
    switch (status?.toUpperCase()) {
      case 'PENDING':
        return VerificationStatus.pending;
      case 'VERIFIED':
        return VerificationStatus.verified;
      case 'FAILED':
        return VerificationStatus.failed;
      default:
        return VerificationStatus.unverified;
    }
  }

  String get label {
    switch (this) {
      case VerificationStatus.unverified:
        return 'UNVERIFIED';
      case VerificationStatus.pending:
        return 'PENDING';
      case VerificationStatus.verified:
        return 'VERIFIED';
      case VerificationStatus.failed:
        return 'FAILED';
    }
  }
}

class UserModel {
  final String id;
  final String email;
  final String phone;
  final UserRole role;
  final VerificationStatus verificationStatus;

  /// Landlord payout state. The backend derives the capability flags below
  /// from this, so the app should gate on the flags rather than re-deriving
  /// the rules itself.
  final PayoutAccountStatus payoutAccountStatus;

  /// True once the landlord may create properties/units/agreements. Payout
  /// setup is deliberately *not* a prerequisite for these.
  final bool canCreateProperties;

  /// False while the landlord still needs verified payout details before
  /// final-signing an agreement.
  final bool canExecuteAgreements;

  /// What payout setup is currently gating, e.g. `"AGREEMENT_EXECUTION"`.
  final String? payoutAccountRequiredFor;

  /// Profile details edited from the v2 Edit profile screen. Empty until the
  /// backend returns them (spec v16 §2).
  final String fullName;
  final String avatarUrl;

  /// `YYYY-MM-DD`, or empty.
  final String dateOfBirth;
  final String bio;

  UserModel({
    required this.id,
    required this.email,
    required this.phone,
    required this.role,
    required this.verificationStatus,
    this.payoutAccountStatus = PayoutAccountStatus.notRequired,
    this.canCreateProperties = false,
    this.canExecuteAgreements = false,
    this.payoutAccountRequiredFor,
    this.fullName = '',
    this.avatarUrl = '',
    this.dateOfBirth = '',
    this.bio = '',
  });

  /// What to call this person: their name when they have given one, else the
  /// part of their email before the @, capitalised.
  String get preferredName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    final handle = email.contains('@') ? email.split('@').first : email;
    if (handle.isEmpty) return 'Your account';
    return handle[0].toUpperCase() + handle.substring(1);
  }

  /// Whether to surface a payout-setup prompt to this user. Tenants never see
  /// one; landlords do once the backend says payout is outstanding.
  bool get needsPayoutSetup =>
      role == UserRole.owner &&
      verificationStatus == VerificationStatus.verified &&
      payoutAccountStatus.needsSetup;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      role: UserRole.fromString(json['role']),
      verificationStatus: VerificationStatus.fromString(
        json['verification_status'],
      ),
      payoutAccountStatus: PayoutAccountStatus.fromString(
        json['payout_account_status']?.toString(),
      ),
      canCreateProperties: json['can_create_properties'] ?? false,
      canExecuteAgreements: json['can_execute_agreements'] ?? false,
      payoutAccountRequiredFor: json['payout_account_required_for']?.toString(),
      fullName: (json['full_name'] ?? json['name'] ?? '').toString(),
      avatarUrl: (json['avatar_url'] ?? '').toString(),
      dateOfBirth: (json['date_of_birth'] ?? '').toString(),
      bio: (json['bio'] ?? '').toString(),
    );
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? phone,
    UserRole? role,
    VerificationStatus? verificationStatus,
    PayoutAccountStatus? payoutAccountStatus,
    bool? canCreateProperties,
    bool? canExecuteAgreements,
    String? payoutAccountRequiredFor,
    String? fullName,
    String? avatarUrl,
    String? dateOfBirth,
    String? bio,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      payoutAccountStatus: payoutAccountStatus ?? this.payoutAccountStatus,
      canCreateProperties: canCreateProperties ?? this.canCreateProperties,
      canExecuteAgreements: canExecuteAgreements ?? this.canExecuteAgreements,
      payoutAccountRequiredFor:
          payoutAccountRequiredFor ?? this.payoutAccountRequiredFor,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      bio: bio ?? this.bio,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'phone': phone,
      'role': role.toServerString(),
      'verification_status': verificationStatus.label,
      'payout_account_status': payoutAccountStatus.wireValue,
      'can_create_properties': canCreateProperties,
      'can_execute_agreements': canExecuteAgreements,
      if (payoutAccountRequiredFor != null)
        'payout_account_required_for': payoutAccountRequiredFor,
      if (fullName.isNotEmpty) 'full_name': fullName,
      if (avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
      if (dateOfBirth.isNotEmpty) 'date_of_birth': dateOfBirth,
      if (bio.isNotEmpty) 'bio': bio,
    };
  }
}
