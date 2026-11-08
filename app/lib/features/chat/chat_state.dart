// THE CHAT: WHAT IS ON THE SCREEN (THE PERSON'S MESSAGES, THE ASSISTANT'S PLAIN TEXT, ITS THINKING, WHAT IT DID, CARDS TO APPROVE) AND HOW A MESSAGE IS SENT.
// A message has an id the phone chooses. If the connection drops, the same id is sent again and the server replays the stored answer, so the assistant
// never does the same thing twice. An expense typed with no connection is kept in the outbox and sent later with its own request id.
// While the assistant works the screen shows it live: a status (waiting, thinking, writing, using a tool), its thinking as it arrives, a row for each
// tool that is running, and the answer growing. The words and the thinking arrive in tiny pieces, so they are gathered and drawn about 25 times a second.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/chat_photos.dart';
import '../../core/clock.dart' show uses24Hour;
import '../../core/json.dart';
import '../../core/photo_budget.dart';
import '../../core/photo_prep.dart';
import '../../core/photo_upload.dart' show uploadTotalBytes;
import '../../core/reminders.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../settings/photo_mode_row.dart' show pictureNoticeKey;
import 'chats_state.dart';
import 'context_info.dart';
import 'tool_label.dart';

// -- TYPES -- //

enum CardState { waiting, approved, declined, failed, expired }

/// What the assistant is doing right now, for the status row under the conversation.
enum TurnPhase { idle, waiting, thinking, writing, tool }

sealed class ChatItem {
  const ChatItem(this.id);

  final int id;
}

final class UserItem extends ChatItem {
  const UserItem(
    super.id,
    this.text, {
    this.photos = 0,
    this.photoPaths = const <String>[],
    this.turnId,
    this.preparing = false,
  });

  final String text;

  /// How many photos' text went along with it.
  final int photos;

  /// The pictures of those photos, kept on this phone, when they are still there. Empty for a message from before this phone kept them.
  final List<String> photoPaths;

  /// The server's id for this message, known once the server has accepted it. Branching and editing start from it.
  final String? turnId;

  /// The photos are still being made ready: their tiles pulse, and the request starts the moment they are.
  final bool preparing;

  UserItem withTurn(String turn) => UserItem(
    id,
    text,
    photos: photos,
    photoPaths: photoPaths,
    turnId: turn,
    preparing: preparing,
  );

  UserItem withPhotoPaths(List<String> paths) => UserItem(
    id,
    text,
    photos: photos,
    photoPaths: paths,
    turnId: turnId,
    preparing: preparing,
  );

  /// The photos are ready (or left out): the words and the count of photos the message finally goes with.
  UserItem prepared(String words, int count) => UserItem(
    id,
    words,
    photos: count,
    photoPaths: photoPaths,
    turnId: turnId,
  );
}

final class AgentItem extends ChatItem {
  const AgentItem(super.id, this.text, {this.streaming = false, this.turnId});

  final String text;
  final bool streaming;

  /// The message this answers, so the person can branch from it.
  final String? turnId;

  AgentItem grow(String more) =>
      AgentItem(id, text + more, streaming: true, turnId: turnId);
  AgentItem done() => AgentItem(id, text, turnId: turnId);
}

/// What the assistant thought before it answered. Open while it is still thinking; then it folds into one line.
/// This is the model's own words and untrusted: it is drawn as plain text, never as markdown.
final class ThinkingItem extends ChatItem {
  const ThinkingItem(super.id, this.text, {this.open = true, this.seconds = 0});

  final String text;
  final bool open;

  /// How long the thinking took, known once it is closed.
  final int seconds;

  ThinkingItem grow(String more) =>
      ThinkingItem(id, text + more, open: true, seconds: seconds);
  ThinkingItem closed(int seconds) =>
      ThinkingItem(id, text, open: false, seconds: seconds);
}

/// Something the assistant did or looked up. [data] is the verb's answer, shown by a card or chip when it has one.
final class ToolItem extends ChatItem {
  const ToolItem(
    super.id, {
    required this.name,
    required this.status,
    this.message,
    this.data,
    this.resolved = false,
    this.callId,
    this.running = false,
    this.restored = false,
    this.family,
    this.subject,
    this.startedAt,
    this.ms,
    this.live,
  });

  final String name;

  /// The counts of a research call while it runs (null for every other tool, and once the call is done).
  final ResearchLive? live;

  /// What kind of call this is (reading a page, searching the web...) as the server labelled it. Null from an older server.
  final String? family;

  /// What the call is about (a page title, a search, a web host), already checked by the server. Null when it has none.
  final String? subject;

  /// When the call was seen to start on this phone, for the time shown once it is done.
  final DateTime? startedAt;

  /// How long the call took in milliseconds, as the server measured it.
  final int? ms;

  /// ok, error, needs_approval or blocked (while [running] it has no answer yet)
  final String status;
  final String? message;
  final Object? data;

  /// The chip on this item was answered (confirmed, chosen or undone).
  final bool resolved;

  /// The model's id for this call, so the answer finds the row that was running. Missing on messages stored before it existed.
  final String? callId;

  /// The tool has started and has not answered yet.
  final bool running;

  /// Brought back from an earlier session: drawn as a plain read-only line, never with Undo or a chip to answer.
  final bool restored;

  ToolItem answered({Object? data}) => ToolItem(
    id,
    name: name,
    status: status,
    message: message,
    data: data ?? this.data,
    resolved: true,
    callId: callId,
    running: running,
    restored: restored,
    family: family,
    subject: subject,
    startedAt: startedAt,
    ms: ms,
    live: live,
  );

  /// The same running call with newer counts.
  ToolItem withLive(ResearchLive next) => ToolItem(
    id,
    name: name,
    status: status,
    message: message,
    data: data,
    resolved: resolved,
    callId: callId,
    running: running,
    restored: restored,
    family: family,
    subject: subject,
    startedAt: startedAt,
    ms: ms,
    live: next,
  );
}

/// What a running research call has done so far: searches and pages, and the newest sites it reached.
final class ResearchLive {
  const ResearchLive({
    this.searches = 0,
    this.reads = 0,
    this.hosts = const <String>[],
  });

  final int searches;
  final int reads;
  final List<String> hosts;
}

final class CardItem extends ChatItem {
  const CardItem(
    super.id, {
    required this.actionId,
    required this.summary,
    this.state = CardState.waiting,
    this.note,
    this.readOnly = false,
    this.turnId,
    this.verb,
  });

  final String actionId;
  final String summary;
  final CardState state;
  final String? note;

  /// The chat turn the card came from: the phone keeps the photos of that message under it (a card that uses a photo cuts it from there).
  final String? turnId;

  /// Set by the server only for a card the phone has to finish itself (a picture cut from a photo); null for every other card.
  final String? verb;

  /// The card was copied into a branch: it can only be answered in the chat it came from.
  final bool readOnly;

  CardItem with_(CardState s, {String? note}) => CardItem(
    id,
    actionId: actionId,
    summary: summary,
    state: s,
    note: note,
    readOnly: readOnly,
    turnId: turnId,
    verb: verb,
  );
}

/// The card state for a status the server reports (pending, applied, rejected, failed, expired or gone).
CardState cardStateOf(String status) => switch (status) {
  'pending' => CardState.waiting,
  'applied' => CardState.approved,
  'rejected' => CardState.declined,
  'failed' => CardState.failed,
  _ => CardState.expired,
};

/// The model is down or over its cap: the manual expense form is offered.
final class FallbackItem extends ChatItem {
  const FallbackItem(super.id, this.reason);

  final String reason;
}

final class NoticeItem extends ChatItem {
  const NoticeItem(super.id, this.text);

  final String text;
}

/// A quiet line between the conversation brought back from before and the one happening now.
final class DividerItem extends ChatItem {
  const DividerItem() : super(-1);
}

/// Where bringing back the earlier conversation is: not asked yet, on its way, brought back (even when there was nothing), or failed.
/// The empty-chat greeting shows only on [done], so it never flashes while the history is still coming, or offline.
enum RestoreStatus { idle, loading, done, failed }

/// Where a branch came from.
class ForkOrigin {
  const ForkOrigin(this.id, this.title);

  final String id;
  final String? title;
}

/// A message that has been sent from the box but waits for its turn: another message is still being answered. It is not part of the
/// conversation yet (it joins [ChatState.items] only when its own turn starts) and it lives in memory only.
class QueuedMessage {
  QueuedMessage({
    required this.id,
    required this.messageId,
    required this.text,
    this.photoJobs = const <PhotoJob>[],
    this.allowPictures = true,
    this.photoTexts = const <String>[],
    this.photoPaths = const <String>[],
    this.images = const <String>[],
    this.imagePaths,
    this.textPaths,
    this.chatId,
  });

  /// Names the chip on screen.
  final int id;

  /// The id the server knows this message by. It stays the same on every try, so a repeat is answered from storage.
  final String messageId;
  final String text;

