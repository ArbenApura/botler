// THE CHAT: WHAT IS ON THE SCREEN (THE PERSON'S MESSAGES, THE ASSISTANT'S PLAIN TEXT, WHAT IT DID, CARDS TO APPROVE) AND HOW A MESSAGE IS SENT.
// A message has an id the phone chooses. If the connection drops, the same id is sent again and the server replays the stored answer, so the assistant
// never does the same thing twice. An expense typed with no connection is kept in the outbox and sent later with its own request id.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../state/providers.dart';

// -- TYPES -- //

enum CardState { waiting, approved, declined, failed }

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

/// Something the assistant did or looked up. [data] is the verb's answer, shown by a card or chip when it has one.
final class ToolItem extends ChatItem {
  const ToolItem(
    super.id, {
    required this.name,
    required this.status,
    this.message,
    this.data,
    this.resolved = false,
  });

  final String name;

  /// ok, error, needs_approval or blocked
  final String status;
  final String? message;
  final Object? data;

  /// The chip on this item was answered (confirmed, chosen or undone).
  final bool resolved;

  ToolItem answered({Object? data}) => ToolItem(
    id,
    name: name,
    status: status,
    message: message,
    data: data ?? this.data,
    resolved: true,
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

class ChatState {
  const ChatState({this.items = const <ChatItem>[], this.busy = false});

  final List<ChatItem> items;
  final bool busy;

  ChatState copyWith({List<ChatItem>? items, bool? busy}) =>
      ChatState(items: items ?? this.items, busy: busy ?? this.busy);
}

// -- CONSTANTS -- //

/// How many times a dropped message is sent again, and how long to wait between.
const int _retries = 3;
const Duration _retryWait = Duration(seconds: 2);

// -- FUNCTIONS -- //

/// True when the text has a number in it, so it may be an expense that can be kept for later without the assistant.
bool looksLikeExpense(String text) => RegExp(r'\d').hasMatch(text);

class ChatNotifier extends Notifier<ChatState> {
  int _next = 0;

  @override
  ChatState build() => const ChatState();

  int _id() => _next++;

  void _add(ChatItem item) =>
      state = state.copyWith(items: <ChatItem>[...state.items, item]);

  void _replace(int id, ChatItem Function(ChatItem old) change) {
    state = state.copyWith(
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

  /// Sends one message. [ocrText] is text the phone read from a photo.
  Future<void> send(String text, {String? ocrText}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.busy) return;
    final messageId = newRequestId();
    _add(
      UserItem(_id(), trimmed, photo: ocrText != null && ocrText.isNotEmpty),
    );
    state = state.copyWith(busy: true);
    var turnStart = state.items.length;
    var agentId = -1;
    for (var attempt = 0; attempt <= _retries; attempt++) {
      try {
        await for (final e
            in ref
                .read(apiProvider)
                .chat(id: messageId, text: trimmed, ocrText: ocrText)) {
          agentId = _handle(e, agentId);
        }
        break;
      } on ApiException catch (e) {
        // A repeat of a finished message is answered from storage, so it is safe to ask again; start the turn's items over
        final again =
            (e.isNetwork || e.code == 'CONFLICT') && attempt < _retries;
        if (again) {
          state = state.copyWith(items: state.items.sublist(0, turnStart));
          agentId = -1;
          await Future<void>.delayed(_retryWait);
          continue;
        }
        if (e.isNetwork && looksLikeExpense(trimmed)) {
          final box = ref.read(outboxProvider);
          await box.add('expense_from_text', <String, Object?>{
            'text': trimmed,
          });
          ref.read(outboxCountProvider.notifier).refresh();
          _add(
            NoticeItem(
              _id(),
              'No connection. Saved on your phone. It will be sent once, when you are back online.',
            ),
          );
        } else {
          _add(NoticeItem(_id(), e.message));
        }
        break;
      }
    }
    // Close any text that is still marked as streaming
    state = state.copyWith(
      busy: false,
      items: <ChatItem>[
        for (final i in state.items)
          i is AgentItem && i.streaming ? i.done() : i,
      ],
    );
    turnStart = state.items.length;
  }

  /// Applies one event of the stream. Returns the id of the assistant text being written, or -1.
  int _handle(Json e, int agentId) {
    switch (str(e['type'])) {
      case 'delta':
        final more = str(e['text']);
        final last = state.items.isEmpty ? null : state.items.last;
        if (agentId >= 0 && last is AgentItem && last.id == agentId) {
          _replace(agentId, (old) => old is AgentItem ? old.grow(more) : old);
          return agentId;
        }
        final id = _id();
        _add(AgentItem(id, more, streaming: true));
        return id;
      case 'tool':
        _add(
          ToolItem(
            _id(),
            name: str(e['name']),
            status: str(e['status']),
            message: e['message'] is String ? str(e['message']) : null,
            data: e['data'],
          ),
        );
        return -1;
      case 'card':
        _add(
          CardItem(
            _id(),
            actionId: str(e['actionId']),
            summary: str(e['summary']),
          ),
        );
        return -1;
      case 'fallback':
        _add(FallbackItem(_id(), str(e['reason'])));
        return -1;
      case 'error':
        _add(
          NoticeItem(_id(), 'The assistant could not finish that. Try again.'),
        );
        return -1;
      default:
        return agentId;
    }
  }

  void notice(String text) => _add(NoticeItem(_id(), text));
}

final NotifierProvider<ChatNotifier, ChatState> chatProvider =
    NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
