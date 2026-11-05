// HEALTH SCREENS (BTL-20261105-0015, P5 TO P8): THE HOME TILES, WEIGHT WITH ITS CHECK-IN, TRAIN, A SESSION, NEXT WEEK AND SLEEP. EVERY ONE IS BUILT AT PHONE WIDTH, SO AN OVERFLOW FAILS.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/health/home_tiles.dart';
import 'package:botler/features/health/review_screen.dart';
import 'package:botler/features/health/session_screen.dart';
import 'package:botler/features/health/sleep_screen.dart';
import 'package:botler/features/health/train_screen.dart';
import 'package:botler/features/health/week_plan_screen.dart';
import 'package:botler/features/health/weight_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/food_camera.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:botler/ui/markdown_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// -- CONSTANTS -- //

const Map<String, Object?> _set = <String, Object?>{
  'position': 0,
  'reps': null,
  'seconds': null,
  'done': false,
};

const Map<String, Object?> _session = <String, Object?>{
  'id': 's1',
  'title': 'Home strength',
  'kind': 'strength',
  'run': null,
  'exercises': <Object?>[
    <String, Object?>{
      'movement': 'push',
      'exerciseKey': 'push_incline',
      'name': 'Incline push-ups',
      'how': 'Hands on a sturdy table, body straight.',
      'measure': 'reps',
      'low': 8,
      'high': 12,
      'level': 1,
      'ladder': <Object?>[
        'Wall push-ups',
        'Incline push-ups',
        'Knee push-ups',
        'Push-ups',
      ],
      'aim': 9,
      'sets': <Object?>[_set],
    },
    <String, Object?>{
      'movement': 'core',
      'exerciseKey': 'core_knee',
      'name': 'Knee plank',
      'how': 'Forearms and knees down, body straight.',
      'measure': 'seconds',
      'low': 20,
      'high': 45,
      'level': 0,
      'ladder': <Object?>['Knee plank', 'Plank'],
      'aim': 20,
      'sets': <Object?>[_set],
    },
  ],
};

// -- FUNCTIONS -- //

ApiClient _api(Map<String, Object?> results, List<(String, Json)> calls) =>
    ApiClient(
      base: 'https://botler.test',
      client: MockClient((http.Request req) async {
        final verb = req.url.pathSegments.last;
        calls.add((verb, decodeJson(req.body)));
        return http.Response(
          jsonEncode(<String, Object?>{
            'result': results[verb] ?? <String, Object?>{},
          }),
          200,
        );
      }),
      token: () async => 'token',
    );

Future<void> _show(WidgetTester tester, Widget home, ApiClient api) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('start')),
        routes: const <RouteBase>[],
      ),
      GoRoute(path: '/screen', builder: (_, _) => home),
      GoRoute(
        path: '/health/:part',
        builder: (_, _) => const Scaffold(body: Text('opened')),
      ),
      GoRoute(
        path: '/health/train/:part',
        builder: (_, _) => const Scaffold(body: Text('opened')),
      ),
    ],
    initialLocation: '/',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiProvider.overrideWithValue(api)],
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  unawaitedPush(router);
  await tester.pumpAndSettle();
}

void unawaitedPush(GoRouter router) {
  // A pushed screen can pop back, as it can in the app
  router.push<void>('/screen').ignore();
}

// -- TESTS -- //

