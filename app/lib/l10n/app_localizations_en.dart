// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accountsAdd => 'Add an account';

  @override
  String get accountsAddInvalid =>
      'Give it a name, and the minimum as an amount.';

  @override
  String get accountsBelowMinimum => 'Below the minimum you set';

  @override
  String accountsBotlerThinks(String amount) {
    return 'Botler thinks there is $amount.';
  }

  @override
  String get accountsConfirmBig => 'That is a big difference';

  @override
  String accountsConfirmBoth(String counted, String expected) {
    return 'You counted $counted and Botler expected $expected.';
  }

  @override
  String accountsConfirmCounted(String counted) {
    return 'You counted $counted.';
  }

  @override
  String get accountsConfirmLarge =>
      'It is more than ten times different, so please check the digits.';

  @override
  String get accountsConfirmRight => 'Is this right?';

  @override
  String get accountsConfirmYes => 'Yes, that is right';

  @override
  String accountsCountInvalid(String currency) {
    return 'Type the amount in $currency.';
  }

  @override
  String accountsCountLabel(String currency) {
    return 'How much is really there? ($currency)';
  }

  @override
  String accountsCountTitle(String name) {
    return 'I counted $name';
  }

  @override
  String accountsCounted(String when) {
    return 'Counted $when';
  }

  @override
  String get accountsCurrencyLabel => 'Currency';

  @override
  String get accountsCurrencyNote =>
      'What is in this account is counted in this currency unless you pick another when you enter something.';

  @override
  String accountsDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
    );
    return '$_temp0';
  }

  @override
  String get accountsEmpty => 'No accounts yet. Add RCBC, GCash, Maya or cash.';

  @override
  String get accountsKindBank => 'Bank';

  @override
  String get accountsKindCash => 'Cash';

  @override
  String get accountsKindEwallet => 'E-wallet';

  @override
  String get accountsKindOther => 'Other';

  @override
  String accountsMinimumLabel(String currency) {
    return 'Keep at least ($currency, optional)';
  }

  @override
  String accountsMissingRate(String currencies) {
    return 'No exchange rate yet for $currencies. It is not in the total.';
  }

  @override
  String get accountsNameHint => 'GCash';

  @override
  String get accountsNameLabel => 'Name';

  @override
  String get accountsNeverCounted => 'Never counted';

  @override
  String accountsNoMainWallet(String currency) {
    return 'Nothing in $currency here, so the minimum is not checked.';
  }

  @override
  String get accountsNotSaved => 'Not saved.';

  @override
  String accountsRatesAsOf(String date) {
    return 'Exchange rates as of $date';
  }

  @override
  String get accountsRatesFailed =>
      'Could not update the rates. The last ones are still used.';

  @override
  String get accountsRatesNone => 'No exchange rates yet. Tap to get them.';

  @override
  String get accountsRatesOffline => 'No connection. Showing the last total.';

  @override
  String get accountsRatesRefresh => 'Update rates';

  @override
  String accountsRatesStale(String date) {
    return 'Exchange rates are old (from $date). Tap to update.';
  }

  @override
  String get accountsRatesTooSoon => 'The rates were just updated.';

  @override
  String get accountsRatesUpdated => 'Exchange rates updated.';

  @override
  String get accountsSaveCount => 'Save the count';

  @override
  String get accountsSaved => 'Saved.';

  @override
  String accountsSavedUntracked(String amount) {
    return 'Saved. $amount went untracked since the last count.';
  }

  @override
  String accountsSubtotal(String amount) {
    return 'About $amount in all';
  }

  @override
  String get accountsTitle => 'Accounts';

  @override
  String get accountsToday => 'today';

  @override
  String get accountsTotalTitle => 'Everything you have';

  @override
  String get accountsTotalUnavailable =>
      'The total needs exchange rates, and there are none yet.';

  @override
  String get accountsWalletAdd => 'Add a currency';

  @override
  String accountsWalletAdded(String currency) {
    return '$currency added.';
  }

  @override
  String get accountsWalletsTitle => 'Currencies in this account';

  @override
  String get accountsYesterday => 'yesterday';

  @override
  String get acctBalanceNow => 'Balance now';

  @override
  String get acctByAnyone => 'Anyone';

  @override
  String get acctByBotler => 'Botler';

  @override
  String get acctByJob => 'Jobs and sync';

  @override
  String get acctByYou => 'You';

  @override
  String get acctDateClear => 'Any date';

  @override
  String get acctDateRange => 'Dates';

  @override
  String get acctEmpty => 'Nothing here yet.';

  @override
  String acctExportCut(int rows, String format, String notice) {
    return 'Copied $rows rows as $format. $notice';
  }

  @override
  String acctExportDone(int rows, String format) {
    return 'Copied $rows rows as $format.';
  }

  @override
  String get acctLoadMore => 'Show older';

  @override
  String get acctMenuCount => 'I counted this';

  @override
  String get acctMenuExport => 'Export history';

  @override
  String get acctMenuPurpose => 'Edit label';

  @override
  String get acctMenuReset => 'Reset to zero';

  @override
  String get acctMenuSet => 'Set balance';

  @override
  String get acctOffline => 'The history needs a connection.';

  @override
  String get acctOpen => 'See what happened';

  @override
  String get acctSearchHint => 'Search notes';

  @override
  String get acctTabAll => 'All';

  @override
  String get acctTabCounts => 'Counts and resets';

  @override
  String get acctTabIn => 'Money in';

  @override
  String get acctTabOut => 'Money out';

  @override
  String get acctTabUndone => 'Undone';

  @override
  String get add => 'Add';

  @override
  String get agendaAddEvent => 'Add an event';

  @override
  String get agendaAddRoutine => 'Add a routine';

  @override
  String get agendaAddTask => 'Add a task';

  @override
  String get agendaAlarm => 'Alarm';

  @override
  String agendaAtTime(String time) {
    return 'At $time';
  }

  @override
  String agendaDaysAt(String days, String time) {
    return '$days at $time';
  }

  @override
  String agendaDue(String when) {
    return 'Due $when';
  }

  @override
  String get agendaEventNeeds => 'Give it a name and a time.';

  @override
  String get agendaEventSubmit => 'Add the event';

  @override
  String get agendaEventWhat => 'What is it?';

  @override
  String get agendaEventsEmpty => 'No events in the next two weeks.';

  @override
  String agendaEveryDayAt(String time) {
    return 'Every day at $time';
  }

  @override
  String agendaEveryNDaysAt(String n, String time) {
    return 'Every $n days at $time';
  }

  @override
  String get agendaFreqDaily => 'Every day';

  @override
  String get agendaFreqWeekly => 'On some days';

  @override
  String agendaMonthlyAt(String day, String time) {
    return 'Every month on the ${day}th at $time';
  }

  @override
  String get agendaPickMoment => 'Pick the day and time';

  @override
  String get agendaRemindMe => 'Remind me';

  @override
  String get agendaReminderNeeds => 'Say what for, and when.';

  @override
  String get agendaReminderWhat => 'What for?';

  @override
  String get agendaRemindersEmpty => 'No reminders waiting.';

  @override
  String get agendaRemove => 'Remove';

  @override
  String get agendaRoutineHint => 'Take vitamins';

  @override
  String get agendaRoutineNeeds => 'Give it a name, and pick at least one day.';

  @override
  String get agendaRoutineSubmit => 'Add the routine';

  @override
  String get agendaRoutinesEmpty =>
      'No routines. Try “gym every Monday, Wednesday and Friday at 6”.';

  @override
  String get agendaSetAlarm => 'Set an alarm';

  @override
  String get agendaStartTimer => 'Start a timer';

  @override
  String get agendaTabEvents => 'Events';

  @override
  String get agendaTabReminders => 'Reminders';

  @override
  String get agendaTabRoutines => 'Routines';

  @override
  String get agendaTabTasks => 'Tasks';

  @override
  String get agendaTaskDeadline => 'Set a deadline (optional)';

  @override
  String get agendaTaskNeedsTitle => 'Say what the task is.';

  @override
  String get agendaTaskSubmit => 'Add the task';

  @override
  String get agendaTaskWhat => 'What needs doing?';

  @override
  String get agendaTasksEmpty =>
      'Nothing open. Add something you want to remember to do.';

  @override
  String get agendaTimerMinutes => 'How many minutes?';

  @override
  String get agendaTimerRange => 'Pick between 1 and 1440 minutes.';

  @override
  String get agendaTimerStart => 'Start';

  @override
  String get agendaTitle => 'Agenda';

  @override
  String get appName => 'Botler';

  @override
  String get auditAcApprove => 'Approved';

  @override
  String get auditAcCount => 'Counted';

  @override
  String get auditAcCreate => 'Added';

  @override
  String get auditAcDataReset => 'Data reset';

  @override
  String get auditAcDelete => 'Removed';

  @override
  String get auditAcExpire => 'Expired';

  @override
  String get auditAcReject => 'Declined';

  @override
  String get auditAcReset => 'Reset';

  @override
  String get auditAcUndo => 'Undone';

  @override
  String get auditAcUpdate => 'Changed';

  @override
  String get auditBalanceAfter => 'Balance after';

  @override
  String auditBannerBody(int seq) {
    return 'Entry $seq no longer matches the one before it. Nothing was lost on this phone. Open Settings, Audit trail, and send the details to whoever runs your server.';
  }

  @override
  String get auditBannerTitle => 'The audit trail does not add up';

  @override
  String get auditBotler => 'Botler';

  @override
  String get auditBotlerApproved => 'Botler, approved by you';

  @override
  String get auditChApp => 'in the app';

  @override
  String get auditChCalendar => 'Calendar sync (retired)';

  @override
  String get auditChChat => 'in chat';

  @override
  String get auditChJob => 'a job';

  @override
  String get auditChOutbox => 'offline, sent later';

  @override
  String get auditChSystem => 'the system';

  @override
  String get auditChWidget => 'from the widget';

  @override
  String auditChangeLine(String field, String before, String after) {
    return '$field: $before to $after';
  }

  @override
  String get auditChanges => 'What changed';

  @override
  String get auditChecking => 'Checking...';

  @override
  String get auditCopied => 'Reference copied.';

  @override
  String get auditCopyRef => 'Copy reference';

  @override
  String get auditEnSnapshot => 'balance count';

  @override
  String get auditEnTxn => 'transaction';

  @override
  String get auditJob => 'A scheduled job';

  @override
  String get auditNone => 'none';

  @override
  String get auditNote => 'Note';

  @override
  String get auditRefApproval => 'approval';

  @override
  String get auditRefRequest => 'request';

  @override
  String get auditRefTurn => 'turn';

  @override
  String get auditRefs => 'References';

  @override
  String auditRowSemantics(
    String what,
    String who,
    String when,
    String balance,
  ) {
    return '$what, $who, $when, balance after $balance';
  }

  @override
  String auditSettingsBad(int seq, String kind) {
    return 'Entry $seq is out of order ($kind).';
  }

  @override
  String get auditSettingsLine =>
      'Every change to your money is written once and can never be edited or deleted.';

  @override
  String auditSettingsOk(int count, String when) {
    return 'Checked $count entries, all in order. Last check $when.';
  }

  @override
  String get auditSettingsTitle => 'Audit trail';

  @override
  String get auditSync => 'Sync';

  @override
  String get auditUnverified => 'The history could not be checked just now.';

  @override
  String get auditWhen => 'When';

  @override
  String get auditWhere => 'Where';

  @override
  String get auditWho => 'Who';

  @override
  String get auditYou => 'You';

  @override
  String billsAboutLabel(String currency) {
    return 'About how much? ($currency)';
  }

  @override
  String billsAboutMain(String amount) {
    return 'about $amount';
  }

  @override
  String get billsAdd => 'Add a bill';

  @override
  String get billsAddButton => 'Add the bill';

  @override
  String get billsAddInvalid => 'Give it a name, an amount and an account.';

  @override
  String get billsAll => 'All bills';

  @override
  String get billsAmountNotKnown => 'amount not known yet';

  @override
  String get billsAmountUnknown => 'amount?';

  @override
  String billsChargedLabel(String currency) {
    return 'Really charged ($currency)';
  }

  @override
  String billsChargedNote(String bill, String wallet) {
    return 'This bill is in $bill, but you pay from a $wallet wallet. Type what was really charged.';
  }

  @override
  String get billsComingUp => 'Coming up';

  @override
  String get billsCurrencyLabel => 'Currency of this bill';

  @override
  String get billsDateLabel => 'Due date';

  @override
  String get billsDateNote =>
      'This moves only this one. To change every date, change how it repeats below.';

  @override
  String get billsEditHint => 'Tap to change it';

  @override
  String get billsEditTitle => 'Change the bill';

  @override
  String get billsEmpty => 'No bills yet. Add rent, internet, electricity...';

  @override
  String billsHowMuchLabel(String currency) {
    return 'How much? ($currency)';
  }

  @override
  String get billsMarkPaid => 'Mark paid';

  @override
  String billsMarkPaidFor(String name) {
    return 'Mark $name paid';
  }

  @override
  String get billsMarkedPaid => 'Marked paid.';

  @override
  String billsMarkedPaidHint(String amount) {
    return 'Marked paid. It came in $amount under the usual: you could set that aside.';
  }

  @override
  String get billsMissingRateTag => 'no exchange rate yet';

  @override
  String get billsMovedTag => 'moved';

  @override
  String get billsNameHint => 'Rent';

  @override
  String get billsNameLabel => 'What is it?';

  @override
  String get billsNoChange => 'Nothing changed.';

  @override
  String get billsNothingDue => 'Nothing is due in the next 4 months.';

  @override
  String get billsOverdue => 'Overdue';

  @override
  String get billsPaid => 'Paid';

  @override
  String get billsPaidFrom => 'Paid from';

  @override
  String billsPaidTitle(String name) {
    return '$name paid';
  }

  @override
  String get billsParentsShare => 'This is my parents’ share';

  @override
  String get billsParentsTag => 'parents’ share';

  @override
  String billsPayInvalid(String currency) {
    return 'Type the amount in $currency.';
  }

  @override
  String billsPayLabel(String currency) {
    return 'How much was it this time? ($currency)';
  }

  @override
  String get billsPutBack => 'Put back as scheduled';

  @override
  String get billsPutBackDone => 'Back to the schedule.';

  @override
  String get billsRepeatChangedNote =>
      'You changed how it repeats, so every date follows the new rule.';

  @override
  String get billsReserveNote =>
      'The payday split keeps the money for this bill in your main currency. Paying from another wallet can take that wallet below zero.';

  @override
  String get billsSave => 'Save';

  @override
  String get billsSaved => 'Saved.';

  @override
  String get billsSavedOffline =>
      'No connection. It will be saved when you are back online.';

  @override
  String get billsScopeAll => 'Every time from now on';

  @override
  String billsScopeThisOne(String date) {
    return 'Just this one ($date)';
  }

  @override
  String get billsScopeTitle => 'Just this one, or every time?';

  @override
  String get billsSkip => 'Skip this date';

  @override
  String get billsSkipBody =>
      'It will not show up for that date. Ask Botler to put it back if you change your mind.';

  @override
  String billsSkipTitle(String name, String date) {
    return 'Skip $name on $date?';
  }

  @override
  String get billsSkipYes => 'Skip it';

  @override
  String get billsSkipped => 'Skipped.';

  @override
  String get billsTitle => 'Bills';

  @override
  String billsUsualSuffix(String amount) {
    return '$amount (usual)';
  }

  @override
  String get billsVaries => 'The amount is different every time';

  @override
  String get billsWalletLabel => 'Paid in';

  @override
  String get calAdd => 'Add';

  @override
  String get calAddBill => 'A bill';

  @override
  String get calAddEvent => 'An event';

  @override
  String get calAddReminder => 'A reminder';

  @override
  String get calAddTask => 'A task';

  @override
  String calAddTitle(String date) {
    return 'Add to $date';
  }

  @override
  String get calAgendaDueThisWeek => 'Due this week';

  @override
  String get calAgendaEmpty => 'Nothing in the next 30 days.';

  @override
  String get calAgendaMore => 'Show 30 more days';

  @override
  String get calAllDay => 'All day';

  @override
  String get calAllDayToggle => 'All day';

  @override
  String get calAmountUnknown => 'amount?';

  @override
  String calBillDue(String date) {
    return 'Due $date';
  }

  @override
  String get calBillOverdue => 'Overdue';

  @override
  String get calBillPaid => 'Paid';

  @override
  String calBillWindow(String start, String end) {
    return 'Pay any day $start to $end';
  }

  @override
  String calCountBills(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bills',
      one: '1 bill',
    );
    return '$_temp0';
  }

  @override
  String calCountEvents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count events',
      one: '1 event',
    );
    return '$_temp0';
  }

  @override
  String calCountPaydays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paydays',
      one: '1 payday',
    );
    return '$_temp0';
  }

  @override
  String calCountReminders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reminders',
      one: '1 reminder',
    );
    return '$_temp0';
  }

  @override
  String calCountRoutines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count routines',
      one: '1 routine',
    );
    return '$_temp0';
  }

  @override
  String calCountTasks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks',
      one: '1 task',
    );
    return '$_temp0';
  }

  @override
  String get calDayNothing => 'nothing planned';

  @override
  String calDaySemantics(String date, String parts) {
    return '$date, $parts';
  }

  @override
  String get calError => 'The calendar could not load.';

  @override
  String get calEstimate => 'Estimate';

  @override
  String calForecastLow(String account) {
    return '$account may drop under its minimum';
  }

  @override
  String calForecastLowDay(String date) {
    return 'Low on $date';
  }

  @override
  String get calForecastNone =>
      'Nothing to estimate yet. Add an account and a bill first.';

  @override
  String get calForecastOk => 'never under the minimum';

  @override
  String calForecastSemantics(String from, String to, String low) {
    return 'Estimated money across accounts from $from to $to, $low';
  }

  @override
  String get calForecastTitle => 'Where your money is heading';

  @override
  String calForecastTotal(String amount) {
    return 'About $amount';
  }

  @override
  String calForecastUnconverted(int count) {
    return '$count bills in other currencies are left out of this forecast because their exchange rate is missing.';
  }

  @override
  String calForecastUnknown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bills have no amount yet, so they count as nothing',
      one: '1 bill has no amount yet, so it counts as nothing',
    );
    return '$_temp0';
  }

  @override
  String get calLayerBills => 'Bills';

  @override
  String get calLayerEvents => 'Events';

  @override
  String get calLayerPaydays => 'Paydays';

  @override
  String get calLayerReminders => 'Reminders';

  @override
  String get calLayerRoutines => 'Routines';

  @override
  String get calLayerTasks => 'Tasks';

  @override
  String get calLayersLabel => 'Show';

  @override
  String get calMarkPaid => 'Mark paid';

  @override
  String calMarkPaidBody(String amount) {
    return 'This writes $amount as an expense.';
  }

  @override
  String calMarkPaidTitle(String name) {
    return 'Mark $name paid?';
  }

  @override
  String calMore(int count) {
    return '+$count';
  }

  @override
  String get calNeedTitle => 'Give it a name first.';

  @override
  String get calNext => 'Next';

  @override
  String get calNow => 'Now';

  @override
  String get calOffline => 'Showing the last calendar this phone saw.';

  @override
  String get calPaidDone => 'Marked paid.';

  @override
  String get calPaydayLabel => 'Payday';

  @override
  String get calPaydaySplit => 'Split your pay';

  @override
  String get calPaydaySplitDone => 'Split done';

  @override
  String get calPrev => 'Previous';

  @override
  String get calReminderLabel => 'Reminder';

  @override
  String get calRoutineLabel => 'Routine';

  @override
  String get calSaved => 'Saved.';

  @override
  String get calTaskLabel => 'Task';

  @override
  String get calTimeLabel => 'Time';

  @override
  String get calTitle => 'Calendar';

  @override
  String get calToday => 'Today';

  @override
  String get calViewAgenda => 'Agenda';

  @override
  String get calViewMonth => 'Month';

  @override
  String get calViewWeek => 'Week';

  @override
  String calWeekOf(String date) {
    return 'Week of $date';
  }

  @override
  String get calWhatIsIt => 'What is it?';

  @override
  String get cancel => 'Cancel';

  @override
  String changelogBuildHeader(String version) {
    return 'Version $version';
  }

  @override
  String get changelogGotIt => 'Got it';

  @override
  String get changelogRowHint => 'Read the changes in the version you have now';

  @override
  String get changelogRowTitle => 'What is new in this version';

  @override
  String changelogTitle(String version) {
    return 'What is new in $version';
  }

  @override
  String get chatAcrossAccounts => 'Across your accounts';

  @override
  String get chatAddExpense => 'Add an expense';

  @override
  String get chatAddExpenseHint => 'You can still add an expense yourself.';

  @override
  String get chatApprove => 'Approve';

  @override
  String get chatApproveRule => 'Approve rule';

  @override
  String get chatAssistantDown => 'The assistant is not available right now.';

  @override
  String get chatCardElsewhere =>
      'Waiting for your answer in the chat it came from.';

  @override
  String get chatCardExpired => 'This request has expired.';

  @override
  String get chatCardFailed => 'That could not be done.';

  @override
  String chatChecked(String what) {
    return 'Checked $what';
  }

  @override
  String chatCheckedMany(String what, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more times',
      one: '1 more time',
    );
    return '$what, $_temp0';
  }

  @override
  String chatCheckedMore(int count) {
    return '+$count';
  }

  @override
  String chatChecking(String what) {
    return 'Checking $what';
  }

  @override
  String get chatChooseScreenshot => 'Choose a screenshot';

  @override
  String chatConfirmQuestion(String amount, String account) {
    return 'Is it $amount on $account?';
  }

  @override
  String get chatEarlier => 'Earlier';

  @override
  String get chatEditCancel => 'Stop editing';

  @override
  String get chatEditing => 'Editing your message';

  @override
  String get chatGreeting => 'What can I help with?';

  @override
  String get chatHintMessage => 'Message Botler';

  @override
  String get chatHowMuch => 'How much was it?';

  @override
  String get chatInForce => 'In force';

  @override
  String get chatJumpLatest => 'Jump to the latest message';

  @override
  String chatLogged(String amount, String account) {
    return 'Logged $amount on $account';
  }

  @override
  String chatMarkedPaid(String amount) {
    return 'Marked paid · $amount';
  }

  @override
  String get chatMenu => 'Menu';

  @override
  String get chatMicBlocked =>
      'This phone cannot listen right now. Check the microphone permission.';

  @override
  String get chatMsgActions => 'Message actions';

  @override
  String get chatMsgBranch => 'Branch from here';

  @override
  String get chatMsgCopied => 'Copied.';

  @override
  String get chatMsgCopy => 'Copy';

  @override
  String get chatMsgEdit => 'Edit and resend';

  @override
  String chatNeedsAmounts(String names) {
    return 'How much is usually $names? I need an amount to make the split.';
  }

  @override
  String chatNextBill(String name, String day) {
    return 'Next bill: $name, $day';
  }

  @override
  String get chatNoAnswer => 'There was no answer to this one.';

  @override
  String get chatNoBill => 'No bill coming up';

  @override
  String get chatNoEvent => 'Nothing on your calendar today';

  @override
  String get chatNotDone => 'Not done';

  @override
  String get chatNotNow => 'Not now';

  @override
  String get chatNoticeFailed =>
      'The assistant could not finish that. Try again.';

  @override
  String get chatNoticeOffline =>
      'No connection. Saved on your phone. It will be sent once, when you are back online.';

  @override
  String get chatOffline => 'offline';

  @override
  String chatPendingSnack(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries are waiting for a connection.',
      one: '$count entry is waiting for a connection.',
    );
    return '$_temp0';
  }

  @override
  String chatPendingTooltip(int count) {
    return '$count waiting to be sent';
  }

  @override
  String get chatPhotoEmpty => 'I could not read any text on that photo.';

  @override
  String get chatPhotoFailed => 'The photo could not be read.';

  @override
  String chatPhotoRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '$count character',
    );
    return 'Photo read ($_temp0)';
  }

  @override
  String get chatPhotoTooltip => 'Photo of a receipt';

  @override
  String get chatPleaseCheck => 'Please check';

  @override
  String get chatReceiptMessage => 'Here is a receipt.';

  @override
  String chatRecorded(String amount) {
    return 'Recorded $amount';
  }

  @override
  String get chatRestoreFailed => 'Could not load your earlier chat.';

  @override
  String get chatSend => 'Send';

  @override
  String get chatSpeak => 'Speak';

  @override
  String get chatStop => 'Stop';

  @override
  String get chatStopListening => 'Stop listening';

  @override
  String get chatStopped => 'Stopped.';

  @override
  String get chatSuggestDue => 'What is due this week?';

  @override
  String get chatSuggestExpense => 'Log an expense';

  @override
  String get chatSuggestExpenseText => 'I spent ';

  @override
  String get chatSuggestToday => 'What is on my calendar today?';

  @override
  String get chatSummaryOpen => 'Money summary';

  @override
  String get chatTakePhoto => 'Take a photo';

  @override
  String get chatThinking => 'Thinking';

  @override
  String chatThoughtFor(int seconds) {
    return 'Thought for $seconds s';
  }

  @override
  String get chatThoughtToggle => 'Show or hide what the assistant thought';

  @override
  String get chatToolFailed => 'That did not work.';

  @override
  String get chatUndoGone => 'That entry can no longer be undone.';

  @override
  String get chatUndoneLine => 'Undone';

  @override
  String get chatUndoneSnack => 'Undone.';

  @override
  String get chatWaiting => 'Working on it';

  @override
  String chatWhichAccount(String amount) {
    return 'Which account was $amount from?';
  }

  @override
  String chatWithPhoto(String text) {
    return '$text\n(with a photo)';
  }

  @override
  String get chatWriting => 'Writing';

  @override
  String get chatYesLogIt => 'Yes, log it';

  @override
  String get chatYourAccount => 'your account';

  @override
  String get chatsArchive => 'Archive';

  @override
  String get chatsArchivedEmpty => 'Nothing is archived.';

  @override
  String get chatsArchivedOpen => 'Archived chats';

  @override
  String get chatsArchivedTitle => 'Archived';

  @override
  String get chatsBranchMark => 'Branch';

  @override
  String chatsBranchedFrom(String title) {
    return 'Branched from $title';
  }

  @override
  String get chatsBranchedNote =>
      'Changes saved before this point stay saved. Undo them in History.';

  @override
  String get chatsBranchedOpen => 'Open the chat this branched from';

  @override
  String get chatsBranchedUntitled => 'an earlier chat';

  @override
  String get chatsBusy =>
      'Botler is answering. Wait for it, or stop it, to change chats.';

  @override
  String get chatsEmpty => 'Your conversations will show here.';

  @override
  String get chatsGroupOlder => 'Older';

  @override
  String get chatsGroupPinned => 'Pinned';

  @override
  String get chatsGroupToday => 'Today';

  @override
  String get chatsGroupWeek => 'Previous 7 days';

  @override
  String get chatsGroupYesterday => 'Yesterday';

  @override
  String get chatsMore => 'More about this chat';

  @override
  String get chatsNew => 'New chat';

  @override
  String get chatsNoResults => 'No chat matches that.';

  @override
  String get chatsOpen => 'Chats';

  @override
  String get chatsPin => 'Pin';

  @override
  String get chatsPinnedMark => 'Pinned';

  @override
  String get chatsRename => 'Rename';

  @override
  String get chatsRenameInvalid => 'Give it a name of 1 to 80 characters.';

  @override
  String get chatsRenameLabel => 'Name';

  @override
  String get chatsRenameSave => 'Save name';

  @override
  String get chatsRenameTitle => 'Name this chat';

  @override
  String get chatsRestore => 'Restore';

  @override
  String chatsRowLabel(String title, String when) {
    return '$title, $when';
  }

  @override
  String get chatsSearchClear => 'Clear the search';

  @override
  String get chatsSearchHint => 'Search your chats';

  @override
  String get chatsTitle => 'Chats';

  @override
  String get chatsUnpin => 'Unpin';

  @override
  String get chatsUntitled => 'New conversation';

  @override
  String get close => 'Close';

  @override
  String get delete => 'Delete';

  @override
  String get done => 'Done';

  @override
  String get entryCurrencyLabel => 'Currency';

  @override
  String get entryCurrencyOther => 'Other…';

  @override
  String expenseAmountError(String code) {
    return 'Type the amount in $code, like 180 or 1,250.50.';
  }

  @override
  String get expenseFromAccount => 'From which account?';

  @override
  String expenseHowMuch(String code) {
    return 'How much? ($code)';
  }

  @override
  String get expenseLogIt => 'Log it';

  @override
  String expenseLogged(String amount) {
    return 'Logged $amount.';
  }

  @override
  String get expenseNoteHint => 'lunch';

  @override
  String get expenseNoteLabel => 'What was it for? (optional)';

  @override
  String get expenseOffline =>
      'No connection. Saved on your phone, it will be sent once.';

  @override
  String get expensePickAccount => 'Pick the account it came from.';

  @override
  String get expenseTitle => 'Add an expense';

  @override
  String get goalsAdd => 'Add a goal';

  @override
  String get goalsAddButton => 'Add the goal';

  @override
  String get goalsAddInvalid =>
      'Give it a name, a place, and amounts as numbers.';

  @override
  String goalsAim(String amount) {
    return ' · aim $amount';
  }

  @override
  String goalsEachPayday(String amount) {
    return '$amount each payday';
  }

  @override
  String get goalsEmpty => 'No goals yet. What would you like to save for?';

  @override
  String get goalsNameHint => 'Emergency fund';

  @override
  String get goalsNameLabel => 'What are you saving for?';

  @override
  String get goalsOnlyRules => 'Only what your rules give it';

  @override
  String goalsPerLabel(String currency) {
    return 'Set aside each payday ($currency, optional)';
  }

  @override
  String goalsTargetLabel(String currency) {
    return 'The amount you want to reach ($currency, optional)';
  }

  @override
  String get goalsTitle => 'Savings goals';

  @override
  String get goalsWhere => 'Where does it sit?';

  @override
  String goalsYear(String amount) {
    return 'In a year (24 paydays) that is $amount.';
  }

  @override
  String get histEntryTitle => 'Details';

  @override
  String get historyAccountFallback => 'account';

  @override
  String get historyEmpty => 'Nothing here yet.';

  @override
  String get historyFixThis => 'Fix this';

  @override
  String get historyMore => 'More';

  @override
  String historyMoved(String from, String to) {
    return 'Moved $from → $to';
  }

  @override
  String historyOtherCurrencies(String currencies) {
    return 'Also spent in $currencies. Those are not added here.';
  }

  @override
  String get historySearchHint => 'Search by note, category or amount';

  @override
  String get historySpentThisMonth => 'Spent this month';

  @override
  String get historyTitle => 'History';

  @override
  String get historyUndoneSaid => 'Undone.';

  @override
  String get historyUndoneTag => 'undone';

  @override
  String historyUntracked(String amount) {
    return '$amount went untracked (found when you counted an account).';
  }

  @override
  String get lockReason => 'Open Botler';

  @override
  String get lockTitle => 'Botler is locked';

  @override
  String get lockUnlock => 'Unlock';

  @override
  String get memoryAboutLabel => 'A few lines about you';

  @override
  String memoryBefore(String text) {
    return 'Before: $text';
  }

  @override
  String get memoryChange => 'Change';

  @override
  String get memoryChangeTitle => 'Change this memory';

  @override
  String get memoryCopied => 'Copied everything to the clipboard.';

  @override
  String get memoryCopyAll => 'Copy everything (memory and money) as text';

  @override
  String get memoryEmpty =>
      'Nothing yet. Botler learns as you talk, or tell it: “remember that…”.';

  @override
  String get memoryForget => 'Forget';

  @override
  String memoryForgetBody(String text) {
    return '“$text” will be deleted and will not come back.';
  }

  @override
  String get memoryForgetTitle => 'Forget this?';

  @override
  String get memoryForgetYes => 'Forget it';

  @override
  String get memoryForgotten => 'Forgotten.';

  @override
  String get memoryInSentence => 'In a sentence';

  @override
  String get memoryKeepOld => 'Keep the old one';

  @override
  String get memoryLearned => 'Learned from chat';

  @override
  String get memoryMore => 'More';

  @override
  String get memoryNotSure => 'Botler is not sure';

  @override
  String memoryNow(String text) {
    return 'Now: $text';
  }

  @override
  String get memoryPeopleHint => 'Mama, Ate Liza';

  @override
  String get memoryPeopleLabel =>
      'Names to keep private (separate with commas)';

  @override
  String get memoryPeopleNote =>
      'Botler hides these names from the AI that writes its replies.';

  @override
  String get memoryPersonaHint => 'Like a friendly older sister, short answers';

  @override
  String get memoryPersonaLabel => 'How should Botler talk?';

  @override
  String get memoryRememberTitle => 'Remember something';

  @override
  String get memoryRemembers => 'What Botler remembers';

  @override
  String get memorySaved => 'Saved.';

  @override
  String get memorySearchHint => 'Search the memories';

  @override
  String get memoryTalks => 'How Botler talks to you';

  @override
  String get memoryTellSomething => 'Tell Botler something to remember';

  @override
  String get memoryTitle => 'Memory';

  @override
  String get memoryUseNew => 'Use the new one';

  @override
  String get memoryWhichRight => 'Which is right?';

  @override
  String get memoryWipe => 'Wipe';

  @override
  String get memoryWipeBody =>
      'This deletes all memories, summaries and your conversations with Botler. Your accounts, bills and money records stay. It cannot be undone.';

  @override
  String get memoryWipeButton => 'Wipe what Botler remembers';

  @override
  String get memoryWipeTitle => 'Wipe everything Botler remembers?';

  @override
  String get memoryWipeType => 'Type WIPE to confirm';

  @override
  String get memoryWipeWord => 'WIPE';

  @override
  String get memoryWiped => 'Wiped.';

  @override
  String get memoryYouSaid => 'You said';

  @override
  String get memoryYourData => 'Your data';

  @override
  String get menuAccounts => 'Accounts';

  @override
  String get menuAccountsLine => 'What is in each of your accounts';

  @override
  String get menuAgenda => 'Agenda';

  @override
  String get menuAgendaLine => 'Tasks, events, routines and reminders';

  @override
  String get menuBills => 'Bills';

  @override
  String get menuBillsLine => 'What is due, and mark it paid';

  @override
  String get menuCalendar => 'Calendar';

  @override
  String get menuCalendarLine => 'Bills, paydays, events and routines by day';

  @override
  String get menuGoals => 'Savings goals';

  @override
  String get menuGoalsLine => 'What you are saving for';

  @override
  String get menuHistory => 'History';

  @override
  String get menuHistoryLine => 'Everything you spent, and undo';

  @override
  String get menuMemory => 'Memory';

  @override
  String get menuMemoryLine => 'What Botler remembers, and how it talks';

  @override
  String get menuPayday => 'Payday';

  @override
  String get menuPaydayLine => 'Split your pay, and the rules for it';

  @override
  String get menuSettings => 'Settings';

  @override
  String get menuSettingsLine => 'Language, money, lock, notifications, look';

  @override
  String get menuTitle => 'Menu';

  @override
  String get no => 'No';

  @override
  String get notifChannel => 'Reminders';

  @override
  String get notifChannelDescription => 'Bills, paydays, tasks and events';

  @override
  String get notifHiddenBody => 'You have a reminder';

  @override
  String get outboxFailedDismiss => 'Got it';

  @override
  String outboxFailedLine(int count) {
    return '$count changes you made offline did not go through. Tap to see why.';
  }

  @override
  String get outboxFailedTitle => 'Changes the server refused';

  @override
  String get paydayAdd => 'Add a payday';

  @override
  String get paydayAddRule => 'Add a rule';

  @override
  String get paydayApprove => 'Approve';

  @override
  String get paydayComingUp => 'Coming up';

  @override
  String get paydayDecline => 'Decline';

  @override
  String get paydayDifferent => 'Different every time';

  @override
  String get paydayEarlier => 'Earlier splits';

  @override
  String get paydayEmpty => 'Tell Botler when you get paid.';

  @override
  String paydayIncomeAmountLabel(String currency) {
    return 'How much, usually? ($currency, optional)';
  }

  @override
  String get paydayIncomeDefault => 'Salary';

  @override
  String get paydayIncomeInvalid =>
      'Give it a name, an account and the amount as a number.';

  @override
  String get paydayIncomeLabel => 'What do you call it?';

  @override
  String get paydayIncomeTitle => 'When do you get paid?';

  @override
  String get paydayLandsIn => 'It lands in';

  @override
  String get paydayMakeSplit => 'Make the split';

  @override
  String paydayNeedsAmounts(String names) {
    return 'How much is $names usually? Add the amount to the bill first.';
  }

  @override
  String get paydayNoEarlier => 'No earlier splits yet.';

  @override
  String get paydayNoneAhead => 'No payday ahead yet.';

  @override
  String paydayPayInvalid(String currency) {
    return 'Type the pay in $currency.';
  }

  @override
  String get paydayPayLabel =>
      'How much is the pay this time? (leave empty for the usual)';

  @override
  String get paydayPlan => 'Plan the split';

  @override
  String paydayPlanTitle(String label, String date) {
    return 'Plan $label on $date';
  }

  @override
  String get paydayRuleAddButton => 'Add the rule';

  @override
  String get paydayRuleExamples =>
      'Examples: “500 to GCash”, “10% of what is left to Maya”, “the rest to RCBC”.';

  @override
  String get paydayRuleHint => '20% to emergency fund';

  @override
  String get paydayRuleLabel => 'Say it in your own words';

  @override
  String get paydayRuleTitle => 'Add a rule';

  @override
  String get paydayRulesEmpty =>
      'No rules yet. Say what should happen to what is left, like “20% to emergency fund”.';

  @override
  String get paydayRulesTitle => 'Rules for the rest';

  @override
  String get paydayStop => 'Stop';

  @override
  String get paydayTitle => 'Payday';

  @override
  String paydayUsually(String amount) {
    return 'Usually $amount';
  }

  @override
  String get paydayWaiting => 'Waiting for your yes';

  @override
  String get paydayYours => 'Your paydays';

  @override
  String get purposeCustom => 'Custom';

  @override
  String get purposeCustomHint => 'e.g. School fund';

  @override
  String get purposeCustomLabel => 'Your own label';

  @override
  String purposeEditTitle(String name) {
    return 'Label for $name';
  }

  @override
  String get purposeInvalid => 'Use up to 24 characters and no long numbers.';

  @override
  String get purposeNone => 'No label';

  @override
  String get purposeSaved => 'Label saved.';

  @override
  String purposeSemantic(String purpose) {
    return 'Purpose: $purpose';
  }

  @override
  String get purposeTitle => 'What is this account for?';

  @override
  String get remBlockedExact =>
      'Botler may not set exact alarms, so reminders can come late.';

  @override
  String get remBlockedFailed =>
      'The last try to set your reminders failed. It will try again.';

  @override
  String get remBlockedNotifications =>
      'Notifications are off for Botler, so reminders cannot show.';

  @override
  String get remFix => 'Open settings';

  @override
  String get resetBack => 'Choose another part';

  @override
  String get resetBiometric =>
      'Confirm with your fingerprint or screen lock first.';

  @override
  String get resetButton => 'Erase now';

  @override
  String get resetChoose => 'What do you want to erase?';

  @override
  String resetDone(int total) {
    return 'Done. $total rows erased.';
  }

  @override
  String get resetExpired => 'The confirmation ran out. Choose the part again.';

  @override
  String get resetExportFirst => 'Copy the history first';

  @override
  String get resetExported => 'History copied. Paste it somewhere safe.';

  @override
  String resetKeeps(String what) {
    return 'Kept: $what.';
  }

  @override
  String get resetLine =>
      'Erase some or all of what Botler holds about you. Your sign-in, settings and phones stay.';

  @override
  String get resetNothing => 'There is nothing to erase in this part.';

  @override
  String get resetOnlineOnly => 'Resetting needs a connection.';

  @override
  String get resetScopeAudit => 'Audit history';

  @override
  String get resetScopeAuditLine =>
      'The record of who changed what. A single note of the reset stays.';

  @override
  String get resetScopeEverything => 'Everything';

  @override
  String get resetScopeEverythingLine => 'All of the above';

  @override
  String get resetScopeMemory => 'Memory and chat';

  @override
  String get resetScopeMemoryLine =>
      'What Botler remembers and your conversations';

  @override
  String get resetScopeMoney => 'Money';

  @override
  String get resetScopeMoneyLine =>
      'Accounts, transactions, bills, goals, rules, paydays and splits';

  @override
  String get resetScopeSchedule => 'Schedule';

  @override
  String get resetScopeScheduleLine => 'Tasks, events, routines and reminders';

  @override
  String get resetSection => 'Danger zone';

  @override
  String get resetTitle => 'Reset data';

  @override
  String resetTypeWord(String word) {
    return 'Type $word to continue';
  }

  @override
  String resetWillErase(int total) {
    return 'This will erase $total rows:';
  }

  @override
  String get resetWrongWord => 'Type the word exactly as shown.';

  @override
  String get resetZeroReason => 'Starting again from zero';

  @override
  String get retry => 'Try again';

  @override
  String get save => 'Save';

  @override
  String get schedBasisCalendar => 'Calendar weeks';

  @override
  String get schedBasisDays => 'Days 1 to 7, 8 to 14 and so on';

  @override
  String get schedDay => 'Day';

  @override
  String get schedEvery1 => 'Every month';

  @override
  String get schedEvery12 => 'Every 12 months';

  @override
  String get schedEvery2 => 'Every 2 months';

  @override
  String get schedEvery3 => 'Every 3 months';

  @override
  String get schedEvery6 => 'Every 6 months';

  @override
  String get schedEveryDays => 'Repeat every (days)';

  @override
  String get schedEveryWeeks1 => 'Every week';

  @override
  String get schedEveryWeeks2 => 'Every 2 weeks';

  @override
  String get schedEveryWeeks3 => 'Every 3 weeks';

  @override
  String get schedEveryWeeks4 => 'Every 4 weeks';

  @override
  String get schedFirstDay => 'First day';

  @override
  String get schedFromDay => 'From day';

  @override
  String get schedHow => 'How often?';

  @override
  String get schedLast => 'last';

  @override
  String get schedLastDay => 'Last day';

  @override
  String get schedMonth => 'Month';

  @override
  String get schedNth1 => '1st';

  @override
  String get schedNth2 => '2nd';

  @override
  String get schedNth3 => '3rd';

  @override
  String get schedNth4 => '4th';

  @override
  String get schedNth5 => '5th';

  @override
  String get schedNthLast => 'Last';

  @override
  String get schedOnDate => 'On';

  @override
  String get schedPatEveryN => 'Every few days';

  @override
  String get schedPatMonthlyDay => 'On a day of the month';

  @override
  String get schedPatNthWeekday =>
      'On a weekday of the month (like the 1st Wednesday)';

  @override
  String get schedPatOnce => 'One time only';

  @override
  String get schedPatRange => 'Between two days of the month';

  @override
  String get schedPatSemi => 'Twice a month';

  @override
  String get schedPatWeek => 'In a week of the month';

  @override
  String get schedPatWeekly => 'Every week';

  @override
  String get schedPatYearly => 'Once a year';

  @override
  String schedPayWindow(String start, String end) {
    return 'Pay any day $start to $end';
  }

  @override
  String get schedPickWeekday => 'One weekday of that week';

  @override
  String get schedPickWindow => 'Any day in that week';

  @override
  String get schedPreviewNone => 'No date found in the next two years.';

  @override
  String get schedPreviewOffline =>
      'Connect to the internet to see the next dates.';

  @override
  String get schedPreviewTitle => 'The next dates';

  @override
  String schedPreviewWindow(String start, String end) {
    return '$start to $end';
  }

  @override
  String get schedRepeat => 'Repeat';

  @override
  String schedSayEveryDay(String date) {
    return 'Every day from $date';
  }

  @override
  String schedSayEveryMonths(int n) {
    return ', every $n months';
  }

  @override
  String schedSayEveryN(int n, String date) {
    return 'Every $n days from $date';
  }

  @override
  String schedSayMonthlyDay(String day, String every) {
    return 'On the $day of the month$every';
  }

  @override
  String schedSayMonthlyLast(String every) {
    return 'On the last day of the month$every';
  }

  @override
  String schedSayNth(String nth, String weekday, String every) {
    return 'Every $nth $weekday of the month$every';
  }

  @override
  String schedSayOnce(String date) {
    return 'One time only, on $date';
  }

  @override
  String schedSayRange(String from, String to, String every) {
    return 'Any day between the $from and the $to$every';
  }

  @override
  String schedSayRangeToLast(String from, String every) {
    return 'Any day from the $from to the end of the month$every';
  }

  @override
  String schedSaySemi(String first, String second) {
    return 'On the $first and the $second of each month';
  }

  @override
  String schedSayWeekWeekday(
    String weekday,
    String nth,
    String span,
    String every,
  ) {
    return 'The $weekday of the $nth week of the month ($span)$every';
  }

  @override
  String schedSayWeekWindow(String nth, String span, String every) {
    return 'Any day in the $nth week of the month ($span)$every';
  }

  @override
  String schedSayWeekly(String days) {
    return 'Every $days';
  }

  @override
  String schedSayWeeklyEvery(int n, String days) {
    return 'Every $n weeks on $days';
  }

  @override
  String schedSayYearly(String month, int day) {
    return 'Once a year on $month $day';
  }

  @override
  String get schedSecondDay => 'Second day';

  @override
  String get schedSpanCalendar => 'calendar week';

  @override
  String schedSpanDays(int from, int to) {
    return 'days $from to $to';
  }

  @override
  String get schedSpanLast => 'the last 7 days';

  @override
  String get schedStartingOn => 'Starting on';

  @override
  String get schedToDay => 'To day';

  @override
  String get schedUnknown => 'A schedule this version of the app cannot edit';

  @override
  String get schedWeekday => 'Weekday';

  @override
  String get schedWeekendAfter => 'Use the working day after';

  @override
  String get schedWeekendBefore => 'Use the working day before';

  @override
  String get schedWeekendLabel => 'If it falls on a weekend';

  @override
  String get schedWeekendNone => 'Keep the date';

  @override
  String get schedWhichOne => 'Which one?';

  @override
  String get schedWhichWeek => 'Which week?';

  @override
  String setBalanceBody(String amount) {
    return 'Botler thinks it is $amount. Nothing is deleted: the history stays and the difference is shown as a reset.';
  }

  @override
  String setBalanceConfirmBody(String old, String diff) {
    return 'It was $old. The difference of $diff is recorded as a reset, not as spending.';
  }

  @override
  String setBalanceConfirmTitle(String name, String amount) {
    return 'Set $name to $amount?';
  }

  @override
  String get setBalanceConfirmYes => 'Set it';

  @override
  String get setBalanceDone => 'Balance set. The history keeps the old one.';

  @override
  String setBalanceNew(String currency) {
    return 'New balance ($currency)';
  }

  @override
  String get setBalanceOffline =>
      'A reset needs a connection, so it is not available offline.';

  @override
  String get setBalanceReason => 'Why? (short)';

  @override
  String get setBalanceReasonNeeded => 'Say why in a few words.';

  @override
  String setBalanceTitle(String name) {
    return 'Set the balance of $name';
  }

  @override
  String get settingsAppLanguage => 'App language';

  @override
  String get settingsCurrency => 'Currency';

  @override
  String get settingsCurrencyChange => 'Change';

  @override
  String settingsCurrencyConfirmBody(String name) {
    return 'Your total will be shown in $name. Your accounts keep the currencies they hold. Your income, goals, rules and minimum balances keep the same numbers, now read in $name: nothing in them is converted. Your bills keep their own currency.';
  }

  @override
  String settingsCurrencyConfirmTitle(String code) {
    return 'Change the currency to $code?';
  }

  @override
  String settingsCurrencyExample(String amount) {
    return 'Example $amount';
  }

  @override
  String get settingsCurrencyNone => 'No currency matches that.';

  @override
  String get settingsCurrencySearch => 'Search currencies';

  @override
  String get settingsHideBody =>
      'A reminder says only “Botler”, so nobody sees it on your lock screen.';

  @override
  String get settingsHideTitle => 'Hide the details in notifications';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageFil => 'Filipino';

  @override
  String get settingsLead1440 => '1 day before';

  @override
  String get settingsLead15 => '15 minutes before';

  @override
  String get settingsLead180 => '3 hours before';

  @override
  String get settingsLead60 => '1 hour before';

  @override
  String get settingsLeadAtTime => 'At the time';

  @override
  String get settingsLeadLabel => 'Remind me this long before';

  @override
  String get settingsListenEn => 'English (Philippines)';

  @override
  String get settingsListenFil => 'Filipino and Taglish';

  @override
  String get settingsListenFor => 'Listen for';

  @override
  String get settingsLockNeeds =>
      'The lock needs a fingerprint or face set up on this phone.';

  @override
  String get settingsLockTitle =>
      'Ask for my fingerprint or face to open Botler';

  @override
  String get settingsLook => 'Look';

  @override
  String get settingsLookDark => 'Dark';

  @override
  String get settingsLookLight => 'Light';

  @override
  String get settingsLookPhone => 'Phone';

  @override
  String get settingsMonday => 'Monday';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String settingsRatesLine(String date, String source) {
    return 'Fetched $date from $source';
  }

  @override
  String get settingsRatesNone => 'No rates yet';

  @override
  String get settingsRatesTap => 'Tap to update';

  @override
  String get settingsRatesTitle => 'Exchange rates';

  @override
  String get settingsReminders => 'Reminders';

  @override
  String get settingsReplies => 'Assistant replies';

  @override
  String get settingsRepliesAuto =>
      'Auto: English, and Filipino when you write it';

  @override
  String get settingsRepliesEn => 'Always English';

  @override
  String get settingsRepliesFil => 'Always Filipino';

  @override
  String get settingsRepliesTaglish => 'Taglish';

  @override
  String get settingsSectionLanguageMoney => 'Language and money';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignOutBody =>
      'Botler stays on the server. You can sign in again any time.';

  @override
  String get settingsSignOutTitle => 'Sign out?';

  @override
  String get settingsSignedIn => 'Signed in';

  @override
  String get settingsSunday => 'Sunday';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsVoice => 'Voice';

  @override
  String get settingsWeekStarts => 'Week starts on';

  @override
  String get signInButton => 'Sign in with Google';

  @override
  String get signInTagline => 'Your money and your time, in one quiet chat.';

  @override
  String get splitAccountFallback => 'account';

  @override
  String get splitApproveButton => 'Approve split';

  @override
  String get splitApproved => 'Approved';

  @override
  String get splitApprovedDone => 'Split approved.';

  @override
  String splitCopied(String amount) {
    return 'Copied $amount';
  }

  @override
  String get splitCopyTooltip => 'Copy the amount';

  @override
  String get splitCutOrMove => 'You could cut or move:';

  @override
  String splitForeignLine(
    String name,
    String amount,
    String converted,
    String rate,
  ) {
    return '$name: $amount counted as $converted ($rate)';
  }

  @override
  String get splitForeignTitle => 'Bills in other currencies';

  @override
  String get splitMarkSent => 'Mark sent';

  @override
  String get splitMarkedSent => 'Marked as sent.';

  @override
  String splitPayday(String date) {
    return 'Payday $date';
  }

  @override
  String get splitSent => 'Sent';

  @override
  String splitShort(String gap) {
    return 'This pay is $gap short of what you set aside.';
  }

  @override
  String get splitTransfers => 'Transfers to make';

  @override
  String summaryMissingRates(int count) {
    return '$count currencies are not in this total: no exchange rate yet.';
  }

  @override
  String transferArrivedLabel(String currency) {
    return 'Amount that arrived ($currency)';
  }

  @override
  String get transferDone => 'Moved.';

  @override
  String transferFeeLabel(String currency) {
    return 'Fee ($currency, optional)';
  }

  @override
  String get transferFrom => 'From';

  @override
  String get transferInvalid => 'Check the amounts.';

  @override
  String get transferMove => 'Move money';

  @override
  String get transferQueued =>
      'Saved on the phone. It is sent when you are back online.';

  @override
  String transferRate(String rate) {
    return 'Your rate: $rate';
  }

  @override
  String get transferSame => 'Pick two different wallets.';

  @override
  String transferSentLabel(String currency) {
    return 'Amount sent ($currency)';
  }

  @override
  String transferSuggest(String amount) {
    return 'Today\'\'s rate suggests about $amount. Change it to what really arrived.';
  }

  @override
  String get transferTo => 'To';

  @override
  String get uiError => 'Something went wrong. Try again.';

  @override
  String get uiLoading => 'Loading';

  @override
  String get uiNotNow => 'Not now';

  @override
  String get undo => 'Undo';

  @override
  String updBannerSize(String size) {
    return 'About $size MB to download.';
  }

  @override
  String updBannerTitle(String version) {
    return 'Update $version is ready';
  }

  @override
  String get updDismiss => 'Not now';

  @override
  String updDownloading(int percent) {
    return 'Downloading $percent percent';
  }

  @override
  String get updFailDamaged => 'The download was damaged. Try again.';

  @override
  String get updFailInstaller => 'The update did not finish. Try again.';

  @override
  String get updFailNetwork =>
      'No connection. Check your internet and try again.';

  @override
  String get updFailPermission =>
      'Allow Botler to install apps in Android settings, then come back and try again.';

  @override
  String get updFailServer =>
      'The server could not give the update. Try again later.';

  @override
  String get updFailSpace =>
      'Not enough space on the phone. Free some space and try again.';

  @override
  String get updFailWrongBuild =>
      'That download is not an update for this app. Nothing was installed.';

  @override
  String get updInstalling =>
      'Android is asking to install it. Tap Install there.';

  @override
  String get updNow => 'Update now';

  @override
  String get updOpenSettings => 'Open Android settings';

  @override
  String updRequiredBody(String version, String size) {
    return 'Botler $version is needed to keep things working. It is about $size MB.';
  }

  @override
  String get updRequiredTitle => 'Update needed';

  @override
  String get updRetry => 'Try again';

  @override
  String updRowAvailable(String version) {
    return 'Version $version is ready. Tap to update.';
  }

  @override
  String get updRowChecking => 'Checking for updates…';

  @override
  String get updRowFailed => 'Could not check. Tap to try again.';

  @override
  String updRowLine(String version, int build) {
    return 'Version $version (build $build)';
  }

  @override
  String updRowPending(int count) {
    return '$count waiting to sync';
  }

  @override
  String get updRowPendingNone => 'Nothing waiting to sync';

  @override
  String get updRowTitle => 'App version';

  @override
  String get updRowUpToDate => 'Up to date. Tap to check again.';

  @override
  String get updUseForNow => 'Use the app for now';

  @override
  String get updVerifying => 'Checking the download…';

  @override
  String get yes => 'Yes';
}
