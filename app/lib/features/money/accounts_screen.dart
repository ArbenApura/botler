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
import '../../core/marks.dart';
import '../../core/money.dart';
import '../../core/money_scope.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'currency_picker.dart';
import 'mark_picker.dart';
import 'money_parts.dart';
import 'net_parts.dart';
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
    final net = ref.watch(settingsProvider.select((s) => s.showNetBalance));
    // What each account comes to in all, from the same answer as the total
    final subtotals = <String, Json>{
      for (final a in asJsonList(assets.value?['accounts']))
        str(a['accountId']): a,
    };
    // What each wallet is worth in the main currency, for the "about" line of a currency that is not the main one
    final walletValues = <String, int>{
      for (final w in asJsonList(assets.value?['wallets']))
        if (w['value'] is int)
          '${str(w['accountId'])}|${str(w['currency'])}': w['value'] as int,
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
            if (list.isNotEmpty) _TotalCard(assets: assets, net: net),
            if (list.isEmpty) Note(context.t.accountsEmpty),
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PaperCard(
                  onTap: () => context.push('/account/${str(a['id'])}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        // The badge, the name and the amount block share one middle line on every account
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          MarkBadge(
                            name: str(a['name']),
                            mark: markOf(a),
                            size: 44,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  str(a['name']),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                PurposeChip(purposeOf(a)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // One right block on every account, capped so a big amount shrinks instead of wrapping
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.5,
                            ),
                            child: _HeadAmount(
                              account: a,
                              subtotal: subtotals[str(a['id'])],
                              main: context.currencyCode,
                              net: net,
                            ),
                          ),
                        ],
                      ),
                      // Several currencies: a ruled list of the wallets under the header
                      if (walletsOf(a).length > 1) ...<Widget>[
                        const SizedBox(height: 12),
                        _Wallets(
                          account: a,
                          net: net,
                          main: context.currencyCode,
                          values: walletValues,
                        ),
                      ],
                      if (boolOf(a['belowMinimum']) ||
                          (!hasWalletIn(a, context.currencyCode) &&
                              intOf(a['minBalance']) > 0)) ...<Widget>[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            if (boolOf(a['belowMinimum']))
                              InfoPill(
                                text: context.t.accountsBelowMinimum,
                                color: c.warning,
                                icon: Icons.warning_amber_rounded,
                              ),
                            if (!hasWalletIn(a, context.currencyCode) &&
                                intOf(a['minBalance']) > 0)
                              InfoPill(
                                text: context.t.accountsNoMainWallet(
                                  context.currencyCode,
                                ),
                                color: c.muted,
                                icon: Icons.info_outline,
                              ),
                          ],
                        ),
                      ],
                      // What consumed the net: the first few bills, rules and goals (only with the net on and sent)
                      if (net) NetHoldLines(account: a),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            FilledButton.icon(
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
    var kind = 'bank';
    var currency = context.currencyCode;
    String? purpose;
    var mark = const MarkChoice.unchanged();
    final done = await showFormSheet<bool>(
      context,
      title: context.t.accountsAdd,
      builder: (sheet, close) => SheetScope(
        texts: const <String>['', ''],
        builder: (_, s) => StatefulBuilder(
          builder: (_, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Field(
                controller: s.c[0],
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
                controller: s.c[1],
                label: sheet.t.accountsMinimumLabel(sheet.currencyCode),
                hint: '500',
                keyboard: TextInputType.number,
              ),
              PurposeField(value: null, onChanged: (v) => purpose = v),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  sheet.t.markTitle,
                  style: Theme.of(sheet).textTheme.titleSmall,
                ),
              ),
              MarkField(
                name: s.c[0].text,
                current: const Mark(),
                onChanged: (c) => mark = c,
              ),
              FilledButton(
                onPressed: s.once.running()
                    ? null
                    : () async {
                        // The minimum is a money plan rule, so it is typed in the main currency
                        final minimum = s.c[1].text.trim().isEmpty
                            ? 0
                            : context.parseAmountMain(s.c[1].text);
                        if (s.c[0].text.trim().isEmpty ||
                            minimum == null ||
                            !purposeValid(purpose)) {
                          say(sheet, sheet.t.accountsAddInvalid);
                          return;
                        }
                        try {
                          if (!await s.once.ok((key) async {
                            await ref.read(apiProvider).verb(
                              'account_create',
                              <String, Object?>{
                                'name': s.c[0].text.trim(),
                                'kind': kind,
                                'minBalance': minimum,
                                'currency': currency,
                                'purpose': ?purpose,
                                ...markArgs(mark, const Mark()),
                              },
                              key,
                            );
                          })) {
                            return;
                          }
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
      // One key for this account and currency until it works, and no second call while one runs
      await _walletOnce.run((key) async {
        await ref.read(apiProvider).verb(
          'account_wallet_add',
          <String, Object?>{
            'accountId': str(account['id']),
            'currency': picked,
          },
          key,
        );
      }, intent: '${str(account['id'])}:$picked');
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
    final wallet = currency ?? str(account['currency'], context.currencyCode);
    final shown = walletsOf(account).firstWhere(
      (w) => str(w['currency']) == wallet,
      orElse: () => <String, Object?>{'balance': account['balance']},
    );
    final result = await showFormSheet<String>(
      context,
      title: context.t.accountsCountTitle(str(account['name'])),
      builder: (sheet, close) => SheetScope(
        builder: (_, s) => Column(
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
              controller: s.c[0],
              label: sheet.t.accountsCountLabel(wallet),
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            FilledButton(
              onPressed: s.once.running()
                  ? null
                  : () async {
                      final cents = context.parseAmountIn(s.c[0].text, wallet);
                      if (cents == null) {
                        say(sheet, sheet.t.accountsCountInvalid(wallet));
                        return;
                      }
                      // The key lives with the sheet: a second tap, or a retry, is the same count
                      final text = await s.once.run(
                        (key) =>
                            _record(sheet, ref, account, cents, wallet, key),
                      );
                      if (text != null) close(text);
                    },
              child: Text(sheet.t.accountsSaveCount),
            ),
          ],
        ),
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
    String key,
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
      var answer = asJson(await api.verb('snapshot_record', base, key));
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
          }, '$key-ok'),
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

/// One key per account and currency for adding a wallet, until it works.
final Once _walletOnce = Once();

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
  const _TotalCard({required this.assets, required this.net});

  final AsyncValue<Json> assets;

  /// The person chose to lead with the net.
  final bool net;

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
    // The net leads only when the server sent it: an older answer or one it could not work out shows the total as counted
    final netTotal = net ? netInt(data, 'netTotal') : null;
    final shortTotal = netInt(data, 'shortfallTotal') ?? 0;
    final ratesLabel = asOf == null
        ? t.accountsRatesNone
        : old
        ? t.accountsRatesStale(ratesDate(context, asOf))
        : t.accountsRatesAsOf(ratesDate(context, asOf));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: PaperCard(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              netTotal == null ? t.accountsTotalTitle : t.netTotalTitle,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: c.muted),
            ),
            const SizedBox(height: 6),
            // A very large total shrinks to fit instead of wrapping
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Amount(
                netTotal ?? intOf(data['total']),
                currency: main,
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ),
            if (netTotal != null ||
                (net && netTotal == null) ||
                missing.isNotEmpty ||
                offline) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (netTotal != null) ...<Widget>[
                    InfoPill(
                      text: t.netGross(
                        context.moneyIn(intOf(data['total']), main),
                      ),
                      color: c.muted,
                    ),
                    if (shortTotal > 0)
                      InfoPill(
                        text: t.netShortfall(context.moneyIn(shortTotal, main)),
                        color: c.warning,
                        icon: Icons.warning_amber_rounded,
                      ),
                  ],
                  if (net && netTotal == null)
                    InfoPill(
                      text: t.netUnavailable,
                      color: c.muted,
                      icon: Icons.info_outline,
                    ),
                  if (missing.isNotEmpty)
                    InfoPill(
                      text: t.accountsMissingRate(missing.join(', ')),
                      color: c.warning,
                      icon: Icons.warning_amber_rounded,
                    ),
                  if (offline)
                    InfoPill(
                      text: t.accountsRatesOffline,
                      color: c.muted,
                      icon: Icons.cloud_off_outlined,
                    ),
                ],
              ),
            ],
            // One line per added currency with its rate against the main currency (display only, shown as the server sent it)
            for (final e in rateLinesOf(data, main).entries)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t.accountsRateLine(e.key, e.value, main),
                  style: TextStyle(color: c.muted, fontFeatures: tabular),
                ),
              ),
            const SizedBox(height: 12),
            const Divider(),
            // The rates line is also the button that updates them (a 48 dp target)
            ActionRow(
              icon: old ? Icons.sync_problem_outlined : Icons.sync,
              label: ratesLabel,
              semanticLabel: t.accountsRatesRefresh,
              onTap: () => refreshRates(context, ref),
            ),
            const Divider(),
            // Time travel: the balances on any past or future day (BTL-20261029-0117)
            ActionRow(
              icon: Icons.timeline,
              label: t.simSeeOverTime,
              onTap: () => context.push('/simulate'),
            ),
            const Divider(),
            // Net or as counted: the same setting as in Settings
            const NetToggleLine(),
          ],
        ),
      ),
    );
  }
}

