// WHICH SERVER OPERATIONS CAN CHANGE WHAT THE ACCOUNTS SCREEN SHOWS (BTL-20261107-0354)
// The balances and the net behind them depend on the ledger, the bills, goals, rules, paydays, splits and the main currency, so the family of a verb
// decides, not a short fixed list: a new verb in a family is covered with no edit here. After one of these succeeds the shared money lists are read again.

// -- CONSTANTS -- //

/// Verb name starts that belong to the money plan or the ledger.
const List<String> _moneyFamilies = <String>[
  'expense_',
  'income_',
  'refund_',
  'transfer_',
  'bill_',
  'goal_',
  'rule_',
  'split_',
  'account_',
  'snapshot_',
  'mark_',
  'payday_',
  'fx_rates_refresh',
  'settings_set',
  'data_reset',
  'undo',
];

/// Name ends of verbs that only read, even inside a money family.
const List<String> _readSuffixes = <String>[
  '_get',
  '_list',
  '_history',
  '_paydays',
  '_upcoming',
  '_undoable',
  '_preview',
  '_convert',
  '_summary',
];

// -- FUNCTIONS -- //

/// True when a successful call of [verb] may have changed a balance, a bill, a goal or the plan around them.
bool changesMoney(String verb) {
  for (final s in _readSuffixes) {
    if (verb.endsWith(s)) return false;
  }
  for (final f in _moneyFamilies) {
    if (verb.startsWith(f)) return true;
  }
  return false;
}