  /// The photos still being made ready in the background (the screen's way of sending).
  final List<PhotoJob> photoJobs;

  /// The person said no to pictures at the notice: only the text read from the photos goes.
  final bool allowPictures;

  /// Photos already made ready by the caller (an older way of sending, kept as it was).
  final List<String> photoTexts;
  final List<String> photoPaths;
  final List<String> images;
  final List<String>? imagePaths;
  final List<String>? textPaths;

  /// The chat it was written in. A message never runs in another one.
  String? chatId;

  /// How many photos it carries.
  int get photoCount =>
      photoJobs.isNotEmpty ? photoJobs.length : photoPaths.length;

  /// The staged copies it holds, to delete if it never runs.
  List<String> get copies => <String>[
    for (final j in photoJobs) j.path,
    ...photoPaths,
  ];
}

class ChatState {
  const ChatState({
    this.chatId,
    this.title,
    this.forkedFrom,
    this.restore = RestoreStatus.idle,
    this.restored = const <ChatItem>[],
    this.items = const <ChatItem>[],
    this.busy = false,
    this.phase = TurnPhase.idle,
    this.toolName,
    this.unseen = false,
    this.queue = const <QueuedMessage>[],
    this.queuePaused = false,
    this.context,
  });

  /// How full this chat's context was at its last answer. Null when unknown (a new chat, or one the server has no figure for): the ring is hidden.
  final ContextInfo? context;

  /// The conversation on screen. Null until the server has said which one it is (the first start, or a first message).
  final String? chatId;

  /// Its name, once it has one.
  final String? title;

  /// Set when this chat started as a branch of another.
  final ForkOrigin? forkedFrom;

  /// The earlier conversation brought back from the server. Kept apart from [items] so it can arrive at any moment without
  /// moving anything the live turn counts on.
  final List<ChatItem> restored;
  final List<ChatItem> items;
  final bool busy;
  final TurnPhase phase;
  final RestoreStatus restore;

  /// The tool in use while [phase] is [TurnPhase.tool].
  final String? toolName;

  /// An answer arrived in this chat while another one was on screen, and has not been looked at yet.
  final bool unseen;

  /// The messages waiting for their turn, in the order they were sent. Never part of [items].
  final List<QueuedMessage> queue;

  /// The queue stopped after a Stop or a failed message and waits for the person: Send now, or Clear.
  final bool queuePaused;

  /// Something is being answered, or messages are waiting: the chat cannot be switched, rewound or branched meanwhile.
  bool get working => busy || queue.isNotEmpty;

  ChatState copyWith({
    String? chatId,
    String? title,
    RestoreStatus? restore,
    List<ChatItem>? restored,
    List<ChatItem>? items,
    bool? busy,
    TurnPhase? phase,
    String? toolName,
    bool clearTool = false,
    bool? unseen,
    List<QueuedMessage>? queue,
    bool? queuePaused,
    ContextInfo? context,
  }) => ChatState(
    chatId: chatId ?? this.chatId,
    title: title ?? this.title,
    forkedFrom: forkedFrom,
    restore: restore ?? this.restore,
    restored: restored ?? this.restored,
    items: items ?? this.items,
    busy: busy ?? this.busy,
    phase: phase ?? this.phase,
    toolName: clearTool ? null : (toolName ?? this.toolName),
    unseen: unseen ?? this.unseen,
    queue: queue ?? this.queue,
    queuePaused: queuePaused ?? this.queuePaused,
    context: context ?? this.context,
  );
}

/// How one message's turn ended: whether the server took it, whether it ran clean (answered, not stopped) so the queue may go on, and whether
/// it was cut short by a fresh start (another person signed in, another chat opened) so nothing more is drawn for it.
class _Outcome {
  const _Outcome({
    required this.accepted,
    required this.clean,
    this.stale = false,
  });

  final bool accepted;
  final bool clean;
  final bool stale;

  static const _Outcome dropped = _Outcome(
    accepted: false,
    clean: false,
    stale: true,
  );
}

// -- CONSTANTS -- //

/// The most messages that may wait for their turn, and the most photos on all of them together (each photo is one prepared picture held in memory).
const int maxQueuedMessages = 5;
const int maxQueuedPhotos = 12;

/// How many times a dropped message is sent again, and how long to wait between.
const int _retries = 3;
const Duration _retryWait = Duration(seconds: 2);

/// Waiting for the server's earlier message of the same chat (BUSY_CHAT): pauses of growing length in units (a second), the last one repeated, until
/// about 130 of them have passed, which is past the server's 120 s rule for a stuck turn. Tests make the unit tiny.
const List<int> _busyPauses = <int>[2, 3, 5, 8, 12, 15];
const int _busyCap = 130;
Duration busyWaitUnit = const Duration(seconds: 1);

/// Pieces of the answer and of the thinking are gathered for this long before the screen is drawn again.
const Duration _flushEvery = Duration(milliseconds: 40);

// -- FUNCTIONS -- //

/// The name a chat gets from its first message: one line, cut short (the server does the same).
String? _titleFrom(String text) {
  final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (one.isEmpty) return null;
  return one.length > 60 ? one.substring(0, 60) : one;
}

// A number that is an amount: digits in groups of three with commas, or plain digits, with at most three decimals. Not part of a time (3:30), a
// date (12/05, 2026-10-01) or a longer number (a phone number or an order id).
final RegExp _amountShape = RegExp(
  r'(?<![\d:/.,\-])(\d{1,3}(?:,\d{3})+|\d{1,9})(?:[.,]\d{1,3})?(?![\d:/\-]|[.,]\d)',
);

// What follows a number that makes it something else than money: a clock time, an ordinal, a percent, a size, a count of days or people.
final RegExp _notMoneyAfter = RegExp(
  r'^\s?(am|pm|a\.m|p\.m|st|nd|rd|th|%|x|kg|km|g|mg|ml|l|cm|mm|m|min|mins|minutes?|hrs?|hours?|days?|weeks?|months?|years?|yrs?|pcs|pieces|people|persons?|items?)\b',
  caseSensitive: false,
);

// A currency written before the number (₱90, php 90, usd 5) or after it (90 pesos, 90 php).
final RegExp _currencyBefore = RegExp(
  r'(₱|\$|€|£|¥|\b(php|peso|pesos|piso|usd|eur|gbp|jpy|krw|sgd|aud|cad|cny|hkd|p))\s?$',
  caseSensitive: false,
);
final RegExp _currencyAfter = RegExp(
  r'^\s?(₱|\$|€|£|¥|php\b|pesos?\b|piso\b|usd\b|eur\b|gbp\b|jpy\b|krw\b|sgd\b|aud\b|cad\b|cny\b|hkd\b)',
  caseSensitive: false,
);

/// True when the text has an amount in it: a number shaped like money that is not a time, a date or a count, with either a currency beside it
/// or a word to say what it was for ("lunch 180", "grab 250 pesos", "₱90 coffee"). A bare number, "meeting at 3pm" or "call mom 12/05" is not.
/// Only then may it be kept for later and sent as an expense without the assistant.
bool looksLikeExpense(String text) {
  final hasWord = RegExp(r'[A-Za-zÀ-ÿ]{2,}').hasMatch(text);
  for (final m in _amountShape.allMatches(text)) {
    final after = text.substring(m.end);
    final before = text.substring(0, m.start);
    final currencyBeside =
        _currencyBefore.hasMatch(before) || _currencyAfter.hasMatch(after);
    if (!currencyBeside && _notMoneyAfter.hasMatch(after)) continue;
    if (currencyBeside || hasWord) return true;
  }
  return false;
}

/// One conversation and the turn it is running. Every chat has its own session, so one can keep working while another is on screen
/// (BTL-20261106-1502-b). The [ChatNotifier] below is the door the screens use: it hands each call to the session on screen.
class ChatSession extends Notifier<ChatState> {
  ChatSession(this.key);

  /// Which session this is. Not the chat's id: a session starts before the server has named its chat, and can be shown another chat later.
  final String key;

  int _next = 0;

  // The turn being shown. All of it is reset when a turn starts over or ends.
  int _agentId = -1;
  int _thinkId = -1;
  DateTime? _thinkStart;
  String _pendingText = '';
  String _pendingThought = '';
  Timer? _flushTimer;
  bool _sawDone = false;
  bool _sawError = false;
  bool _stopped = false;
  Completer<void>? _abort;

  // Bringing back the earlier conversation: once per run of the app (and per signed-in person), and never twice for the same turn.
  bool _restoreStarted = false;

  /// Counts fresh starts. An answer that comes back after another person signed in belongs to the old start and is thrown away.
  int _generation = 0;
  final Set<String> _sentIds = <String>{};

  // The message being answered: the server's id for it, and the row on screen it belongs to.
  String? _turnId;
  int _userItemId = -1;

  // Pictures went with the message being sent, so a server that did not use them is told to the person.
  bool _picturesSent = false;

