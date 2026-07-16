import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable wall clock. Tests override this to pin the Home greeting to a
/// fixed time; `localDayTickProvider` (providers/transactions.dart) is only
/// day-granular and can't drive hour-of-day logic.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);
