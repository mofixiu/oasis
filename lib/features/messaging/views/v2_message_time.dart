import 'package:intl/intl.dart';

/// Local time of a backend timestamp, or null when it does not parse.
DateTime? v2LocalTime(String raw) => DateTime.tryParse(raw)?.toLocal();

int _daysAgo(DateTime at) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.difference(DateTime(at.year, at.month, at.day)).inDays;
}

/// "10:24 AM" today, "Yesterday", a weekday within the week, then "8 Oct".
String v2InboxTime(String raw) {
  final at = v2LocalTime(raw);
  if (at == null) return '';
  final days = _daysAgo(at);
  if (days <= 0) return DateFormat('h:mm a').format(at);
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE').format(at);
  return DateFormat('d MMM').format(at);
}

/// Separator between days in a thread: "Today", "Yesterday", "10 Dec 2026".
String v2DayLabel(DateTime at) {
  final days = _daysAgo(at);
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return DateFormat('d MMM yyyy').format(at);
}
