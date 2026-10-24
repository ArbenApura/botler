// THE ONE SHEET FOR A BILL: ADD A NEW ONE, CHANGE ONE DUE DATE (MOVE IT, ANOTHER AMOUNT OR ACCOUNT, SKIP IT), OR CHANGE THE BILL FOR EVERY DATE.
// Opened from a row of "Coming up" it edits that date; opened from "All bills" it edits the bill. What only makes sense for the whole
// bill (its name, how it repeats) always changes the bill. An amount or an account changed on a date asks "just this one, or every time?".
// The server applies the rules; this sheet sends only what changed, with one request id per call so a retry never repeats a change.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/manila.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'bills_parts.dart';
import 'currency_picker.dart';
import 'schedule_picker.dart';

// -- CONSTANTS -- //

/// A date can move this far from the day its schedule gives (the server's limit).
const int _moveLimitDays = 31;

const Size _tap = Size(48, 48);

// -- TYPES -- //

/// One request to the server, in the order it is sent.
class _Call {
  const _Call(this.verb, this.args);

  final String verb;
  final Json args;
}

/// What the person chose when asked "just this one, or every time?".
enum _Scope { thisOne, everyTime }

/// The sheet's content. [bill] is a row of `bills_list` (null to add a bill); [due] is a row of `bills_due` when a date was tapped.
class BillEditor extends ConsumerStatefulWidget {
  const BillEditor({required this.close, this.bill, this.due, super.key});

  final Json? bill;
  final Json? due;
  final void Function(String? message) close;

  @override
  ConsumerState<BillEditor> createState() => _BillEditorState();
}

class _BillEditorState extends ConsumerState<BillEditor> {
  // -- STATES -- //

  late final TextEditingController _name;
  late final TextEditingController _amount;
  late ScheduleValue? _schedule;
  late String _weekend;
  late bool _varies;
  late bool _parents;
  late String _accountId;
  late String _date;

  /// The currency of the bill and of its amount. A new bill starts in the main currency.
  String? _currency;
  List<Json> _accounts = const <Json>[];
  bool _saving = false;
  final Map<String, String> _keys = <String, String>{};

  // What the form held when it opened, to send only what changed
  late final String _origName;
  late final int? _origAmount;
  late final String _origCurrency;
  late final String _origAccountId;
  late final String _origSchedule;
  late final String _origWeekend;
  late final bool _origVaries;
  late final bool _origParents;
  late final String _origDate;
  bool _seeded = false;

  // -- FUNCTIONS -- //

  /// The currency the amount is typed in: the one picked, else the bill's own, else the main currency.
  String get _code =>
      _currency ??
      (_origCurrency.isEmpty ? context.currencyCode : _origCurrency);

  Json get _bill => widget.bill ?? const <String, Object?>{};
  Json? get _due => widget.due;
  bool get _adding => widget.bill == null;

  /// A date that is not paid yet and was tapped: its own changes are offered.
  bool get _onADate => _due != null && !boolOf(_due?['paid']);
  bool get _overridden => boolOf(_due?['overridden']);
  // An older server answers without the schedule's own day: the day it is due on then stands in for it
  String get _original => str(_due?['originalDueDate'], str(_due?['dueDate']));

  String _scheduleKey() =>
      _schedule == null ? '' : jsonEncode(_schedule?.toJson());

  bool get _scheduleChanged => !_adding && _scheduleKey() != _origSchedule;

  /// A new repeat rule or weekend rule moves every date, so one date can no longer be changed on its own.
  bool get _repeatChanged =>
      _scheduleChanged ||
      (!_adding &&
          _weekend != _origWeekend &&
          (_schedule?.isSingleDay ?? false));

