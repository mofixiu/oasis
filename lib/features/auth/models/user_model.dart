enum UserRole {
  owner,
  tenant;

  static UserRole fromString(String? role) {
    if (role?.toUpperCase() == 'OWNER' || role?.toUpperCase() == 'LANDLORD') {
      return UserRole.owner;
    }
    return UserRole.tenant;
  }

  String toServerString() {
    switch (this) {
      case UserRole.owner:
        return 'OWNER';
      case UserRole.tenant:
        return 'TENANT';
    }
  }

  String get displayName {
    switch (this) {
      case UserRole.owner:
        return 'Landlord';
      case UserRole.tenant:
        return 'Tenant';
    }
  }
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

  UserModel({
    required this.id,
    required this.email,
    required this.phone,
    required this.role,
    required this.verificationStatus,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      role: UserRole.fromString(json['role']),
      verificationStatus: VerificationStatus.fromString(
        json['verification_status'],
      ),
    );
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? phone,
    UserRole? role,
    VerificationStatus? verificationStatus,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      verificationStatus: verificationStatus ?? this.verificationStatus,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'phone': phone,
      'role': role.toServerString(),
      'verification_status': verificationStatus.label,
    };
  }
}
