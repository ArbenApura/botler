// THE HEALTH DATA THE WEIGHT, TRAIN AND SLEEP SCREENS READ. THE RULES ARE ON THE SERVER: THESE ONLY ASK AND KEEP THE ANSWER.

// -- DEP-MODULES -- //
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../core/json.dart';
import 'providers.dart';

// -- CONSTANTS -- //

/// The trend, the change, the forecast and the gentle low-intake flag, over about the last month.
final FutureProvider<Json> weightTrendProvider =
    FutureProvider.autoDispose<Json>(
      (ref) => ref.watch(apiProvider).verbJson('weight_trend'),
    );

/// The check-ins still open.
final FutureProvider<List<Json>> proposalsProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('proposals_list'),
    );

/// This week of training.
final FutureProvider<Json> trainProvider = FutureProvider.autoDispose<Json>(
  (ref) => ref.watch(apiProvider).verbJson('train_get'),
);

/// The programs that exist and the questions before starting one.
final FutureProvider<Json> programsProvider = FutureProvider.autoDispose<Json>(
  (ref) => ref.watch(apiProvider).verbJson('programs_list'),
);

/// The nights, the average and any pattern.
final FutureProvider<Json> sleepProvider = FutureProvider.autoDispose<Json>(
  (ref) => ref.watch(apiProvider).verbJson('sleep_summary'),
);
