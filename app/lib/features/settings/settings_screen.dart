// SETTINGS: WHO IS SIGNED IN, THE LANGUAGE AND CURRENCY, THE APP LOCK, WHAT NOTIFICATIONS SHOW, HOW EARLY REMINDERS COME, WHICH LANGUAGE TO LISTEN FOR AND THE LOOK.
// The lock is only turned on after it has worked once, so a phone with no fingerprint set up cannot lock the person out.
// The language, the assistant's replies, the currency and the first day of the week are kept on the server too (the assistant needs them),
// so they are saved there first and only then shown here. Changing the currency never converts an amount, and the screen says so before it does.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/reminders.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../auth/lock_gate.dart';
import '../money/account_detail_screen.dart';
import 'reminder_status_row.dart';
import 'update_row.dart';

// -- TYPES -- //

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.t;
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final session = ref.watch(sessionProvider).value;
    final currency = currencyOf(s.currency);
    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          PaperCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        session?.name.isNotEmpty ?? false
                            ? session!.name
                            : t.settingsSignedIn,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        session?.email ?? '',
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (await confirm(
                      context,
                      title: t.settingsSignOutTitle,
                      body: t.settingsSignOutBody,
                      yes: t.settingsSignOut,
                    )) {
                      await ref.read(sessionProvider.notifier).signOut();
                    }
                  },
                  child: Text(t.settingsSignOut),
                ),
              ],
            ),
          ),

          // -- LANGUAGE AND MONEY -- //
          SectionTitle(t.settingsSectionLanguageMoney),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: s.language,
            decoration: InputDecoration(labelText: t.settingsAppLanguage),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'en',
                child: Text(t.settingsLanguageEn),
              ),
              DropdownMenuItem<String>(
                value: 'fil',
                child: Text(t.settingsLanguageFil),
              ),
            ],
            onChanged: (l) =>
                l == null ? null : _save(context, ref, language: l),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: s.replyLanguage,
            decoration: InputDecoration(labelText: t.settingsReplies),
            isExpanded: true,
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'auto',
                child: Text(t.settingsRepliesAuto),
              ),
              DropdownMenuItem<String>(
                value: 'en',
                child: Text(t.settingsRepliesEn),
              ),
              DropdownMenuItem<String>(
                value: 'fil',
                child: Text(t.settingsRepliesFil),
              ),
              DropdownMenuItem<String>(
                value: 'taglish',
                child: Text(t.settingsRepliesTaglish),
              ),
            ],
            onChanged: (r) =>
                r == null ? null : _save(context, ref, replyLanguage: r),
          ),
          const SizedBox(height: 12),
          PaperCard(
            onTap: () => _pickCurrency(context, ref, s.currency),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        t.settingsCurrency,
                        style: TextStyle(color: c.muted),
                      ),
                      Text(
                        '${currency.code} · ${currency.name}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Text(
                  formatMoney(123456, currency.code),
                  style: TextStyle(color: c.muted, fontFeatures: tabular),
                ),
                Icon(Icons.chevron_right, color: c.muted),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(t.settingsWeekStarts, style: TextStyle(color: c.muted)),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: <ButtonSegment<int>>[
              ButtonSegment<int>(value: 1, label: Text(t.settingsMonday)),
              ButtonSegment<int>(value: 0, label: Text(t.settingsSunday)),
            ],
            selected: <int>{s.weekStartsOn},
            onSelectionChanged: (w) =>
                _save(context, ref, weekStartsOn: w.first),
          ),

          // -- PRIVACY -- //
          SectionTitle(t.settingsPrivacy),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.settingsLockTitle),
            value: s.lockOn,
            onChanged: (on) async {
              if (on && !await ref.read(authenticateProvider)()) {
                if (context.mounted) say(context, t.settingsLockNeeds);
                return;
              }
              await notifier.update(s.copyWith(lockOn: on));
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.settingsHideTitle),
            subtitle: Text(
              t.settingsHideBody,
              style: TextStyle(color: c.muted),
            ),
            value: s.hideDetails,
            onChanged: (on) async {
              await notifier.update(s.copyWith(hideDetails: on));
              await flushAndSync(ref.container);
            },
          ),

          // -- AUDIT TRAIL -- //
          const _AuditRow(),

          // -- APP VERSION AND UPDATES -- //
          const UpdateRow(),

          // -- REMINDERS -- //
          SectionTitle(t.settingsReminders),
          const ReminderStatusRow(),
          DropdownButtonFormField<int>(
            // ignore: deprecated_member_use
            value: s.leadMinutes,
            decoration: InputDecoration(labelText: t.settingsLeadLabel),
            items: <DropdownMenuItem<int>>[
              DropdownMenuItem<int>(
                value: 0,
                child: Text(t.settingsLeadAtTime),
              ),
              DropdownMenuItem<int>(value: 15, child: Text(t.settingsLead15)),
              DropdownMenuItem<int>(value: 60, child: Text(t.settingsLead60)),
              DropdownMenuItem<int>(value: 180, child: Text(t.settingsLead180)),
              DropdownMenuItem<int>(
                value: 1440,
                child: Text(t.settingsLead1440),
              ),
            ],
            onChanged: (m) async {
              if (m == null) return;
              await notifier.update(s.copyWith(leadMinutes: m));
              await flushAndSync(ref.container);
            },
          ),

          // -- VOICE -- //
          SectionTitle(t.settingsVoice),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: s.speechLocale,
            decoration: InputDecoration(labelText: t.settingsListenFor),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'en_PH',
                child: Text(t.settingsListenEn),
              ),
              DropdownMenuItem<String>(
                value: 'fil_PH',
                child: Text(t.settingsListenFil),
              ),
            ],
            onChanged: (l) =>
                l == null ? null : notifier.update(s.copyWith(speechLocale: l)),
          ),

          // -- LOOK -- //
          SectionTitle(t.settingsLook),
          SegmentedButton<ThemeMode>(
            segments: <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text(t.settingsLookPhone),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                label: Text(t.settingsLookLight),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                label: Text(t.settingsLookDark),
              ),
            ],
            selected: <ThemeMode>{s.themeMode},
            onSelectionChanged: (m) =>
                notifier.update(s.copyWith(themeMode: m.first)),
          ),

          // -- DANGER ZONE -- //
          SectionTitle(t.resetSection),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 56,
            leading: Icon(Icons.delete_outline, color: c.danger),
            title: Text(t.resetTitle),
            subtitle: Text(t.resetLine, style: TextStyle(color: c.muted)),
            onTap: () => context.push('/settings/reset'),
          ),
        ],
      ),
    );
  }

  // -- FUNCTIONS -- //

  /// Saves one of the shared choices on the server and then here. A failure is said in words and the old value stays.
  Future<void> _save(
    BuildContext context,
    WidgetRef ref, {
    String? currency,
    String? language,
    String? replyLanguage,
    int? weekStartsOn,
  }) async {
    try {
      final notice = await ref
          .read(settingsProvider.notifier)
          .saveToServer(
            currency: currency,
            language: language,
            replyLanguage: replyLanguage,
            weekStartsOn: weekStartsOn,
          );
      // The notice is the server's English sentence; the screen's own words carry the meaning in the person's language
      if (notice != null) ref.invalidate(balancesProvider);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
  }

  /// A searchable list of currencies. Choosing one asks once, and says that nothing is converted.
  Future<void> _pickCurrency(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colors.paper,
      builder: (sheet) => _CurrencySheet(current: current),
    );
    if (chosen == null || chosen == current || !context.mounted) return;
    final t = context.t;
    final picked = currencyOf(chosen);
    final yes = await confirm(
      context,
      title: t.settingsCurrencyConfirmTitle(picked.code),
      body: t.settingsCurrencyConfirmBody(picked.name),
      yes: t.settingsCurrencyChange,
    );
    if (yes && context.mounted) {
      await _save(context, ref, currency: chosen);
    }
  }
}