void main() {
  test('plain words from a line of Markdown', () {
    expect(plainFromMarkdown('**Rice** and *beans*'), 'Rice and beans');
    expect(plainFromMarkdown('## Lunch'), 'Lunch');
    expect(plainFromMarkdown('- one\n- two'), 'one\ntwo');
    expect(
      plainFromMarkdown('See [the page](https://a.b) and [[Food]]'),
      'See the page and Food',
    );
    expect(plainFromMarkdown('`code` and ~~old~~'), 'code and old');
    expect(
      plainFromMarkdown('2*3*4 and snake_case_name'),
      '2*3*4 and snake_case_name',
    );
    expect(plainFromMarkdown('5 * 3 * 2'), '5 * 3 * 2');
    expect(plainFromMarkdown('| a |\n|---|\n| b |'), '| a |\n| b |');
  });

  group('the meal review', () {
    const args = <String, Object?>{
      'meal': 'lunch',
      'items': <Json>[
        <String, Object?>{'foodId': 'fil:adobo_chicken', 'grams': 180},
      ],
    };
    const preview = <String, Object?>{
      'items': <Object?>[
        <String, Object?>{
          'name': 'Chicken adobo',
          'grams': 180,
          'kcal': 360,
          'lowKcal': 300,
          'highKcal': 420,
          'sourceKind': 'filipino',
        },
      ],
      'kcal': 360,
      'lowKcal': 300,
      'highKcal': 420,
      'proteinMg': 30000,
      'carbsMg': 2000,
      'fatMg': 20000,
    };

    testWidgets(
      'draws the assistant\'s note as Markdown, with no marks showing',
      (tester) async {
        await _show(
          tester,
          const MealReviewScreen(
            actionId: 'c1',
            args: args,
            note: '**Was it fried?** Oil is *hard* to see.',
          ),
          _api(<String, Object?>{'meal_preview': preview}, <(String, Json)>[]),
        );
        expect(
          find.textContaining('Was it fried?', findRichText: true),
          findsOneWidget,
        );
        expect(find.textContaining('**', findRichText: true), findsNothing);
      },
    );

    testWidgets(
      'offers no correction when there is no photo to look at again',
      (tester) async {
        await _show(
          tester,
          const MealReviewScreen(actionId: 'c1', args: args),
          _api(<String, Object?>{'meal_preview': preview}, <(String, Json)>[]),
        );
        expect(find.text('Not right?'), findsNothing);
      },
    );

    testWidgets(
      'sends the correction and lets the old card go for the new one',
      (tester) async {
        final calls = <(String, Json)>[];
        String? sent;
        await _show(
          tester,
          MealReviewScreen(
            actionId: 'old',
            args: args,
            photo: 'no-such-file.jpg',
            resend: (words) async {
              sent = words;
              return const FoodCameraResult(
                actionId: 'new',
                args: args,
                note: 'Fixed.',
              );
            },
          ),
          _api(<String, Object?>{'meal_preview': preview}, calls),
        );
        final field = find.widgetWithText(TextField, 'What is it really?');
        await tester.scrollUntilVisible(
          field,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(field, 'That is tinola');
        await tester.pump();
        final send = find.text('Ask Botler to fix it');
        await tester.ensureVisible(send);
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(sent, contains('That is tinola'));
        expect(sent, contains('Chicken adobo 180 g'));
        expect(find.text('opened'), findsOneWidget);
        // The old card was declined, at its own address, only after the new one came
        expect(calls.any((c) => c.$1 == 'old'), isTrue);
      },
    );

    testWidgets('keeps the card and says so when Botler finds nothing new', (
      tester,
    ) async {
      final calls = <(String, Json)>[];
      await _show(
        tester,
        MealReviewScreen(
          actionId: 'old',
          args: args,
          photo: 'no-such-file.jpg',
          resend: (_) async => const FoodCameraResult(failure: 'Could not.'),
        ),
        _api(<String, Object?>{'meal_preview': preview}, calls),
      );
      final field = find.widgetWithText(TextField, 'What is it really?');
      await tester.scrollUntilVisible(
        field,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(field, 'That is tinola');
      await tester.pump();
      final send = find.text('Ask Botler to fix it');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Could not.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(calls.any((c) => c.$1 == 'old'), isFalse);
    });
  });

  testWidgets('the home tiles show each part, with data and with none', (
    tester,
  ) async {
    await _show(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: HomeTiles(
            home: <String, Object?>{
              'food': <String, Object?>{
                'eatenKcal': 1210,
                'targetKcal': 1850,
                'leftKcal': 640,
              },
              'weight': <String, Object?>{
                'trendG': 73000,
                'changeG': -1000,
                'points': <Object?>[74000, 73500, 73000],
              },
              'train': <String, Object?>{
                'days': <Object?>[
                  <String, Object?>{'day': '2030-01-07', 'state': 'done'},
                  <String, Object?>{'day': '2030-01-08', 'state': 'today'},
                  <String, Object?>{'day': '2030-01-09', 'state': 'planned'},
                ],
                'next': <String, Object?>{
                  'title': 'Walk',
                  'day': '2030-01-08',
                  'time': '19:15',
                },
                'minutes': 40,
              },
              'sleep': <String, Object?>{
                'last': <String, Object?>{'minutes': 400},
                'nights': <Object?>[420, 400],
              },
              'free': <String, Object?>{'from': '19:00', 'to': '22:00'},
              'proposals': <Object?>[
                <String, Object?>{'id': 'p1', 'kind': 'target'},
              ],
            },
          ),
        ),
      ),
      _api(const <String, Object?>{}, <(String, Json)>[]),
    );
    expect(find.text('About 640 left'), findsOneWidget);
    expect(find.text('73 kg'), findsOneWidget);
    expect(find.text('6 h 40 min'), findsOneWidget);
    expect(find.text('Your weekly check-in is ready'), findsOneWidget);
    expect(find.text('Down 1 kg'), findsOneWidget);
    await tester.tap(find.text('Your weekly check-in is ready'));
    await tester.pumpAndSettle();
    expect(find.text('opened'), findsOneWidget);
  });

  testWidgets('home with nothing logged says what to do, without a number', (
    tester,
  ) async {
    await _show(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: HomeTiles(
            home: <String, Object?>{
              'food': <String, Object?>{'eatenKcal': 0},
              'weight': <String, Object?>{},
              'train': <String, Object?>{},
              'sleep': <String, Object?>{},
            },
          ),
        ),
      ),
      _api(const <String, Object?>{}, <(String, Json)>[]),
    );
    expect(find.text('Add your first weigh-in'), findsOneWidget);
    expect(find.text('Tell Botler how you slept'), findsOneWidget);
  });

  testWidgets('weight asks for a second weigh-in before drawing a line', (
    tester,
  ) async {
    final calls = <(String, Json)>[];
    await _show(
      tester,
      const WeightScreen(),
      _api(<String, Object?>{
        'weight_trend': <String, Object?>{
          'points': <Object?>[
            <String, Object?>{
              'day': '2030-01-07',
              'trendG': 74000,
              'grams': 74000,
            },
          ],
          'trendG': 74000,
        },
        'proposals_list': <Object?>[],
      }, calls),
    );
    expect(find.textContaining('Two weigh-ins draw your line'), findsOneWidget);
  });

  testWidgets('accepting a check-in sends the id and the value shown', (
    tester,
  ) async {
    final calls = <(String, Json)>[];
    await _show(
      tester,
      const WeightScreen(),
      _api(<String, Object?>{
        'weight_trend': <String, Object?>{
          'points': <Object?>[
            <String, Object?>{
              'day': '2030-01-07',
              'trendG': 74000,
              'grams': 74100,
            },
            <String, Object?>{
              'day': '2030-01-08',
              'trendG': 73900,
              'grams': 73800,
            },
          ],
          'trendG': 73900,
          'changeG': -100,
          'scaleG': 73800,
          'goalWeightG': 70000,
          'lowIntake': true,
          'forecast': <String, Object?>{
            'reachOn': null,
            'weeks': null,
            'reason': 'flat',
          },
        },
        'proposals_list': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'kind': 'target',
            'payload': <String, Object?>{
              'toKcal': 1780,
              'fromKcal': 1850,
              'burnKcal': 2180,
            },
          },
        ],
      }, calls),
    );
    expect(find.text('Try 1,780 kcal a day'), findsOneWidget);
    expect(find.textContaining('talk to a doctor'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Your weight from')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Your trend is steady'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final use = find.text('Use 1,780');
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    final sent = calls.lastWhere((c) => c.$1 == 'proposal_answer').$2;
    final args = asJson(sent['args'] ?? sent);
    expect(args['proposalId'], 'p1');
    expect(args['accept'], true);
    expect(args['value'], 1780);
  });

  testWidgets('train shows today, the goals and a move that is needed', (
    tester,
  ) async {
    final calls = <(String, Json)>[];
    await _show(
      tester,
      const TrainScreen(),
      _api(<String, Object?>{
        'train_get': <String, Object?>{
          'days': <Object?>[
            <String, Object?>{'day': '2030-01-07', 'state': 'done'},
            <String, Object?>{'day': '2030-01-08', 'state': 'today'},
          ],
          'todayPlanned': <String, Object?>{
            'id': 'w1',
            'title': 'Walk',
            'kind': 'walk',
            'time': '19:15',
            'minutes': 30,
          },
          'minutes': 70,
          'minutesGoal': 150,
          'strengthDays': 2,
          'strengthGoal': 2,
          'needsMove': <Object?>[
            <String, Object?>{
              'id': 'w2',
              'title': 'Home strength',
              'day': '2030-01-12',
              'suggestion': '16:00',
            },
          ],
          'programs': <Object?>[],
          'recent': <Object?>[],
        },
        'programs_list': <String, Object?>{
          'templates': <Object?>[
            <String, Object?>{
              'key': 'walk_to_run',
              'name': 'Walk to run',
              'line': 'Three times a week.',
            },
          ],
          'readiness': <Object?>['Has a doctor told you to avoid exercise?'],
        },
      }, calls),
    );
    expect(find.text('Walk, 30 minutes'), findsOneWidget);
    expect(find.text('70 of 150'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.textContaining('needs a move'), findsOneWidget);
    final move = find.textContaining('Move to');
    await tester.ensureVisible(move);
    await tester.tap(move);
    await tester.pumpAndSettle();
    final sent = calls.lastWhere((c) => c.$1 == 'workout_move').$2;
    final args = asJson(sent['args'] ?? sent);
    expect(args['time'], '16:00');
  });

  testWidgets('a session logs a set and offers an easier version', (
    tester,
  ) async {
    final calls = <(String, Json)>[];
    await _show(
      tester,
      const SessionScreen(),
      _api(<String, Object?>{
        'workout_start': _session,
        'workout_set_log': _session,
      }, calls),
    );
    expect(find.text('Incline push-ups'), findsWidgets);
    expect(find.text('Exercise 1 of 2'), findsOneWidget);
    expect(
      find.textContaining('knee push-ups', findRichText: true),
      findsNothing,
    );
    expect(find.textContaining('If something hurts'), findsOneWidget);
    await tester.tap(find.text('Finish set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(seconds: 1));
    final sent = calls.lastWhere((c) => c.$1 == 'workout_set_log').$2;
    final args = asJson(sent['args'] ?? sent);
    expect(args['exerciseKey'], 'push_incline');
    expect(args['reps'], 9);
    expect(find.textContaining('Rest, '), findsOneWidget);
    await tester.tap(find.text('Swap'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Make it easier'), findsOneWidget);
    expect(find.text('Make it harder'), findsOneWidget);
    // Closing the screen stops the rest clock
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'next week writes nothing until accepted, and says what did not fit',
    (tester) async {
      final calls = <(String, Json)>[];
      await _show(
        tester,
        const WeekPlanScreen(),
        _api(<String, Object?>{
          'proposals_list': <Object?>[],
          'week_propose': <String, Object?>{
            'proposalId': 'p9',
            'monday': '2030-01-07',
            'movingMinutes': 175,
            'strengthDays': 3,
            'placed': <Object?>[
              <String, Object?>{
                'day': '2030-01-07',
                'title': 'Home strength',
                'time': '19:30',
                'minutes': 20,
              },
            ],
            'unplaced': <Object?>[
              <String, Object?>{'title': 'Walk'},
            ],
          },
        }, calls),
      );
      expect(find.text('175'), findsOneWidget);
      expect(find.text('Home strength'), findsOneWidget);
      expect(find.text('No free time held: Walk'), findsOneWidget);
      expect(calls.where((c) => c.$1 == 'proposal_answer'), isEmpty);
      await tester.tap(find.text('Accept this week'));
      await tester.pumpAndSettle();
      final sent = calls.lastWhere((c) => c.$1 == 'proposal_answer').$2;
      expect(asJson(sent['args'] ?? sent)['proposalId'], 'p9');
    },
  );

  testWidgets(
    'sleep has the night, the chart, wind down and a pattern, and no score',
    (tester) async {
      await _show(
        tester,
        const SleepScreen(),
        _api(<String, Object?>{
          'sleep_summary': <String, Object?>{
            'last': <String, Object?>{
              'id': 'e1',
              'minutes': 400,
              'startsAt': '2030-01-07T15:10:00.000Z',
              'endsAt': '2030-01-07T21:50:00.000Z',
              'byAgent': true,
            },
            'nights': <Object?>[
              <String, Object?>{
                'day': '2030-01-08',
                'startsAt': '2030-01-07T15:10:00.000Z',
                'endsAt': '2030-01-07T21:50:00.000Z',
              },
            ],
            'averageMinutes': 418,
            'bedtimeSpreadMinutes': 60,
            'pattern': <String, Object?>{'shortNightExtraKcal': 300},
            'windDownOn': true,
            'windDownTonight': <String, Object?>{
              'time': '22:00',
              'firstAt': '07:00',
            },
          },
        }, <(String, Json)>[]),
      );
      expect(find.text('6 h 40 min'), findsOneWidget);
      expect(find.text('About 6 h 58 min'), findsOneWidget);
      expect(find.textContaining('Wind down by'), findsOneWidget);
      expect(
        find.textContaining('It may not be the only reason'),
        findsOneWidget,
      );
      expect(find.text('Undo'), findsOneWidget);
      expect(find.textContaining('Score'), findsNothing);
    },
  );
}
