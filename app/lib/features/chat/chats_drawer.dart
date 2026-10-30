// THE LIST OF CONVERSATIONS: A DRAWER WITH ONE NEW CHAT BUTTON, A SEARCH BOX, THE CHATS GROUPED BY WHEN THEY WERE LAST USED, AND THE ARCHIVE.
// Tapping a chat opens it and carries on there. A long press (or the "more" button) renames, pins or archives it. Nothing is ever deleted here.
// While Botler is answering a message the chats cannot be switched, so the rows are quiet and a Stop button is offered.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'chat_state.dart';
import 'chats_state.dart';

// -- CONSTANTS -- //

/// A search starts at two characters, like the server's.
const int _minSearch = 2;
const Duration _typingPause = Duration(milliseconds: 300);

// -- FUNCTIONS -- //

String _groupName(BuildContext context, ChatGroup g) => switch (g) {
  ChatGroup.pinned => context.t.chatsGroupPinned,
  ChatGroup.today => context.t.chatsGroupToday,
  ChatGroup.yesterday => context.t.chatsGroupYesterday,
  ChatGroup.week => context.t.chatsGroupWeek,
  ChatGroup.older => context.t.chatsGroupOlder,
};

/// When a chat was last used, short: the time today, the weekday this week, the date after that. In Manila time.
String whenLabel(BuildContext context, ChatSummary c, {DateTime? now}) {
  final locale = Localizations.localeOf(context).toString();
  final manila = c.lastActive.toUtc().add(const Duration(hours: 8));
  return switch (timeGroupOf(c.lastActive, now: now)) {
    ChatGroup.today => DateFormat.jm(locale).format(manila),
    ChatGroup.yesterday => context.t.chatsGroupYesterday,
    ChatGroup.week => DateFormat.E(locale).format(manila),
    _ => DateFormat.MMMd(locale).format(manila),
  };
}

/// The name a chat shows: its title, or a plain placeholder when it has none.
String chatName(BuildContext context, ChatSummary c) =>
    (c.title ?? '').trim().isEmpty ? context.t.chatsUntitled : c.title!;

/// Asks for a new name and saves it. Used by the drawer and by the title of the open chat. A failure keeps the sheet open with the words in it.
Future<void> renameWithSheet(
  BuildContext context, {
  required String current,
  required Future<void> Function(String title) save,
}) async {
  await showFormSheet<void>(
    context,
    title: context.t.chatsRenameTitle,
    builder: (sheet, close) => _RenameForm(
      initial: current,
      save: (title) async {
        try {
          await save(title);
          close(null);
        } catch (e) {
          if (sheet.mounted) say(sheet, errorWords(e, sheet));
        }
      },
    ),
  );
}

// -- TYPES -- //

class _RenameForm extends StatefulWidget {
  const _RenameForm({required this.initial, required this.save});

  final String initial;
  final Future<void> Function(String title) save;

  @override
  State<_RenameForm> createState() => _RenameFormState();
}

class _RenameFormState extends State<_RenameForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );
  bool _busy = false;
  bool _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final title = _name.text.trim();
    if (title.isEmpty || title.length > 80) {
      setState(() => _invalid = true);
      return;
    }
    setState(() {
      _invalid = false;
      _busy = true;
    });
    await widget.save(title);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _go(),
          decoration: InputDecoration(
            labelText: context.t.chatsRenameLabel,
            errorText: _invalid ? context.t.chatsRenameInvalid : null,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _go,
          child: Text(context.t.chatsRenameSave),
        ),
      ],
    );
  }
}

/// The drawer itself.
class ChatsDrawer extends ConsumerStatefulWidget {
  const ChatsDrawer({this.onOpened, super.key});

  /// Called after a chat was opened or started, so the screen can go to the end of it.
  final VoidCallback? onOpened;

  @override
  ConsumerState<ChatsDrawer> createState() => _ChatsDrawerState();
}

class _ChatsDrawerState extends ConsumerState<ChatsDrawer> {
  final TextEditingController _search = TextEditingController();
  Timer? _pause;
  String _query = '';
  bool _archive = false;

