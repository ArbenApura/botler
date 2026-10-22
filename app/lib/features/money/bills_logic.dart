// HOW THE BILLS SCREEN GROUPS WHAT IS DUE: OVERDUE FIRST, THEN ONE GROUP PER MONTH. NO WIDGETS HERE, SO IT IS EASY TO TEST.
// A date is text (yyyy-MM-dd), so the month of a date is its first seven letters and no time zone can move it into another month.

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/manila.dart';

// -- CONSTANTS -- //

/// How far back the screen looks for a bill that is late (about three months), and how far ahead it shows (about four months).
const int billsLookbackDays = 92;
const int billsAheadDays = 122;

// -- TYPES -- //

/// One block of the list: the late bills, or the bills of one month.
class DueGroup {
  const DueGroup({required this.month, required this.rows});

  /// yyyy-MM, or an empty text for the late bills.
  final String month;
  final List<Json> rows;

  bool get isOverdue => month.isEmpty;
}

// -- FUNCTIONS -- //

/// The first and last date the screen asks for, from today.
({String from, String to}) billsRange(String today) => (
  from: addDaysTo(today, -billsLookbackDays),
  to: addDaysTo(today, billsAheadDays),
);

/// Leaves out unpaid due dates from before the month a bill was added: nobody owes what Botler did not know about. A bill added on
/// the 22nd still shows its 5th as late, but not the months before. [bills] are the rows of `bills_list` (they carry `createdAt`).
List<Json> withoutBeforeAdded(List<Json> rows, List<Json> bills) {
  final added = <String, String>{};
  for (final b in bills) {
    final at = DateTime.tryParse(str(b['createdAt']));
    if (at != null) added[str(b['id'])] = manilaToday(at).substring(0, 7);
  }
  return rows.where((r) {
    final month = added[str(r['billId'])];
    return month == null ||
        boolOf(r['paid']) ||
        str(r['dueDate']).substring(0, 7).compareTo(month) >= 0;
  }).toList();
}

/// Splits the due rows (from `bills_due`) into the late ones and one group per month, in date order. A late bill is one that is unpaid
/// and due before [today]; a paid bill from before this month is left out, and an empty month is not shown.
List<DueGroup> groupDue(List<Json> rows, String today) {
  final sorted = List<Json>.of(rows)
    ..sort((a, b) {
      final byDate = str(a['dueDate']).compareTo(str(b['dueDate']));
      return byDate != 0 ? byDate : str(a['name']).compareTo(str(b['name']));
    });
  final monthStart = '${today.substring(0, 7)}-01';
  final overdue = <Json>[];
  final months = <String, List<Json>>{};
  for (final r in sorted) {
    final date = str(r['dueDate']);
    final paid = boolOf(r['paid']);
    if (!paid && date.compareTo(today) < 0) {
      overdue.add(r);
    } else if (date.compareTo(paid ? monthStart : today) >= 0) {
      months.putIfAbsent(date.substring(0, 7), () => <Json>[]).add(r);
    }
  }
  return <DueGroup>[
    if (overdue.isNotEmpty) DueGroup(month: '', rows: overdue),
    for (final m in months.keys.toList()..sort())
      DueGroup(month: m, rows: months[m] ?? const <Json>[]),
  ];
}

/// Whether anything in the groups still has to be paid.
bool anyUnpaid(List<DueGroup> groups) =>
    groups.any((g) => g.rows.any((r) => !boolOf(r['paid'])));
