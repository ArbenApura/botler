// THE WORDS FOR AN AUDIT ENTRY: WHO DID IT, WHERE, WHAT KIND OF CHANGE, AND A FIELD OR VALUE IN PLAIN LANGUAGE.
// The trail stores short codes; this is the one place that turns them into the person's language.

// -- DEP-MODULES -- //
import 'package:flutter/widgets.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';

// -- FUNCTIONS -- //

/// Who did it. An assistant action the person approved reads as "Botler, approved by you".
String actorWords(AppLocalizations t, Json e) {
  final actor = str(e['actor']);
  final onBehalf = str(e['onBehalf']);
  if (actor == 'person' && onBehalf == 'agent') return t.auditBotlerApproved;
  return switch (actor) {
    'person' => t.auditYou,
    'agent' => t.auditBotler,
    'job' => t.auditJob,
    _ => t.auditSync,
  };
}

String channelWords(AppLocalizations t, String channel) => switch (channel) {
  'app' => t.auditChApp,
  'chat' => t.auditChChat,
  'widget' => t.auditChWidget,
  'outbox' => t.auditChOutbox,
  'calendar_sync' => t.auditChCalendar,
  'job' => t.auditChJob,
  _ => t.auditChSystem,
};

String actionWords(AppLocalizations t, String action) => switch (action) {
  'create' => t.auditAcCreate,
  'update' => t.auditAcUpdate,
  'delete' => t.auditAcDelete,
  'undo' => t.auditAcUndo,
  'count' => t.auditAcCount,
  'reset' => t.auditAcReset,
  'approve' => t.auditAcApprove,
  'reject' => t.auditAcReject,
  'expire' => t.auditAcExpire,
  'data_reset' => t.auditAcDataReset,
  _ => action,
};

String entityWords(AppLocalizations t, String entity) => switch (entity) {
  'ledger_txn' => t.auditEnTxn,
  'balance_snapshot' => t.auditEnSnapshot,
  _ => entity.replaceAll('_', ' '),
};

/// "Added transaction", "Reset balance count", or the name the row carries.
String entryTitle(AppLocalizations t, Json e) {
  final after = asJson(e['after']);
  final before = asJson(e['before']);
  final name = str(after['name'], str(before['name']));
  final what = name.isNotEmpty ? name : entityWords(t, str(e['entity']));
  return '${actionWords(t, str(e['action']))} $what';
}

/// A column name as words ("min_balance" becomes "min balance").
String fieldWords(String key) => key.replaceAll('_', ' ');

/// The currency an entry of the trail is in, or empty when it has none (an account or a bill changing).
String entryCurrency(Json e) {
  final after = asJson(e['after']);
  final before = asJson(e['before']);
  return str(after['currency'], str(before['currency']));
}

/// A value for the screen: money fields in the currency they are in, empty as "none". A minimum balance belongs to the money plan, so it is
/// in the main currency; the amount that arrived in a transfer is in the currency it landed in; the rest are in the entry's own wallet.
String valueWords(
  BuildContext context,
  String key,
  Object? v, [
  String? currency,
  String own = '',
]) {
  if (v == null) return context.t.auditNone;
  final isMoney = key.contains('amount') || key.contains('balance');
  if (isMoney && v is num) {
    final code = key == 'min_balance'
        ? context.currencyCode
        : currency ?? (own.isEmpty ? context.currencyCode : own);
    return context.moneyIn(v.toInt(), code);
  }
  return '$v';
}

String shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);
