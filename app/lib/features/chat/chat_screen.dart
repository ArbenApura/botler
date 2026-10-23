// THE ONE SCREEN THE APP OPENS ON: THE SUMMARY CARD, THE CONVERSATION, AND A BOX TO TALK TO BOTLER BY TYPING, SPEAKING OR PHOTOGRAPHING A RECEIPT.
// One primary action: send. The menu holds everything else (accounts, bills, payday, history, agenda, memory, settings).

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/device.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../update/update_gate.dart';
import 'chat_group.dart';
import 'chat_items.dart';
import 'chat_start.dart';
import 'chat_state.dart';
import 'chats_drawer.dart';
import 'live_parts.dart';
import 'message_actions.dart';
import 'summary_card.dart';

// -- TYPES -- //

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

/// Within this many logical pixels of the end counts as "at the bottom".
const double _nearBottom = 48;

/// Scrolled this far above the newest words, a button brings the person back to them.
const double _farFromEnd = 320;

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final VoiceListener _listener = VoiceListener();
  String? _photoText;
  bool _hearing = false;

  /// Words typed and not sent, kept for each chat while the person looks at another one.
  final Map<String, String> _drafts = <String, String>{};

  /// Keep following the newest words (the person is at the bottom).
  bool _stick = true;

  /// The person has scrolled well above the newest words, so the jump button shows.
  final ValueNotifier<bool> _away = ValueNotifier<bool>(false);

  /// The keyboard height last seen, to tell when it opens.
  double _keyboard = 0;

  /// The keyboard shrinks the list from the bottom, so when it opens the newest words are brought back above it.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = View.of(context);
    final height = view.viewInsets.bottom / view.devicePixelRatio;
    final opened = height > _keyboard;
    _keyboard = height;
    if (opened) {
      // Typing a message means the person wants the end of the conversation in view
      _stick = true;
      _toEnd();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Bring back the recent conversation once the first frame is up. The notifier remembers it did, so a rebuild of this screen
    // (the lock screen, coming back from the menu) never asks again
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(chatProvider.notifier).restore());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _away.dispose();
    // Release the microphone if the screen goes away while listening
    unawaited(_listener.stop());
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A suggestion fills the message box and puts the cursor at its end. It never sends: that stays the person's own press.
  void _fill(String words) {
    _text.value = TextEditingValue(
      text: words,
      selection: TextSelection.collapsed(offset: words.length),
    );
    _focus.requestFocus();
  }

  /// Follows the newest words, but only while the person is at the bottom: scrolling up to read stays where it is.
  void _toEnd([int passes = 3]) {
    if (!_stick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stick && _scroll.hasClients) {
        // A jump, not an animation: many small ones a second would pile up and fight the person's finger
        final end = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(math.min(end, _answerTop() ?? end));
        // The rows below the screen are measured only once they are reached, so the end moves: look again until it settles
        if (passes > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients && _scroll.position.maxScrollExtent != end) {
              _toEnd(passes - 1);
            }
          });
        }
      }
    });
  }

  /// Marks the answer being written, so following the newest words can stop where that answer starts.
  final GlobalKey _answerKey = GlobalKey();

  /// The scroll position that puts the start of the answer being written at the top, or null when no answer is being written.
  /// A long answer is followed only until its first line reaches the top: the person reads from the start, not from the end.
  double? _answerTop() {
    final box = _answerKey.currentContext?.findRenderObject();
    if (box == null || !box.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(box, 0).offset;
  }

  /// The earlier conversation arrived above what the person is looking at: keep their place instead of letting the page jump.
  void _keepPlaceAfterRestore() {
    if (_stick || !_scroll.hasClients) return;
    final before = _scroll.position.maxScrollExtent;
    final at = _scroll.position.pixels;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || _stick) return;
      _scroll.jumpTo(at + (_scroll.position.maxScrollExtent - before));
    });
  }

  /// Decides from the person's own scrolling whether to keep following.
  bool _onScroll(ScrollNotification n) {
    // Only the conversation's own list, and only real movement (not a layout measurement), says whether the end is far away
    if ((n is ScrollUpdateNotification || n is ScrollEndNotification) &&
        n.depth == 0 &&
        n.metrics.axis == Axis.vertical) {
      _away.value = n.metrics.maxScrollExtent - n.metrics.pixels > _farFromEnd;
    }
    final byPerson =
        (n is ScrollUpdateNotification && n.dragDetails != null) ||
        n is ScrollEndNotification;
    // Only the conversation's own list counts, not the thinking panel's small scroller inside it
    if (byPerson && n.depth == 0 && n.metrics.axis == Axis.vertical) {
      _stick = n.metrics.maxScrollExtent - n.metrics.pixels < _nearBottom;
    }
    return false;
  }

  /// Brings the newest words back into view and follows them again.
  Future<void> _jumpToLatest() async {
    if (!_scroll.hasClients) return;
    _stick = true;
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    // The rows below were only measured on the way down, so the end moved: settle on the true end
    if (mounted) _toEnd();
  }

  /// Whether the person is well above the newest words, read from the list itself: an answer that grows the list moves the end without
  /// any scroll notification.
  void _syncAway() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final p = _scroll.position;
      _away.value = p.maxScrollExtent - p.pixels > _farFromEnd;
    });
  }

  /// A chat was opened or started from the drawer: show its end, and forget any half-written edit.
  void _opened() {
    _stick = true;
    _away.value = false;
    ref.read(editProvider.notifier).stop();
    _toEnd();
  }

  /// Names the open chat. The title in the bar opens this.
  Future<void> _rename() => renameWithSheet(
    context,
    current: ref.read(chatProvider).title ?? '',
    save: ref.read(chatProvider.notifier).rename,
  );

  Future<void> _openOrigin(String id) async {
    try {
      await ref.read(chatProvider.notifier).openChat(id);
      _opened();
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
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
    final editing = ref.read(editProvider);
    if (editing != null) {
      // Only new words can be sent as an edit
      if (text.isEmpty) return;
      // The words stay in the box until the server has made the branch; a failure leaves them there to try again
      final bool opened;
      try {
        opened = await ref
            .read(chatProvider.notifier)
            .branchBefore(editing.turnId);
      } catch (e) {
        if (mounted) say(context, errorWords(e, context));
        return;
      }
      if (!opened) return;
      // The branch exists: the edit is over (this also empties the box), and the new words go to it like any message
      ref.read(editProvider.notifier).stop();
      _opened();
      setState(() => _photoText = null);
      await ref.read(chatProvider.notifier).send(text);
      ref
        ..invalidate(syncProvider)
        ..invalidate(balancesProvider);
      return;
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
    ref.listen<EditTarget?>(editProvider, (prev, next) {
      if (next != null && next != prev) {
        _fill(next.text);
      } else if (next == null && prev != null) {
        _text.clear();
      }
    });
    ref.listen<ChatState>(chatProvider, (prev, next) {
      // Another chat came on screen: its own unsent words come back, and the ones in the box wait for their chat
      final from = prev?.chatId;
      final to = next.chatId;
      if (from != null && to != null && from != to) {
        // Words being edited belong to no draft
        if (ref.read(editProvider) == null && _text.text.isNotEmpty) {
          _drafts[from] = _text.text;
        }
        _fill(_drafts.remove(to) ?? '');
        if (_text.text.isEmpty) _focus.unfocus();
        // An edit belongs to the chat it was started in
        ref.read(editProvider.notifier).stop();
      }
      if ((prev?.restored.isEmpty ?? true) && next.restored.isNotEmpty) {
        _keepPlaceAfterRestore();
      }
      _toEnd();
      _syncAway();
    });
    // The earlier conversation, then a line, then what is happening now. The line shows only when there is something after it
    final shown = <ChatItem>[
      ...chat.restored,
      if (chat.restored.isNotEmpty && chat.items.isNotEmpty)
        const DividerItem(),
      ...chat.items,
    ];
    // "Working on it" shows until the answer starts; the thinking panel and a running tool row say it themselves once they exist
    final last = shown.isEmpty ? null : shown.last;
    // A run of identical quiet "Checked ..." lines is one line with a count
    final rows = groupQuietTools(shown);
    final working =
        chat.busy &&
        (chat.phase == TurnPhase.waiting ||
            chat.phase == TurnPhase.thinking ||
            // The first words are a moment away: no blank gap between the thinking and the answer
            (chat.phase == TurnPhase.writing &&
                !(last is AgentItem && last.streaming))) &&
        !(last is ThinkingItem && last.open);
    // Before anyone has said anything: the earlier chat coming, its retry line, or the greeting
    final showStart = shown.isEmpty && !working;
    // The summary card, then (in a branch) the line that says where it came from
    final forked = chat.forkedFrom != null;
    final lead = forked ? 2 : 1;
    return Scaffold(
      drawer: ChatsDrawer(onOpened: _opened),
      appBar: AppBar(
        leading: Builder(
          builder: (bar) => IconButton(
            tooltip: bar.t.chatsOpen,
            onPressed: () => Scaffold.of(bar).openDrawer(),
            icon: const Icon(Icons.forum_outlined),
          ),
        ),
        title: (chat.title ?? '').trim().isEmpty
            ? Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: 'B',
                      style: TextStyle(
                        color: c.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: 'otler'),
                  ],
                ),
              )
            : InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _rename,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      chat.title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      semanticsLabel: '${chat.title}, ${context.t.chatsRename}',
                    ),
                  ),
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
            tooltip: context.t.chatSummaryOpen,
            onPressed: () => showSummarySheet(context),
            icon: const Icon(Icons.account_balance_wallet_outlined),
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
            // A newer build, when one is ready and was not dismissed
            const UpdateBanner(),
            Expanded(
              child: Stack(
                children: <Widget>[
                  RefreshIndicator(
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
                        itemCount:
                            rows.length + lead + (working || showStart ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, i) {
                          if (i == 0) return const SummaryCard();
                          if (forked && i == 1) {
                            return _BranchNote(
                              from: chat.forkedFrom!,
                              onOpen: () => _openOrigin(chat.forkedFrom!.id),
                            );
                          }
                          if (i - lead == rows.length && showStart) {
                            return ChatStart(
                              status: chat.restore,
                              onPick: _fill,
                              onRetry: () => unawaited(
                                ref.read(chatProvider.notifier).restore(),
                              ),
                            );
                          }
                          if (i - lead == rows.length) {
                            return WorkingRow(
                              phase: chat.phase,
                              tool: chat.toolName,
                            );
                          }
                          final row = rows[i - lead];
                          return ChatItemView(
                            row.item,
                            more: row.more,
                            // Only the answer being written carries the marker
                            key:
                                row.item == last &&
                                    last is AgentItem &&
                                    last.streaming
                                ? _answerKey
                                : ValueKey<int>(row.item.id),
                          );
                        },
                      ),
                    ),
                  ),
                  // Back to the newest words, there only while the person has scrolled well above them
                  Positioned(
                    bottom: 12,
                    right: 16,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _away,
                      builder: (context, away, button) => IgnorePointer(
                        ignoring: !away,
                        child: AnimatedOpacity(
                          opacity: away ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: button,
                        ),
                      ),
                      child: Semantics(
                        key: const ValueKey<String>('jumpLatest'),
                        button: true,
                        label: context.t.chatJumpLatest,
                        excludeSemantics: true,
                        child: Material(
                          color: c.chip,
                          shape: CircleBorder(side: BorderSide(color: c.line)),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _jumpToLatest,
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(
                                Icons.arrow_downward,
                                size: 20,
                                color: c.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
            if (ref.watch(editProvider) != null)
              _EditingBar(onCancel: ref.read(editProvider.notifier).stop),
            _Composer(
              controller: _text,
              focus: _focus,
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

/// Says where a branch came from, and that what was saved before it stays saved. Tapping it goes back to the original.
class _BranchNote extends StatelessWidget {
  const _BranchNote({required this.from, required this.onOpen});

  final ForkOrigin from;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final name = (from.title ?? '').trim().isEmpty
        ? t.chatsBranchedUntitled
        : from.title!;
    return Semantics(
      container: true,
      button: true,
      label: t.chatsBranchedOpen,
      excludeSemantics: true,
      onTap: onOpen,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.call_split, size: 16, color: c.muted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        t.chatsBranchedFrom(name),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: c.ink),
                      ),
                      Text(
                        t.chatsBranchedNote,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Above the box while a message is being edited: what is happening, and a way out.
class _EditingBar extends StatelessWidget {
  const _EditingBar({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: <Widget>[
          Icon(Icons.edit_outlined, size: 16, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.t.chatEditing,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.muted),
            ),
          ),
          IconButton(
            tooltip: context.t.chatEditCancel,
            onPressed: onCancel,
            icon: Icon(Icons.close, size: 20, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.hearing,
    required this.onSend,
    required this.onStop,
    required this.onSpeak,
    required this.onPhoto,
  });

  final TextEditingController controller;
  final FocusNode focus;
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
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
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