  // The staged copies of the photos of the message being sent, until the server accepts it.
  List<String> _staged = const <String>[];
  // Which of those copies the server counts as its photos: the ones sent as pictures, or the ones whose text was sent. A card that says
  // "photo 2" means the second of these, so the phone files them with the turn
  List<String> _numberedImages = const <String>[];
  List<String> _numberedTexts = const <String>[];

  // A branch is made once per action: asking again after a failure reuses the request id, so no second branch appears.
  final Map<String, String> _forkKeys = <String, String>{};

  /// A branch is being made. A second tap meanwhile does nothing.
  bool _forking = false;

  /// An edit and resend is taking messages out of the open chat. A message cannot be sent meanwhile.
  bool _rewinding = false;

  @override
  ChatState build() {
    ref.onDispose(() {
      _flushTimer?.cancel();
      // Sign-out or a fresh start: messages still waiting are forgotten and their photo copies deleted
      try {
        _dropQueued(state.queue);
      } on Object {
        // The state may already be gone; leftover copies are swept at the next start
      }
      // A message still on its way for the old start is stopped: its socket closes and its answer is never drawn
      final abort = _abort;
      if (abort != null && !abort.isCompleted) abort.complete();
    });
    // A fresh start (the app opening, or another person signing in): nothing from before carries over, whether or not Riverpod
    // keeps this same object
    _restoreStarted = false;
    _generation++;
    _sentIds.clear();
    _resetTurn();
    return const ChatState();
  }

  int _id() => _next++;

  /// The words in the app's language, for text made outside a widget.
  AppLocalizations get _words => wordsFor(ref.read(settingsProvider).language);

  void _add(ChatItem item) =>
      state = state.copyWith(items: <ChatItem>[...state.items, item]);

  /// Changes one item wherever it is: a card that came back from before can still be answered, and then it has to change on screen.
  void _replace(int id, ChatItem Function(ChatItem old) change) {
    state = state.copyWith(
      restored: <ChatItem>[
        for (final i in state.restored) i.id == id ? change(i) : i,
      ],
      items: <ChatItem>[
        for (final i in state.items) i.id == id ? change(i) : i,
      ],
    );
  }

  /// Marks a chip or card as answered.
  void answer(int id, {Object? data}) =>
      _replace(id, (old) => old is ToolItem ? old.answered(data: data) : old);

  void setCard(int id, CardState s, {String? note}) =>
      _replace(id, (old) => old is CardItem ? old.with_(s, note: note) : old);

  /// Runs a call the assistant made to the phone and posts its answer. The photos of this message are handed in by their number.
  Future<void> _runOnPhone(String tool, Json device) async {
    final callId = str(device['callId']);
    if (callId.isEmpty) return;
    try {
      await _runOnPhoneChecked(tool, device, callId);
    } on Object {
      // The chat was closed or signed out while the call was starting: the server's wait ends on its own
    }
  }

  Future<void> _runOnPhoneChecked(
    String tool,
    Json device,
    String callId,
  ) async {
    var photos = const <String>[];
    final turn = _turnId;
    // The person chose "text only" for photos: a script gets none of them either, so no picture can leave through what it prints
    final textOnly = ref.read(settingsProvider).photoMode == 'text';
    if (turn != null && !textOnly) {
      try {
        final store = ref.read(chatPhotoStoreProvider);
        await store.ready();
        photos = store.numberedPhotosOf(turn);
      } on Object {
        // A script that wants a photo is told there is none
      }
    }
    await ref
        .read(deviceToolRunnerProvider)
        .handle(
          callId: callId,
          tool: tool,
          args: asJson(device['args']),
          chatId: state.chatId,
          photos: photos,
          tainted: device['tainted'] == true,
        );
  }

