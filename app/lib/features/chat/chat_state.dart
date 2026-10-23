// THE CHAT: WHAT IS ON THE SCREEN (THE PERSON'S MESSAGES, THE ASSISTANT'S PLAIN TEXT, ITS THINKING, WHAT IT DID, CARDS TO APPROVE) AND HOW A MESSAGE IS SENT.
// A message has an id the phone chooses. If the connection drops, the same id is sent again and the server replays the stored answer, so the assistant
// never does the same thing twice. An expense typed with no connection is kept in the outbox and sent later with its own request id.
// While the assistant works the screen shows it live: a status (waiting, thinking, writing, using a tool), its thinking as it arrives, a row for each
// tool that is running, and the answer growing. The words and the thinking arrive in tiny pieces, so they are gathered and drawn about 25 times a second.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/reminders.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';

// -- TYPES -- //

enum CardState { waiting, approved, declined, failed, expired }

/// What the assistant is doing right now, for the status row under the conversation.
enum TurnPhase { idle, waiting, thinking, writing, tool }

sealed class ChatItem {
  const ChatItem(this.id);

  final int id;
}

final class UserItem extends ChatItem {
  const UserItem(super.id, this.text, {this.photo = false});

  final String text;

  /// Text from a photo went along with it.
  final bool photo;
}

final class AgentItem extends ChatItem {
  const AgentItem(super.id, this.text, {this.streaming = false});

  final String text;
  final bool streaming;

  AgentItem grow(String more) => AgentItem(id, text + more, streaming: true);
  AgentItem done() => AgentItem(id, text);
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
  });

  final String name;

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
  );
}

final class CardItem extends ChatItem {
  const CardItem(
    super.id, {
    required this.actionId,
    required this.summary,
    this.state = CardState.waiting,
    this.note,
  });

  final String actionId;
  final String summary;
  final CardState state;
  final String? note;

  CardItem with_(CardState s, {String? note}) =>
      CardItem(id, actionId: actionId, summary: summary, state: s, note: note);
}

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

class ChatState {
  const ChatState({
    this.restore = RestoreStatus.idle,
    this.restored = const <ChatItem>[],
    this.items = const <ChatItem>[],
    this.busy = false,
    this.phase = TurnPhase.idle,
    this.toolName,
  });

  /// The earlier conversation brought back from the server. Kept apart from [items] so it can arrive at any moment without
  /// moving anything the live turn counts on.
  final List<ChatItem> restored;
  final List<ChatItem> items;
  final bool busy;
  final TurnPhase phase;
  final RestoreStatus restore;

  /// The tool in use while [phase] is [TurnPhase.tool].
  final String? toolName;

  ChatState copyWith({
    RestoreStatus? restore,
    List<ChatItem>? restored,
    List<ChatItem>? items,
    bool? busy,
    TurnPhase? phase,
    String? toolName,
    bool clearTool = false,
  }) => ChatState(
    restore: restore ?? this.restore,
    restored: restored ?? this.restored,
    items: items ?? this.items,
    busy: busy ?? this.busy,
    phase: phase ?? this.phase,
    toolName: clearTool ? null : (toolName ?? this.toolName),
  );
}

// -- CONSTANTS -- //

/// How many times a dropped message is sent again, and how long to wait between.
const int _retries = 3;
const Duration _retryWait = Duration(seconds: 2);

/// Pieces of the answer and of the thinking are gathered for this long before the screen is drawn again.
const Duration _flushEvery = Duration(milliseconds: 40);

// -- FUNCTIONS -- //

/// True when the text has a number in it, so it may be an expense that can be kept for later without the assistant.
bool looksLikeExpense(String text) => RegExp(r'\d').hasMatch(text);

class ChatNotifier extends Notifier<ChatState> {
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