/// The list inside the sheet: a search field and every currency with its symbol and an example amount.
class _CurrencySheet extends StatefulWidget {
  const _CurrencySheet({required this.current});

  final String current;

  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  // -- STATES -- //

  String _query = '';

  // -- FUNCTIONS -- //

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    final needle = _query.trim().toLowerCase();
    final shown = currencies
        .where(
          (x) =>
              needle.isEmpty ||
              x.code.toLowerCase().contains(needle) ||
              x.name.toLowerCase().contains(needle),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: t.settingsCurrencySearch,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Note(t.settingsCurrencyNone)
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final x = shown[i];
                          final selected = x.code == widget.current;
                          return ListTile(
                            minTileHeight: 56,
                            selected: selected,
                            leading: SizedBox(
                              width: 48,
                              child: Text(
                                x.code,
                                style: TextStyle(
                                  color: c.accentText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            title: Text(x.name),
                            subtitle: Text(
                              t.settingsCurrencyExample(
                                formatMoney(123456, x.code),
                              ),
                              style: TextStyle(
                                color: c.muted,
                                fontFeatures: tabular,
                              ),
                            ),
                            trailing: selected
                                ? Icon(Icons.check, color: c.accent)
                                : null,
                            onTap: () => Navigator.of(context).pop(x.code),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -- AUDIT ROW -- //

/// The audit trail's state in one quiet row: checked and in order, or the entry that is not.
class _AuditRow extends ConsumerWidget {
  const _AuditRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final verify = ref.watch(auditVerifyProvider);
    final String detail = verify.when(
      data: (v) {
        if (boolOf(v['ok'], true)) {
          final at = dateOf(v['verifiedAt'])?.toLocal() ?? DateTime.now();
          return t.auditSettingsOk(
            intOf(v['checked']),
            DateFormat.MMMd(Localizations.localeOf(context).toString())
                .add_jm()
                .format(at),
          );
        }
        final p = asJson(v['problem']);
        return t.auditSettingsBad(intOf(p['seq']), str(p['kind']));
      },
      loading: () => t.auditChecking,
      error: (_, _) => t.auditChecking,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      leading: Icon(Icons.verified_outlined, color: c.accentText),
      title: Text(t.auditSettingsTitle),
      subtitle: Text(
        '${t.auditSettingsLine}\n$detail',
        style: TextStyle(color: c.muted),
      ),
      onTap: () => ref.invalidate(auditVerifyProvider),
    );
  }
}
