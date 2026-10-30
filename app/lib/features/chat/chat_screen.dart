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
import '../../core/chat_photos.dart';
import '../../core/device.dart';
import '../../core/photo_budget.dart';
import '../../core/photo_upload.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../settings/photo_mode_row.dart';
import '../update/changelog_sheet.dart';
import '../update/update_gate.dart';
import 'chat_group.dart';
import 'chat_items.dart';
import 'chat_start.dart';
import 'chat_state.dart';
import 'chats_drawer.dart';
import 'live_parts.dart';
import 'message_actions.dart';
import 'photo_widgets.dart';
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

  /// The photos read for the next message, in the order they were added.
  final List<PhotoNote> _photos = <PhotoNote>[];

  /// Photos copied and shown, still being read. They have a tile with a spinner; sending waits for them.
  final List<String> _pending = <String>[];

  /// Where each copy came from, so a picture chosen twice is added once.
  final Map<String, String> _sourceOf = <String, String>{};

  /// The strip was showing at the last build: it appearing or going moves the end of the list.
  bool _stripShown = false;

  /// Photos are being read: sending waits for them.
  bool _reading = false;

  /// The pictures of a message are being made ready to send: sending waits for them.
  bool _preparing = false;
  bool _hearing = false;

  /// Words typed and not sent, kept for each chat while the person looks at another one.
  final Map<String, String> _drafts = <String, String>{};

  /// Keep following the newest words (the person is at the bottom).
  bool _stick = true;

  /// The person has scrolled well above the newest words, so the jump button shows.
  final ValueNotifier<bool> _away = ValueNotifier<bool>(false);

  /// The photo store last used, so the copies still on the strip can be deleted when this screen goes away.
  ChatPhotoStore? _store;

  /// The keyboard height last seen, to tell when it opens.
  double _keyboard = 0;

  /// The keyboard shrinks the list from the bottom, so when it opens the newest words are kept above it, but only for someone who was
  /// already at the bottom. A person reading older messages keeps their place.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = View.of(context);
    final height = view.viewInsets.bottom / view.devicePixelRatio;
    final opened = height > _keyboard;
    _keyboard = height;
    if (opened && _stick) {
      _readFromStart = false;
      _toEnd();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Mounted while a turn runs (back from the menu): what is on screen already belongs to earlier answers
    _earlier = _answerIds(ref.read(chatProvider));
    // Bring back the recent conversation once the first frame is up. The notifier remembers it did, so a rebuild of this screen
    // (the lock screen, coming back from the menu) never asks again
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(chatProvider.notifier).restore());
      // What is new after an update: once per run, never over the lock or the required-update screen (this screen is below both)
      unawaited(showPendingChangelog(context, ref));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Photos chosen and never sent are not kept
    final left = <String>[for (final p in _photos) p.path, ..._pending];
    if (left.isNotEmpty)
      unawaited(_store?.discard(left) ?? Future<void>.value());
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
        final top = _answerTop();
        // Never backwards: someone who has read on past the answer's first line is followed to the end instead
        final held = top != null && _scroll.position.pixels <= top + 1;
        _scroll.jumpTo(held ? math.min(end, top) : end);
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

  /// A turn has run since the person last sent, opened a chat or asked for the end: follow stops at the answer's first line, also after it is done.
  bool _readFromStart = false;

  /// The answers that were already there when the running turn began. Only an answer outside this set is anchored: while the
  /// assistant is still thinking or using tools the page follows the end as usual, instead of rising to the previous answer.
  Set<int> _earlier = <int>{};

  /// The ids of the answers on screen.
  Set<int> _answerIds(ChatState chat) => <ChatItem>[
    ...chat.restored,
    ...chat.items,
  ].whereType<AgentItem>().map((a) => a.id).toSet();

  /// The scroll position that puts the start of the answer being written at the top, or null when no answer is being written.
  /// A long answer is followed only until its first line reaches the top: the person reads from the start, not from the end.
  double? _answerTop() {
    if (!_readFromStart) return null;
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
      // Back at the bottom by hand with nothing running: the answer no longer holds the page
      if (_stick && !ref.read(chatProvider).busy) _readFromStart = false;
    }
    return false;
  }

  /// Brings the newest words back into view and follows them again.
  Future<void> _jumpToLatest() async {
    if (!_scroll.hasClients) return;
    _stick = true;
    _readFromStart = false;
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
    _readFromStart = false;
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
    // A photo still being read would be left out of the message
    if (_reading || _preparing) {
      say(context, context.t.chatPhotosWait);
      return;
    }
    final text = _text.text.trim();
    // Whether the pictures themselves go with this message: the person chose them AND the server says its AI server reads them. Decided now, at
    // the moment of sending, whatever it was when the photos were picked
    var usePictures = ref.read(settingsProvider).usesPictures;
    // Pictures going for the first time, when the choice was made after the photos were picked: the person is told once, and may say no
    if (usePictures &&
        _photos.isNotEmpty &&
        ref.read(editProvider) == null &&
        !await pictureNoticeAccepted(context, ref)) {
      usePictures = false;
    }
    if (!mounted) return;
    // Without the pictures a photo is worth its text only, so the ones that held none are left out
    final usable = <PhotoNote>[
      for (final p in _photos)
        if (usePictures || p.text.isNotEmpty) p,
    ];
    if (text.isEmpty && usable.isEmpty) {
      if (_photos.isNotEmpty) say(context, context.t.chatPhotoEmpty);
      return;
    }
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
      // The photos stay on their chips for the next message: an edit sends only the new words
      await ref.read(chatProvider.notifier).send(text);
      ref
        ..invalidate(syncProvider)
        ..invalidate(balancesProvider);
      return;
    }
    final chatId = ref.read(chatProvider).chatId;
    // The words leave the box now, so anything typed while the pictures are made ready belongs to the next message
    _text.clear();
    // The pictures are made ready first, one at a time, with the strip locked: a picture that cannot be made is sent as its text, and a photo
    // that has neither its picture nor any text has nothing to send
    var images = <String>[];
    var sendable = usable;
    if (usePictures) {
      setState(() => _preparing = true);
      final made = await prepareUploads(<String>[
        for (final p in usable) p.path,
      ], cancelled: () => !mounted);
      if (!mounted) return;
      setState(() => _preparing = false);
      // Another chat came on screen meanwhile: this message is not sent from it, and its words go back
      if (ref.read(chatProvider).chatId != chatId) {
        if (_text.text.isEmpty) _text.text = text;
        return;
      }
      sendable = <PhotoNote>[
        for (var i = 0; i < usable.length; i++)
          if (made[i] != null || usable[i].text.isNotEmpty) usable[i],
      ];
      images = <String>[
        for (final m in made)
          if (m != null) m.data,
      ];
      if (made.any((m) => m == null)) {
        say(
          context,
          sendable.length < usable.length
              ? context.t.chatPhotosSkipped(usable.length - sendable.length)
              : context.t.chatPictureSkipped,
        );
      }
      if (text.isEmpty && sendable.isEmpty) {
        _dropPhotos();
        return;
      }
    }
    if (!mounted) return;
    final photos = fitPhotoTexts(<String>[
      for (final p in sendable)
        if (p.text.isNotEmpty) p.text,
    ]);
    final receipt = usePictures && sendable.isNotEmpty
        ? context.t.chatPhotoOnlyMessage
        : context.t.chatReceiptMessage;
    final sent = <String>[for (final p in sendable) p.path];
    final left = <String>[
      for (final p in _photos)
        if (!sendable.contains(p)) p.path,
    ];
    // The copies now belong to the message being sent; those left out (no text, and no picture to send) are deleted
    setState(() {
      _photos.clear();
      _sourceOf.clear();
    });
    if (left.isNotEmpty && mounted) {
      unawaited(ref.read(chatPhotoStoreProvider).discard(left));
      if (!usePictures) say(context, context.t.chatPhotosSkipped(left.length));
    }
    if (photos.trimmed && mounted) say(context, context.t.chatPhotosTrimmed);
    await ref
        .read(chatProvider.notifier)
        .send(
          text.isEmpty ? receipt : text,
          photoTexts: photos.texts,
          photoPaths: sent,
          images: images,
        );
    ref
      ..invalidate(syncProvider)
      ..invalidate(balancesProvider);
  }

  /// Forgets every photo chosen for the next message and deletes their copies.
  void _dropPhotos() {
    final copies = <String>[for (final p in _photos) p.path, ..._pending];
    setState(() {
      _photos.clear();
      _pending.clear();
      _sourceOf.clear();
    });
    unawaited(ref.read(chatPhotoStoreProvider).discard(copies));
  }

  /// Takes the photo at [index] of the strip (the ones read first, then the ones still being read) off the next message.
  void _removePhoto(int index) {
    // Nothing on the strip changes while the pictures are made ready
    if (_preparing) return;
    final String copy;
    if (index < _photos.length) {
      copy = _photos[index].path;
    } else {
      copy = _pending[index - _photos.length];
    }
    setState(() {
      _photos.removeWhere((p) => p.path == copy);
      _pending.remove(copy);
      _sourceOf.remove(copy);
    });
    unawaited(ref.read(chatPhotoStoreProvider).discard(<String>[copy]));
  }

  /// Adds photos to the next message: one from the camera or several from the gallery. They are read one after another on the phone,
  /// the ones that hold no text are left out and counted, and a picture chosen twice is added once.
  Future<void> _photo(PhotoSource source) async {
    if (_reading || _preparing) return;
    // The photos wait while a message is edited: an edit sends only new words
    if (ref.read(editProvider) != null) {
      say(context, context.t.chatPhotoEditing);
      return;
    }
    final room = maxPhotos - _photos.length;
    if (room <= 0) {
      say(context, context.t.chatPhotosLimit(maxPhotos));
      return;
    }
    // The first time pictures would go, the person is told once that a picture is sent as it is, and may choose text only instead
    var pictures = ref.read(settingsProvider).usesPictures;
    if (pictures && !await pictureNoticeAccepted(context, ref))
      pictures = false;
    if (!mounted) return;
    final reader = PhotoReader();
    final store = ref.read(chatPhotoStoreProvider);
    _store = store;
    final chatId = ref.read(chatProvider).chatId;
    var picked = 0;
    var unread = 0;
    var failed = false;
    // The copies this pick made that are not yet read or dropped
    final staged = <String>[];
    try {
      final paths = await pickPhotos(source, room: room);
      if (paths.isEmpty || !mounted) return;
      picked = paths.length;
      setState(() => _reading = true);
      // Every picture is copied first (the picker's own copy can be cleared by the phone) so its tile shows at once, then read one by one
      for (final path in paths) {
        if (staged.length + _photos.length + _pending.length >= maxPhotos) {
          break;
        }
        if (_sourceOf.containsValue(path)) continue;
        final copy = await store.stage(path);
        if (copy == null) {
          unread++;
          continue;
        }
        staged.add(copy);
        // Gone from the screen, or the person moved to another chat meanwhile: nothing of this pick is kept
        if (!mounted || ref.read(chatProvider).chatId != chatId) return;
        _sourceOf[copy] = path;
        setState(() => _pending.add(copy));
      }
      for (final copy in List<String>.of(staged)) {
        if (!mounted) return;
        // Removed by the person while waiting
        if (!_pending.contains(copy)) {
          staged.remove(copy);
          continue;
        }
        try {
          final text = await reader.read(copy);
          if (!mounted) return;
          // The person moved to another chat while this was read: the photo is left out
          if (ref.read(chatProvider).chatId != chatId) return;
          // Removed during the read: not an unreadable photo, the person took it off
          if (!_pending.contains(copy)) {
            staged.remove(copy);
            continue;
          }
          staged.remove(copy);
          // A picture with no words on it (a dish, a chart, a handwritten note) is still worth sending when the picture itself goes
          if (text.isEmpty && !pictures) {
            unread++;
            setState(() {
              _pending.remove(copy);
              _sourceOf.remove(copy);
            });
            unawaited(store.discard(<String>[copy]));
          } else {
            setState(() {
              _pending.remove(copy);
              _photos.add(PhotoNote(copy, text));
            });
          }
        } on Object {
          // One photo that cannot be read does not stop the others
          staged.remove(copy);
          if (_pending.contains(copy)) unread++;
          if (mounted) {
            setState(() {
              _pending.remove(copy);
              _sourceOf.remove(copy);
            });
          }
          unawaited(store.discard(<String>[copy]));
        }
      }
    } on Object {
      failed = true;
    } finally {
      await reader.close();
      // Copies left over (a chat switch, the screen going away, an error) are deleted and leave the strip
      if (staged.isNotEmpty) {
        if (mounted) {
          setState(() {
            _pending.removeWhere(staged.contains);
            staged.forEach(_sourceOf.remove);
          });
        }
        unawaited(store.discard(staged));
      }
      if (mounted) setState(() => _reading = false);
    }
    if (!mounted) return;
    if (failed) {
      say(context, context.t.chatPhotoFailed);
    } else if (unread > 0) {
      say(
        context,
        picked == 1
            ? context.t.chatPhotoEmpty
            : context.t.chatPhotosSkipped(unread),
      );
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
    // While a message is edited the photos wait out of sight: an edit sends only new words
    final stripShown =
        (_photos.isNotEmpty || _pending.isNotEmpty) &&
        ref.watch(editProvider) == null;
    if (stripShown != _stripShown) {
      _stripShown = stripShown;
      // The strip shrinks or grows the list from the bottom: a person at the end stays at the end
      _toEnd();
    }
    // With the net on the money is kept ready while the chat is open: the drawer's accounts and the wallet sheet then open with their numbers,
    // with no skeleton and no jump
    if (ref.watch(settingsProvider.select((s) => s.showNetBalance))) {
      ref.listen(balancesProvider, (_, _) {});
      ref.listen(assetsProvider, (_, _) {});
    }
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
        // Photos belong to the chat they were added in: receipts for one conversation never go into another
        if (_photos.isNotEmpty || _pending.isNotEmpty) _dropPhotos();
      }
      if ((prev?.restored.isEmpty ?? true) && next.restored.isNotEmpty) {
        _keepPlaceAfterRestore();
      }
      if (next.busy && !(prev?.busy ?? false)) {
        // A turn begins: armed once, so a reset by the keyboard or the jump button is not undone by the next chunk
        _readFromStart = true;
        _earlier = _answerIds(next);
      } else if (next.busy && !identical(prev?.restored, next.restored)) {
        // Earlier conversation arriving while the turn runs is not part of this turn's answer
        _earlier = <int>{..._earlier, ..._answerIds(next)};
      } else if (!next.busy && !(prev?.busy ?? false)) {
        // Long after the turn, a change (an undo, a rename) must not pull the page back up to the answer
        _readFromStart = false;
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
    // The newest answer of this turn holds the page only while it is the last row: a tool or approval row after it is followed
    final tail = rows.isEmpty ? null : rows.last.item;
    final lastAnswer = tail is AgentItem && !_earlier.contains(tail.id)
        ? tail
        : null;
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
                            // Only the newest answer carries the marker
                            key: row.item == lastAnswer
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
            if (stripShown)
              PhotoStrip(
                photos: <StripPhoto>[
                  for (final p in _photos) StripPhoto(p.path, p.text.length),
                  for (final p in _pending) StripPhoto(p, null),
                ],
                onRemove: _removePhoto,
              ),
            if (_preparing)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.t.chatPicturePreparing,
                    style: TextStyle(color: c.muted),
                  ),
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
