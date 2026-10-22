// THE SUMMARY CARD AT THE TOP OF THE CHAT: THREE QUIET LINES (THE TOTAL ACROSS ACCOUNTS, THE NEXT BILL, TODAY'S FIRST EVENT). IT SCROLLS AWAY WITH THE CHAT.
// With no connection it shows the last answer that worked and says so. A calendar sync that stopped shows one line with a way to fix it.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
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
      child: sync.when(
        loading: () => const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text(errorWords(e), style: TextStyle(color: c.muted)),
        data: (s) {
          final summary = asJson(s['summary']);
          final bill = summary['nextBill'] is Map<Object?, Object?>
              ? asJson(summary['nextBill'])
              : null;
          final event = summary['firstEventToday'] is Map<Object?, Object?>
              ? asJson(summary['firstEventToday'])
              : null;
          final calendar = asJson(s['calendar']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'Across your accounts',
                    style: TextStyle(color: c.muted),
                  ),
                  const Spacer(),
                  if (boolOf(s['offline']))
                    Text('offline', style: TextStyle(color: c.warning)),
                ],
              ),
              Amount(intOf(summary['total'])),
              const SizedBox(height: 12),
              _Line(
                icon: Icons.receipt_long_outlined,
                text: bill == null
                    ? 'No bill coming up'
                    : 'Next bill: ${str(bill['name'])}, ${_day(str(bill['dueDate']))}',
              ),
              const SizedBox(height: 6),
              _Line(
                icon: Icons.event_outlined,
                text: event == null
                    ? 'Nothing on your calendar today'
                    : '${_time(str(event['startsAt']))}  ${str(event['title'])}',
              ),
              if (str(calendar['status']) == 'error') ...<Widget>[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => context.push('/settings'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Google Calendar stopped syncing. Tap to reconnect.',
                      style: TextStyle(color: c.warning),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
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

String _day(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat('MMM d').format(d);
}

String _time(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? '' : DateFormat('h:mm a').format(d.toLocal());
}