  @override
  void initState() {
    super.initState();
    final b = _bill;
    _origName = str(b['name']);
    _name = TextEditingController(text: _origName);
    _origVaries = str(b['kind']) == 'variable';
    _varies = _origVaries;
    _origParents = str(b['category']) == 'parents';
    _parents = _origParents;
    final due = _due;
    // On a date the amount shown is the one for that date; otherwise the bill's own
    final seed = _onADate && due != null && !boolOf(due['unknownAmount'])
        ? intOf(due['amount'])
        : intOf(b['amount']);
    _origAmount = seed > 0 ? seed : null;
    _origCurrency = str(b['currency']);
    _amount = TextEditingController();
    _origAccountId = _onADate && due != null
        ? str(due['accountId'], str(b['accountId']))
        : str(b['accountId']);
    _accountId = _origAccountId;
    _schedule = _adding
        ? ScheduleValue()
        : ScheduleValue.fromJson(asJson(b['schedule']));
    _origSchedule = _scheduleKey();
    _origWeekend = str(b['weekendRule'], 'none');
    _weekend = _origWeekend;
    _origDate = str(due?['dueDate']);
    _date = _origDate;
    _loadAccounts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The amount text needs the currency, which a context above this sheet gives, so it is filled once here
    if (!_seeded) {
      _seeded = true;
      final seed = _origAmount;
      if (seed != null) _amount.text = plainAmountIn(seed, _code);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final list = await ref.read(balancesProvider.future);
      if (!mounted) return;
      setState(() {
        _accounts = list;
        if (_accountId.isEmpty) _accountId = str(list.firstOrNull?['id']);
      });
    } on Object {
      // The chips stay empty and the save says an account is needed
    }
  }

  /// One request id per call and per set of arguments, so a retry of the same call repeats nothing and a changed call gets a new id.
  String _keyFor(_Call c) =>
      _keys.putIfAbsent('${c.verb}|${jsonEncode(c.args)}', newRequestId);

  Future<void> _pickDate() async {
    final original = dayOf(_original);
    final current = dayOf(_date);
    if (original == null || current == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: original.subtract(const Duration(days: _moveLimitDays)),
      lastDate: original.add(const Duration(days: _moveLimitDays)),
    );
    if (picked != null && mounted) setState(() => _date = isoOf(picked));
  }

  /// Sends the calls in order. Without a connection the call that failed and the ones after it go to the outbox with the same ids.
  Future<String> _send(List<_Call> calls) async {
    final words = context.t;
    final api = ref.read(apiProvider);
    for (var i = 0; i < calls.length; i++) {
      final call = calls[i];
      try {
        await api.verb(call.verb, call.args, _keyFor(call));
      } on ApiException catch (e) {
        if (e.code != 'NETWORK') rethrow;
        for (final rest in calls.skip(i)) {
          await ref
              .read(outboxProvider)
              .add(rest.verb, rest.args, key: _keyFor(rest));
        }
        ref.read(outboxCountProvider.notifier).refresh();
        return words.billsSavedOffline;
      }
    }
    return words.billsSaved;
  }

