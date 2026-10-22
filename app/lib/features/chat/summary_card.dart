// THE SUMMARY CARD AT THE TOP OF THE CHAT: THREE QUIET LINES (THE TOTAL ACROSS ACCOUNTS, THE NEXT BILL, TODAY'S FIRST EVENT). IT SCROLLS AWAY WITH THE CHAT,
// AND A SMALL CHIP WITH THE TOTAL TAKES ITS PLACE AT THE TOP OF A LONG CHAT.
// With no connection it shows the last answer that worked and says so.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- TYPES -- //

class SummaryCard extends ConsumerWidget {
  const SummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sync = ref.watch(syncProvider);
    return PaperCard(
      // A refresh keeps the last answer on screen instead of flashing the card empty
      child: sync.when(
        skipLoadingOnReload: true,
        loading: () => const _SummarySkeleton(),
        error: (e, _) =>
            Text(errorWords(e, context), style: TextStyle(color: c.muted)),
        data: (s) {
          final summary = asJson(s['summary']);
          final bill = summary['nextBill'] is Map<Object?, Object?>
              ? asJson(summary['nextBill'])
              : null;
          final event = summary['firstEventToday'] is Map<Object?, Object?>
              ? asJson(summary['firstEventToday'])
              : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.t.chatAcrossAccounts,
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                  if (boolOf(s['offline'])) const _OfflineChip(),
                ],
              ),
              const SizedBox(height: 2),
              // The same light figure as every other balance in the app
              Amount(intOf(summary['total'])),
              const SizedBox(height: 14),
              _Line(
                icon: Icons.receipt_long_outlined,
                text: bill == null
                    ? context.t.chatNoBill
                    : context.t.chatNextBill(
                        str(bill['name']),
                        _day(context, str(bill['dueDate'])),
                      ),
              ),
              const SizedBox(height: 8),
              _Line(
                icon: Icons.event_outlined,
                text: event == null
                    ? context.t.chatNoEvent
                    : '${_time(context, str(event['startsAt']))}  ${str(event['title'])}',
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The card while it loads: the same lines in the same places, so it does not change height when the answer comes.
class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SkeletonLine(widthFactor: 0.4, height: 20),
        SizedBox(height: 2),
        SkeletonLine(widthFactor: 0.55, height: 36),
        SizedBox(height: 14),
        SkeletonLine(widthFactor: 0.75, height: 20),
        SizedBox(height: 8),
        SkeletonLine(widthFactor: 0.65, height: 20),
      ],
    ),
  );
}

/// "Offline" as a small outlined chip in the warning colour (outlined, so no tinted background is needed in either mode).
class _OfflineChip extends StatelessWidget {
  const _OfflineChip();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c.warning),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.t.chatOffline,
        style: TextStyle(color: c.warning, fontSize: 12),
      ),
    );
  }
}

/// Opens the summary in a sheet, from the app bar, so the person never has to scroll a long chat back to its top to see the money.
void showSummarySheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.colors.paper,
    builder: (_) => const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SummaryCard(),
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, size: 18, color: context.colors.muted),
      const SizedBox(width: 8),
      Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ],
  );
}

// -- FUNCTIONS -- //

String _day(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  return d == null
      ? iso
      : DateFormat(
          'MMM d',
          Localizations.localeOf(context).toString(),
        ).format(d);
}

String _time(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  return d == null
      ? ''
      : DateFormat(
          'h:mm a',
          Localizations.localeOf(context).toString(),
        ).format(d.toLocal());
}
