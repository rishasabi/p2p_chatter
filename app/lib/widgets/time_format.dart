import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Clock time in the user's preferred 12/24-hour style. The Go node stamps
/// messages in UTC, so everything is shown in local time.
String formatClock(BuildContext context, DateTime time) {
  final local = time.toLocal();
  return MediaQuery.alwaysUse24HourFormatOf(context)
      ? DateFormat('HH:mm').format(local)
      : DateFormat('h:mm a').format(local);
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Short stamp for the chat list: the time today, then a weekday, then a date.
String formatListTime(BuildContext context, DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final days = _day(now ?? DateTime.now()).difference(_day(local)).inDays;
  if (days <= 0) return formatClock(context, local);
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEEE').format(local);
  return DateFormat('d MMM yyyy').format(local);
}

/// Separator above the first message of each day in a thread.
String formatDayHeading(DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final current = now ?? DateTime.now();
  final days = _day(current).difference(_day(local)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEEE').format(local);
  return local.year == current.year
      ? DateFormat('EEEE d MMMM').format(local)
      : DateFormat('d MMMM yyyy').format(local);
}

bool isSameDay(DateTime a, DateTime b) => _day(a.toLocal()) == _day(b.toLocal());
