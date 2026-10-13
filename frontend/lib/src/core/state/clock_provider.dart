import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Current time for "has the timetable data ended?" checks. Tests override
/// it to pin the date.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
