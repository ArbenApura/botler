// ONE ACCOUNT: ITS BALANCE AND A TIMELINE OF EVERYTHING THAT HAPPENED TO IT, WHO DID IT AND WHERE, WITH THE RUNNING BALANCE.
// The timeline is read from the append-only audit trail, so it is complete and cannot be edited here. Setting a balance never deletes anything:
// the difference is written as a reset and the history keeps the old balance. A reset needs a connection and is never queued.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'accounts_screen.dart';
import 'audit_words.dart';

// -- CONSTANTS -- //

/// What the audit trail says about the whole chain, checked once per visit.
final FutureProvider<Json> auditVerifyProvider =
    FutureProvider.autoDispose<Json>(
      (ref) => ref.watch(apiProvider).verbJson('audit_verify'),
    );

// -- TYPES -- //

/// The filters the person chose. Who, dates and search go to the server; the tabs cut what was loaded.
class _Filter {
  const _Filter({this.by, this.from, this.to, this.search = ''});

  final String? by;
  final DateTime? from;
  final DateTime? to;
  final String search;

  _Filter copyWith({
    String? by,
    bool clearBy = false,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    String? search,
  }) => _Filter(
    by: clearBy ? null : (by ?? this.by),
    from: clearDates ? null : (from ?? this.from),
    to: clearDates ? null : (to ?? this.to),
    search: search ?? this.search,
  );

  Json args(String accountId, {int? cursor}) => <String, Object?>{
    'accountId': accountId,
    'by': ?by,
    if (from != null) 'from': DateFormat('yyyy-MM-dd').format(from!),
    if (to != null) 'to': DateFormat('yyyy-MM-dd').format(to!),
    if (search.isNotEmpty) 'search': search,
    'cursor': ?cursor,
  };
}

class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({required this.accountId, super.key});

  final String accountId;

  @override
  ConsumerState<AccountDetailScreen> createState() => _State();
}

class _State extends ConsumerState<AccountDetailScreen> {
  // -- STATES -- //

  final List<Json> _entries = <Json>[];
  _Filter _filter = const _Filter();
  int? _cursor;
  bool _loading = true;
  bool _more = false;
  Object? _error;
  int _balance = 0;
  int _gen = 0;
  final TextEditingController _search = TextEditingController();

  // -- LIFECYCLES -- //

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // -- FUNCTIONS -- //

