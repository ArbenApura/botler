// ACCOUNTS: WHAT IS IN EACH ONE, THE TOTAL OF EVERYTHING, ADD ONE, AND "I COUNTED THIS" TO CORRECT THE BALANCE.
// An account can hold several currencies (a Wise account with pesos and dollars): each currency is a wallet with its own balance and count.
// The total at the top converts every wallet to the main currency with the stored exchange rates, and says when the rates are old or a
// currency has no rate yet (it is then left out of the total, never counted as zero).
// A count that differs a lot from what Botler expected is shown for a yes first; one ten times off asks twice. Money that went missing between two
// counts is shown as "untracked", never hidden.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/money.dart';
import '../../core/money_scope.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'currency_picker.dart';
import 'purpose.dart';
import 'rates.dart';

// -- TYPES -- //

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final accounts = ref.watch(balancesProvider);
    final assets = ref.watch(assetsProvider);
    // What each account comes to in all, from the same answer as the total
    final subtotals = <String, Json>{
      for (final a in asJsonList(assets.value?['accounts']))
        str(a['accountId']): a,
    };
    return Scaffold(
      appBar: AppBar(title: Text(context.t.accountsTitle)),
      body: AsyncBody<List<Json>>(
        value: accounts,
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 4, kind: SkeletonKind.tile),
        ),
        onRetry: () {
          ref
            ..invalidate(balancesProvider)
            ..invalidate(assetsProvider);
        },
        data: (list) => ListView(
          padding: pagePadding(context),
          children: <Widget>[
            if (list.isNotEmpty) _TotalCard(assets: assets),
            if (list.isEmpty) Note(context.t.accountsEmpty),
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PaperCard(
                  onTap: () => context.push('/account/${str(a['id'])}'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              str(a['name']),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            PurposeChip(purposeOf(a)),
                            Text(
                              a['countedAt'] == null
                                  ? context.t.accountsNeverCounted
                                  : context.t.accountsCounted(
                                      _ago(context, str(a['countedAt'])),
                                    ),
                              style: TextStyle(color: c.muted),
                            ),
                            if (boolOf(a['belowMinimum']))
                              Text(
                                context.t.accountsBelowMinimum,
                                style: TextStyle(color: c.warning),
                              ),
                            if (!hasWalletIn(a, context.currencyCode) &&
                                intOf(a['minBalance']) > 0)
                              Text(
                                context.t.accountsNoMainWallet(
                                  context.currencyCode,
                                ),
                                style: TextStyle(color: c.muted),
                              ),
                          ],
                        ),
                      ),
                      _Wallets(
                        account: a,
                        subtotal: subtotals[str(a['id'])],
                        main: context.currencyCode,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: Text(context.t.accountsAdd),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final min = TextEditingController();
    var kind = 'bank';
    var currency = context.currencyCode;
    String? purpose;
    final done = await showFormSheet<bool>(
      context,
      title: context.t.accountsAdd,
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(
              controller: name,
              label: context.t.accountsNameLabel,
              hint: sheet.t.accountsNameHint,
              capitalization: TextCapitalization.words,
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final (k, label) in <(String, String)>[
                  ('bank', sheet.t.accountsKindBank),
                  ('ewallet', sheet.t.accountsKindEwallet),
                  ('cash', sheet.t.accountsKindCash),
                  ('other', sheet.t.accountsKindOther),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: kind == k,
                    onSelected: (_) => setState(() => kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              sheet.t.accountsCurrencyLabel,
              style: TextStyle(color: sheet.colors.muted),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: CurrencyButton(
                code: currency,
                label: sheet.t.accountsCurrencyLabel,
                onPressed: () async {
                  final picked = await pickCurrency(
                    sheet,
                    current: currency,
                    first: <String>{sheet.currencyCode},
                  );
                  if (picked != null) setState(() => currency = picked);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 12),
              child: Text(
                sheet.t.accountsCurrencyNote,
                style: TextStyle(color: sheet.colors.muted),
              ),
            ),
            Field(
              controller: min,
              label: sheet.t.accountsMinimumLabel(sheet.currencyCode),
              hint: '500',
              keyboard: TextInputType.number,
            ),
            PurposeField(value: null, onChanged: (v) => purpose = v),
            FilledButton(
              onPressed: () async {
                // The minimum is a money plan rule, so it is typed in the main currency
                final minimum = min.text.trim().isEmpty
                    ? 0
                    : context.parseAmountMain(min.text);
                if (name.text.trim().isEmpty ||
                    minimum == null ||
                    !purposeValid(purpose)) {
                  say(sheet, sheet.t.accountsAddInvalid);
                  return;
                }
                try {
                  await ref.read(apiProvider).verb(
                    'account_create',
                    <String, Object?>{
                      'name': name.text.trim(),
                      'kind': kind,
                      'minBalance': minimum,
                      'currency': currency,
                      'purpose': ?purpose,
                    },
                  );
                  close(true);
                } catch (e) {
                  if (sheet.mounted) say(sheet, errorWords(e, context));
                }
              },
              child: Text(sheet.t.add),
            ),
          ],
        ),
      ),
    );
    if (done == true) {
      ref
        ..invalidate(balancesProvider)
        ..invalidate(assetsProvider)
        ..invalidate(syncProvider);
    }
  }

  /// Adds a currency to an account (a Wise account with pesos and dollars). A currency the account already has is not offered.
  static Future<void> addWallet(
    BuildContext context,
    WidgetRef ref,
    Json account,
  ) async {
    final t = context.t;
    final have = <String>{
      for (final w in walletsOf(account)) str(w['currency']),
    };
    final picked = await pickCurrency(
      context,
      current: str(account['currency'], context.currencyCode),
      first: <String>{context.currencyCode},
      hide: have,
    );
    if (picked == null) return;
    try {
      await ref.read(apiProvider).verb('account_wallet_add', <String, Object?>{
        'accountId': str(account['id']),
        'currency': picked,
      });
      if (context.mounted) say(context, t.accountsWalletAdded(picked));
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
    ref
      ..invalidate(balancesProvider)
      ..invalidate(assetsProvider);
  }

  /// The count sheet, also opened from an account's own screen. [currency] is the wallet that is counted (the account's own when left out).
  static Future<void> count(
    BuildContext context,
    WidgetRef ref,
    Json account, {
    String? currency,
  }) async {
    final amount = TextEditingController();
    final wallet = currency ?? str(account['currency'], context.currencyCode);
    final shown = walletsOf(account).firstWhere(
      (w) => str(w['currency']) == wallet,
      orElse: () => <String, Object?>{'balance': account['balance']},
    );
    final result = await showFormSheet<String>(
      context,
      title: context.t.accountsCountTitle(str(account['name'])),
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            sheet.t.accountsBotlerThinks(
              sheet.moneyIn(intOf(shown['balance']), wallet),
            ),
            style: TextStyle(color: sheet.colors.muted),
          ),
          const SizedBox(height: 12),
          Field(
            controller: amount,
            label: sheet.t.accountsCountLabel(wallet),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          FilledButton(
            onPressed: () async {
              final cents = context.parseAmountIn(amount.text, wallet);
              if (cents == null) {
                say(sheet, sheet.t.accountsCountInvalid(wallet));
                return;
              }
              close(await _record(sheet, ref, account, cents, wallet));
            },
            child: Text(sheet.t.accountsSaveCount),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) say(context, result);
    ref
      ..invalidate(balancesProvider)
      ..invalidate(assetsProvider)
      ..invalidate(syncProvider);
  }

  /// Saves a count, asking for a yes (twice for a ten-times difference) when the server wants it.
  static Future<String> _record(
    BuildContext sheet,
    WidgetRef ref,
    Json account,
    int cents,
    String code,
  ) async {
    final api = ref.read(apiProvider);
    // The context is read before any await, so none is used after one
    final t = sheet.t;
    final base = <String, Object?>{
      'accountId': str(account['id']),
      // Only when it is not the account's own currency, so an ordinary count is the same request as before
      if (code != str(account['currency'], defaultCurrency)) 'currency': code,
      'amount': cents,
    };
    try {
      var answer = asJson(await api.verb('snapshot_record', base));
      if (str(answer['status']) == 'needs_confirmation') {
        final chip = asJson(answer['chip']);
        final large = str(chip['severity']) == 'large';
        final expected = chip['expected'] == null
            ? null
            : intOf(chip['expected']);
        if (!sheet.mounted) return '';
        final yes = await confirm(
          sheet,
          title: large ? t.accountsConfirmBig : t.accountsConfirmRight,
          body:
              '${expected == null ? t.accountsConfirmCounted(formatMoney(cents, code)) : t.accountsConfirmBoth(formatMoney(cents, code), formatMoney(expected, code))}${large ? ' ${t.accountsConfirmLarge}' : ''}',
          yes: t.accountsConfirmYes,
        );
        if (!yes) return t.accountsNotSaved;
        answer = asJson(
          await api.verb('snapshot_record', <String, Object?>{
            ...base,
            'confirmed': true,
            'acknowledgeLarge': large,
          }),
        );
      }
      final untracked = intOf(answer['untracked']);
      return untracked > 0
          ? t.accountsSavedUntracked(formatMoney(untracked, code))
          : t.accountsSaved;
    } catch (e) {
      return errorWords(e);
    }
  }
}

// -- HELPERS -- //

/// The wallets of an account row of `accounts_balances`. An older server has none: the account itself is the one wallet.
List<Json> walletsOf(Json account) {
  final list = asJsonList(account['wallets']);
  if (list.isNotEmpty) return list;
  return <Json>[
    <String, Object?>{
      'currency': str(account['currency'], defaultCurrency),
      'balance': account['balance'],
      'countedAt': account['countedAt'],
    },
  ];
}

/// Whether the account holds a wallet in this currency.
bool hasWalletIn(Json account, String currency) =>
    walletsOf(account).any((w) => str(w['currency']) == currency);

// -- TOTAL -- //

/// The rate of each added currency against the main one, by currency code. Read from the wallets of the assets answer; a currency without a
/// rate (or the main currency itself) is left out, and the missing-rate warning names those.
Map<String, String> rateLinesOf(Json assets, String main) {
  final out = <String, String>{};
  for (final w in asJsonList(assets['wallets'])) {
    final code = str(w['currency']);
    final rate = w['rate'];
    if (code.isEmpty || code == main || rate is! String || rate.isEmpty)
      continue;
    out[code] = rate;
  }
  return Map<String, String>.fromEntries(
    out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// Everything the person has, in the main currency, with the date of the rates and what is missing. Tapping it updates the rates.
class _TotalCard extends ConsumerWidget {
  const _TotalCard({required this.assets});

  final AsyncValue<Json> assets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.t;
    final data = assets.value;
    if (data == null) {
      // Loading, or no answer and nothing stored: the accounts below still work
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PaperCard(
          child: assets.hasError
              ? Text(
                  t.accountsTotalUnavailable,
                  style: TextStyle(color: c.muted),
                )
              : const SkeletonRows(count: 1, kind: SkeletonKind.tile),
        ),
      );
    }
    final rates = asJson(data['rates']);
    final asOf = rates['asOf'] is String ? str(rates['asOf']) : null;
    final age = ratesAgeDays(asOf);
    final old =
        asOf == null || boolOf(rates['stale']) && (age ?? 99) >= staleDays;
    final missing = asList(data['missing']).whereType<String>().toList();
    final offline = boolOf(data['offline']);
    final main = str(data['currency'], context.currencyCode);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.accountsTotalTitle, style: TextStyle(color: c.muted)),
            const SizedBox(height: 4),
            Amount(intOf(data['total']), currency: main),
            if (missing.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                t.accountsMissingRate(missing.join(', ')),
                style: TextStyle(color: c.warning),
              ),
            ],
            if (offline) ...<Widget>[
              const SizedBox(height: 6),
              Text(t.accountsRatesOffline, style: TextStyle(color: c.muted)),
            ],
            // One line per added currency with its rate against the main currency (display only, shown as the server sent it)
            for (final e in rateLinesOf(data, main).entries)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t.accountsRateLine(e.key, e.value, main),
                  style: TextStyle(color: c.muted, fontFeatures: tabular),
                ),
              ),
            const SizedBox(height: 6),
            // The rates line is also the button that updates them (a 48 dp target)
            Semantics(
              button: true,
              label: t.accountsRatesRefresh,
              child: InkWell(
                onTap: () => refreshRates(context, ref),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      asOf == null
                          ? t.accountsRatesNone
                          : old
                          ? t.accountsRatesStale(ratesDate(context, asOf))
                          : t.accountsRatesAsOf(ratesDate(context, asOf)),
                      style: TextStyle(color: old ? c.warning : c.muted),
                    ),
                  ),
                ),
              ),
            ),
            // Time travel: the balances on any past or future day (BTL-20261029-0117), a line like the rates line, not a second button
            Semantics(
              button: true,
              label: t.simSeeOverTime,
              child: InkWell(
                onTap: () => context.push('/simulate'),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ExcludeSemantics(
                      child: Text(
                        t.simSeeOverTime,
                        style: TextStyle(color: c.muted),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- WALLETS OF ONE ACCOUNT -- //

/// The right side of an account card: the balance of its one wallet, or every wallet with what the account comes to in all.
class _Wallets extends StatelessWidget {
  const _Wallets({
    required this.account,
    required this.subtotal,
    required this.main,
  });

  final Json account;
  final Json? subtotal;
  final String main;

  @override
  Widget build(BuildContext context) {
    final wallets = walletsOf(account);
    final own = str(account['currency'], defaultCurrency);
    if (wallets.length == 1) {
      return Amount(
        intOf(wallets.first['balance']),
        currency: str(wallets.first['currency'], own),
      );
    }
    final sub = subtotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (final w in wallets)
          Amount(
            intOf(w['balance']),
            currency: str(w['currency'], own),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        if (sub != null)
          Text(
            context.t.accountsSubtotal(
              context.moneyIn(intOf(sub['subtotal']), main),
            ),
            style: TextStyle(
              color: context.colors.muted,
              fontFeatures: tabular,
            ),
          ),
      ],
    );
  }
}

// -- FUNCTIONS -- //

String _ago(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final days = DateTime.now().difference(d).inDays;
  return days <= 0
      ? context.t.accountsToday
      : days == 1
      ? context.t.accountsYesterday
      : context.t.accountsDaysAgo(days);
}
