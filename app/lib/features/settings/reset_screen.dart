// RESET DATA: CHOOSE A PART, SEE HOW MANY ROWS IT WOULD ERASE, COPY THE HISTORY FIRST IF WANTED, THEN CONFIRM WITH THE PHONE'S LOCK AND A TYPED WORD.
// Only this screen can erase. The assistant is never offered the action. It needs a connection and is never queued. Sign-in, settings and phones
// are always kept, so the person stays signed in.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/person_data.dart';
import '../../l10n/l10n.dart';
import '../../state/library.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../auth/lock_gate.dart';
import '../calendar/calendar_data.dart';
import '../money/account_detail_screen.dart';
import '../simulate/simulate_data.dart';

// -- TYPES -- //

class ResetScreen extends ConsumerStatefulWidget {
  const ResetScreen({super.key});

  @override
  ConsumerState<ResetScreen> createState() => _State();
}

class _State extends ConsumerState<ResetScreen> {
  // -- STATES -- //

  String? _scope;
  Json? _preview;
  bool _busy = false;
  final TextEditingController _typed = TextEditingController();

  // -- LIFECYCLES -- //

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  // -- FUNCTIONS -- //

  (String, String, String) _scopeWords(String scope) {
    final t = context.t;
    return switch (scope) {
      'money' => (t.resetScopeMoney, t.resetScopeMoneyLine, scope),
      'schedule' => (t.resetScopeSchedule, t.resetScopeScheduleLine, scope),
      'memory_and_chat' => (t.resetScopeMemory, t.resetScopeMemoryLine, scope),
      'audit' => (t.resetScopeAudit, t.resetScopeAuditLine, scope),
      _ => (t.resetScopeEverything, t.resetScopeEverythingLine, scope),
    };
  }

  Future<void> _choose(String scope) async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).verbJson(
        'data_reset_preview',
        <String, Object?>{'scope': scope},
      );
      if (!mounted) return;
      _typed.clear();
      setState(() {
        _scope = scope;
        _preview = r;
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      say(
        context,
        e.code == 'NETWORK'
            ? context.t.resetOnlineOnly
            : errorWords(e, context),
      );
    }
  }

  Future<void> _exportFirst() async {
    final t = context.t;
    try {
      final r = await ref.read(apiProvider).verbJson(
        'audit_export',
        <String, Object?>{'format': 'json'},
      );
      await Clipboard.setData(ClipboardData(text: str(r['body'])));
      if (mounted) say(context, t.resetExported);
    } on Object catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _erase() async {
    final t = context.t;
    final preview = _preview;
    final scope = _scope;
    if (preview == null || scope == null) return;
    if (_typed.text.trim() != str(preview['word'])) {
      say(context, t.resetWrongWord);
      return;
    }
    // Busy before the lock prompt, so a second tap cannot start a second erase
    if (_busy) return;
    setState(() => _busy = true);
    // The phone's own lock is asked first, so a borrowed phone cannot erase anything
    final unlocked = await ref.read(authenticateProvider)();
    if (!unlocked) {
      if (mounted) {
        setState(() => _busy = false);
        say(context, t.resetBiometric);
      }
      return;
    }
    try {
      final r = await ref.read(apiProvider).verbJson(
        'data_reset',
        <String, Object?>{
          'scope': scope,
          'token': str(preview['token']),
          'typed': _typed.text.trim(),
        },
      );
      final deleted = asJson(r['deleted']);
      final total = deleted.values.fold<int>(0, (a, b) => a + intOf(b));
      // Writes queued before the reset must not replay onto the empty account, and the saved calendar is old now
      final outbox = ref.read(outboxProvider);
      await outbox.clear();
      // The refused writes of the old data are part of what was reset
      await outbox.dismissFailed();
      ref.read(outboxCountProvider.notifier).refresh();
      // The pictures of sent messages are part of what was reset
      if (scope == 'memory_and_chat' || scope == 'everything') {
        try {
          await ref.read(chatPhotoStoreProvider).wipe();
        } on Object {
          // The reset itself is done; a folder that will not go is swept later
        }
      }
      // The notebook pages kept for offline reading are old now too
      if (scope == 'memory_and_chat' || scope == 'everything') {
        await ref.read(pageCacheProvider).wipe();
        ref
          ..invalidate(recentsProvider)
          ..invalidate(libraryProvider);
      }
      await ref.read(prefsProvider).remove(calendarCacheKey);
      // The saved time travel answers hold the old balances too
      for (final key in simulateCacheKeys) {
        await ref.read(prefsProvider).remove(key);
      }
      // The saved balances, summary and reminder bookkeeping are old as well
      final withChat = scope == 'memory_and_chat' || scope == 'everything';
      await clearPersonData(
        ref.read(prefsProvider),
        notebooks: withChat,
        photos: withChat,
      );
      ref
        ..invalidate(balancesProvider)
        ..invalidate(auditVerifyProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _preview = null;
        _scope = null;
      });
      say(context, t.resetDone(total));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      say(
        context,
        e.code == 'NETWORK'
            ? t.resetOnlineOnly
            : e.code == 'INVALID' || e.code == 'FORBIDDEN'
            ? t.resetExpired
            : errorWords(e, context),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      say(context, errorWords(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: Text(t.resetTitle)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          Text(t.resetLine, style: TextStyle(color: c.muted)),
          if (preview == null) ...<Widget>[
            SectionTitle(t.resetChoose),
            for (final scope in const <String>[
              'money',
              'schedule',
              'memory_and_chat',
              'audit',
              'everything',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PaperCard(
                  onTap: _busy ? null : () => _choose(scope),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _scopeWords(scope).$1,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              _scopeWords(scope).$2,
                              style: TextStyle(color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: c.muted),
                    ],
                  ),
                ),
              ),
          ] else
            ..._confirm(context, preview),
        ],
      ),
    );
  }

  List<Widget> _confirm(BuildContext context, Json preview) {
    final t = context.t;
    final c = context.colors;
    final counts = asJson(preview['counts']);
    final total = intOf(preview['total']);
    final word = str(preview['word']);
    final keeps = <String>[for (final k in asList(preview['keeps'])) str(k)]
        .join(', ');
    return <Widget>[
      SectionTitle(_scopeWords(_scope ?? '').$1),
      if (total == 0)
        Text(t.resetNothing)
      else ...<Widget>[
        Text(t.resetWillErase(total)),
        const SizedBox(height: 8),
        for (final e in counts.entries)
          if (intOf(e.value) > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(e.key.replaceAll('_', ' '))),
                  Text('${intOf(e.value)}'),
                ],
              ),
            ),
      ],
      const SizedBox(height: 8),
      Text(t.resetKeeps(keeps), style: TextStyle(color: c.muted)),
      const SizedBox(height: 16),
      OutlinedButton(onPressed: _exportFirst, child: Text(t.resetExportFirst)),
      const SizedBox(height: 16),
      if (total > 0) ...<Widget>[
        Field(
          controller: _typed,
          label: t.resetTypeWord(word),
          capitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.danger,
            foregroundColor: c.paper,
          ),
          onPressed: _busy ? null : _erase,
          child: Text(t.resetButton),
        ),
      ],
      TextButton(
        onPressed: () => setState(() {
          _preview = null;
          _scope = null;
        }),
        child: Text(t.resetBack),
      ),
    ];
  }
}