  Future<void> _load({bool reset = false}) async {
    // Only the newest request may fill the list, so a slow old answer never lands under a new filter
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _entries.clear();
        _cursor = null;
      }
    });
    try {
      final r = await ref
          .read(apiProvider)
          .verbJson(
            'account_history',
            _filter.args(widget.accountId, cursor: reset ? null : _cursor),
          );
      if (!mounted || gen != _gen) return;
      setState(() {
        _entries.addAll(asJsonList(r['entries']));
        _cursor = r['nextCursor'] is num ? intOf(r['nextCursor']) : null;
        _more = _cursor != null;
        _balance = intOf(r['balance']);
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      // A failed "show older" keeps the rows and says so
      if (_entries.isNotEmpty) say(context, errorWords(e, context));
    }
  }

  void _setFilter(_Filter f) {
    _filter = f;
    _load(reset: true);
  }

  Json? _account() {
    final list = ref.read(balancesProvider).value ?? <Json>[];
    for (final a in list) {
      if (str(a['id']) == widget.accountId) return a;
    }
    return null;
  }

  Future<void> _export(String format) async {
    final t = context.t;
    try {
      final r = await ref.read(apiProvider).verbJson(
        'audit_export',
        <String, Object?>{
          'accountId': widget.accountId,
          'format': format,
          if (_filter.from != null)
            'from': DateFormat('yyyy-MM-dd').format(_filter.from!),
          if (_filter.to != null)
            'to': DateFormat('yyyy-MM-dd').format(_filter.to!),
        },
      );
      await Clipboard.setData(ClipboardData(text: str(r['body'])));
      if (!mounted) return;
      final notice = str(r['notice']);
      say(
        context,
        notice.isEmpty
            ? t.acctExportDone(intOf(r['rows']), format.toUpperCase())
            : t.acctExportCut(intOf(r['rows']), format.toUpperCase(), notice),
      );
    } on Object catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  /// Sets the balance to [cents] as a reset: the history keeps the old balance. Needs a connection and is never queued.
  Future<void> _setBalance(Json account, int cents, String reason) async {
    final t = context.t;
    final name = str(account['name']);
    final old = intOf(account['balance']);
    final yes = await confirm(
      context,
      title: t.setBalanceConfirmTitle(name, context.money(cents)),
      body: t.setBalanceConfirmBody(
        context.money(old),
        context.money(cents - old),
      ),
      yes: t.setBalanceConfirmYes,
      danger: cents == 0 && old != 0,
    );
    if (!yes || !mounted) return;
    try {
      await ref.read(apiProvider).verb('snapshot_record', <String, Object?>{
        'accountId': widget.accountId,
        'amount': cents,
        'mode': 'reset',
        'reason': reason,
        'confirmed': true,
        'source': 'manual',
      });
      ref.invalidate(balancesProvider);
      if (!mounted) return;
      say(context, t.setBalanceDone);
      await _load(reset: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      say(
        context,
        e.code == 'NETWORK' ? t.setBalanceOffline : errorWords(e, context),
      );
    }
  }

  Future<void> _askBalance({required bool zero}) async {
    final account = _account();
    if (account == null) return;
    final t = context.t;
    final amount = TextEditingController();
    final reason = TextEditingController(text: zero ? t.resetZeroReason : '');
    final picked = await showFormSheet<(int, String)>(
      context,
      title: zero ? t.acctMenuReset : t.setBalanceTitle(str(account['name'])),
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            sheet.t.setBalanceBody(sheet.money(intOf(account['balance']))),
            style: TextStyle(color: sheet.colors.muted),
          ),
          const SizedBox(height: 12),
          if (!zero)
            Field(
              controller: amount,
              label: sheet.t.setBalanceNew(sheet.currencyCode),
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
          Field(controller: reason, label: sheet.t.setBalanceReason),
          FilledButton(
            onPressed: () {
              final cents = zero ? 0 : sheet.parseAmount(amount.text);
              if (cents == null) {
                say(sheet, sheet.t.accountsCountInvalid(sheet.currencyCode));
                return;
              }
              if (reason.text.trim().isEmpty) {
                say(sheet, sheet.t.setBalanceReasonNeeded);
                return;
              }
              close((cents, reason.text.trim()));
            },
            child: Text(zero ? t.acctMenuReset : t.acctMenuSet),
          ),
        ],
      ),
    );
    amount.dispose();
    reason.dispose();
    if (picked != null && mounted)
      await _setBalance(account, picked.$1, picked.$2);
  }

  Future<void> _pickDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _filter.from == null || _filter.to == null
          ? null
          : DateTimeRange(start: _filter.from!, end: _filter.to!),
    );
    if (range != null) {
      _setFilter(_filter.copyWith(from: range.start, to: range.end));
    }
  }

  /// The loaded rows a tab shows.
  List<Json> _tab(int i) => <Json>[
    for (final e in _entries)
      if (switch (i) {
        1 => intOf(e['delta']) > 0,
        2 => intOf(e['delta']) < 0,
        3 => const <String>{'count', 'reset'}.contains(str(e['action'])),
        4 => str(e['action']) == 'undo',
        _ => true,
      })
        e,
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    // Watched, so the name and balance appear as soon as the accounts arrive
    ref.watch(balancesProvider);
    final account = _account();
    final verify = ref.watch(auditVerifyProvider).value;
    // A check that could not run is said, never shown as a clean chain
    final unverified = ref.watch(auditVerifyProvider).hasError;
    final broken = verify != null && !boolOf(verify['ok']);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(str(account?['name'], t.accountsTitle)),
          actions: <Widget>[
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'count':
                    if (account != null) {
                      AccountsScreen.count(context, ref, account).then((_) {
                        if (mounted) _load(reset: true);
                      });
                    }
                  case 'set':
                    _askBalance(zero: false);
                  case 'zero':
                    _askBalance(zero: true);
                  case 'csv':
                    _export('csv');
                  case 'json':
                    _export('json');
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'count',
                  height: 48,
                  child: Text(t.acctMenuCount),
                ),
                PopupMenuItem<String>(
                  value: 'set',
                  height: 48,
                  child: Text(t.acctMenuSet),
                ),
                PopupMenuItem<String>(
                  value: 'zero',
                  height: 48,
                  child: Text(t.acctMenuReset),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'csv',
                  height: 48,
                  child: Text('${t.acctMenuExport} (CSV)'),
                ),
                PopupMenuItem<String>(
                  value: 'json',
                  height: 48,
                  child: Text('${t.acctMenuExport} (JSON)'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Tab>[
              Tab(text: t.acctTabAll),
              Tab(text: t.acctTabIn),
              Tab(text: t.acctTabOut),
              Tab(text: t.acctTabCounts),
              Tab(text: t.acctTabUndone),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            if (broken)
              AuditBanner(seq: intOf(asJson(verify['problem'])['seq'])),
            if (unverified) const _Unverified(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      t.acctBalanceNow,
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                  Amount(_balance),
                ],
              ),
            ),
            _Filters(
              filter: _filter,
              search: _search,
              onChange: _setFilter,
              onDates: _pickDates,
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[for (var i = 0; i < 5; i++) _list(_tab(i))],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<Json> rows) {
    final t = context.t;
    if (_error != null && _entries.isEmpty) {
      final offline =
          _error is ApiException && (_error! as ApiException).code == 'NETWORK';
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              offline ? t.acctOffline : errorWords(_error!, context),
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: () => _load(reset: true),
              child: Text(t.retry),
            ),
          ],
        ),
      );
    }
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: <Widget>[
        if (rows.isEmpty) Note(t.acctEmpty),
        for (final e in rows) _EntryRow(entry: e),
        if (_more)
          TextButton(
            onPressed: _loading ? null : () => _load(),
            child: Text(t.acctLoadMore),
          ),
      ],
    );
  }
}