  /// Stops the message being answered. What has arrived stays on screen, and nothing is sent again.
  void stop() {
    // Nothing left to stop once the answer is complete
    if (!state.busy || _sawDone) return;
    // Only this chat's phone calls are given up on: another chat that is working keeps its own
    ref.read(deviceToolRunnerProvider).stopChat(state.chatId);
    _stopped = true;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  // -- CHATS -- //

  /// Everything on screen belongs to the old conversation: forget it, and throw away any answer still on its way for it.
  void _fresh() {
    _generation++;
    _sentIds.clear();
    _resetTurn();
    _turnId = null;
    _userItemId = -1;
    // Messages still waiting belong to the old conversation: their photo copies are deleted (the callers' states replace the queue itself)
    _dropQueued(state.queue);
    // The next conversation is loaded or started by the caller, so a later screen mount must not ask again
    _restoreStarted = true;
  }

  void _listsChanged() => ref
    ..invalidate(chatListProvider)
    ..invalidate(archivedChatsProvider)
    ..invalidate(chatSearchProvider);

  /// Starts a new chat in this session. The earlier conversation stays in the list. Needs a connection. A turn being answered is not
  /// interrupted: the door gives a new chat its own session when this one is working.
  Future<void> showNew() async {
    if (state.working || _forking) return;
    final answer = asJson(await ref.read(apiProvider).verb('chat_new'));
    // A message sent while the request was on its way is a live turn: it is not wiped
    if (state.working) return;
    _fresh();
    state = ChatState(
      chatId: str(answer['chatId']),
      restore: RestoreStatus.done,
    );
    _listsChanged();
  }

  /// Shows another conversation and its recent messages in this session (the door only does this when the session is not working).
  Future<void> showChat(String chatId) async {
    if (state.working || _forking || chatId == state.chatId) return;
    await ref.read(apiProvider).verb('chat_open', <String, Object?>{
      'chatId': chatId,
    });
    if (state.working) return;
    _fresh();
    state = ChatState(chatId: chatId, restore: RestoreStatus.loading);
    await _load(chatId);
    _listsChanged();
  }

  /// Branches from a message (that message included) into a new chat and opens it.
  Future<bool> branch(String turnId) => _fork(turnId, include: true);

  /// The first half of "edit and resend": a new chat that holds everything before the message, opened. The screen sends the new words next.
  /// False when nothing was opened (a second tap, a reply being written, another chat opened meanwhile): then nothing is sent.
  Future<bool> branchBefore(String turnId) => _fork(turnId, include: false);

  /// "Edit and resend", in the same chat: the server removes the message and the ones after it, and the chat is loaded again (no new chat is
  /// made). The screen sends the new words next. True when the chat was rewound and shown; false when nothing was done (a second tap, a reply
  /// being written, the account changed). Throws when the server refuses or cannot be reached: nothing was removed then and the words stay.
  /// "Edit and resend" of a message the server never accepted (it failed before it was taken): there is nothing on the server to remove, so
  /// the message and the notices right after it (the failure line) leave the screen and the words are sent again as a new message.
  /// False when nothing was done (a reply being written, a rewind running, the message is not on screen or the server knows it).
  bool dropUnsent(int itemId) {
    if (state.working || _rewinding) return false;
    final at = state.items.indexWhere((i) => i.id == itemId);
    if (at < 0) return false;
    final item = state.items[at];
    if (item is! UserItem || item.turnId != null) return false;
    var end = at + 1;
    while (end < state.items.length && state.items[end] is NoticeItem) {
      end++;
    }
    state = state.copyWith(
      items: <ChatItem>[
        ...state.items.sublist(0, at),
        ...state.items.sublist(end),
      ],
    );
    return true;
  }

  Future<bool> rewindFrom(String turnId) async {
    final from = state.chatId;
    if (state.working || _forking || from == null) return false;
    final generation = _generation;
    // While this runs, sending and opening another chat wait, so the screen cannot change under it
    _forking = true;
    _rewinding = true;
    try {
      final key = '$from|$turnId|rewind';
      final requestId = _forkKeys.putIfAbsent(key, newRequestId);
      try {
        await ref.read(apiProvider).verb('chat_rewind', <String, Object?>{
          'chatId': from,
          'fromTurnId': turnId,
        }, requestId);
      } on ApiException catch (e) {
        // A lost answer is asked again with the same key (the server replays it); a refusal is final, and a later try is a new one
        if (!e.isNetwork) _forkKeys.remove(key);
        rethrow;
      }
      _forkKeys.remove(key);
      if (generation != _generation) return false;
      _listsChanged();
      // The server has removed the messages whatever happens next: the screen is rebuilt from it, even if that read fails (it then shows a
      // retry line, and the chat id is kept so the new words still go to this chat)
      _fresh();
      state = ChatState(chatId: from, restore: RestoreStatus.loading);
      await _load(from);
      return true;
    } finally {
      _forking = false;
      _rewinding = false;
    }
  }

  Future<bool> _fork(String turnId, {required bool include}) async {
    final from = state.chatId;
    if (state.working || _forking || from == null) return false;
    _forking = true;
    try {
      final key = '$from|$turnId|$include';
      final requestId = _forkKeys.putIfAbsent(key, newRequestId);
      final answer = asJson(
        await ref.read(apiProvider).verb('chat_fork', <String, Object?>{
          'chatId': from,
          'upToTurnId': turnId,
          if (!include) 'includeTurn': false,
        }, requestId),
      );
      _forkKeys.remove(key);
      // A message sent, or another chat opened, while the branch was being made: the screen stays as it is (the branch is in the list)
      _listsChanged();
      if (state.working || state.chatId != from) return false;
      final id = str(answer['chatId']);
      _fresh();
      state = ChatState(chatId: id, restore: RestoreStatus.loading);
      await _load(id);
      return true;
    } finally {
      _forking = false;
    }
  }

  /// Gives the open conversation a name of the person's own.
  Future<void> rename(String title) async {
    final id = state.chatId;
    if (id == null) return;
    final clean = title.trim();
    await ref.read(chatActionsProvider).rename(id, clean);
    if (state.chatId == id) state = state.copyWith(title: clean);
  }

  // -- RESTORE -- //

  /// Brings back the recent conversation, once. It is a plain read from the server (no model, no tokens). Without a connection, or on
  /// any error, the status says it failed (the chat shows a quiet retry line, never the greeting) and a later visit may try again.
  Future<void> restore() async {
    if (_restoreStarted) return;
    _restoreStarted = true;
    state = state.copyWith(restore: RestoreStatus.loading);
    await _load(state.chatId);
  }

  /// Reads one chat's recent messages ([chatId] null means the newest one) and puts them on screen as read-only items.
  Future<void> _load(String? chatId) async {
    final generation = _generation;
    try {
      final answer = await ref.read(apiProvider).verbJson(
        'chat_history',
        <String, Object?>{'chatId': ?chatId},
      );
      if (generation != _generation) return;
      final head = asJson(answer['chat']);
      final origin = asJson(head['forkedFrom']);
      final turns = asJsonList(answer['turns']);
      final items = <ChatItem>[];
      final store = await _openPhotos();
      if (generation != _generation) return;
      for (final t in turns) {
        // A turn already sent in this run is on screen as it happened
        if (_sentIds.contains(str(t['clientMessageId']))) continue;
        items.addAll(_restoredTurn(t, store));
      }
      state = ChatState(
        chatId: head['id'] is String ? str(head['id']) : state.chatId,
        title: head['title'] is String ? str(head['title']) : state.title,
        forkedFrom: origin['id'] is String
            ? ForkOrigin(
                str(origin['id']),
                origin['title'] is String ? str(origin['title']) : null,
              )
            : null,
        restored: items,
        items: state.items,
        busy: state.busy,
        phase: state.phase,
        toolName: state.toolName,
        queue: state.queue,
        queuePaused: state.queuePaused,
        restore: RestoreStatus.done,
        // The server's figure for this chat; with none, what a live answer already showed stays
        context: ContextInfo.fromHead(head) ?? state.context,
      );
    } on Object {
      if (generation == _generation) {
        _restoreStarted = false;
        state = state.copyWith(restore: RestoreStatus.failed);
      }
    }
  }

  /// Asks the server how every card still shown as waiting really stands, and puts the answer on screen. A card answered elsewhere, or
  /// answered here while this list was rebuilt, never keeps its Approve button. Quiet on any error: the card keeps what it shows.
  Future<void> syncCards() async {
    bool waiting(ChatItem i) =>
        i is CardItem && i.state == CardState.waiting && !i.readOnly;
    if (![...state.restored, ...state.items].any(waiting)) return;
    final generation = _generation;
    try {
      final answer = await ref.read(apiProvider).verbJson(
        'chat_history',
        <String, Object?>{'chatId': ?state.chatId},
      );
      if (generation != _generation) return;
      final now = <String, CardState>{
        for (final t in asJsonList(answer['turns']))
          for (final e in asJsonList(t['events']))
            if (str(e['type']) == 'card')
              str(e['actionId']): cardStateOf(str(e['status'])),
      };
      ChatItem fix(ChatItem i) {
        if (!waiting(i)) return i;
        final real = now[(i as CardItem).actionId];
        return real == null || real == CardState.waiting ? i : i.with_(real);
      }

      state = state.copyWith(
        restored: <ChatItem>[for (final i in state.restored) fix(i)],
        items: <ChatItem>[for (final i in state.items) fix(i)],
      );
    } on Object {
      // Offline or signed out: the next visit asks again
    }
  }

  /// One earlier turn as read-only items: what was said, what was done, what was answered.
  List<ChatItem> _restoredTurn(Json t, ChatPhotoStore? store) {
    final turn = t['id'] is String ? str(t['id']) : null;
    final out = <ChatItem>[
      UserItem(
        _id(),
        str(t['text']),
        photoPaths: turn == null || store == null
            ? const <String>[]
            : store.photosOf(turn),
        turnId: turn,
      ),
    ];
    for (final e in asJsonList(t['events'])) {
      switch (str(e['type'])) {
        case 'tool':
          // A request for approval draws nothing of its own: its card follows
          if (str(e['status']) == 'needs_approval') break;
          final label = toolLabelOf(e);
          out.add(
            ToolItem(
              _id(),
              name: str(e['name']),
              status: str(e['status']),
              message: e['message'] is String ? str(e['message']) : null,
              data: e['data'],
              restored: true,
              family: label.family,
              subject: label.subject,
              ms: label.ms,
            ),
          );
        case 'card':
          out.add(
            CardItem(
              _id(),
              actionId: str(e['actionId']),
              summary: str(e['summary']),
              readOnly: t['copied'] == true,
              turnId: turn,
              verb: e['verb'] is String ? str(e['verb']) : null,
              state: cardStateOf(str(e['status'])),
            ),
          );
        case 'fallback':
          out.add(NoticeItem(_id(), _words.chatAssistantDown));
      }
    }
    final reply = str(t['reply']);
    if (reply.trim().isNotEmpty) {
      out.add(AgentItem(_id(), reply, turnId: turn));
    } else if (str(t['status']) == 'failed' && out.length == 1) {
      out.add(NoticeItem(_id(), _words.chatNoAnswer));
    }
    return out;
  }

  // -- PHOTOS -- //

  /// The photo store with its index read, or null when this phone holds no photos (or cannot read them): the conversation then shows words only.
  Future<ChatPhotoStore?> _openPhotos() async {
    try {
      // Nothing was ever kept: no need to touch the files at all
      final kept = ref
          .read(prefsProvider)
          .getKeys()
          .any((k) => k.startsWith(photoIndexPrefix));
      // Photos belong to a signed-in person: with no session the store is not opened
      if (!kept || ref.read(sessionProvider).value == null) return null;
      final store = ref.read(chatPhotoStoreProvider);
      await store.ready();
      return store;
    } on Object {
      return null;
    }
  }

  /// Files the staged photos of the message just accepted under its turn and swaps their paths into the message on screen.
  Future<void> _keepPhotos(
    int itemId,
    String turn,
    List<String> staged, {
    List<String>? numbered,
  }) async {
    final generation = _generation;
    try {
      final kept = await ref
          .read(chatPhotoStoreProvider)
          .promote(turn, staged, numbered: numbered);
      if (generation != _generation) return;
      // Nothing filed (a wipe, or the files would not move): the message goes back to words only rather than point at staging
      _replace(
        itemId,
        (old) => old is UserItem ? old.withPhotoPaths(kept) : old,
      );
    } on Object {
      // The thumbnails are a convenience: the message itself was sent
      if (generation == _generation) {
        _replace(
          itemId,
          (old) => old is UserItem ? old.withPhotoPaths(const <String>[]) : old,
        );
      }
    }
  }

  Future<void> _discardPhotos(List<String> staged) async {
    try {
      await ref.read(chatPhotoStoreProvider).discard(staged);
    } on Object {
      // A leftover is swept at the next start
    }
  }

  // -- BATCHING -- //

  void _queueText(String more) {
    if (_pendingThought.isNotEmpty) _flush();
    _pendingText += more;
    _flushTimer ??= Timer(_flushEvery, _flush);
  }

  void _queueThought(String more) {
    if (_pendingText.isNotEmpty) _flush();
    _pendingThought += more;
    _flushTimer ??= Timer(_flushEvery, _flush);
  }

  /// Draws what has been gathered. Called by the timer, and at once before any other kind of event so the order never changes.
  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pendingThought.isNotEmpty) {
      final more = _pendingThought;
      _pendingThought = '';
      _thinkStart ??= DateTime.now();
      final last = state.items.isEmpty ? null : state.items.last;
      if (_thinkId >= 0 && last is ThinkingItem && last.id == _thinkId) {
        _replace(_thinkId, (old) => old is ThinkingItem ? old.grow(more) : old);
      } else {
        _thinkId = _id();
        _add(ThinkingItem(_thinkId, more));
      }
    }
    if (_pendingText.isNotEmpty) {
      final more = _pendingText;
      _pendingText = '';
      final last = state.items.isEmpty ? null : state.items.last;
      if (_agentId >= 0 && last is AgentItem && last.id == _agentId) {
        _replace(_agentId, (old) => old is AgentItem ? old.grow(more) : old);
      } else {
        _agentId = _id();
        _add(AgentItem(_agentId, more, streaming: true, turnId: _turnId));
      }
    }
  }

  /// The thinking is over: it folds into one line that says how long it took.
  void _closeThinking() {
    _flush();
    if (_thinkId < 0) return;
    final started = _thinkStart;
    final seconds = started == null
        ? 0
        : DateTime.now().difference(started).inSeconds;
    _replace(
      _thinkId,
      (old) => old is ThinkingItem && old.open ? old.closed(seconds) : old,
    );
    _thinkId = -1;
    _thinkStart = null;
  }

  /// Every way a turn can end (done, error, stop, start over) goes through here, so no spinner or caret is ever left behind.
  void _closeTurn({bool keepBusy = false}) {
    _closeThinking();
    _flush();
    state = state.copyWith(
      busy: keepBusy,
      phase: keepBusy ? state.phase : TurnPhase.idle,
      clearTool: true,
      items: <ChatItem>[
        for (final i in state.items)
          if (i is ToolItem && i.running)
            ...const <ChatItem>[]
          else if (i is AgentItem && i.streaming)
            i.done()
          else
            i,
      ],
    );
    _agentId = -1;
  }

  void _resetTurn() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingText = '';
    _pendingThought = '';
    _agentId = -1;
    _thinkId = -1;
    _thinkStart = null;
    _sawDone = false;
    _sawError = false;
    _turnId = null;
  }

  /// Sends one message. [photoTexts] is the text the phone read from each photo, already within the budget of photo_budget.dart.
  ///
  /// [images] are the pictures themselves (JPEG base64), sent beside the text only when the person and the server both allow it. They are held for the
  /// attempts of this one message and let go after it: never stored on the phone and never put in a message on screen.
  ///
  /// [photoPaths] are the staged copies of those photos (see ChatPhotoStore.stage), in the same order. They are filed under the turn once the
  /// server has accepted the message, and deleted if it never does.
  ///
  /// True when the message went through: the server accepted it, or it was kept in the outbox to go later. False when it failed, was stopped,
  /// or the account changed meanwhile, so a caller that took the words out of the box can put them back.
  ///
  /// [photoJobs] are photos still being made ready in the background (see PhotoPrepper): the message is put on screen at once, and the request waits
  /// for them only at the last moment. [allowPictures] false means the person refused pictures at the notice.
  ///
  /// While another message is being answered, or others are waiting, this one joins the queue and true is returned at once; its turn comes
  /// in the order it was sent. A full queue says so and returns false.
  Future<bool> send(
    String text, {
    List<String> photoTexts = const <String>[],
    List<String> photoPaths = const <String>[],
    List<String> images = const <String>[],
    List<String>? imagePaths,
    List<String>? textPaths,
    List<PhotoJob> photoJobs = const <PhotoJob>[],
    bool allowPictures = true,
  }) async {
    final trimmed = text.trim();
    // A rewind being made holds a send back: the chat on screen is about to be rebuilt (a branch being made does not, the message stays here)
    if ((trimmed.isEmpty && photoJobs.isEmpty) || _rewinding) return false;
    final message = QueuedMessage(
      id: _id(),
      messageId: newRequestId(),
      text: trimmed,
      photoJobs: photoJobs,
      allowPictures: allowPictures,
      photoTexts: photoTexts,
      photoPaths: photoPaths,
      images: images,
      imagePaths: imagePaths,
      textPaths: textPaths,
    );
    // Something is being answered, or others are waiting: this one takes its place at the end and a fresh Send never jumps ahead
    if (state.working) return _enqueue(message);
    final outcome = await _run(message);
    // Whatever was queued meanwhile follows, unless this one was stopped or failed (then the queue pauses)
    unawaited(_after(outcome));
    return outcome.accepted;
  }

  // -- QUEUE -- //

  /// The one flag behind the queue: only one drain loop ever runs.
  bool _draining = false;

  /// Adds [message] to the end of the queue. False, with a plain notice, when the queue or its photos are full.
  bool _enqueue(QueuedMessage message) {
    if (state.queue.length >= maxQueuedMessages) {
      notice(_words.chatQueueFull);
      _dropQueued(<QueuedMessage>[message]);
      return false;
    }
    final photos = state.queue.fold<int>(0, (n, m) => n + m.photoCount);
    if (photos + message.photoCount > maxQueuedPhotos) {
      notice(_words.chatQueuePhotosFull);
      _dropQueued(<QueuedMessage>[message]);
      return false;
    }
    message.chatId = state.chatId;
    // Sending while the queue is paused is the person asking again: the queue goes on, in order, with this one at its end
    state = state.copyWith(
      queue: <QueuedMessage>[...state.queue, message],
      queuePaused: false,
    );
    unawaited(_drain());
    return true;
  }

  /// Deletes the staged photo copies of messages that will never run.
  void _dropQueued(List<QueuedMessage> messages) {
    final copies = <String>[for (final m in messages) ...m.copies];
    if (copies.isNotEmpty) unawaited(_discardPhotos(copies));
  }

  /// The turn that just ended decides what happens to the queue: a clean one lets the next message start, a stopped or failed one pauses it.
  Future<void> _after(_Outcome outcome) async {
    if (outcome.stale || state.queue.isEmpty) return;
    if (!outcome.clean) {
      state = state.copyWith(queuePaused: true);
      return;
    }
    await _drain();
  }

  /// Runs the waiting messages one after another. It starts the next only when nothing is being answered and the queue is not paused.
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (!state.busy && !state.queuePaused && state.queue.isNotEmpty) {
        final generation = _generation;
        final next = state.queue.first;
        state = state.copyWith(queue: state.queue.sublist(1));
        // A message belongs to the chat it was written in
        if (next.chatId != null && next.chatId != state.chatId) {
          _dropQueued(<QueuedMessage>[next]);
          continue;
        }
        final outcome = await _run(next);
        if (outcome.stale || generation != _generation) return;
        if (!outcome.clean) {
          if (state.queue.isNotEmpty) state = state.copyWith(queuePaused: true);
          return;
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// "Send now": the paused queue goes on. If a message is still being answered, the queue follows it as usual.
  void resumeQueue() {
    if (state.queue.isEmpty) return;
    state = state.copyWith(queuePaused: false);
    unawaited(_drain());
  }

  /// "Clear": every waiting message is forgotten and its photo copies are deleted.
  void clearQueue() {
    final gone = state.queue;
    if (gone.isEmpty) return;
    state = state.copyWith(queue: const <QueuedMessage>[], queuePaused: false);
    _dropQueued(gone);
  }

  /// Takes one waiting message off the queue (its photos are deleted). Null when it is not waiting any more.
  QueuedMessage? removeQueued(int id) {
    final found = state.queue.where((m) => m.id == id).firstOrNull;
    if (found == null) return null;
    final rest = <QueuedMessage>[
      for (final m in state.queue)
        if (m.id != id) m,
    ];
    state = state.copyWith(
      queue: rest,
      queuePaused: rest.isEmpty ? false : null,
    );
    _dropQueued(<QueuedMessage>[found]);
    return found;
  }

  /// Runs one message: puts it on screen, waits for its photos, asks the server and shows the answer. The per-turn state of this class belongs
  /// to the message being run, which is why only one runs at a time.
  Future<_Outcome> _run(QueuedMessage message) async {
    final trimmed = message.text;
    final photoJobs = message.photoJobs;
    var photoTexts = message.photoTexts;
    // Another person signing in (or a fresh start) makes this send stale: it stops and draws nothing more
    final generation = _generation;
    var accepted = false;
    var clean = false;
    // Waiting for an earlier message of this chat on the server
    var busyWaits = 0;
    var busyTotal = 0;
    int? busyNotice;
    // The pictures were taken away and the text read from them went instead; said to the person only once that is true
    var picturesSwapped = false;
    final messageId = message.messageId;
    // The retry below cuts the screen back to this message by its id, not by a position, so nothing arriving meanwhile can move it
    final userItemId = _id();
    _userItemId = userItemId;
    _sentIds.add(messageId);
    final waiting = photoJobs.isNotEmpty;
    _staged = waiting
        ? <String>[for (final j in photoJobs) j.path]
        : List<String>.of(message.photoPaths);
    // Callers that know which copies went as pictures and which as text say so; otherwise every copy counts in order
    _numberedImages = List<String>.of(message.imagePaths ?? _staged);
    _numberedTexts = List<String>.of(message.textPaths ?? _staged);
    var pictures = List<String>.of(message.images);
    _picturesSent = pictures.isNotEmpty;
    var words = trimmed;
    _add(
      UserItem(
        userItemId,
        words,
        photos: photoTexts.length,
        photoPaths: _staged,
        preparing: waiting,
      ),
    );
    state = state.copyWith(busy: true, phase: TurnPhase.waiting);
    _stopped = false;
    final abort = Completer<void>();
    _abort = abort;
    _resetTurn();
    try {
      // The photos finish in the background; the request waits for them only now, and the picture mode is read again at this moment
      if (waiting) {
        final made = await Future.wait(<Future<PhotoResult>>[
          for (final j in photoJobs) j.result,
        ]);
        if (generation != _generation) return _Outcome.dropped;
        if (_stopped) {
          // Stopped while the photos were still being made ready: nothing is sent, and the message leaves the screen with its copies
          _replace(
            userItemId,
            (old) =>
                old is UserItem ? old.withPhotoPaths(const <String>[]) : old,
          );
          return const _Outcome(accepted: false, clean: false);
        }
        final usePictures =
            message.allowPictures &&
            ref.read(settingsProvider).usesPictures &&
            (ref.read(prefsProvider).getBool(pictureNoticeKey) ?? false);
        // Pictures go in order while they fit the message's total; one that does not fit goes by its text
        var total = 0;
        var cutPictures = 0;
        final picked = <PhotoResult>[];
        for (final r in made) {
          final picture = r.picture;
          if (usePictures && picture != null) {
            if (total + picture.bytes <= uploadTotalBytes) {
              total += picture.bytes;
              picked.add(r);
            } else {
              cutPictures++;
              picked.add(PhotoResult(r.text, null));
            }
          } else {
            picked.add(PhotoResult(r.text, null));
          }
        }
        final keep = <int>[
          for (var i = 0; i < photoJobs.length; i++)
            if (picked[i].text.isNotEmpty || picked[i].picture != null) i,
        ];
        final left = <String>[
          for (var i = 0; i < photoJobs.length; i++)
            if (!keep.contains(i)) photoJobs[i].path,
        ];
        if (left.isNotEmpty) {
          unawaited(_discardPhotos(left));
          _add(NoticeItem(_id(), _words.chatPhotosSkipped(left.length)));
        } else if (cutPictures > 0) {
          _add(NoticeItem(_id(), _words.chatPictureSkipped));
        }
        if (trimmed.isEmpty && keep.isEmpty) {
          // Nothing to send: the message goes away again
          _staged = const <String>[];
          _remove(userItemId);
          if (left.isEmpty) {
            _add(NoticeItem(_id(), _words.chatPhotoEmpty));
          }
          return const _Outcome(accepted: false, clean: true);
        }
        final budget = fitPhotoTexts(<String>[
          for (final i in keep)
            if (picked[i].text.isNotEmpty) picked[i].text,
        ]);
        photoTexts = budget.texts;
        if (budget.trimmed) {
          _add(NoticeItem(_id(), _words.chatPhotosTrimmed));
        }
        _staged = <String>[for (final i in keep) photoJobs[i].path];
        _numberedImages = <String>[
          for (final i in keep)
            if (picked[i].picture != null) photoJobs[i].path,
        ];
        _numberedTexts = <String>[
          for (final i in keep)
            if (picked[i].text.isNotEmpty) photoJobs[i].path,
        ];
        pictures = <String>[
          for (final i in keep)
            if (picked[i].picture != null) picked[i].picture!.data,
        ];
        _picturesSent = pictures.isNotEmpty;
        words = trimmed.isEmpty
            ? (pictures.isNotEmpty
                  ? _words.chatPhotoOnlyMessage
                  : _words.chatReceiptMessage)
            : trimmed;
        // The message on screen takes its final words, photos and tiles
        _replace(
          userItemId,
          (old) => old is UserItem
              ? old.withPhotoPaths(_staged).prepared(words, photoTexts.length)
              : old,
        );
      }
      for (var attempt = 0; attempt <= _retries; attempt++) {
        try {
          await for (final e
              in ref
                  .read(apiProvider)
                  .chat(
                    id: messageId,
                    text: words,
                    ocrTexts: photoTexts,
                    images: pictures,
                    chatId: state.chatId,
                    abort: abort.future,
                    scripts: true,
                    clock: uses24Hour ? '24' : '12',
                  )) {
            if (generation != _generation) return _Outcome.dropped;
            // The earlier message has finished and this one has begun: the waiting line goes
            if (busyNotice != null) {
              _remove(busyNotice);
              busyNotice = null;
            }
            _handle(e);
            if (_turnId != null || _sawDone) accepted = true;
          }
          if (generation != _generation) return _Outcome.dropped;
          // A stream that ends with no "done" was cut: ask again under the same id, as for any dropped connection
          // (a stream that ended with an "error" event is a server failure, not a dropped connection: asking again would run the turn again)
          if (!_sawDone && !_sawError && !_stopped) {
            throw const ApiException('NETWORK', 'The connection was lost.', 0);
          }
          break;
        } on ApiException catch (e) {
          if (generation != _generation) return _Outcome.dropped;
          if (_stopped) break;
          // Another message of this chat is still being answered on the server (a second phone, or a repeat that raced): wait with growing
          // pauses, past the server's 120 s rule for a stuck turn, and keep the same id. Stop ends the wait at once
          if (e.code == 'BUSY_CHAT') {
            if (busyTotal < _busyCap) {
              final pause =
                  _busyPauses[math.min(busyWaits, _busyPauses.length - 1)];
              busyWaits++;
              busyTotal += pause;
              if (busyNotice == null) {
                busyNotice = _id();
                _add(NoticeItem(busyNotice, _words.chatStillFinishing));
              }
              // Not one of the dropped-connection retries
              attempt--;
              await Future.any<void>(<Future<void>>[
                Future<void>.delayed(busyWaitUnit * pause),
                abort.future,
              ]);
              if (_stopped) break;
              continue;
            }
            _closeTurn(keepBusy: true);
            _add(NoticeItem(_id(), _words.chatEarlierNotFinished));
            break;
          }
          // The server refused the message with its pictures in it (an older server that knows no pictures, or one it will not take): once more
          // on the text read from them. Nothing was claimed, so the same id is used, and this is not one of the dropped-connection retries
          if (pictures.isNotEmpty && e.code == 'INVALID') {
            pictures = const <String>[];
            _picturesSent = false;
            picturesSwapped = true;
            attempt--;
            continue;
          }
          // A repeat of a finished message is answered from storage, so it is safe to ask again; start the turn's items over
          final again =
              (e.isNetwork || e.code == 'CONFLICT') && attempt < _retries;
          if (again) {
            _resetTurn();
            final cut = state.items.indexWhere((i) => i.id == userItemId);
            state = state.copyWith(
              items: cut < 0 ? state.items : state.items.sublist(0, cut + 1),
              phase: TurnPhase.waiting,
              clearTool: true,
            );
            await Future<void>.delayed(_retryWait);
            if (_stopped) break;
            continue;
          }
          _closeTurn(keepBusy: true);
          if (e.isNetwork && looksLikeExpense(words)) {
            try {
              final box = ref.read(outboxProvider);
              // Under the id of the first try: if that try did reach the server, its answer is the one a repeat gets
              await box.add('expense_from_text', <String, Object?>{
                'text': words,
              }, key: messageId);
              ref.read(outboxCountProvider.notifier).refresh();
              if (generation != _generation) return _Outcome.dropped;
              accepted = true;
              _add(NoticeItem(_id(), _words.chatNoticeOffline));
            } on Object {
              // Kept nowhere: say so instead of leaving the person thinking it was saved
              _add(NoticeItem(_id(), _words.chatNoticeFailed));
            }
          } else {
            _add(NoticeItem(_id(), e.message));
          }
          break;
        } on Object {
          // Anything else that goes wrong while reading the stream is not shown in words: the screen is just left in a clean state
          if (generation != _generation) return _Outcome.dropped;
          if (_stopped) break;
          _closeTurn(keepBusy: true);
          _add(NoticeItem(_id(), _words.chatNoticeFailed));
          break;
        }
      }
    } finally {
      final stale = generation != _generation;
      if (!stale) _picturesSent = false;
      // Photos never filed (the server did not accept the message) are not kept
      if (_staged.isNotEmpty) {
        final left = _staged;
        _staged = const <String>[];
        if (!stale) {
          _replace(
            userItemId,
            (old) =>
                old is UserItem ? old.withPhotoPaths(const <String>[]) : old,
          );
        }
        unawaited(_discardPhotos(left));
      }
      // A stale send leaves the new start alone: its screen, its turn and its abort belong to somebody else now
      if (!stale) {
        // The pictures were left out and the answer went by their text: the notice comes only when that is what happened
        if (picturesSwapped && _sawDone && photoTexts.isNotEmpty) {
          _add(NoticeItem(_id(), _words.chatPicturesNoted));
        }
        final answered = _sawDone;
        final wasStopped = _stopped;
        _closeTurn();
        if (wasStopped) _add(NoticeItem(_id(), _words.chatStopped));
        _stopped = false;
        // Only an answered, not stopped turn lets the queue go on
        clean = answered && !wasStopped;
        if (identical(_abort, abort)) _abort = null;
        // The answer came while another chat was on screen: the list and the menu button say so until this chat is opened
        if (ref.read(activeChatKeyProvider) != key && answered) {
          state = state.copyWith(unseen: true);
        }
        // What the message may have changed on the phone's money screens is read again as soon as its turn is over
        ref
          ..invalidate(syncProvider)
          ..invalidate(balancesProvider);
      }
    }
    final stale = generation != _generation;
    return _Outcome(accepted: accepted && !stale, clean: clean, stale: stale);
  }

  void _remove(int id) => state = state.copyWith(
    items: <ChatItem>[
      for (final i in state.items)
        if (i.id != id) i,
    ],
  );

  /// Applies one event of the stream.
  void _handle(Json e) {
    // The caller drops events of a start that is over; this is the second line of defence
    switch (str(e['type'])) {
      case 'start':
        // The server says which message and which chat this is: the message can be branched from, and a first message names the chat
        final turn = e['turnId'] is String ? str(e['turnId']) : null;
        _turnId = turn;
        if (turn != null) {
          _replace(
            _userItemId,
            (old) => old is UserItem ? old.withTurn(turn) : old,
          );
          // Once: a retried send reports its start again, and the files have already moved
          if (_staged.isNotEmpty) {
            final staged = _staged;
            _staged = const <String>[];
            // The server numbers the pictures when it used them, otherwise the texts read from them
            final byPictures = _picturesSent && e['usedImages'] != false;
            unawaited(
              _keepPhotos(
                _userItemId,
                turn,
                staged,
                numbered: byPictures ? _numberedImages : _numberedTexts,
              ),
            );
          }
        }
        // The pictures went up but this answer goes by the text read from them (the person or the server's host does not use them)
        if (_picturesSent && e['usedImages'] == false) {
          _picturesSent = false;
          _add(NoticeItem(_id(), _words.chatPicturesNoted));
        }
        state = state.copyWith(
          phase: TurnPhase.waiting,
          clearTool: true,
          chatId: e['chatId'] is String ? str(e['chatId']) : null,
          title: state.title ?? _titleFrom(_userWords()),
        );
      case 'phase':
        _flush();
        if (str(e['phase']) == 'writing') {
          _closeThinking();
          state = state.copyWith(phase: TurnPhase.writing, clearTool: true);
        } else {
          state = state.copyWith(phase: TurnPhase.thinking, clearTool: true);
        }
      case 'reasoning':
        if (state.phase != TurnPhase.thinking) {
          state = state.copyWith(phase: TurnPhase.thinking, clearTool: true);
        }
        _queueThought(str(e['text']));
      case 'delta':
        if (state.phase != TurnPhase.writing) {
          _closeThinking();
          state = state.copyWith(phase: TurnPhase.writing, clearTool: true);
        }
        _queueText(str(e['text']));
      case 'tool_start':
        _closeThinking();
        _flush();
        _agentId = -1;
        _closeStreamingText();
        // A call the assistant makes to this phone (a script, the toolbox): run it now and post the answer under the id the server sent
        final device = e['device'];
        if (device is Map<String, Object?>) {
          unawaited(_runOnPhone(str(e['name']), asJson(device)));
        }
        final began = toolLabelOf(e);
        _add(
          ToolItem(
            _id(),
            name: str(e['name']),
            status: 'running',
            callId: str(e['id']),
            running: true,
            family: began.family,
            subject: began.subject,
            startedAt: DateTime.now(),
          ),
        );
        state = state.copyWith(phase: TurnPhase.tool, toolName: str(e['name']));
      case 'research':
        // Live counts of a research call: put on the running row with the same call id. Nothing else about the turn changes
        final id = str(e['id']);
        final hosts = asList(e['hosts']).whereType<String>().toList();
        for (final t in state.items.whereType<ToolItem>()) {
          if (t.running && t.callId == id) {
            _replace(
              t.id,
              (old) => old is ToolItem
                  ? old.withLive(
                      ResearchLive(
                        searches: intOf(e['searches']),
                        reads: intOf(e['reads']),
                        hosts: hosts,
                      ),
                    )
                  : old,
            );
            break;
          }
        }
      case 'tool':
        _closeThinking();
        _flush();
        _agentId = -1;
        _closeStreamingText();
        _finishTool(e);
      case 'card':
        _closeThinking();
        _flush();
        _agentId = -1;
        _closeStreamingText();
        _add(
          CardItem(
            _id(),
            actionId: str(e['actionId']),
            summary: str(e['summary']),
            turnId: _turnId,
            verb: e['verb'] is String ? str(e['verb']) : null,
          ),
        );
      case 'usage':
        // The size of the prompt after a model call, live: the ring follows a long turn as it grows
        _setContext(e['promptTokens'], e['window']);
      case 'pictures':
        // The host would not take the pictures: this answer goes by the text read from them
        _picturesSent = false;
        _add(NoticeItem(_id(), _words.chatPicturesNoted));
      case 'fallback':
        _closeThinking();
        _flush();
        _agentId = -1;
        _add(FallbackItem(_id(), str(e['reason'])));
      case 'error':
        _sawError = true;
        _closeThinking();
        _flush();
        _agentId = -1;
        _add(NoticeItem(_id(), _words.chatNoticeFailed));
      case 'done':
        _sawDone = true;
        // "At the last answer": the final figure of a message that ended well (the server leaves it out of a stopped one)
        final ctx = e['context'];
        if (ctx is Map<String, Object?>) {
          _setContext(ctx['promptTokens'], ctx['window']);
        }
        _closeThinking();
        _flush();
        // A reminder, alarm, timer, task or event made in this reply reaches the phone's alarms now, not at the next 15 minute round
        if (changesReminders(e['toolsRun'])) {
          ref.invalidate(syncProvider);
          unawaited(flushAndSync(ref.container).catchError((Object _) {}));
        }
      default:
        break;
    }
  }

  /// Puts a reported prompt size on the chat. Anything that is not a whole size and window is ignored, so a bad event never hides the ring.
  void _setContext(Object? tokens, Object? window) {
    if (tokens is! int || window is! int || window <= 0) return;
    state = state.copyWith(
      context: ContextInfo(
        tokens: tokens,
        window: window,
        summarizedAt: state.context?.summarizedAt,
      ),
    );
  }

  /// Reads the chat's figure again (one message, no photos): after "Summarize now" the time of the new summary arrives this way. Quiet on any error.
  Future<ContextInfo?> refreshContext() async {
    final id = state.chatId;
    if (id == null) return state.context;
    final generation = _generation;
    try {
      final answer = await ref.read(apiProvider).verbJson(
        'chat_history',
        <String, Object?>{'chatId': id, 'limit': 1},
      );
      if (generation != _generation || state.chatId != id) return state.context;
      final fresh = ContextInfo.fromHead(asJson(answer['chat']));
      // The summary time comes from the server; the size stays the one of the last answer, which a live turn may already have moved on
      if (fresh != null) {
        final now = state.context;
        state = state.copyWith(
          context: now == null
              ? fresh
              : now.copyWith(summarizedAt: fresh.summarizedAt),
        );
      }
    } on Object {
      // Offline or signed out: the sheet shows what it had
    }
    return state.context;
  }

  void _closeStreamingText() {
    state = state.copyWith(
      items: <ChatItem>[
        for (final i in state.items)
          i is AgentItem && i.streaming ? i.done() : i,
      ],
    );
  }

  /// A tool answered: it takes the place of the row that showed it running (same position, same id). With no such row it is added.
  void _finishTool(Json e) {
    final callId = e['id'] is String ? str(e['id']) : null;
    final status = str(e['status']);
    final found = callId == null
        ? null
        : state.items
              .whereType<ToolItem>()
              .where((t) => t.running && t.callId == callId)
              .firstOrNull;
    // A request for approval draws nothing of its own (the card follows), so the running row just goes away
    if (found != null && status == 'needs_approval') {
      state = state.copyWith(
        items: <ChatItem>[
          for (final i in state.items)
            if (i.id != found.id) i,
        ],
        phase: TurnPhase.thinking,
        clearTool: true,
      );
      return;
    }
    // The label of the answer wins; else the one the running row started with; else none (the old wording shows)
    final label = toolLabelOf(e);
    final started = found?.startedAt;
    // The server's own time wins; with none (an older server) the time between start and answer on this phone stands in
    final took =
        label.ms ??
        (started == null
            ? null
            : DateTime.now().difference(started).inMilliseconds);
    final done = ToolItem(
      found?.id ?? _id(),
      name: str(e['name']),
      status: status,
      message: e['message'] is String ? str(e['message']) : null,
      data: e['data'],
      callId: callId,
      family: label.family ?? found?.family,
      // A blocked call was sent without its subject, and the running row's must not bring it back
      subject: label.family != null ? label.subject : found?.subject,
      startedAt: started,
      ms: took,
    );
    if (found == null) {
      _add(done);
    } else {
      _replace(found.id, (_) => done);
    }
    // Other tools may still be running; otherwise the model is thinking again
    final stillRunning = state.items.whereType<ToolItem>().where(
      (t) => t.running,
    );
    state = state.copyWith(
      phase: stillRunning.isEmpty ? TurnPhase.thinking : TurnPhase.tool,
      toolName: stillRunning.isEmpty ? null : stillRunning.last.name,
      clearTool: stillRunning.isEmpty,
    );
  }

  void notice(String text) => _add(NoticeItem(_id(), text));

  /// The answer waiting in this chat has been looked at (the chat is on screen).
  void markSeen() {
    if (state.unseen) state = state.copyWith(unseen: false);
  }

  /// Said when too many chats are working to start one more.
  String get limitWords => _words.chatsLimit;

  /// The words of the message being sent, for naming a chat that has no name yet.
  String _userWords() {
    for (final i in state.items.reversed) {
      if (i is UserItem && i.id == _userItemId) return i.text;
    }
    return '';
  }
}

// -- SESSIONS -- //

/// Which session is on screen. The first one is called "main"; more are made when a chat is opened or started while another is working.
class ActiveChatKey extends Notifier<String> {
  @override
  String build() => 'main';

  void show(String key) => state = key;
}

final NotifierProvider<ActiveChatKey, String> activeChatKeyProvider =
    NotifierProvider<ActiveChatKey, String>(ActiveChatKey.new);

/// Every session that exists, in the order they were made.
class ChatKeys extends Notifier<List<String>> {
  int _made = 0;

  @override
  List<String> build() => const <String>['main'];

  /// Makes room for one more session and says its key.
  String add() {
    final key = 'chat${++_made}';
    state = <String>[...state, key];
    return key;
  }
}

final NotifierProvider<ChatKeys, List<String>> chatKeysProvider =
    NotifierProvider<ChatKeys, List<String>>(ChatKeys.new);

/// One chat's own state and turn, by session key.
final chatSessionProvider =
    NotifierProvider.family<ChatSession, ChatState, String>(ChatSession.new);

/// How many chats may work at the same time: more would use the monthly allowance of the assistant and the phone's data too fast.
const int maxWorkingChats = 3;

/// What the screens use. Its state is the state of the session on screen, and every call goes to that session, so a screen never has to
/// know there are several. Opening or starting a chat is never refused because another chat is working: that chat keeps working in its own
/// session while the new one is shown in another.
class ChatNotifier extends Notifier<ChatState> {
  ChatSession get _session =>
      ref.read(chatSessionProvider(ref.read(activeChatKeyProvider)).notifier);

  @override
  ChatState build() =>
      ref.watch(chatSessionProvider(ref.watch(activeChatKeyProvider)));

  /// How many other chats are working right now.
  int get _othersWorking {
    final active = ref.read(activeChatKeyProvider);
    var n = 0;
    for (final k in ref.read(chatKeysProvider)) {
      if (k != active && ref.read(chatSessionProvider(k)).working) n++;
    }
    return n;
  }

  /// Shows the session [key], and says the answer waiting there has been looked at.
  void _show(String key) {
    ref.read(activeChatKeyProvider.notifier).show(key);
    final session = ref.read(chatSessionProvider(key).notifier);
    session.markSeen();
  }

  /// The session that already shows [chatId], if there is one.
  String? _keyOf(String chatId) {
    for (final k in ref.read(chatKeysProvider)) {
      if (ref.read(chatSessionProvider(k)).chatId == chatId) return k;
    }
    return null;
  }

  Future<void> startNew() async {
    final active = ref.read(activeChatKeyProvider);
    if (!ref.read(chatSessionProvider(active)).working) {
      await _session.showNew();
      return;
    }
    final key = ref.read(chatKeysProvider.notifier).add();
    await ref.read(chatSessionProvider(key).notifier).showNew();
    _show(key);
  }

  Future<void> openChat(String chatId) async {
    final active = ref.read(activeChatKeyProvider);
    if (ref.read(chatSessionProvider(active)).chatId == chatId) {
      _session.markSeen();
      return;
    }
    // A chat that already has a session (working, or finished meanwhile) is shown as it is, with no waiting
    final have = _keyOf(chatId);
    if (have != null) {
      _show(have);
      return;
    }
    if (!ref.read(chatSessionProvider(active)).working) {
      await _session.showChat(chatId);
      return;
    }
    final key = ref.read(chatKeysProvider.notifier).add();
    await ref.read(chatSessionProvider(key).notifier).showChat(chatId);
    _show(key);
  }

  /// Sends one message in the chat on screen. False, and a plain notice in that chat, when [maxWorkingChats] chats are already working.
  Future<bool> send(
    String text, {
    List<String> photoTexts = const <String>[],
    List<String> photoPaths = const <String>[],
    List<String> images = const <String>[],
    List<String>? imagePaths,
    List<String>? textPaths,
    List<PhotoJob> photoJobs = const <PhotoJob>[],
    bool allowPictures = true,
  }) {
    if ((text.trim().isNotEmpty || photoJobs.isNotEmpty) &&
        !state.working &&
        _othersWorking >= maxWorkingChats) {
      _session.notice(_session.limitWords);
      return Future<bool>.value(false);
    }
    return _session.send(
      text,
      photoTexts: photoTexts,
      photoPaths: photoPaths,
      images: images,
      imagePaths: imagePaths,
      textPaths: textPaths,
      photoJobs: photoJobs,
      allowPictures: allowPictures,
    );
  }

  void stop() => _session.stop();

  /// "Send now" on a paused queue.
  void resumeQueue() => _session.resumeQueue();

  /// "Clear" on a paused queue.
  void clearQueue() => _session.clearQueue();

  /// Takes a waiting message off the queue; null when it is not waiting any more.
  QueuedMessage? removeQueued(int id) => _session.removeQueued(id);

  void answer(int id, {Object? data}) => _session.answer(id, data: data);

  void setCard(int id, CardState s, {String? note}) =>
      _session.setCard(id, s, note: note);

  Future<bool> branch(String turnId) => _session.branch(turnId);

  Future<bool> branchBefore(String turnId) => _session.branchBefore(turnId);

  Future<bool> rewindFrom(String turnId) => _session.rewindFrom(turnId);

  bool dropUnsent(int itemId) => _session.dropUnsent(itemId);

  Future<void> rename(String title) => _session.rename(title);

  Future<void> restore() => _session.restore();

  Future<ContextInfo?> refreshContext() => _session.refreshContext();

  Future<void> syncCards() => _session.syncCards();

  void notice(String text) => _session.notice(text);
}

final NotifierProvider<ChatNotifier, ChatState> chatProvider =
    NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);