// -- WALLETS OF ONE ACCOUNT -- //

/// The right block of an account's header, the same on every card: one amount on one line (it shrinks, never wraps) and one small muted
/// line under it. One wallet: its balance (net first when the person chose that) and the gross under it. Several wallets: what the account
/// comes to in the main currency, and under it the currency codes.
class _HeadAmount extends StatelessWidget {
  const _HeadAmount({
    required this.account,
    required this.subtotal,
    required this.main,
    required this.net,
  });

  final Json account;
  final Json? subtotal;
  final String main;
  final bool net;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wallets = walletsOf(account);
    final big = Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w400);
    if (wallets.length == 1) {
      final only = wallets.first;
      return NetAmount(
        wallet: only,
        currency: str(
          only['currency'],
          str(account['currency'], defaultCurrency),
        ),
        style: big,
        lead: net,
      );
    }
    final sub = subtotal;
    if (sub == null) return const SizedBox.shrink();
    final gross = intOf(sub['subtotal']);
    final netTotal = net ? netInt(sub, 'netSubtotal') : null;
    // The currencies it holds, so the total reads as "all of these"
    final small = wallets.map((w) => str(w['currency'])).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Amount(netTotal ?? gross, currency: main, style: big),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            small,
            maxLines: 1,
            style: TextStyle(color: c.muted, fontFeatures: tabular),
          ),
        ),
      ],
    );
  }
}