  @override
  ChatState build() {
    ref.onDispose(() => _flushTimer?.cancel());
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

  /// Stops the message being answered. What has arrived stays on screen, and nothing is sent again.
  void stop() {
    // Nothing left to stop once the answer is complete
    if (!state.busy || _sawDone) return;
    _stopped = true;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  // -- NEW CHAT -- //

  /// Starts a new chat: the server sets the earlier conversation aside (so the assistant starts without it too), and the screen empties.
  /// Needs a connection. A turn being answered is not interrupted.
  Future<void> startNew() async {
    if (state.busy) return;
    await ref.read(apiProvider).verb('chat_clear');
    // A message sent while the request was on its way is a live turn: it is not wiped
    if (state.busy) return;
    // Anything still on its way back from before belongs to the old conversation
    _generation++;
    _sentIds.clear();
    _resetTurn();
    // Cleared on the server too, so there is nothing to bring back (a later screen mount must not ask again): the empty chat may greet
    _restoreStarted = true;
    state = const ChatState(restore: RestoreStatus.done);
  }

  // -- RESTORE -- //

  /// Brings back the recent conversation, once. It is a plain read from the server (no model, no tokens). Without a connection, or on
  /// any error, the status says it failed (the chat shows a quiet retry line, never the greeting) and a later visit may try again.
  Future<void> restore() async {
    if (_restoreStarted) return;
    _restoreStarted = true;
    final generation = _generation;
    state = state.copyWith(restore: RestoreStatus.loading);
    try {
      final answer = await ref.read(apiProvider).verbJson('chat_history');
      if (generation != _generation) return;
      final turns = asJsonList(answer['turns']);
      final items = <ChatItem>[];
      for (final t in turns) {
        // A turn already sent in this run is on screen as it happened
        if (_sentIds.contains(str(t['clientMessageId']))) continue;
        items.addAll(_restoredTurn(t));
      }
      state = state.copyWith(restored: items, restore: RestoreStatus.done);
    } on Object {
      if (generation == _generation) {
        _restoreStarted = false;
        state = state.copyWith(restore: RestoreStatus.failed);
      }
    }
  }

  /// One earlier turn as read-only items: what was said, what was done, what was answered.
  List<ChatItem> _restoredTurn(Json t) {
    final out = <ChatItem>[UserItem(_id(), str(t['text']))];
    for (final e in asJsonList(t['events'])) {
      switch (str(e['type'])) {
        case 'tool':
          // A request for approval draws nothing of its own: its card follows
          if (str(e['status']) == 'needs_approval') break;
          out.add(
            ToolItem(
              _id(),
              name: str(e['name']),
              status: str(e['status']),
              message: e['message'] is String ? str(e['message']) : null,
              data: e['data'],
              restored: true,
            ),
          );
        case 'card':
          out.add(
            CardItem(
              _id(),
              actionId: str(e['actionId']),
              summary: str(e['summary']),
              state: switch (str(e['status'])) {
                'pending' => CardState.waiting,
                'applied' => CardState.approved,
                'rejected' => CardState.declined,
                'failed' => CardState.failed,
                _ => CardState.expired,
              },
            ),
          );
        case 'fallback':
          out.add(NoticeItem(_id(), _words.chatAssistantDown));
      }
    }
    final reply = str(t['reply']);
    if (reply.trim().isNotEmpty) {
      out.add(AgentItem(_id(), reply));
    } else if (str(t['status']) == 'failed' && out.length == 1) {
      out.add(NoticeItem(_id(), _words.chatNoAnswer));
    }
    return out;
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
        _add(AgentItem(_agentId, more, streaming: true));
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
  }

  /// Sends one message. [ocrText] is text the phone read from a photo.
  Future<void> send(String text, {String? ocrText}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.busy) return;
    final messageId = newRequestId();
    // The retry below cuts the screen back to this message by its id, not by a position, so nothing arriving meanwhile can move it
    final userItemId = _id();
    _sentIds.add(messageId);
    _add(
      UserItem(
        userItemId,
        trimmed,
        photo: ocrText != null && ocrText.isNotEmpty,
      ),
    );
    state = state.copyWith(busy: true, phase: TurnPhase.waiting);
    _stopped = false;
    final abort = Completer<void>();
    _abort = abort;
    _resetTurn();
    try {
      for (var attempt = 0; attempt <= _retries; attempt++) {
        try {
          await for (final e
              in ref
                  .read(apiProvider)
                  .chat(
                    id: messageId,
                    text: trimmed,
                    ocrText: ocrText,
                    abort: abort.future,
                  )) {
            _handle(e);
          }
          // A stream that ends with no "done" was cut: ask again under the same id, as for any dropped connection
          // (a stream that ended with an "error" event is a server failure, not a dropped connection: asking again would run the turn again)
          if (!_sawDone && !_sawError && !_stopped) {
            throw const ApiException('NETWORK', 'The connection was lost.', 0);
          }
          break;
        } on ApiException catch (e) {
          if (_stopped) break;
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
          if (e.isNetwork && looksLikeExpense(trimmed)) {
            try {
              final box = ref.read(outboxProvider);
              await box.add('expense_from_text', <String, Object?>{
                'text': trimmed,
              });
              ref.read(outboxCountProvider.notifier).refresh();
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
          if (_stopped) break;
          _closeTurn(keepBusy: true);
          _add(NoticeItem(_id(), _words.chatNoticeFailed));
          break;
        }
      }
    } finally {
      _closeTurn();
      if (_stopped) _add(NoticeItem(_id(), _words.chatStopped));
      _stopped = false;
      _abort = null;
    }
  }

  /// Applies one event of the stream.
  void _handle(Json e) {
    switch (str(e['type'])) {
      case 'start':
        state = state.copyWith(phase: TurnPhase.waiting, clearTool: true);
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
        _add(
          ToolItem(
            _id(),
            name: str(e['name']),
            status: 'running',
            callId: str(e['id']),
            running: true,
          ),
        );
        state = state.copyWith(phase: TurnPhase.tool, toolName: str(e['name']));
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
          ),
        );
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
    final done = ToolItem(
      found?.id ?? _id(),
      name: str(e['name']),
      status: status,
      message: e['message'] is String ? str(e['message']) : null,
      data: e['data'],
      callId: callId,
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
}

final NotifierProvider<ChatNotifier, ChatState> chatProvider =
    NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
