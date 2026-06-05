/// Monday of the week containing [instant] (date-only).
DateTime mondayOfWeekContaining(DateTime instant) {
  final date = DateTime(instant.year, instant.month, instant.day);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}