/// Every provider that holds a chat's state. Invalidate all of them for a fresh start (another person signs in): no session, no answer
/// still on its way, and no chat on screen is kept from before.
List<ProviderOrFamily> get chatProviders => <ProviderOrFamily>[
  chatSessionProvider,
  chatKeysProvider,
  activeChatKeyProvider,
  chatProvider,
];

/// What one chat is doing, for its row in the list.
enum ChatActivity { working, needsOk, newAnswer }

/// The activity of every chat that has a session, by chat id. A chat with nothing to say is not in it.
final Provider<Map<String, ChatActivity>> chatActivityProvider =
    Provider<Map<String, ChatActivity>>((ref) {
      final active = ref.watch(activeChatKeyProvider);
      final out = <String, ChatActivity>{};
      for (final k in ref.watch(chatKeysProvider)) {
        final s = ref.watch(chatSessionProvider(k));
        final id = s.chatId;
        if (id == null) continue;
        final waiting = [...s.restored, ...s.items].any(
          (i) => i is CardItem && i.state == CardState.waiting && !i.readOnly,
        );
        if (s.working) {
          out[id] = ChatActivity.working;
        } else if (waiting) {
          out[id] = ChatActivity.needsOk;
        } else if (s.unseen && k != active) {
          out[id] = ChatActivity.newAnswer;
        }
      }
      return out;
    });

/// True when a chat that is not on screen has something for the person: a new answer, or a card waiting. The menu button shows a dot.
final Provider<bool> otherChatWaitsProvider = Provider<bool>((ref) {
  final active = ref.watch(activeChatKeyProvider);
  for (final k in ref.watch(chatKeysProvider)) {
    if (k == active) continue;
    final s = ref.watch(chatSessionProvider(k));
    if (s.unseen) return true;
    final waiting = [
      ...s.restored,
      ...s.items,
    ].any((i) => i is CardItem && i.state == CardState.waiting && !i.readOnly);
    if (waiting) return true;
  }
  return false;
});
