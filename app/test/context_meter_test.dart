// THE CONTEXT METER: THE FIGURE (PERCENT, LEVEL), HOW THE CHAT STATE TAKES IT FROM THE STREAM AND FROM A RESTORE, THE RING (HIDDEN UNTIL THERE IS A FIGURE),
// THE SHEET AND "SUMMARIZE NOW" IN EVERY STATE, IN LIGHT AND IN DARK.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/features/chat/context_info.dart';
import 'package:botler/features/chat/context_meter.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

/// A chat whose state is fixed, and whose refresh answers from a list (one answer per call), for the sheet.
class FakeChat extends ChatNotifier {
  FakeChat(this.fixed, [this.refreshes = const <ContextInfo?>[]]);

  final ChatState fixed;
  final List<ContextInfo?> refreshes;
  int refreshed = 0;

  @override
  ChatState build() => fixed;

  @override
  Future<ContextInfo?> refreshContext() async {
    final i = refreshed++;
    final now = i < refreshes.length ? refreshes[i] : refreshes.lastOrNull;
    if (now != null) {
      state = ChatState(chatId: fixed.chatId, context: now);
    }
    return now ?? fixed.context;
  }
}

/// A server for the verbs of the meter, and the chat stream fed by hand.
class MeterServer {
  Json compact = <String, Object?>{'queued': true};
  bool compactFails = false;
  final List<(String, Json)> calls = <(String, Json)>[];
  Json history = <String, Object?>{'turns': <Object?>[]};
  final List<StreamController<List<int>>> streams =
      <StreamController<List<int>>>[];

  MockClient get client => MockClient.streaming((req, body) async {
    final text = await http.ByteStream(body).bytesToString();
    final verb = req.url.path.contains('/do/')
        ? req.url.pathSegments.last
        : null;
    http.StreamedResponse reply(Object? result, [int status = 200]) =>
        http.StreamedResponse(
          Stream<List<int>>.value(
            utf8.encode(jsonEncode(<String, Object?>{'result': result})),
          ),
          status,
        );
    if (verb != null) {
      calls.add((verb, text.isEmpty ? <String, Object?>{} : decodeJson(text)));
      if (verb == 'chat_usage') {
        return reply(<String, Object?>{'used': 1520000, 'cap': 8000000});
      }
      if (verb == 'chat_compact') {
        if (compactFails) {
          return http.StreamedResponse(
            Stream<List<int>>.value(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'error': <String, Object?>{
                    'code': 'INTERNAL',
                    'message': 'Something went wrong.',
                  },
                }),
              ),
            ),
            500,
          );
        }
        return reply(compact);
      }
      if (verb == 'chat_history') return reply(history);
      return reply(<String, Object?>{});
    }
    final controller = StreamController<List<int>>();
    streams.add(controller);
    return http.StreamedResponse(controller.stream, 200);
  });

  void emit(Json event) =>
      streams.last.add(utf8.encode('data: ${jsonEncode(event)}\n\n'));
}

// -- FUNCTIONS -- //