  @override
  void dispose() {
    _pause?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _typed(String words) {
    _pause?.cancel();
    _pause = Timer(_typingPause, () {
      if (mounted) setState(() => _query = words.trim());
    });
  }

  void _clearSearch() {
    _pause?.cancel();
    _search.clear();
    setState(() => _query = '');
  }

  /// Runs one action. True when it worked; a failure is said in words and the drawer stays as it was.
  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
      return false;
    }
  }

  Future<void> _open(ChatSummary c) async {
    final navigator = Navigator.of(context);
    final ok = await _run(() => ref.read(chatProvider.notifier).openChat(c.id));
    if (!ok || !mounted) return;
    widget.onOpened?.call();
    navigator.pop();
  }

  Future<void> _new() async {
    final navigator = Navigator.of(context);
    final ok = await _run(() => ref.read(chatProvider.notifier).startNew());
    if (!ok || !mounted) return;
    widget.onOpened?.call();
    navigator.pop();
  }

  Future<void> _actions(ChatSummary c) async {
    final t = context.t;
    final c0 = context.colors;
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: c0.paper,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(t.chatsRename),
              onTap: () => Navigator.of(s).pop('rename'),
            ),
            ListTile(
              leading: Icon(
                c.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(c.pinned ? t.chatsUnpin : t.chatsPin),
              onTap: () => Navigator.of(s).pop('pin'),
            ),
            ListTile(
              leading: Icon(
                c.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              title: Text(c.archived ? t.chatsRestore : t.chatsArchive),
              onTap: () => Navigator.of(s).pop('archive'),
            ),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    final actions = ref.read(chatActionsProvider);
    switch (pick) {
      case 'rename':
        await renameWithSheet(
          context,
          current: c.title ?? '',
          save: (title) async {
            await actions.rename(c.id, title);
            // The chat on screen shows its new name too
            if (ref.read(chatProvider).chatId == c.id) {
              await ref.read(chatProvider.notifier).rename(title);
            }
          },
        );
      case 'pin':
        await _run(() => actions.pin(c.id, pinned: !c.pinned));
      case 'archive':
        await _run(() => actions.archive(c.id, archived: !c.archived));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final chat = ref.watch(chatProvider);
    final searching = _query.length >= _minSearch;
    final AsyncValue<List<ChatSummary>> list = _archive
        ? ref.watch(archivedChatsProvider)
        : searching
        ? ref.watch(chatSearchProvider(_query))
        : ref.watch(chatListProvider);
    return Drawer(
      backgroundColor: c.paper,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: <Widget>[
                  if (_archive)
                    IconButton(
                      tooltip: t.chatsTitle,
                      onPressed: () => setState(() => _archive = false),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  Expanded(
                    child: Text(
                      _archive ? t.chatsArchivedTitle : t.chatsTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            if (!_archive) ...<Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: FilledButton.icon(
                  onPressed: chat.busy ? null : _new,
                  icon: const Icon(Icons.add_comment_outlined),
                  label: Text(t.chatsNew),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: _typed,
                  textInputAction: TextInputAction.search,
                  // A search box stays as typed
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    hintText: t.chatsSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty && _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: t.chatsSearchClear,
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
            ],
            if (chat.busy)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        t.chatsBusy,
                        style: TextStyle(color: c.muted),
                      ),
                    ),
                    TextButton(
                      onPressed: ref.read(chatProvider.notifier).stop,
                      child: Text(t.chatStop),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: AsyncBody<List<ChatSummary>>(
                value: list,
                onRetry: () => _archive
                    ? ref.invalidate(archivedChatsProvider)
                    : searching
                    ? ref.invalidate(chatSearchProvider(_query))
                    : ref.invalidate(chatListProvider),
                skeleton: const SkeletonPage(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SkeletonRows(count: 5),
                ),
                data: (chats) {
                  if (chats.isEmpty) {
                    return Note(
                      _archive
                          ? t.chatsArchivedEmpty
                          : searching
                          ? t.chatsNoResults
                          : t.chatsEmpty,
                    );
                  }
                  return _ChatRows(
                    chats: chats,
                    // A search lists its results newest first, without sections
                    grouped: !_archive && !searching,
                    activeId: chat.chatId,
                    busy: chat.busy,
                    onOpen: _open,
                    onMore: _actions,
                  );
                },
              ),
            ),
            if (!_archive)
              ListTile(
                minTileHeight: 52,
                leading: const Icon(Icons.archive_outlined),
                title: Text(t.chatsArchivedOpen),
                onTap: () => setState(() => _archive = true),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatRows extends StatelessWidget {
  const _ChatRows({
    required this.chats,
    required this.grouped,
    required this.activeId,
    required this.busy,
    required this.onOpen,
    required this.onMore,
  });

  final List<ChatSummary> chats;
  final bool grouped;
  final String? activeId;
  final bool busy;
  final void Function(ChatSummary chat) onOpen;
  final void Function(ChatSummary chat) onMore;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (grouped) {
      for (final g in ChatGroup.values) {
        final inGroup = chats.where((c) => groupOf(c) == g).toList();
        if (inGroup.isEmpty) continue;
        rows.add(SectionTitle(_groupName(context, g)));
        for (final chat in inGroup) {
          rows.add(_row(chat));
        }
      }
    } else {
      rows.addAll(chats.map(_row));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: rows,
    );
  }

  Widget _row(ChatSummary chat) => _ChatRow(
    key: ValueKey<String>('chat.${chat.id}'),
    chat: chat,
    active: chat.id == activeId,
    enabled: !busy,
    onTap: () => onOpen(chat),
    onMore: () => onMore(chat),
  );
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.active,
    required this.enabled,
    required this.onTap,
    required this.onMore,
    super.key,
  });

  final ChatSummary chat;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final name = chatName(context, chat);
    final when = whenLabel(context, chat);
    // The row opens the chat; the "more" button beside it is its own control, so a screen reader finds both
    return Material(
      color: active ? c.accentSoft : c.paper,
      borderRadius: BorderRadius.circular(14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              container: true,
              button: true,
              selected: active,
              enabled: enabled,
              label: context.t.chatsRowLabel(name, when),
              excludeSemantics: true,
              onTap: enabled ? onTap : null,
              onLongPress: onMore,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: enabled ? onTap : null,
                onLongPress: onMore,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
                    child: Opacity(
                      opacity: enabled || active ? 1 : 0.5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              if (chat.pinned)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.push_pin,
                                    size: 14,
                                    color: c.muted,
                                  ),
                                ),
                              if (chat.forked)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.call_split,
                                    size: 14,
                                    color: c.muted,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.bodyLarge?.copyWith(
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                when,
                                style: theme.bodySmall?.copyWith(
                                  color: c.muted,
                                  fontFeatures: tabular,
                                ),
                              ),
                            ],
                          ),
                          if (chat.preview.isNotEmpty)
                            Text(
                              chat.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodySmall?.copyWith(color: c.muted),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: context.t.chatsMore,
            onPressed: onMore,
            icon: Icon(Icons.more_horiz, color: c.muted),
          ),
        ],
      ),
    );
  }
}
