// HEALTH: THE UNITS AT THE DISPLAY EDGE, THE HOME SCREEN WITH SETUP NOT DONE, AND SETUP SAVING WHAT WAS TYPED IN WHOLE UNITS.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/health_units.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/health/availability_screen.dart';
import 'package:botler/features/health/barcode_screen.dart';
import 'package:botler/features/health/review_screen.dart';
import 'package:botler/features/health/health_home_screen.dart';
import 'package:botler/features/health/food_sheets.dart';
import 'package:botler/features/health/health_setup_screen.dart';
import 'package:botler/features/health/today_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// -- FUNCTIONS -- //

/// A client that answers each verb from [results] and records every call.
ApiClient fakeApi(Map<String, Object?> results, List<(String, Json)> calls) =>
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

Widget host(Widget home, ApiClient api) {
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/health/setup',
        builder: (_, _) => const Scaffold(body: Text('setup opened')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [apiProvider.overrideWithValue(api)],
    child: MaterialApp.router(
      theme: buildTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      routerConfig: router,
    ),
  );
}

// -- TESTS -- //

void main() {
  group('units', () {
    test('read what a person types without a float', () {
      expect(gramsFromKgText('74'), 74000);
      expect(gramsFromKgText('74.2'), 74200);
      expect(gramsFromKgText('74,25'), 74250);
      expect(gramsFromKgText('heavy'), isNull);
      expect(mmFromCmText('168'), 1680);
    });

    test('write what a person sees', () {
      expect(kgText(74200), '74.2');
      expect(kgText(74000), '74');
      expect(kcalText(1850), '1,850');
      expect(kcalText(640), '640');
      expect(gramsFromMgText(118400), '118');
      expect(durationText(400), '6 h 40 min');
      expect(durationText(30), '30 min');
      expect(durationText(120), '2 h');
    });
  });

  testWidgets('my week shows work days and saves them', (tester) async {
    final calls = <(String, Json)>[];
    final api = fakeApi(<String, Object?>{
      'availability_get': <String, Object?>{
        'days': <Json>[
          for (var w = 0; w < 7; w++)
            <String, Object?>{
              'weekday': w,
              'blocks': (w >= 1 && w <= 5)
                  ? <Json>[
                      <String, Object?>{
                        'start': '07:00',
                        'end': '18:30',
                        'kind': 'work',
                      },
                    ]
                  : <Json>[],
            },
        ],
        'changes': <Json>[],
        'awakeFrom': '06:00',
        'awakeTo': '22:00',
        'travelMinutes': 30,
      },
    }, calls);
    tester.view.physicalSize = const Size(1200, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const AvailabilityScreen(), api));
    await tester.pumpAndSettle();
    expect(find.text('Saturday'), findsOneWidget);
    expect(find.text('Free all day'), findsNWidgets(2));
    expect(find.text('Save my week'), findsOneWidget);
    await tester.tap(find.text('Save my week'));
    await tester.pumpAndSettle();
    final saved = calls.firstWhere((c) => c.$1 == 'availability_set').$2;
    expect(asJsonList(saved['days']), hasLength(7));
  });

  group('today', () {
    final foods = <String, Object?>{
      'day': '2026-11-26',
      'complete': false,
      'targetKcal': 1850,
      'totals': <String, Object?>{
        'kcal': 1210,
        'foods': 2,
        'core': <String, Object?>{
          'proteinMg': <String, Object?>{'mg': 60000, 'unknownFoods': 0},
          'sodiumMg': <String, Object?>{'mg': 0, 'unknownFoods': 2},
          'sugarMg': <String, Object?>{'mg': 5000, 'unknownFoods': 1},
        },
        'nutrients': <Json>[
          <String, Object?>{
            'code': 'vitamin_b12',
            'label': 'Vitamin B12',
            'unit': 'µg',
            'ng': 40,
            'knownFoods': 1,
          },
        ],
      },
      'entries': <Json>[
        <String, Object?>{
          'id': 'e1',
          'meal': 'lunch',
          'name': 'Chicken adobo',
          'kcal': 380,
          'grams': 180,
          'byAgent': true,
        },
      ],
    };

    testWidgets('shows what is left, the meal, and who logged it', (
      tester,
    ) async {
      final calls = <(String, Json)>[];
      final api = fakeApi(<String, Object?>{'food_day': foods}, calls);
      tester.view.physicalSize = const Size(1200, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const TodayScreen(), api));
      await tester.pumpAndSettle();
      expect(find.text('640'), findsOneWidget);
      expect(find.text('kcal left'), findsOneWidget);
      expect(find.text('1,210 eaten of 1,850'), findsOneWidget);
      expect(find.text('Chicken adobo'), findsOneWidget);
      expect(find.text('By Botler'), findsOneWidget);
      expect(find.text('Log food'), findsOneWidget);
    });

    testWidgets('going over reads plainly, with no warning colour', (
      tester,
    ) async {
      final over = Map<String, Object?>.of(foods)..['targetKcal'] = 1000;
      final api = fakeApi(<String, Object?>{
        'food_day': over,
      }, <(String, Json)>[]);
      tester.view.physicalSize = const Size(1200, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const TodayScreen(), api));
      await tester.pumpAndSettle();
      expect(find.text('Over by about'), findsOneWidget);
      expect(find.text('210'), findsOneWidget);
    });

    testWidgets('nutrients show unknown, never zero', (tester) async {
      final api = fakeApi(<String, Object?>{
        'food_day': foods,
      }, <(String, Json)>[]);
      tester.view.physicalSize = const Size(1200, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const NutrientsScreen(), api));
      await tester.pumpAndSettle();
      expect(find.text('Unknown'), findsWidgets);
      expect(find.text('Known for 1 of 2 foods'), findsWidgets);
      expect(find.text('0.04 µg'), findsOneWidget);
    });
  });

  group('the review', () {
    Json preview(int grams) => <String, Object?>{
      'items': <Json>[
        <String, Object?>{
          'name': 'Chicken adobo',
          'grams': grams,
          'kcal': grams * 2,
          'lowKcal': grams,
          'highKcal': grams * 3,
          'proteinMg': 38000,
          'sourceKind': 'filipino',
        },
        <String, Object?>{
          'name': 'Greens',
          'grams': 100,
          'kcal': 90,
          'lowKcal': 60,
          'highKcal': 120,
          'sourceKind': 'estimate',
        },
      ],
      'kcal': 450,
      'lowKcal': 300,
      'highKcal': 600,
      'proteinMg': 46000,
      'carbsMg': 62000,
      'fatMg': 33000,
    };

    Widget review(ApiClient api) => host(
      const MealReviewScreen(
        actionId: 'card-1',
        args: <String, Object?>{
          'meal': 'lunch',
          'items': <Json>[
            <String, Object?>{'foodId': 'fil:adobo_chicken', 'grams': 180},
            <String, Object?>{
              'estimate': <String, Object?>{
                'name': 'Greens',
                'proteinG': 3,
                'carbsG': 5,
                'fatG': 6,
              },
              'grams': 100,
            },
          ],
        },
      ),
      api,
    );

    testWidgets('shows server numbers and where they came from', (
      tester,
    ) async {
      final calls = <(String, Json)>[];
      final api = fakeApi(<String, Object?>{
        'meal_preview': preview(180),
      }, calls);
      tester.view.physicalSize = const Size(1200, 3400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(review(api));
      await tester.pumpAndSettle();
      expect(find.text('About 450 kcal'), findsOneWidget);
      expect(find.text('Could be 300 to 600'), findsOneWidget);
      expect(find.text('Chicken adobo'), findsOneWidget);
      expect(find.text('Filipino list'), findsOneWidget);
      expect(find.text('AI estimate'), findsOneWidget);
      expect(find.text('Save meal'), findsOneWidget);
      expect(calls.where((c) => c.$1 == 'meal_preview'), isNotEmpty);
    });

    testWidgets('sends the corrected amounts with the approval', (
      tester,
    ) async {
      final calls = <(String, Json)>[];
      final api = fakeApi(<String, Object?>{
        'meal_preview': preview(180),
        'card-1': <String, Object?>{},
      }, calls);
      tester.view.physicalSize = const Size(1200, 3400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(review(api));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      await tester.tap(find.text('Save meal'));
      await tester.pumpAndSettle();
      final sent = calls.lastWhere((c) => c.$1 == 'card-1').$2;
      expect(sent['decision'], 'approve');
      final edited = asJson(sent['editedArgs']);
      expect(asJsonList(edited['items']).first['grams'], 190);
    });

    testWidgets('leaving it untouched sends no edits, and discard rejects', (
      tester,
    ) async {
      final calls = <(String, Json)>[];
      final api = fakeApi(<String, Object?>{
        'meal_preview': preview(180),
      }, calls);
      tester.view.physicalSize = const Size(1200, 3400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(review(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      final sent = calls.lastWhere((c) => c.$1 == 'card-1').$2;
      expect(sent['decision'], 'reject');
      expect(sent.containsKey('editedArgs'), isFalse);
    });

    testWidgets('a not found barcode goes to the label', (tester) async {
      final api = fakeApi(<String, Object?>{
        'barcode_lookup': <String, Object?>{'found': false},
      }, <(String, Json)>[]);
      await tester.pumpWidget(
        host(const BarcodeResultScreen(code: '4801234567890'), api),
      );
      await tester.pumpAndSettle();
      expect(find.text('Read the label'), findsOneWidget);
    });

    testWidgets('a found barcode shows its numbers and its credit', (
      tester,
    ) async {
      final calls = <(String, Json)>[];
      final api = fakeApi(<String, Object?>{
        'barcode_lookup': <String, Object?>{
          'found': true,
          'id': 'barcode:4801234567890',
          'source': 'off',
          'name': 'Instant pancit canton',
          'servingG': 60,
          'facts': <String, Object?>{'kcal': 483, 'proteinMg': 10000},
        },
      }, calls);
      tester.view.physicalSize = const Size(1200, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(const BarcodeResultScreen(code: '4801234567890'), api),
      );
      await tester.pumpAndSettle();
      expect(find.text('Instant pancit canton'), findsOneWidget);
      expect(find.text('290 kcal'), findsOneWidget);
      expect(find.textContaining('Open Food Facts'), findsOneWidget);
      await tester.tap(find.text('Add to today'));
      await tester.pumpAndSettle();
      final sent = calls.lastWhere((c) => c.$1 == 'meal_log').$2;
      expect(asJsonList(sent['items']).first['grams'], 60);
    });
  });

  test('tiny amounts keep their digits', () {
    expect(microText(40, 'µg'), '0.04 µg');
    expect(microText(2400, 'µg'), '2.4 µg');
    expect(microText(7400000, 'mg'), '7.4 mg');
  });

  testWidgets('the home screen offers setup until it is done', (tester) async {
    final calls = <(String, Json)>[];
    final api = fakeApi(<String, Object?>{
      'health_home': <String, Object?>{'setupDone': false},
    }, calls);
    await tester.pumpWidget(host(const HealthHomeScreen(), api));
    await tester.pumpAndSettle();
    expect(find.text('Finish setting up Health'), findsOneWidget);
    expect(find.text('Log food'), findsOneWidget);
    await tester.tap(find.text('Finish setting up Health'));
    await tester.pumpAndSettle();
    expect(find.text('setup opened'), findsOneWidget);
  });

  testWidgets('setup saves the facts in whole units and asks for a preview', (
    tester,
  ) async {
    final calls = <(String, Json)>[];
    final api = fakeApi(<String, Object?>{
      'health_get': <String, Object?>{
        'profile': <String, Object?>{'sex': 'skip', 'activity': 'sitting'},
        'goal': <String, Object?>{'kind': 'track', 'paceBp': 50},
      },
      'health_goal_preview': <String, Object?>{
        'targetKcal': 1850,
        'gramsPerWeek': 370,
        'reachOn': '2027-01-28',
      },
    }, calls);
    await tester.pumpWidget(host(const HealthSetupScreen(), api));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Height in centimetres'),
      '168',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Weight today in kilograms'),
      '74.5',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final saved = calls.firstWhere((c) => c.$1 == 'health_profile_save').$2;
    expect(saved['heightMm'], 1680);
    expect(saved['weightG'], 74500);
    expect(find.text('What do you want to do?'), findsOneWidget);
    expect(find.text('About 1,850 kcal a day'), findsOneWidget);
  });
}