Future<ProviderContainer> containerFor(MeterServer s) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: s.client,
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> settle([int ms = 0]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Json ev(String type, [Map<String, Object?> more = const <String, Object?>{}]) =>
    <String, Object?>{'type': type, ...more};

Widget app(
  MeterServer s,
  ChatState state, {
  Brightness mode = Brightness.light,
  List<ContextInfo?> refreshes = const <ContextInfo?>[],
}) => ProviderScope(
  overrides: [
    chatProvider.overrideWith(() => FakeChat(state, refreshes)),
    apiProvider.overrideWithValue(
      ApiClient(
        base: 'https://botler.test',
        token: () async => 'tok',
        client: s.client,
      ),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildTheme(mode),
    home: const Scaffold(body: Center(child: ContextRingButton())),
  ),
);

ChatState chatWith(int tokens, {DateTime? summarizedAt}) => ChatState(
  chatId: 'chat-1',
  context: ContextInfo(
    tokens: tokens,
    window: 1000000,
    summarizedAt: summarizedAt,
  ),
);

void main() {
  group('the figure', () {
    test('is a whole percent, never 0 once something is used', () {
      const window = 1000000;
      expect(const ContextInfo(tokens: 82000, window: window).percent, 8);
      expect(const ContextInfo(tokens: 400, window: window).percent, 1);
      expect(const ContextInfo(tokens: 0, window: window).percent, 0);
      expect(const ContextInfo(tokens: 2000000, window: window).percent, 100);
    });

    test('is calm under 70, warning from 70, danger from 90', () {
      ContextLevel at(int t) => ContextInfo(tokens: t, window: 1000000).level;
      expect(at(699999), ContextLevel.calm);
      expect(at(700000), ContextLevel.warning);
      expect(at(899999), ContextLevel.warning);
      expect(at(900000), ContextLevel.danger);
    });

    test('reads from a chat head, and is unknown when the server has none', () {
      expect(
        ContextInfo.fromHead(<String, Object?>{
          'contextTokens': 82000,
          'contextWindow': 1000000,
          'summarizedAt': '2026-11-08T01:14:00.000Z',
        }),
        ContextInfo(
          tokens: 82000,
          window: 1000000,
          summarizedAt: DateTime.utc(2026, 11, 8, 1, 14),
        ),
      );
      expect(
        ContextInfo.fromHead(<String, Object?>{
          'contextTokens': null,
          'contextWindow': 1000000,
        }),
        isNull,
      );
      expect(ContextInfo.fromHead(<String, Object?>{}), isNull);
      expect(
        ContextInfo.fromHead(<String, Object?>{
          'contextTokens': 5,
          'contextWindow': 0,
        }),
        isNull,
      );
    });
  });

  group('the chat state', () {
    test('has no figure before the first answer', () async {
      final c = await containerFor(MeterServer());
      expect(c.read(chatProvider).context, isNull);
    });

    test('follows the live usage events and keeps the final figure', () async {
      final s = MeterServer();
      final c = await containerFor(s);
      final run = c.read(chatProvider.notifier).send('how much is left?');
      await settle();
      s.emit(ev('start'));
      s.emit(
        ev('usage', <String, Object?>{
          'promptTokens': 82000,
          'window': 1000000,
        }),
      );
      await settle(10);
      expect(c.read(chatProvider).context?.tokens, 82000);
      expect(c.read(chatProvider).context?.window, 1000000);
      s.emit(
        ev('usage', <String, Object?>{
          'promptTokens': 90000,
          'window': 1000000,
        }),
      );
      s.emit(
        ev('done', <String, Object?>{
          'reply': 'x',
          'toolsRun': <String>[],
          'context': <String, Object?>{
            'promptTokens': 91000,
            'window': 1000000,
          },
        }),
      );
      await streams(s).close();
      await run;
      expect(c.read(chatProvider).context?.tokens, 91000);
    });

    test('ignores an event that is not a whole size and window', () async {
      final s = MeterServer();
      final c = await containerFor(s);
      final run = c.read(chatProvider.notifier).send('hi');
      await settle();
      s.emit(ev('start'));
      s.emit(ev('usage', <String, Object?>{'promptTokens': 'lots'}));
      s.emit(ev('usage', <String, Object?>{'promptTokens': 5, 'window': 0}));
      await settle(10);
      expect(c.read(chatProvider).context, isNull);
      s.emit(
        ev('done', <String, Object?>{'reply': 'x', 'toolsRun': <String>[]}),
      );
      await streams(s).close();
      await run;
      // A stopped message has no context in its done event: nothing is shown
      expect(c.read(chatProvider).context, isNull);
    });

    test('comes back with the restored chat, summary time included', () async {
      final s = MeterServer()
        ..history = <String, Object?>{
          'chat': <String, Object?>{
            'id': 'chat-1',
            'title': 'Rent',
            'forkedFrom': null,
            'contextTokens': 20000,
            'contextWindow': 1000000,
            'summarizedAt': '2026-11-08T01:14:00.000Z',
          },
          'turns': <Object?>[],
        };
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).restore();
      final info = c.read(chatProvider).context;
      expect(info?.tokens, 20000);
      expect(info?.summarizedAt, DateTime.utc(2026, 11, 8, 1, 14));
    });

    test('stays unknown for a chat the server has no figure for', () async {
      final s = MeterServer()
        ..history = <String, Object?>{
          'chat': <String, Object?>{
            'id': 'chat-2',
            'title': null,
            'forkedFrom': null,
            'contextTokens': null,
            'contextWindow': 1000000,
            'summarizedAt': null,
          },
          'turns': <Object?>[],
        };
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).restore();
      expect(c.read(chatProvider).context, isNull);
    });
  });

  group('the ring', () {
    testWidgets('is not there until the chat has a figure', (tester) async {
      await tester.pumpWidget(app(MeterServer(), const ChatState()));
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('says how full it is, in a 48 dp target', (tester) async {
      await tester.pumpWidget(app(MeterServer(), chatWith(82000)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byTooltip('Context 8 percent full'), findsOneWidget);
      final size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('the sheet', () {
    for (final mode in Brightness.values) {
      testWidgets('shows the figure, the month and the button (${mode.name})', (
        tester,
      ) async {
        final s = MeterServer();
        await tester.pumpWidget(app(s, chatWith(82000), mode: mode));
        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();
        expect(find.text('8 percent full'), findsOneWidget);
        expect(find.text('Used 82,000 of 1,000,000 tokens'), findsOneWidget);
        expect(find.text('At the last answer'), findsOneWidget);
        expect(find.text('Not yet'), findsOneWidget);
        expect(find.text('19 percent of the monthly limit'), findsOneWidget);
        expect(find.text('Summarize now'), findsOneWidget);
        // Plenty of room: no callout
        expect(find.textContaining('Getting full'), findsNothing);
        expect(find.textContaining('Almost full'), findsNothing);
      });
    }

    testWidgets('has a quiet callout from 70 percent', (tester) async {
      await tester.pumpWidget(app(MeterServer(), chatWith(720000)));
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('Getting full'), findsOneWidget);
      expect(find.textContaining('Almost full'), findsNothing);
    });

    testWidgets('has a stronger one from 90 percent', (tester) async {
      await tester.pumpWidget(app(MeterServer(), chatWith(930000)));
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('Almost full'), findsOneWidget);
      expect(find.textContaining('Getting full'), findsNothing);
    });

    testWidgets('summarizes: working, then the new summary time', (
      tester,
    ) async {
      final s = MeterServer();
      final after = DateTime.utc(2026, 11, 8, 1, 14);
      await tester.pumpWidget(
        app(
          s,
          chatWith(82000),
          refreshes: <ContextInfo?>[
            // The first read still shows no new summary, the second does
            const ContextInfo(tokens: 82000, window: 1000000),
            ContextInfo(tokens: 82000, window: 1000000, summarizedAt: after),
          ],
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Summarize now'));
      await tester.pump();
      expect(find.text('Summarizing'), findsOneWidget);
      // The button is off while it works
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Summarized. The ring updates with your next message.'),
        findsOneWidget,
      );
      expect(find.text('Not yet'), findsNothing);
      expect(s.calls.where((c) => c.$1 == 'chat_compact'), hasLength(1));
      expect(
        s.calls.firstWhere((c) => c.$1 == 'chat_compact').$2['chatId'],
        'chat-1',
      );
    });

    testWidgets(
      'says why when the chat is too short, and turns the button off',
      (tester) async {
        final s = MeterServer()
          ..compact = <String, Object?>{'queued': false, 'reason': 'short'};
        await tester.pumpWidget(app(s, chatWith(3000)));
        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Summarize now'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Too short to summarize yet'),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'says so when it cannot summarize, and the button works again',
      (tester) async {
        final s = MeterServer()..compactFails = true;
        await tester.pumpWidget(app(s, chatWith(82000)));
        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Summarize now'));
        await tester.pumpAndSettle();
        expect(find.text('Could not summarize. Try again.'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );
      },
    );
  });
}

/// The chat stream the test feeds, to close it when the message is over.
StreamController<List<int>> streams(MeterServer s) => s.streams.last;
