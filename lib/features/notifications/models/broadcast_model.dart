/// A landlord announcement, fanned out into each tenant's notification list.
///
/// Broadcasts are one-way and are not conversations: a tenant who wants to
/// reply opens a chat, which keeps every two-way exchange inside the messaging
/// feature where it can be moderated and kept with its unit.
library;

/// Who a broadcast reaches.
enum BroadcastAudience {
  /// Every tenant with a live tenancy under this landlord.
  allTenants,

  /// Tenants in one property.
  property;

  String get wireValue {
    switch (this) {
      case BroadcastAudience.allTenants:
        return 'ALL_TENANTS';
      case BroadcastAudience.property:
        return 'PROPERTY';
    }
  }

  static BroadcastAudience fromString(String? value) =>
      value?.toUpperCase() == 'PROPERTY'
      ? BroadcastAudience.property
      : BroadcastAudience.allTenants;

  String get label {
    switch (this) {
      case BroadcastAudience.allTenants:
        return 'All my tenants';
      case BroadcastAudience.property:
        return 'One property';
    }
  }
}

/// A sent broadcast, with delivery figures.
class Broadcast {
  final String id;
  final BroadcastAudience audience;
  final String propertyId;
  final String propertyName;
  final String title;
  final String body;

  /// How many tenants it was delivered to.
  final int recipientCount;

  /// How many have opened it. Kept current by the backend so the landlord can
  /// see whether an announcement actually landed.
  final int readCount;

  final String createdAt;

  const Broadcast({
    required this.id,
    required this.audience,
    required this.title,
    required this.body,
    this.propertyId = '',
    this.propertyName = '',
    this.recipientCount = 0,
    this.readCount = 0,
    this.createdAt = '',
  });

  factory Broadcast.fromJson(Map<String, dynamic> json) {
    final property = json['property'];
    final propertyMap = property is Map<String, dynamic>
        ? property
        : const <String, dynamic>{};

    return Broadcast(
      id: json['id']?.toString() ?? '',
      audience: BroadcastAudience.fromString(json['audience']?.toString()),
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      propertyId: propertyMap['id']?.toString() ?? '',
      propertyName: propertyMap['name']?.toString() ?? '',
      recipientCount:
          int.tryParse(json['recipient_count']?.toString() ?? '') ?? 0,
      readCount: int.tryParse(json['read_count']?.toString() ?? '') ?? 0,
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  /// "Read by 7 of 12", or a plainer line when nothing has been opened yet.
  String get deliverySummary {
    if (recipientCount == 0) return 'No recipients';
    if (readCount == 0) {
      return 'Sent to $recipientCount ${recipientCount == 1 ? 'tenant' : 'tenants'}';
    }
    return 'Read by $readCount of $recipientCount';
  }
}
