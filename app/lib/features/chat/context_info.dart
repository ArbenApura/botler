// HOW FULL THE OPEN CHAT'S CONTEXT IS, AT ITS LAST ANSWER: NUMBERS ONLY. The server reports the prompt size of the last model call and the window it is measured against
// (a live usage event while a message runs, the done event, and chat_history when a chat is brought back). Unknown means the ring stays hidden.

// -- DEP-MODULES -- //
import 'package:flutter/foundation.dart';

// -- MODULES -- //
import '../../core/json.dart';

// -- TYPES -- //

/// How the ring is coloured: the accent while there is plenty of room, `warning` from 70 percent, `danger` from 90 (never the accent for a status).
enum ContextLevel { calm, warning, danger }

@immutable
class ContextInfo {
  const ContextInfo({
    required this.tokens,
    required this.window,
    this.summarizedAt,
  });

  /// The size of the last prompt, in tokens, as the host reported it.
  final int tokens;

  /// The window it is measured against, in tokens.
  final int window;

  /// When the earlier part of this chat was last folded into its summary, if ever.
  final DateTime? summarizedAt;

  /// The share used, 0 to 1.
  double get share => window <= 0 ? 0 : (tokens / window).clamp(0.0, 1.0);

  /// The whole percent shown in words. Never 0 once something is used, so "0 percent full" is never said of a chat that has begun.
  int get percent {
    if (tokens <= 0 || window <= 0) return 0;
    return (share * 100).round().clamp(1, 100);
  }

  ContextLevel get level => share >= 0.9
      ? ContextLevel.danger
      : share >= 0.7
      ? ContextLevel.warning
      : ContextLevel.calm;

  ContextInfo copyWith({int? tokens, int? window, DateTime? summarizedAt}) =>
      ContextInfo(
        tokens: tokens ?? this.tokens,
        window: window ?? this.window,
        summarizedAt: summarizedAt ?? this.summarizedAt,
      );

  /// From the chat head chat_history answers with. Null when the server has no figure for this chat yet (the ring stays hidden).
  static ContextInfo? fromHead(Json head) {
    final tokens = head['contextTokens'];
    final window = head['contextWindow'];
    if (tokens is! int || window is! int || window <= 0) return null;
    final at = head['summarizedAt'];
    return ContextInfo(
      tokens: tokens,
      window: window,
      summarizedAt: at is String ? DateTime.tryParse(at) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ContextInfo &&
      other.tokens == tokens &&
      other.window == window &&
      other.summarizedAt == summarizedAt;

  @override
  int get hashCode => Object.hash(tokens, window, summarizedAt);
}