/// The wallets of an account that holds several currencies, in one calm panel under the header: a row per currency with its code, what it is
/// worth in the main currency (for the others), and its balance on the right, all on one line so the rows read as a list.
class _Wallets extends StatelessWidget {
  const _Wallets({
    required this.account,
    required this.net,
    required this.main,
    required this.values,
  });

  final Json account;

  /// Lead with each wallet's net where the server sent one.
  final bool net;
  final String main;

  /// What each wallet is worth in the main currency, by "accountId|CODE" (a wallet without a rate is not in it).
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final own = str(account['currency'], defaultCurrency);
    final rows = <Widget>[];
    for (final w in walletsOf(account)) {
      final code = str(w['currency'], own);
      final netBalance = net ? netInt(w, 'netBalance') : null;
      final short = net ? (netInt(w, 'shortfall') ?? 0) : 0;
      final worth = code == main ? null : values['${str(account['id'])}|$code'];
      if (rows.isNotEmpty) rows.add(Divider(height: 1, color: c.line));
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.chip,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      code,
                      style: text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: worth == null
                        ? const SizedBox.shrink()
                        : Text(
                            '≈ ${context.moneyIn(worth, main)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.muted,
                              fontFeatures: tabular,
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Amount(
                        netBalance ?? intOf(w['balance']),
                        currency: code,
                        style: text.titleMedium,
                      ),
                    ),
                  ),
                ],
              ),
              if (short > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.t.netShortfall(context.moneyIn(short, code)),
                    textAlign: TextAlign.end,
                    style: TextStyle(color: c.warning, fontFeatures: tabular),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(children: rows),
    );
  }
}

// -- FUNCTIONS -- //