  Future<void> _run(List<_Call> calls, [String? done]) async {
    if (calls.isEmpty) {
      widget.close(context.t.billsNoChange);
      return;
    }
    setState(() => _saving = true);
    try {
      final message = await _send(calls);
      widget.close(done ?? message);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        say(context, errorWords(e, context));
      }
    }
  }

  Future<_Scope?> _askScope() => showDialog<_Scope>(
    context: context,
    builder: (d) => SimpleDialog(
      backgroundColor: d.colors.surface,
      title: Text(d.t.billsScopeTitle),
      children: <Widget>[
        SimpleDialogOption(
          onPressed: () => Navigator.of(d).pop(_Scope.thisOne),
          child: SizedBox(
            height: _tap.height,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(d.t.billsScopeThisOne(_niceDate(d, _original))),
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(d).pop(_Scope.everyTime),
          child: SizedBox(
            height: _tap.height,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(d.t.billsScopeAll),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    final t = context.t;
    final text = _amount.text.trim();
    final cents = text.isEmpty ? null : context.parseAmountIn(text, _code);
    final currencyChanged =
        _code != (_origCurrency.isEmpty ? context.currencyCode : _origCurrency);
    if (_name.text.trim().isEmpty ||
        _accountId.isEmpty ||
        (text.isNotEmpty && (cents == null || cents <= 0)) ||
        (!_varies && cents == null && (!_onADate || _origVaries))) {
      say(context, t.billsAddInvalid);
      return;
    }
    final schedule = _schedule;
    if (_adding) {
      await _run(<_Call>[
        _Call('bill_create', <String, Object?>{
          'name': _name.text.trim(),
          'category': _parents ? 'parents' : 'bills',
          'accountId': _accountId,
          'kind': _varies ? 'variable' : 'fixed',
          // Only when it is not the main currency, so an ordinary bill is the same request as before
          if (_code != context.currencyCode) 'currency': _code,
          'amount': cents,
          'schedule': schedule?.toJson(),
          'weekendRule': schedule != null && schedule.isSingleDay
              ? _weekend
              : 'none',
          'deferrable': false,
        }),
      ], t.billsSaved);
      return;
    }
    final billId = str(_bill['id']);
    // What belongs to the whole bill
    final series = <String, Object?>{};
    if (_name.text.trim() != _origName) series['name'] = _name.text.trim();
    if (_parents != _origParents) {
      series['category'] = _parents ? 'parents' : 'bills';
    }
    if (_varies != _origVaries) series['kind'] = _varies ? 'variable' : 'fixed';
    if (currencyChanged) series['currency'] = _code;
    if (_scheduleChanged && schedule != null) {
      series['schedule'] = schedule.toJson();
      series['weekendRule'] = schedule.isSingleDay ? _weekend : 'none';
    } else if (_weekend != _origWeekend &&
        schedule != null &&
        schedule.isSingleDay) {
      series['weekendRule'] = _weekend;
    }
    // A bill that turns fixed sends the amount that was shown, so what is saved is what the person read
    final amountChanged =
        cents != null && (cents != _origAmount || (_origVaries && !_varies));
    final accountChanged = _accountId != _origAccountId;
    // A date can only be changed on its own while the way it repeats is left alone
    final dateChanged = _onADate && !_repeatChanged && _date != _origDate;
    var perDate = false;
    if (_onADate &&
        !_repeatChanged &&
        _origVaries == _varies &&
        (amountChanged || accountChanged)) {
      final scope = await _askScope();
      if (scope == null || !mounted) return;
      perDate = scope == _Scope.thisOne;
    }
    final wholeBill = !_onADate || _repeatChanged || !perDate;
    if (amountChanged && wholeBill) series['amount'] = cents;
    if (accountChanged && wholeBill) series['accountId'] = _accountId;
    final one = <String, Object?>{};
    if (dateChanged) one['newDueDate'] = _date == _original ? null : _date;
    if (amountChanged && perDate) one['amount'] = cents;
    if (accountChanged && perDate) one['accountId'] = _accountId;
    await _run(<_Call>[
      if (series.isNotEmpty)
        _Call('bill_update', <String, Object?>{'billId': billId, ...series}),
      if (one.isNotEmpty)
        _Call('bill_occurrence_update', <String, Object?>{
          'billId': billId,
          'dueDate': str(_due?['dueDate']),
          ...one,
        }),
    ]);
  }

  Future<void> _skip() async {
    final t = context.t;
    final date = str(_due?['dueDate']);
    final ok = await confirm(
      context,
      title: t.billsSkipTitle(_origName, _niceDate(context, date)),
      body: t.billsSkipBody,
      yes: t.billsSkipYes,
    );
    if (!ok || !mounted) return;
    await _run(<_Call>[
      _Call('bill_occurrence_update', <String, Object?>{
        'billId': str(_bill['id']),
        'dueDate': date,
        'skipped': true,
      }),
    ], t.billsSkipped);
  }

  Future<void> _putBack() => _run(<_Call>[
    _Call('bill_occurrence_reset', <String, Object?>{
      'billId': str(_bill['id']),
      'dueDate': str(_due?['dueDate']),
    }),
  ], context.t.billsPutBackDone);

  // -- BUILD -- //

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final schedule = _schedule;
    final showDate = _onADate && !_repeatChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Field(
          controller: _name,
          label: t.billsNameLabel,
          hint: _adding ? t.billsNameHint : null,
          capitalization: TextCapitalization.words,
        ),
        if (showDate) ...<Widget>[
          Semantics(
            button: true,
            label: '${t.billsDateLabel}, ${_niceDate(context, _date)}',
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: _tap),
              onPressed: _saving ? null : _pickDate,
              icon: const Icon(Icons.event),
              label: Text('${t.billsDateLabel}: ${_niceDate(context, _date)}'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
            child: Text(t.billsDateNote, style: TextStyle(color: c.muted)),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.billsVaries),
          value: _varies,
          onChanged: _saving ? null : (v) => setState(() => _varies = v),
        ),
        Field(
          controller: _amount,
          label: _varies
              ? t.billsAboutLabel(_code)
              : t.billsHowMuchLabel(_code),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        // The bill's currency: a dollar subscription is typed in dollars, and follows the latest rate against the main currency.
        // It belongs to the whole bill, so it is not offered while only one date is being changed
        if (!_onADate || _repeatChanged)
          Align(
            alignment: Alignment.centerLeft,
            child: CurrencyButton(
              code: _code,
              label: t.billsCurrencyLabel,
              onPressed: _saving
                  ? null
                  : () async {
                      final picked = await pickCurrency(
                        context,
                        current: _code,
                        first: <String>{context.currencyCode},
                      );
                      if (picked != null) setState(() => _currency = picked);
                    },
            ),
          ),
        const SizedBox(height: 8),
        Text(t.billsPaidFrom, style: TextStyle(color: c.muted)),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final a in _accounts)
              ChoiceChip(
                label: Text(str(a['name'])),
                selected: str(a['id']) == _accountId,
                onSelected: _saving
                    ? null
                    : (_) => setState(() => _accountId = str(a['id'])),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (schedule != null) ...<Widget>[
          SchedulePicker(
            value: schedule,
            weekend: schedule.isSingleDay ? _weekend : 'none',
            onChanged: () => setState(() {}),
          ),
          if (_repeatChanged)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t.billsRepeatChangedNote,
                style: TextStyle(color: c.muted),
              ),
            ),
          if (schedule.isSingleDay) ...<Widget>[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _weekend,
              isExpanded: true,
              decoration: InputDecoration(labelText: t.schedWeekendLabel),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'none',
                  child: Text(t.schedWeekendNone),
                ),
                DropdownMenuItem<String>(
                  value: 'before',
                  child: Text(t.schedWeekendBefore),
                ),
                DropdownMenuItem<String>(
                  value: 'after',
                  child: Text(t.schedWeekendAfter),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (w) => setState(() => _weekend = w ?? 'none'),
            ),
          ],
        ] else
          Text(t.schedUnknown, style: TextStyle(color: c.muted)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.billsParentsShare),
          value: _parents,
          onChanged: _saving ? null : (v) => setState(() => _parents = v),
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: _tap),
          onPressed: _saving ? null : _save,
          child: Text(_adding ? t.billsAddButton : t.billsSave),
        ),
        if (_onADate) ...<Widget>[
          const SizedBox(height: 4),
          if (_overridden)
            TextButton(
              style: TextButton.styleFrom(minimumSize: _tap),
              onPressed: _saving ? null : _putBack,
              child: Text(t.billsPutBack),
            ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: _tap),
            onPressed: _saving ? null : _skip,
            child: Text(t.billsSkip),
          ),
        ],
      ],
    );
  }
}

// -- FUNCTIONS -- //

String _niceDate(BuildContext context, String iso) => niceDate(context, iso);

/// Opens the sheet. The answer is a short message to show, or null when the sheet was dismissed.
Future<String?> showBillEditor(BuildContext context, {Json? bill, Json? due}) =>
    showFormSheet<String>(
      context,
      title: bill == null ? context.t.billsAdd : context.t.billsEditTitle,
      builder: (sheet, close) => BillEditor(bill: bill, due: due, close: close),
    );
