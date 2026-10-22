// THE ONE SCREEN THE APP OPENS ON: THE SUMMARY CARD, THE CONVERSATION, AND A BOX TO TALK TO BOTLER BY TYPING, SPEAKING OR PHOTOGRAPHING A RECEIPT.
// One primary action: send. The menu holds everything else (accounts, bills, payday, history, agenda, memory, settings).

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/device.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'chat_items.dart';
import 'chat_state.dart';
import 'live_parts.dart';
import 'summary_card.dart';

// -- TYPES -- //

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

/// Within this many logical pixels of the end counts as "at the bottom".
const double _nearBottom = 48;

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final VoiceListener _listener = VoiceListener();
  String? _photoText;
  bool _hearing = false;

  /// Keep following the newest words (the person is at the bottom).
  bool _stick = true;

  @override
  void dispose() {
    // Release the microphone if the screen goes away while listening
    unawaited(_listener.stop());
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Follows the newest words, but only while the person is at the bottom: scrolling up to read stays where it is.
  void _toEnd() {
    if (!_stick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stick && _scroll.hasClients) {
        // A jump, not an animation: many small ones a second would pile up and fight the person's finger
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// Decides from the person's own scrolling whether to keep following.
  bool _onScroll(ScrollNotification n) {
    final byPerson =
        (n is ScrollUpdateNotification && n.dragDetails != null) ||
        n is ScrollEndNotification;
    // Only the conversation's own list counts, not the thinking panel's small scroller inside it
    if (byPerson && n.depth == 0 && n.metrics.axis == Axis.vertical) {
      _stick = n.metrics.maxScrollExtent - n.metrics.pixels < _nearBottom;
    }
    return false;
  }

  Future<void> _send() async {
    // A turn is running: the words stay in the box instead of being lost
    if (ref.read(chatProvider).busy) return;
    final text = _text.text.trim();
    final photo = _photoText;
    final receipt = context.t.chatReceiptMessage;
    if (text.isEmpty && photo == null) return;
    // Sending always brings the newest words into view
    _stick = true;
    // The keyboard goes away with the message, and a dictation still running is stopped so it cannot refill the box
    FocusManager.instance.primaryFocus?.unfocus();
    if (_hearing) {
      await _listener.stop();
      if (mounted) setState(() => _hearing = false);
    }
    _text.clear();
    setState(() => _photoText = null);
    await ref
        .read(chatProvider.notifier)
        .send(text.isEmpty ? receipt : text, ocrText: photo);
    ref
      ..invalidate(syncProvider)
      ..invalidate(balancesProvider);
  }

  Future<void> _photo(PhotoSource source) async {
    try {
      final read = await readPhotoText(source);
      if (read == null || !mounted) return;
      if (read.isEmpty) {
        say(context, context.t.chatPhotoEmpty);
        return;
      }
      setState(() => _photoText = read);
    } catch (_) {
      if (mounted) say(context, context.t.chatPhotoFailed);
    }
  }

  Future<void> _speak() async {
    if (_hearing) {
      await _listener.stop();
      setState(() => _hearing = false);
      return;
    }
    final locale = ref.read(settingsProvider).speechLocale;
    // Set before the first word can arrive, so a late result after stop is ignored
    setState(() => _hearing = true);
    final ok = await _listener.start(
      locale,
      (words, {required finished}) {
        if (!mounted || !_hearing) return;
        _text.text = words;
        _text.selection = TextSelection.collapsed(offset: words.length);
        if (finished) setState(() => _hearing = false);
      },
      onEnded: () {
        if (mounted && _hearing) setState(() => _hearing = false);
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _hearing = false);
      say(context, context.t.chatMicBlocked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chat = ref.watch(chatProvider);
    final pending = ref.watch(outboxCountProvider);
    ref.listen<ChatState>(chatProvider, (_, _) => _toEnd());
    // "Working on it" shows until the answer starts; the thinking panel and a running tool row say it themselves once they exist
    final last = chat.items.isEmpty ? null : chat.items.last;
    final working =
        chat.busy &&
        (chat.phase == TurnPhase.waiting ||
            chat.phase == TurnPhase.thinking ||
            // The first words are a moment away: no blank gap between the thinking and the answer
            (chat.phase == TurnPhase.writing &&
                !(last is AgentItem && last.streaming))) &&
        !(last is ThinkingItem && last.open);
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: 'B',
                style: TextStyle(color: c.accent, fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: 'otler'),
            ],
          ),
        ),
        actions: <Widget>[
          if (pending > 0)
            IconButton(
              tooltip: context.t.chatPendingTooltip(pending),
              onPressed: () =>
                  say(context, context.t.chatPendingSnack(pending)),
              icon: Badge(
                label: Text('$pending'),
                child: const Icon(Icons.cloud_off_outlined),
              ),
            ),
          IconButton(
            tooltip: context.t.chatMenu,
            onPressed: () => context.push('/menu'),
            icon: const Icon(Icons.menu),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(syncProvider);
                  await ref.read(syncProvider.future);
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: ListView.separated(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: chat.items.length + 1 + (working ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      if (i == 0) return const SummaryCard();
                      if (i - 1 == chat.items.length) {
                        return WorkingRow(
                          phase: chat.phase,
                          tool: chat.toolName,
                        );
                      }
                      return ChatItemView(
                        chat.items[i - 1],
                        key: ValueKey<int>(chat.items[i - 1].id),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_photoText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: InputChip(
                  label: Text(context.t.chatPhotoRead(_photoText!.length)),
                  onDeleted: () => setState(() => _photoText = null),
                ),
              ),
            _Composer(
              controller: _text,
              busy: chat.busy,
              hearing: _hearing,
              onSend: _send,
              onStop: ref.read(chatProvider.notifier).stop,
              onSpeak: _speak,
              onPhoto: () async {
                final source = await showModalBottomSheet<PhotoSource>(
                  context: context,
                  showDragHandle: true,
                  backgroundColor: c.paper,
                  builder: (s) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ListTile(
                          leading: const Icon(Icons.photo_camera_outlined),
                          title: Text(s.t.chatTakePhoto),
                          onTap: () => Navigator.of(s).pop(PhotoSource.camera),
                        ),
                        ListTile(
                          leading: const Icon(Icons.photo_outlined),
                          title: Text(s.t.chatChooseScreenshot),
                          onTap: () => Navigator.of(s).pop(PhotoSource.gallery),
                        ),
                      ],
                    ),
                  ),
                );
                if (source != null) await _photo(source);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.hearing,
    required this.onSend,
    required this.onStop,
    required this.onSpeak,
    required this.onPhoto,
  });

  final TextEditingController controller;
  final bool busy;
  final bool hearing;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onSpeak;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // One soft pill: photo and voice inside it, a round send button at the end. The field has no border of its own.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            IconButton(
              tooltip: context.t.chatPhotoTooltip,
              onPressed: busy ? null : onPhoto,
              icon: Icon(Icons.add_photo_alternate_outlined, color: c.muted),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: context.t.chatHintMessage,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintStyle: TextStyle(color: c.muted),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: hearing
                  ? context.t.chatStopListening
                  : context.t.chatSpeak,
              onPressed: busy ? null : onSpeak,
              icon: Icon(
                hearing ? Icons.stop_circle_outlined : Icons.mic_none,
                color: hearing ? c.danger : c.muted,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              // The one primary action: send, and while a turn runs the same button stops it
              child: IconButton.filled(
                tooltip: busy ? context.t.chatStop : context.t.chatSend,
                onPressed: busy ? onStop : onSend,
                icon: Icon(busy ? Icons.stop_rounded : Icons.arrow_upward),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
