/// Models for landlord ↔ tenant messaging.
///
/// A conversation exists because a relationship exists, an application or a
/// tenancy, the way a ride's chat exists because of the ride. There is no
/// contact list and no search: the only people reachable are the ones already
/// on the other side of a live application or agreement.
library;

/// What a conversation hangs off.
enum ConversationContext {
  /// The tenant has applied for the unit; nothing is signed yet.
  application,

  /// There is a tenancy agreement between the two parties.
  tenancy,

  /// A paid short-let booking. Opened only once the stay is confirmed, and
  /// it is where the practical arrangements happen, where the key is, what
  /// the gate code is, what time the guest lands.
  shortLet,

  unknown;

  static ConversationContext fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'APPLICATION':
        return ConversationContext.application;
      case 'TENANCY':
        return ConversationContext.tenancy;
      case 'SHORT_LET':
      case 'SHORTLET':
      case 'SHORT_LET_BOOKING':
        return ConversationContext.shortLet;
      default:
        return ConversationContext.unknown;
    }
  }

  String get label {
    switch (this) {
      case ConversationContext.application:
        return 'Application';
      case ConversationContext.tenancy:
        return 'Tenancy';
      case ConversationContext.shortLet:
        return 'Stay';
      case ConversationContext.unknown:
        return '';
    }
  }
}

/// Whether new messages are still accepted.
///
/// A closed conversation stays readable: the history is evidence if the
/// tenancy is ever disputed, but nothing more can be added to it.
enum ConversationStatus {
  open,
  closed;

  static ConversationStatus fromString(String? value) =>
      value?.toUpperCase() == 'CLOSED'
      ? ConversationStatus.closed
      : ConversationStatus.open;

  bool get isClosed => this == ConversationStatus.closed;
}

/// The other party, resolved by the backend per caller.
///
/// Deliberately thin: a name, a role and verification standing. Contact
/// details stay in the application payload where they already are, so
/// messaging never becomes a way to harvest phone numbers.
class Counterparty {
  final String id;
  final String fullName;
  final String role;
  final String verificationStatus;

  const Counterparty({
    this.id = '',
    this.fullName = '',
    this.role = '',
    this.verificationStatus = '',
  });

  factory Counterparty.fromJson(Map<String, dynamic> json) => Counterparty(
    id: json['id']?.toString() ?? '',
    fullName: json['full_name']?.toString() ?? '',
    role: json['role']?.toString() ?? '',
    verificationStatus: json['verification_status']?.toString() ?? '',
  );

  bool get isVerified => verificationStatus.toUpperCase() == 'VERIFIED';

  /// Falls back to something addressable rather than rendering a blank row.
  String get displayName =>
      fullName.trim().isEmpty ? 'Oasis user' : fullName.trim();

  String get initial =>
      displayName.isEmpty ? '?' : displayName[0].toUpperCase();
}

/// One message in a thread.
class Message {
  final String id;
  final String body;

  /// `OWNER`, `TENANT`, or `SYSTEM`.
  final String senderRole;
  final String senderName;

  /// System messages mark what happened to the relationship (application
  /// approved, rent paid, tenancy ended) and render as a centred line rather
  /// than a bubble, because nobody said them.
  final bool isSystem;

  /// Echoed back by the backend so an optimistic bubble can be replaced by the
  /// real message rather than duplicated beside it.
  final String clientMessageId;

  final String? readAt;
  final String createdAt;

  /// True while this message exists only on this device. Rendered at reduced
  /// opacity with a clock instead of a tick.
  final bool isPending;

  /// True when sending failed and the message can be retried.
  final bool hasFailed;