// -- FILTERS -- //

class _Filters extends StatelessWidget {
  const _Filters({
    required this.filter,
    required this.search,
    required this.onChange,
    required this.onDates,
  });

  final _Filter filter;
  final TextEditingController search;
  final ValueChanged<_Filter> onChange;
  final VoidCallback onDates;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final locale = Localizations.localeOf(context).toString();
    final dates = filter.from == null || filter.to == null
        ? t.acctDateRange
        : '${DateFormat.MMMd(locale).format(filter.from!)} - ${DateFormat.MMMd(locale).format(filter.to!)}';
    return Column(
      children: <Widget>[
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: <Widget>[
              for (final (value, label) in <(String?, String)>[
                (null, t.acctByAnyone),
                ('person', t.acctByYou),
                ('agent', t.acctByBotler),
                ('job', t.acctByJob),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: ChoiceChip(
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      label: Text(label),
                      selected: filter.by == value,
                      onSelected: (_) => onChange(
                        value == null
                            ? filter.copyWith(clearBy: true)
                            : filter.copyWith(by: value),
                      ),
                    ),
                  ),
                ),
              Center(
                child: ActionChip(
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(dates),
                  onPressed: onDates,
                ),
              ),
              if (filter.from != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Center(
                    child: ActionChip(
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      label: Text(t.acctDateClear),
                      onPressed: () =>
                          onChange(filter.copyWith(clearDates: true)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: t.acctSearchHint,
              prefixIcon: const Icon(Icons.search),
            ),
            onSubmitted: (v) => onChange(filter.copyWith(search: v.trim())),
          ),
        ),
      ],
    );
  }
}

// -- ROWS -- //

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final Json entry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final locale = Localizations.localeOf(context).toString();
    final at = (dateOf(entry['at']) ?? DateTime.now()).toLocal();
    final when = DateFormat.MMMd(locale).add_jm().format(at);
    final delta = intOf(entry['delta']);
    final what = entryTitle(t, entry);
    final who = actorWords(t, entry);
    final where = channelWords(t, str(entry['channel']));
    final balance = context.money(intOf(entry['balanceAfter']));
    return Semantics(
      button: true,
      label: t.auditRowSemantics(what, who, when, balance),
      child: InkWell(
        onTap: () => showEntrySheet(context, entry),
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(what, style: Theme.of(context).textTheme.bodyLarge),
                      Text(
                        '$who · $where · $when',
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      delta == 0
                          ? ''
                          : '${delta > 0 ? '+' : ''}${context.money(delta)}',
                      style: TextStyle(fontFeatures: tabular),
                    ),
                    Text(
                      balance,
                      style: TextStyle(color: c.muted, fontFeatures: tabular),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One entry in full: who, where, when, what changed in words, the note and the references.
Future<void> showEntrySheet(BuildContext context, Json entry) {
  final t = context.t;
  final locale = Localizations.localeOf(context).toString();
  final at = (dateOf(entry['at']) ?? DateTime.now()).toLocal();
  final before = asJson(entry['before']);
  final after = asJson(entry['after']);
  final keys = <String>{...before.keys, ...after.keys}.toList()..sort();
  final changes = <String>[
    for (final k in keys)
      if ('${before[k]}' != '${after[k]}')
        t.auditChangeLine(
          fieldWords(k),
          valueWords(context, k, before[k]),
          valueWords(context, k, after[k]),
        ),
  ];
  final note = str(entry['note']);
  final refs = <String>[
    '#${intOf(entry['seq'])}',
    if (str(entry['requestId']).isNotEmpty)
      '${t.auditRefRequest} ${shortId(str(entry['requestId']))}',
    if (str(entry['approvalId']).isNotEmpty)
      '${t.auditRefApproval} ${shortId(str(entry['approvalId']))}',
    if (str(entry['turnId']).isNotEmpty)
      '${t.auditRefTurn} ${shortId(str(entry['turnId']))}',
  ];
  Widget line(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: context.colors.muted),
        ),
        Text(value),
      ],
    ),
  );
  return showFormSheet<void>(
    context,
    title: entryTitle(t, entry),
    builder: (sheet, close) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        line(t.auditWho, actorWords(t, entry)),
        line(t.auditWhere, channelWords(t, str(entry['channel']))),
        line(t.auditWhen, DateFormat.yMMMMd(locale).add_jm().format(at)),
        line(t.auditBalanceAfter, sheet.money(intOf(entry['balanceAfter']))),
        if (changes.isNotEmpty) line(t.auditChanges, changes.join('\n')),
        if (note.isNotEmpty) line(t.auditNote, note),
        line(t.auditRefs, refs.join(' · ')),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: refs.join(' ')));
            if (sheet.mounted) say(sheet, sheet.t.auditCopied);
          },
          icon: const Icon(Icons.copy, size: 18),
          label: Text(t.auditCopyRef),
        ),
      ],
    ),
  );
}

// -- BANNER -- //

/// Calm notice that the audit chain has a break. Shown only when the check found one.
class AuditBanner extends StatelessWidget {
  const AuditBanner({required this.seq, super.key});

  final int seq;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: c.chip,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.t.auditBannerTitle,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: c.warning),
            ),
            const SizedBox(height: 4),
            Text(context.t.auditBannerBody(seq)),
          ],
        ),
      ),
    );
  }
}

/// Said when the audit check itself could not run.
class _Unverified extends StatelessWidget {
  const _Unverified();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: context.colors.chip,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      context.t.auditUnverified,
      style: TextStyle(color: context.colors.muted),
    ),
  );
}
