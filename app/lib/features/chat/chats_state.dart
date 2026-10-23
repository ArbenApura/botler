// THE LIST OF CONVERSATIONS AND WHAT THE PERSON DOES TO THEM (RENAME, PIN, ARCHIVE, SEARCH). EVERY CALL NEEDS A CONNECTION: NOTHING CHANGES ON SCREEN
// UNTIL THE SERVER HAS DONE IT, AND A FAILURE LEAVES THE LIST AS IT WAS. THE SERVER KEEPS EVERY CHAT: ARCHIVING ONLY HIDES IT FROM THE MAIN LIST.

// -- DEP-MODULES -- //
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/manila.dart';
import '../../state/providers.dart';

// -- TYPES -- //

/// One conversation as the list shows it.
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.title,
    required this.preview,
    required this.lastActive,
    required this.turns,
    required this.pinned,
    required this.archived,
    required this.forked,
  });

  factory ChatSummary.fromJson(Json j) => ChatSummary(
    id: str(j['id']),
    title: j['title'] is String ? str(j['title']) : null,
    preview: str(j['preview']),
    lastActive:
        DateTime.tryParse(str(j['lastActiveAt'])) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    turns: j['turns'] is num ? (j['turns'] as num).toInt() : 0,
    pinned: j['pinned'] == true,
    archived: j['archived'] == true,
    forked: j['forkedFromChatId'] is String,
  );

  final String id;

  /// The name the person gave it, or the start of the first message. Null for a chat nothing was said in.
  final String? title;
  final String preview;
  final DateTime lastActive;
  final int turns;
  final bool pinned;
  final bool archived;

  /// It started as a branch of another chat.
  final bool forked;
}

/// Where a chat sits in the list, from the newest to the oldest.
enum ChatGroup { pinned, today, yesterday, week, older }

// -- FUNCTIONS -- //

/// Which group a chat belongs to, by Manila calendar days (a day is a Manila date). [now] is for tests.
ChatGroup groupOf(ChatSummary c, {DateTime? now}) =>
    c.pinned ? ChatGroup.pinned : timeGroupOf(c.lastActive, now: now);

/// The group of a moment alone, ignoring pins.
ChatGroup timeGroupOf(DateTime lastActive, {DateTime? now}) {
  final today = manilaToday(now);
  final day = manilaToday(lastActive);
  if (day == today) return ChatGroup.today;
  if (day == addDaysTo(today, -1)) return ChatGroup.yesterday;
  // Previous 7 days: from six days before yesterday on
  if (day.compareTo(addDaysTo(today, -7)) >= 0) return ChatGroup.week;
  return ChatGroup.older;
}

List<ChatSummary> _read(Json answer) => <ChatSummary>[
  for (final c in asJsonList(answer['chats'])) ChatSummary.fromJson(c),
];

// -- PROVIDERS -- //

/// The main list: the chats that are not archived, newest first. Reloaded whenever it is invalidated.
final FutureProvider<List<ChatSummary>> chatListProvider =
    FutureProvider.autoDispose<List<ChatSummary>>((ref) async {
      final answer = await ref.read(apiProvider).verbJson('chat_list');
      return _read(answer);
    });

/// The archive, on its own.
final FutureProvider<List<ChatSummary>> archivedChatsProvider =
    FutureProvider.autoDispose<List<ChatSummary>>((ref) async {
      final answer = await ref.read(apiProvider).verbJson(
        'chat_list',
        <String, Object?>{'archived': true},
      );
      return _read(answer);
    });

/// A search over titles and messages. The words are typed by the person and go to the server only: never into a log.
final chatSearchProvider = FutureProvider.autoDispose
    .family<List<ChatSummary>, String>((ref, words) async {
      final answer = await ref.read(apiProvider).verbJson(
        'chat_list',
        <String, Object?>{'search': words},
      );
      return _read(answer);
    });

/// What the person can do to one conversation. Each call is one action with one request id, so a repeat of it does nothing twice.
class ChatActions {
  const ChatActions(this._ref);

  final Ref _ref;

  Future<void> _done(String verb, Json args) async {
    await _ref.read(apiProvider).verb(verb, args);
    _ref
      ..invalidate(chatListProvider)
      ..invalidate(archivedChatsProvider)
      ..invalidate(chatSearchProvider);
  }

  Future<void> rename(String chatId, String title) => _done(
    'chat_rename',
    <String, Object?>{'chatId': chatId, 'title': title.trim()},
  );

  Future<void> pin(String chatId, {required bool pinned}) =>
      _done('chat_pin', <String, Object?>{'chatId': chatId, 'pinned': pinned});

  Future<void> archive(String chatId, {required bool archived}) => _done(
    'chat_archive',
    <String, Object?>{'chatId': chatId, 'archived': archived},
  );
}

final Provider<ChatActions> chatActionsProvider = Provider<ChatActions>(
  ChatActions.new,
);