  const Message({
    required this.id,
    required this.body,
    required this.senderRole,
    this.senderName = '',
    this.isSystem = false,
    this.clientMessageId = '',
    this.readAt,
    this.createdAt = '',
    this.isPending = false,
    this.hasFailed = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id']?.toString() ?? '',
    body: json['body']?.toString() ?? '',
    senderRole: json['sender_role']?.toString() ?? '',
    senderName: json['sender_name']?.toString() ?? '',
    isSystem: json['is_system'] == true,
    clientMessageId: json['client_message_id']?.toString() ?? '',
    readAt: json['read_at']?.toString(),
    createdAt: json['created_at']?.toString() ?? '',
  );

  bool get isRead => readAt != null && readAt!.isNotEmpty;

  /// Whether this device's user wrote it.
  bool isMine(String myRole) =>
      !isSystem && senderRole.toUpperCase() == myRole.toUpperCase();

  Message copyWith({String? id, bool? isPending, bool? hasFailed}) => Message(
    id: id ?? this.id,
    body: body,
    senderRole: senderRole,
    senderName: senderName,
    isSystem: isSystem,
    clientMessageId: clientMessageId,
    readAt: readAt,
    createdAt: createdAt,
    isPending: isPending ?? this.isPending,
    hasFailed: hasFailed ?? this.hasFailed,
  );
}

/// A thread, as it appears in the inbox.
class Conversation {
  final String id;
  final ConversationStatus status;
  final ConversationContext context;
  final String contextId;

  final String propertyId;
  final String propertyName;
  final String propertyPhotoUrl;
  final String unitId;
  final String unitNumber;

  final Counterparty counterparty;
  final Message? lastMessage;
  final int unreadCount;
  final String createdAt;

  const Conversation({
    required this.id,
    required this.status,
    required this.context,
    this.contextId = '',
    this.propertyId = '',
    this.propertyName = '',
    this.propertyPhotoUrl = '',
    this.unitId = '',
    this.unitNumber = '',
    this.counterparty = const Counterparty(),
    this.lastMessage,
    this.unreadCount = 0,
    this.createdAt = '',
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final property = json['property'];
    final propertyMap = property is Map<String, dynamic>
        ? property
        : const <String, dynamic>{};
    final unit = json['unit'];
    final unitMap = unit is Map<String, dynamic>
        ? unit
        : const <String, dynamic>{};
    final counterparty = json['counterparty'];
    final last = json['last_message'];

    return Conversation(
      id: json['id']?.toString() ?? '',
      status: ConversationStatus.fromString(json['status']?.toString()),
      context: ConversationContext.fromString(json['context_type']?.toString()),
      contextId: json['context_id']?.toString() ?? '',
      propertyId: propertyMap['id']?.toString() ?? '',
      propertyName: propertyMap['name']?.toString() ?? '',
      propertyPhotoUrl: propertyMap['cover_photo_url']?.toString() ?? '',
      unitId: unitMap['id']?.toString() ?? '',
      unitNumber: unitMap['unit_number']?.toString() ?? '',
      counterparty: counterparty is Map<String, dynamic>
          ? Counterparty.fromJson(counterparty)
          : const Counterparty(),
      lastMessage: last is Map<String, dynamic> ? Message.fromJson(last) : null,
      unreadCount: int.tryParse(json['unread_count']?.toString() ?? '') ?? 0,
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  /// The same thread with a few fields moved on.
  ///
  /// Only the three that change while the app is running are settable: a new
  /// message landing, the badge going up or being cleared, and the backend
  /// closing the thread when the relationship ends. Everything else about a
  /// conversation (who it is with, which unit it is about) is fixed at
  /// creation, so allowing it to be overwritten locally would only ever let a
  /// bug rewrite history.
  Conversation copyWith({
    Message? lastMessage,
    int? unreadCount,
    ConversationStatus? status,
  }) => Conversation(
    id: id,
    status: status ?? this.status,
    context: context,
    contextId: contextId,
    propertyId: propertyId,
    propertyName: propertyName,
    propertyPhotoUrl: propertyPhotoUrl,
    unitId: unitId,
    unitNumber: unitNumber,
    counterparty: counterparty,
    lastMessage: lastMessage ?? this.lastMessage,
    unreadCount: unreadCount ?? this.unreadCount,
    createdAt: createdAt,
  );

  /// "Sunset House · Unit A1", or whichever half is available.
  String get subjectLine {
    final unit = unitNumber.isEmpty ? '' : 'Unit $unitNumber';
    if (propertyName.isEmpty) return unit;
    return unit.isEmpty ? propertyName : '$propertyName · $unit';
  }

  bool get hasUnread => unreadCount > 0;
}
