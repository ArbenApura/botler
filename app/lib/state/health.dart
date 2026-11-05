// THE HEALTH DATA THE SCREENS READ. THE RULES ARE ON THE SERVER: THESE ONLY ASK AND KEEP THE ANSWER.

// -- DEP-MODULES -- //
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../core/api.dart';
import '../core/json.dart';
import 'providers.dart';

// -- CONSTANTS -- //

/// The setup, the goal and the estimates.
final FutureProvider<Json> healthProvider = FutureProvider.autoDispose<Json>(
  (ref) => ref.watch(apiProvider).verbJson('health_get'),
);

/// Work hours, free time, one-day changes and the settings around them.
final FutureProvider<Json> availabilityProvider =
    FutureProvider.autoDispose<Json>(
      (ref) => ref.watch(apiProvider).verbJson('availability_get'),
    );

/// Today's food, totals and what is left.
final FutureProvider<Json> foodDayProvider = FutureProvider.autoDispose<Json>(
  (ref) => ref.watch(apiProvider).verbJson('food_day'),
);

/// One line for each part of Health.
final FutureProvider<Json> healthHomeProvider =
    FutureProvider.autoDispose<Json>(
      (ref) => ref.watch(apiProvider).verbJson('health_home'),
    );

// -- FUNCTIONS -- //

/// Sends a write now, or keeps it on the phone under the same key when there is no connection. True when it was kept for later.
Future<bool> writeOrQueue(
  WidgetRef ref,
  String verb,
  Json args,
  String key,
) async {
  try {
    await ref.read(apiProvider).verb(verb, args, key);
    return false;
  } on ApiException catch (e) {
    if (!e.isNetwork) rethrow;
    await ref.read(outboxProvider).add(verb, args, key: key);
    ref.read(outboxCountProvider.notifier).refresh();
    return true;
  }
}
