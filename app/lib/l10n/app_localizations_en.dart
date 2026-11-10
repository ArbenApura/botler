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
  String get accountsCurrencyLabel => 'Currency';

  @override
  String get accountsCurrencyNote =>
      'What is in this account is counted in this currency unless you pick another when you enter something.';

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
  String accountsNoMainWallet(String currency) {
    return 'Nothing in $currency here, so the minimum is not checked.';
  }

  @override
  String get accountsNotSaved => 'Not saved.';

  @override
  String accountsRateLine(String from, String rate, String main) {
    return '1 $from = $rate $main';
  }

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
  String activityUndoCreatedBody(String page) {
    return 'Botler made \"$page\". Undoing it deletes the page. You can put it back for 30 days.';
  }

  @override
  String get activityUndoCreatedTitle => 'Delete the page Botler made?';

  @override
  String get activityUndoUnavailable =>
      'The earlier text is no longer kept, so this cannot be undone.';

  @override
  String get activityUndoneDeleted =>
      'Deleted. You can put it back for 30 days.';

  @override
  String get activityUndoneRestored => 'Put back the earlier text.';

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
  String get billsThisMonth => 'This month';

  @override
  String get billsThisWeek => 'This week';

  @override
  String get billsTitle => 'Bills';

  @override
  String billsUsualSuffix(String amount) {
    return '$amount (usual)';
  }

  @override
  String get billsVaries => 'The amount is different every time';

  @override
  String get billsViewMonth => 'Month';

  @override
  String get billsViewWeek => 'Week';

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
  String calCountWorkouts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count workouts',
      one: '1 workout',
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
  String get calLayerWorkouts => 'Workouts';

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
  String get calWorkoutLabel => 'Workout';

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
  String get chatContextAtLast => 'At the last answer';

  @override
  String get chatContextDanger =>
      'Almost full. Summarize now to start the next answer with room.';

  @override
  String get chatContextExplain =>
      'As a chat grows, the older messages are summarized on their own. Nothing is lost and you do not need to do anything.';

  @override
  String get chatContextFailed => 'Could not summarize. Try again.';

  @override
  String chatContextFull(int percent) {
    return '$percent percent full';
  }

  @override
  String get chatContextLastSummary => 'Last summary';

  @override
  String get chatContextLevelCalm => 'Plenty of room';

  @override
  String get chatContextLevelDanger => 'Almost full';

  @override
  String get chatContextLevelWarn => 'Getting full';

  @override
  String get chatContextMonth => 'This month, all chats';

  @override
  String chatContextMonthShare(int percent) {
    return '$percent percent of the monthly limit';
  }

  @override
  String get chatContextNever => 'Not yet';

  @override
  String get chatContextOffline => 'Summarizing needs a connection.';

  @override
  String get chatContextShort =>
      'Too short to summarize yet. It needs a few more messages.';

  @override
  String get chatContextSummarize => 'Summarize now';

  @override
  String get chatContextSummarized =>
      'Summarized. The ring updates with your next message.';

  @override
  String get chatContextSummarizing => 'Summarizing';

  @override
  String get chatContextTitle => 'Context';

  @override
  String chatContextTooltip(int percent) {
    return 'Context $percent percent full';
  }

  @override
  String chatContextUsed(int used, int window) {
    final intl.NumberFormat usedNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String usedString = usedNumberFormat.format(used);
    final intl.NumberFormat windowNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String windowString = windowNumberFormat.format(window);

    return 'Used $usedString of $windowString tokens';
  }

  @override
  String get chatContextWarn =>
      'Getting full. Summarizing now keeps the next answers lighter.';

  @override
  String get chatEarlier => 'Earlier';

  @override
  String get chatEarlierNotFinished =>
      'The earlier message did not finish, so the waiting ones were paused.';

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
  String get chatNotebookAlready => 'Already in your notebook';

  @override
  String chatNotebookChanged(String what) {
    return 'Updated $what';
  }

  @override
  String get chatNotebookChangedPlain => 'Updated your notebooks';

  @override
  String chatNotebookMade(String what) {
    return 'Made $what';
  }

  @override
  String chatNotebookRemoved(String what) {
    return 'Deleted $what';
  }

  @override
  String chatNotebookRestored(String what) {
    return 'Put back $what';
  }

  @override
  String chatNotebookSaved(String where) {
    return 'Saved to your notebook · $where';
  }

  @override
  String get chatNotebookSavedPlain => 'Saved to your notebook';

  @override
  String get chatNoticeFailed =>
      'The assistant could not finish that. Try again.';

  @override
  String get chatNoticeOffline =>
      'No connection. Saved on your phone. It will be sent once, when you are back online.';

  @override
  String get chatOffline => 'offline';

  @override
  String get chatOutputShowAll => 'Show all of it';

  @override
  String get chatOutputShowLess => 'Show less';

  @override
  String chatPageSaved(String page, String notebook) {
    return 'Saved to $page in $notebook';
  }

  @override
  String get chatPasteNothing => 'There is no picture on the clipboard.';

  @override
  String get chatPastePhoto => 'Paste photo';

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
  String chatPhotoChars(int count) {
    return '$count characters read';
  }

  @override
  String get chatPhotoClose => 'Close';

  @override
  String chatPhotoCount(int current, int total) {
    return '$current of $total';
  }

  @override
  String get chatPhotoEditing => 'Photos wait while you edit a message.';

  @override
  String get chatPhotoEmpty => 'I could not read any text on that photo.';

  @override
  String get chatPhotoFailed => 'The photo could not be read.';

  @override
  String chatPhotoItem(int number, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '$count character',
    );
    return 'Photo $number ($_temp0)';
  }

  @override
  String get chatPhotoMissing => 'This photo is no longer on this phone.';

  @override
  String get chatPhotoOnlyMessage => 'Here are the photos.';

  @override
  String chatPhotoOpen(int number, int total) {
    return 'Open photo $number of $total';
  }

  @override
  String chatPhotoRemove(int number) {
    return 'Remove photo $number';
  }

  @override
  String chatPhotoTileReading(int number) {
    return 'Reading photo $number';
  }

  @override
  String get chatPhotoTooltip => 'Photo of a receipt';

  @override
  String get chatPhotoZoomIn => 'Zoom in';

  @override
  String get chatPhotoZoomOut => 'Zoom out';

  @override
  String chatPhotosLimit(int count) {
    return 'At most $count photos in one message.';
  }

  @override
  String get chatPhotosReading => 'Reading the photos…';

  @override
  String chatPhotosSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos could not be read and were left out.',
      one: '$count photo could not be read and was left out.',
    );
    return '$_temp0';
  }

  @override
  String get chatPhotosTrimmed =>
      'The photos hold a lot of text, so only the first part of each is sent.';

  @override
  String get chatPictureSkipped =>
      'A picture could not be sent, so only its text goes.';

  @override
  String get chatPicturesNoted =>
      'This answer goes by the text read from the picture, not the picture itself.';

  @override
  String get chatPleaseCheck => 'Please check';

  @override
  String get chatQueueClear => 'Clear';

  @override
  String get chatQueueEdit => 'Edit this waiting message';

  @override
  String get chatQueueFull =>
      'Too many messages are waiting. Wait until one has been sent.';

  @override
  String chatQueuePaused(int count) {
    return '$count waiting';
  }

  @override
  String get chatQueuePhotosFull =>
      'Too many photos are waiting. Wait until one message has been sent.';

  @override
  String get chatQueueRemove => 'Remove this waiting message';

  @override
  String get chatQueueSendNow => 'Send now';

  @override
  String get chatQueueWaiting => 'Waiting';

  @override
  String chatRanScript(String output) {
    return 'Ran a script: $output';
  }

  @override
  String get chatRanScriptQuiet => 'Ran a script on your phone';

  @override
  String get chatReceiptMessage => 'Here is a receipt.';

  @override
  String chatRecorded(String amount) {
    return 'Recorded $amount';
  }

  @override
  String get chatRestoreFailed => 'Could not load your earlier chat.';

  @override
  String get chatRunningScript => 'Running a script on your phone';

  @override
  String get chatSavingNotebook => 'Updating your notebooks';

  @override
  String get chatScriptFailed => 'The script did not finish';

  @override
  String get chatSend => 'Send';

  @override
  String get chatSpeak => 'Speak';

  @override
  String get chatStillFinishing => 'Still finishing the earlier message…';

  @override
  String get chatStop => 'Stop';

  @override
  String get chatStopListening => 'Stop listening';

  @override
  String get chatStopped => 'Stopped.';

  @override
  String get chatStopping => 'Stopping...';

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
  String get chatUsedToolbox => 'Used your toolbox';

  @override
  String get chatUsingToolbox => 'Opening your toolbox';

  @override
  String get chatWaiting => 'Working on it';

  @override
  String chatWhichAccount(String amount) {
    return 'Which account was $amount from?';
  }

  @override
  String chatWithPhotos(String text, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos attached',
      one: '$count photo attached',
    );
    return '$text\n($_temp0)';
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
  String get chatsLimit =>
      'Three chats are already working. Wait for one to finish, then send this again.';

  @override
  String get chatsMore => 'More about this chat';

  @override
  String get chatsNeedsOk => 'Needs your OK';

  @override
  String get chatsNew => 'New chat';

  @override
  String get chatsNewAnswer => 'New answer';

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
  String get chatsWorking => 'Working on it';

  @override
  String get close => 'Close';

  @override
  String get delete => 'Delete';

  @override
  String get done => 'Done';

  @override
  String drawerAccountShort(String amount) {
    return 'Short by $amount';
  }

  @override
  String get drawerAccounts => 'Accounts';

  @override
  String get drawerAccountsEmpty => 'No accounts yet.';

  @override
  String get drawerAccountsError => 'Accounts could not be loaded.';

  @override
  String get drawerAccountsOpen => 'Open all accounts';

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
  String get fileGone => 'This file is no longer on this phone.';

  @override
  String fileOpen(String name, String size) {
    return '$name, $size. Tap to save or share.';
  }

  @override
  String filePicture(String name) {
    return 'Picture $name';
  }

  @override
  String get fileSave => 'Save to phone';

  @override
  String get fileSaveFailed => 'Could not open the share sheet.';

  @override
  String get fileSaved => 'Saved to your phone.';

  @override
  String get fileShare => 'Share or open with…';

  @override
  String get fixQueued =>
      'The new entry is saved on this phone and goes out when you are online. The old entry stays until you undo it.';

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
  String get goalsDelete => 'Delete for good';

  @override
  String goalsDeleteBody(String name) {
    return '“$name” and any payday rules that point at it will be deleted for good. The money you saved for it stays where it is.';
  }

  @override
  String get goalsDeleteTitle => 'Delete this goal?';

  @override
  String get goalsDeleteYes => 'Delete it';

  @override
  String get goalsDeleted => 'Deleted.';

  @override
  String goalsEachPayday(String amount) {
    return '$amount each payday';
  }

  @override
  String get goalsEmpty => 'No goals yet. What would you like to save for?';

  @override
  String get goalsMenu => 'More about this goal';

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
  String goalsYear(int count, String amount) {
    return 'In a year ($count paydays) that is $amount.';
  }

  @override
  String get healthAbout => 'About';

  @override
  String healthAboutTime(String time) {
    return 'About $time';
  }

  @override
  String get healthAcceptWeek => 'Accept this week';

  @override
  String get healthActivityFeet => 'On my feet';

  @override
  String get healthActivitySitting => 'Mostly sitting';

  @override
  String get healthActivityVery => 'Very active';

  @override
  String get healthActivityWalking => 'Some walking';

  @override
  String get healthAddByHand => 'Add by hand';

  @override
  String get healthAddFood => 'Add a food';

  @override
  String get healthAddKcal => 'Calories (kcal)';

  @override
  String get healthAddName => 'What did you eat?';

  @override
  String get healthAddNeeds => 'Give a name and the calories.';

  @override
  String get healthAddProtein => 'Protein in grams (optional)';

  @override
  String get healthAddSleep => 'Add sleep';

  @override
  String get healthAddToToday => 'Add to today';

  @override
  String get healthAddWeight => 'Add weight';

  @override
  String get healthAskBotler => 'Ask Botler';

  @override
  String get healthBack => 'Back';

  @override
  String healthBedtimeSteady(String time) {
    return 'Your bedtime stayed within about $time.';
  }

  @override
  String get healthByBotler => 'By Botler';

  @override
  String get healthCalories => 'Calories';

  @override
  String get healthCameraBarcode => 'Barcode';

  @override
  String get healthCameraDenied =>
      'Botler needs the camera for this. You can allow it in the phone settings, or add the food by hand.';

  @override
  String get healthCameraGallery => 'Choose from gallery';

  @override
  String healthCameraHintAngle(String count, String total) {
    return 'Angle $count of $total. Take another, or tap Done.';
  }

  @override
  String get healthCameraHintBarcode =>
      'Point at the barcode. It scans by itself.';

  @override
  String get healthCameraHintLabel => 'Fit the whole label in the frame.';

  @override
  String get healthCameraHintMeal =>
      'Take it from above. A second angle helps.';

  @override
  String get healthCameraLabel => 'Label';

  @override
  String get healthCameraMeal => 'Meal';

  @override
  String get healthCameraOffline =>
      'Reading a photo needs the internet, and nothing was saved. You can add the food by hand.';

  @override
  String get healthCameraOfflineTitle => 'This needs a connection';

  @override
  String get healthCameraTake => 'Take the photo';

  @override
  String get healthCarbs => 'Carbohydrates';

  @override
  String get healthChartEmpty =>
      'Two weigh-ins draw your line. Any time of day is fine, but the same time each day is easiest to compare.';

  @override
  String healthChartLabel(String from, String to) {
    return 'Your weight from $from kilograms to a trend of $to kilograms';
  }

  @override
  String get healthCheckInLine => 'A new calorie target to look at';

  @override
  String get healthCheckInReady => 'Your weekly check-in is ready';

  @override
  String get healthCheckInTitle => 'Weekly check-in';

  @override
  String healthCheckInWhy(String burn) {
    return 'Your body seems to burn about $burn a day. This keeps you moving toward your goal at the pace you chose.';
  }

  @override
  String get healthClose => 'Close';

  @override
  String get healthCorrectBusy => 'Botler is looking again';

  @override
  String get healthCorrectHint => 'That is tinola, and half a cup of rice';

  @override
  String get healthCorrectLabel => 'What is it really?';

  @override
  String get healthCorrectLine =>
      'Tell Botler what it really is, and it will look at your photo again. You check the result before anything is saved.';

  @override
  String get healthCorrectSend => 'Ask Botler to fix it';

  @override
  String get healthCorrectTitle => 'Not right?';

  @override
  String healthCouldBe(String low, String high) {
    return 'Could be $low to $high';
  }

  @override
  String get healthDataCredit =>
      'Food data from USDA FoodData Central and Open Food Facts. Filipino dishes are rough estimates.';

  @override
  String get healthDayComplete => 'Today is complete';

  @override
  String get healthDayCompleteLine =>
      'Turn on when everything you ate is logged';

  @override
  String get healthDayDone => 'done';

  @override
  String get healthDayPlanned => 'planned';

  @override
  String get healthDayRest => 'rest';

  @override
  String healthDayState(String day, String state) {
    return '$day, $state';
  }

  @override
  String get healthDayToday => 'today';

  @override
  String get healthDetailTitle => 'Today in detail';

  @override
  String get healthDetails => 'Details';

  @override
  String get healthDiscard => 'Discard';

  @override
  String get healthDiscardBody =>
      'The meal read from your photo will not be saved.';

  @override
  String get healthDistanceField => 'Distance in km (optional)';

  @override
  String get healthDone => 'Done';

  @override
  String healthDown(String kg) {
    return 'Down $kg kg';
  }

  @override
  String get healthEasier => 'Make it easier';

  @override
  String healthEatenKcal(String kcal) {
    return '$kcal kcal eaten';
  }

  @override
  String healthEatenOf(String eaten, String target) {
    return '$eaten eaten of $target';
  }

  @override
  String healthExerciseOf(String index, String count) {
    return 'Exercise $index of $count';
  }

  @override
  String get healthFat => 'Fat';

  @override
  String get healthFibre => 'Fibre';

  @override
  String get healthFieldActivity => 'How active is a normal day?';

  @override
  String get healthFieldGoalWeight => 'Goal weight in kilograms';

  @override
  String get healthFieldHeight => 'Height in centimetres';

  @override
  String get healthFieldHeightHint => 'For example, 168';

  @override
  String get healthFieldSex => 'Sex, used only for the first estimate';

  @override
  String get healthFieldWeight => 'Weight today in kilograms';

  @override
  String get healthFieldWeightHint => 'For example, 74';

  @override
  String get healthFieldYear => 'Year you were born';

  @override
  String get healthFieldYearHint => 'For example, 1995';

  @override
  String get healthFinishLater => 'Finish later';

  @override
  String get healthFinishSet => 'Finish set';

  @override
  String get healthFinishWorkout => 'Finish workout';

  @override
  String get healthFlash => 'Flash';

  @override
  String healthForecastAround(String kg, String date) {
    return '$kg kg around $date';
  }

  @override
  String get healthForecastAway => 'Your trend is moving away from your goal';

  @override
  String get healthForecastFar => 'Your goal is a long way off at this pace';

  @override
  String get healthForecastFlat => 'Your trend is steady';

  @override
  String get healthForecastLine => 'An estimate at your pace of the last weeks';

  @override
  String get healthForecastNoDate =>
      'There is no date to give right now, and that is fine.';

  @override
  String get healthForecastReached => 'You are at your goal';

  @override
  String healthFromFoods(String count) {
    return 'From $count foods. Amounts are estimates.';
  }

  @override
  String get healthGoalGain => 'Gain';

  @override
  String get healthGoalLose => 'Lose weight';

  @override
  String get healthGoalMaintain => 'Maintain';

  @override
  String get healthGoalTrack => 'Just track';

  @override
  String healthGrams(String value) {
    return '$value g';
  }

  @override
  String healthGramsOf(String value, String target) {
    return '$value of $target g';
  }

  @override
  String get healthHalf => 'Half';

  @override
  String get healthHarder => 'Make it harder';

  @override
  String get healthHowMuch => 'How much did you have?';

  @override
  String get healthIsThisIt => 'Is this it?';

  @override
  String healthKcal(String value) {
    return '$value kcal';
  }

  @override
  String get healthKcalEaten => 'kcal eaten';

  @override
  String get healthKcalLeft => 'kcal left';

  @override
  String get healthKcalOver => 'kcal';

  @override
  String healthKeepKcal(String kcal) {
    return 'Keep $kcal';
  }

  @override
  String get healthKindRun => 'Run';

  @override
  String get healthKindWalk => 'Walk';

  @override
  String healthKnownFor(String known, String total) {
    return 'Known for $known of $total foods';
  }

  @override
  String healthLabelBasis(String grams) {
    return 'These numbers are for $grams g';
  }

  @override
  String get healthLabelFits => 'Calories match protein, carbs and fat';

  @override
  String get healthLabelNoFit =>
      'Check this: the calories do not match protein, carbs and fat';

  @override
  String get healthLastNightTitle => 'Last night';

  @override
  String healthLeftKcal(String kcal) {
    return 'About $kcal kcal left';
  }

  @override
  String healthLeftWordsAbout(String kcal) {
    return 'About $kcal kcal';
  }

  @override
  String get healthLess => 'Less';

  @override
  String healthLevelUp(String names) {
    return 'Next time: $names';
  }

  @override
  String get healthLogFood => 'Log food';

  @override
  String get healthLogWalkTitle => 'Log a walk or a run';

  @override
  String get healthLowIntake =>
      'You have been eating very little this week. That can be hard on your body. It may help to talk to a doctor or someone you trust.';

  @override
  String healthMacroLine(String protein, String carbs, String fat) {
    return 'Protein $protein g · Carbs $carbs g · Fat $fat g';
  }

  @override
  String get healthMacroSplit => 'Where the calories come from';

  @override
  String get healthMealBreakfast => 'Breakfast';

  @override
  String get healthMealDinner => 'Dinner';

  @override
  String get healthMealFoods => 'Foods in this meal';

  @override
  String get healthMealLunch => 'Lunch';

  @override
  String get healthMealMerienda => 'Merienda';

  @override
  String healthMealOfDay(String percent) {
    return '$percent% of today\'s target';
  }

  @override
  String get healthMealPhoto => 'The photo of your meal';

  @override
  String get healthMealSnack => 'Snack';

  @override
  String healthMilligrams(String value) {
    return '$value mg';
  }

  @override
  String get healthMinutesBad => 'Enter the minutes, such as 30';

  @override
  String get healthMinutesField => 'Minutes';

  @override
  String healthMinutesLabel(String done, String goal) {
    return '$done of $goal minutes moving this week';
  }

  @override
  String get healthMinutesMoving => 'minutes moving';

  @override
  String healthMinutesOf(String done, String goal) {
    return '$done of $goal';
  }

  @override
  String get healthMore => 'More';

  @override
  String healthMoveTo(String time) {
    return 'Move to $time';
  }

  @override
  String healthNeedsMove(String title, String day) {
    return '$title on $day needs a move';
  }

  @override
  String get healthNeedsMoveLine => 'Your free time changed.';

  @override
  String get healthNewWeek => 'Plan it again';

  @override
  String get healthNext => 'Next';

  @override
  String healthNextAt(String day, String time) {
    return '$day at $time';
  }

  @override
  String get healthNextWeek => 'Next week';

  @override
  String healthNoFit(String titles) {
    return 'No free time held: $titles';
  }

  @override
  String get healthNoRoom => 'No time fits that day. You can skip it.';

  @override
  String get healthNotFoundLine =>
      'Take a photo of its nutrition label. Botler reads it and remembers this product for next time.';

  @override
  String get healthNotFoundTitle => 'This product is not in the food data yet';

  @override
  String get healthNotMedical =>
      'Botler gives general guidance, not medical advice. If you have a health condition or take medication, check with your doctor first.';

  @override
  String get healthNotThisProduct => 'Not this product';

  @override
  String get healthOffCredit =>
      'Contains data from Open Food Facts, available under the Open Database License. Anyone can edit this data, so check it looks right.';

  @override
  String get healthOilLine =>
      'Oil is hard to see, and it changes the calories the most.';

  @override
  String get healthOilLots => 'About two spoons';

  @override
  String get healthOilName => 'Cooking oil';

  @override
  String get healthOilNone => 'No added oil';

  @override
  String get healthOilQuestion => 'Was it cooked in oil?';

  @override
  String get healthOilSome => 'About a spoon';

  @override
  String get healthOneServing => 'One';

  @override
  String get healthOverBy => 'Over by about';

  @override
  String get healthPaceFastest => 'Fastest allowed';

  @override
  String get healthPaceGentle => 'Gentle';

  @override
  String get healthPaceSteady => 'Steady';

  @override
  String get healthPaceTitle => 'How fast?';

  @override
  String get healthPainNote =>
      'If something hurts, stop and swap it. If pain keeps coming back, see a clinician.';

  @override
  String healthPathNext(String high, String next) {
    return 'Reach $high on all sets and $next comes next.';
  }

  @override
  String get healthPathTop =>
      'This is the hardest version here. Nice and steady.';

  @override
  String healthPatternLine(String kcal) {
    return 'After nights under 6 hours, you ate about $kcal kcal more. It may not be the only reason.';
  }

  @override
  String get healthPatternTitle => 'A pattern to notice';

  @override
  String healthPer100(String kcal) {
    return '$kcal kcal per 100 g';
  }

  @override
  String get healthPhotoFailedLine =>
      'Botler could not find any food in it, and nothing was saved. Try again with the whole plate in view and more light.';

  @override
  String get healthPhotoFailedTitle => 'That photo did not work';

  @override
  String get healthPhotoLabel => 'Your photo';

  @override
  String get healthPhotoSettingTitle => 'Your settings keep pictures private';

  @override
  String get healthPlanNextWeek => 'Plan next week';

  @override
  String get healthPlanRest => 'Rest';

  @override
  String healthPlanWhen(String minutes, String time) {
    return '$minutes min at $time';
  }

  @override
  String healthPreviewKcal(String kcal) {
    return 'About $kcal kcal a day';
  }

  @override
  String healthPreviewReach(String kg, String date) {
    return 'About $kg kg a week, reaching your goal around $date. This first estimate improves as you log.';
  }

  @override
  String get healthPreviewTitle => 'What this means for you';

  @override
  String get healthProgramWarning =>
      'Another program is already running. Starting this one adds its sessions to every week.';

  @override
  String healthProgramWeek(String week, String weeks) {
    return 'Week $week of $weeks';
  }

  @override
  String get healthProgramsNone =>
      'Pick one when you feel ready. Both need no equipment.';

  @override
  String get healthProtein => 'Protein';

  @override
  String healthProteinShort(String value) {
    return '$value g protein';
  }

  @override
  String get healthReadLabel => 'Read the label';

  @override
  String get healthReadingLine =>
      'Finding the foods and checking their nutrition.';

  @override
  String get healthReadingTitle => 'Your meal';

  @override
  String get healthReadyLine =>
      'If you answer yes to any of these, talk to a clinician first.';

  @override
  String get healthReadyNo => 'Not now';

  @override
  String get healthReadyTitle => 'Before you start';

  @override
  String get healthReadyYes => 'All no, start';

  @override
  String get healthRecent => 'This week';

  @override
  String get healthRecentWeights => 'Recent weigh-ins';

  @override
  String get healthRemove => 'Remove';

  @override
  String get healthRemoveWeight => 'Remove this weigh-in';

  @override
  String get healthRemoveWeightBody =>
      'This weigh-in leaves your trend for good.';

  @override
  String get healthRepsAsk => 'How many did you do?';

  @override
  String get healthRestDay => 'A rest day';

  @override
  String healthRestLeft(String time) {
    return 'Rest, $time left';
  }

  @override
  String get healthRestLine =>
      'Nothing planned today. A walk still counts if you feel like one.';

  @override
  String get healthResume => 'Back to your workout';

  @override
  String get healthReviewAsk => 'Ask Botler';

  @override
  String get healthReviewDone => 'Got it';

  @override
  String healthReviewFood(String days, String kcal) {
    return 'Food logged on $days days, about $kcal kcal a day';
  }

  @override
  String healthReviewMoved(String minutes, String days) {
    return '$minutes minutes moving, $days strength days';
  }

  @override
  String get healthReviewNoFood => 'No full days of food logged';

  @override
  String healthReviewSleep(String time) {
    return 'About $time of sleep a night';
  }

  @override
  String get healthReviewTitle => 'Your week';

  @override
  String healthRingLabel(String percent) {
    return '$percent percent of the calorie target';
  }

  @override
  String healthRunSteps(String run, String walk, String repeat) {
    return 'Run $run, walk $walk, $repeat times';
  }

  @override
  String healthRunTotal(String minutes) {
    return 'About $minutes minutes in all';
  }

  @override
  String get healthRunWarm => 'Walk 5 minutes first and 5 minutes after.';

  @override
  String get healthSatFat => 'Saturated fat';

  @override
  String get healthSave => 'Save';

  @override
  String get healthSaveMeal => 'Save meal';

  @override
  String get healthSaveSleep => 'Save sleep';

  @override
  String get healthSavedOffline =>
      'Saved on your phone. It will send when you are back online.';

  @override
  String healthScaleToday(String kg) {
    return 'Scale today: $kg kg. Daily changes are mostly water, so the line is what counts.';
  }

  @override
  String get healthScanBarcode => 'Scan a barcode';

  @override
  String get healthSecondsAsk => 'How many seconds?';

  @override
  String healthSecondsShort(String seconds) {
    return '$seconds s';
  }

  @override
  String healthSessionMinutes(String title, String minutes) {
    return '$title, $minutes minutes';
  }

  @override
  String healthSetDoneLabel(String index, String value) {
    return 'Set $index, $value done';
  }

  @override
  String healthSetOpenLabel(String index, String value) {
    return 'Set $index, aim for $value';
  }

  @override
  String healthSetsOfHolds(String sets, String low, String high) {
    return '$sets holds of $low to $high seconds.';
  }

  @override
  String healthSetsOfReps(String sets, String low, String high) {
    return '$sets sets of $low to $high.';
  }

  @override
  String get healthSetupAboutLine =>
      'Your real weight trend corrects these after a few weeks, so close is fine.';

  @override
  String get healthSetupAboutTitle => 'A few facts to start';

  @override
  String get healthSetupGoalTitle => 'What do you want to do?';

  @override
  String get healthSetupPrompt => 'Finish setting up Health';

  @override
  String get healthSetupPromptLine =>
      'It takes a minute, or just tell Botler in chat';

  @override
  String get healthSetupTitle => 'Set up Health';

  @override
  String get healthSevenNights => 'Last 7 nights';

  @override
  String get healthSexFemale => 'Female';

  @override
  String get healthSexMale => 'Male';

  @override
  String get healthSexSkip => 'Skip';

  @override
  String get healthSkip => 'Skip';

  @override
  String get healthSleepBars => 'Hours slept on the last nights';

  @override
  String get healthSleepChart => 'Bedtimes and wake times for the last nights';

  @override
  String get healthSleepEmpty =>
      'No sleep logged yet. Say \"I slept 11 to 6\" in chat, or add it here.';

  @override
  String get healthSleepFrom => 'Went to sleep';

  @override
  String get healthSleepTitle => 'Sleep';

  @override
  String get healthSleepTo => 'Woke up';

  @override
  String get healthSodium => 'Sodium';

  @override
  String get healthSourceEstimate => 'AI estimate';

  @override
  String get healthSourceFilipino => 'Filipino list';

  @override
  String get healthSourceLabel => 'From the label';

  @override
  String get healthSourceSaved => 'Saved';

  @override
  String get healthSourceWeb => 'From the web';

  @override
  String get healthSourceYours => 'Your numbers';

  @override
  String get healthStart => 'Start';

  @override
  String healthStartProgram(String name) {
    return 'Start $name';
  }

  @override
  String healthStartSession(String title) {
    return 'Start $title';
  }

  @override
  String get healthStartWalk => 'Log a walk';

  @override
  String get healthSteady => 'Steady';

  @override
  String healthStepOf(String step) {
    return '$step of 2';
  }

  @override
  String get healthStopProgram => 'Stop this program';

  @override
  String get healthStrengthDays => 'strength days';

  @override
  String healthStrengthLabel(String done, String goal) {
    return '$done of $goal strength days this week';
  }

  @override
  String get healthSugar => 'Sugar';

  @override
  String get healthSuggestFood =>
      'Try logging a few more full days, so the numbers can help you.';

  @override
  String get healthSuggestKeep => 'Keep doing what you are doing.';

  @override
  String get healthSuggestMove => 'Try one more walk this week.';

  @override
  String get healthSuggestSleep =>
      'Try to get to bed a little earlier this week.';

  @override
  String get healthSuggestWeigh =>
      'Try a few more weigh-ins, so the trend is clearer.';

  @override
  String get healthSwap => 'Swap';

  @override
  String get healthTakeAnother => 'Take another photo';

  @override
  String healthTileEaten(String kcal) {
    return 'About $kcal kcal';
  }

  @override
  String healthTileFreeToday(String from, String to) {
    return 'Free today from $from to $to';
  }

  @override
  String get healthTileLastNight => 'Last night';

  @override
  String healthTileLeft(String kcal) {
    return 'About $kcal left';
  }

  @override
  String get healthTileNoFree => 'No free time left in the plan today';

  @override
  String get healthTileNoPlan => 'Nothing planned';

  @override
  String healthTileOfTarget(String eaten, String target) {
    return '$eaten of $target kcal';
  }

  @override
  String healthTileOver(String kcal) {
    return 'About $kcal over';
  }

  @override
  String get healthTileSleep => 'Sleep';

  @override
  String get healthTileSleepEmpty => 'Tell Botler how you slept';

  @override
  String get healthTileToday => 'Today';

  @override
  String get healthTileTodayEmpty => 'Nothing logged yet';

  @override
  String get healthTileTrain => 'Train';

  @override
  String get healthTileTrainEmpty => 'Plan a week around your work';

  @override
  String get healthTileWeek => 'My week';

  @override
  String get healthTileWeekEmpty => 'Add your work hours';

  @override
  String get healthTileWeight => 'Weight';

  @override
  String get healthTileWeightEmpty => 'Add your first weigh-in';

  @override
  String get healthTitle => 'Health';

  @override
  String healthTodayAt(String time) {
    return 'Today at $time';
  }

  @override
  String get healthTodayDone => 'Done today';

  @override
  String get healthTodayEmptyLine =>
      'Take a photo of your food, or tell Botler what you ate.';

  @override
  String healthTodayProgram(String name) {
    return '$name is running';
  }

  @override
  String get healthTodayProgramLine =>
      'Nothing is set for today yet. Plan your next week and Botler places the sessions around your day.';

  @override
  String get healthTodayRoutine => 'Your routine today';

  @override
  String healthTodayRoutineItem(String time, String title) {
    return '$time, $title';
  }

  @override
  String get healthTodayRoutineLine =>
      'From your routines. Log it when you are done and it counts here.';

  @override
  String get healthTodayRunning => 'A session is in progress';

  @override
  String get healthTodayRunningLine => 'Pick up where you stopped.';

  @override
  String get healthTotalWeight =>
      'Weighed it? Total weight in grams (optional)';

  @override
  String get healthTrainTitle => 'Train';

  @override
  String healthTryKcal(String kcal) {
    return 'Try $kcal kcal a day';
  }

  @override
  String get healthTwoServings => 'Two';

  @override
  String get healthUndo => 'Undo';

  @override
  String get healthUnknown => 'Unknown';

  @override
  String healthUp(String kg) {
    return 'Up $kg kg';
  }

  @override
  String healthUseKcal(String kcal) {
    return 'Use $kcal';
  }

  @override
  String get healthVitamins => 'Vitamins and minerals';

  @override
  String get healthWalkSave => 'Save';

  @override
  String get healthWeekAccepted =>
      'Your week is set. Reminders come before each one.';

  @override
  String get healthWeekAddBlock => 'Add a time';

  @override
  String get healthWeekAddOnce => 'Add a change for one day';

  @override
  String get healthWeekAwake => 'Awake hours';

  @override
  String get healthWeekAwakeFrom => 'Change when you wake';

  @override
  String get healthWeekAwakeTo => 'Change when you sleep';

  @override
  String healthWeekBusyLine(String ranges) {
    return 'Busy $ranges';
  }

  @override
  String get healthWeekCopy => 'Copy to Tuesday through Friday';

  @override
  String get healthWeekFree => 'Free all day';

  @override
  String get healthWeekFrom => 'From';

  @override
  String get healthWeekIntro =>
      'Planned around your work and calendar. Nothing is set until you accept.';

  @override
  String get healthWeekLegendBusy => 'Busy';

  @override
  String get healthWeekLegendFree => 'Free';

  @override
  String get healthWeekLegendWork => 'Work';

  @override
  String get healthWeekLine =>
      'Botler plans workouts and reminders around this. You can also just say it in chat.';

  @override
  String healthWeekMinutes(String minutes) {
    return '$minutes minutes';
  }

  @override
  String get healthWeekOff => 'Day off';

  @override
  String get healthWeekOnce => 'Just this once';

  @override
  String get healthWeekOverlap =>
      'Two times on this day run into each other. Change one so they do not overlap.';

  @override
  String healthWeekRange(String from, String to) {
    return '$from to $to';
  }

  @override
  String get healthWeekReady => 'A new week of workouts is ready';

  @override
  String get healthWeekReadyLine => 'Nothing is set until you accept';

  @override
  String get healthWeekSameTime =>
      'A time cannot start and end at the same minute.';

  @override
  String get healthWeekSave => 'Save my week';

  @override
  String get healthWeekSaved => 'Saved your week.';

  @override
  String get healthWeekTitle => 'My week';

  @override
  String get healthWeekTo => 'To';

  @override
  String get healthWeekTravel => 'Travel to and from work';

  @override
  String get healthWeekWorking => 'I work this day';

  @override
  String get healthWeightBad => 'Enter your weight in kilograms, such as 74.2';

  @override
  String get healthWeightKg => 'Weight in kg';

  @override
  String get healthWeightQueued =>
      'Saved on this phone. It goes up when you are back online.';

  @override
  String get healthWeightSpark => 'Your weight trend';

  @override
  String get healthWeightTitle => 'Weight';

  @override
  String get healthWeightToday => 'Your weight today';

  @override
  String healthWindDownBy(String time) {
    return 'Wind down by $time';
  }

  @override
  String get healthWindDownNoEarly => 'No early start tomorrow';

  @override
  String get healthWindDownNone => 'Wind-down reminder';

  @override
  String get healthWindDownSwitch => 'Wind-down reminder';

  @override
  String healthWindDownWhy(String time) {
    return 'You start at $time tomorrow';
  }

  @override
  String get healthWokeToday => 'Woke up today';

  @override
  String get healthWorkingOnIt => 'Working on it';

  @override
  String healthWorkoutMinutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get healthWorkoutSaved => 'Saved. Well done for showing up.';

  @override
  String get healthYourPath => 'Your path';

  @override
  String get healthYourPrograms => 'Your programs';

  @override
  String get healthYourTrend => 'Your trend';

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
  String libraryActionsFor(String title) {
    return 'More for $title';
  }

  @override
  String get libraryActivity => 'Botler\'s recent changes';

  @override
  String libraryActivityAll(int count) {
    return 'Show all $count';
  }

  @override
  String get libraryActivityFewer => 'Show fewer';

  @override
  String libraryActivityLine(String page, String notebook) {
    return 'Botler changed $page in $notebook';
  }

  @override
  String libraryAgoDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String libraryAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String libraryAgoMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String get libraryAgoNow => 'just now';

  @override
  String get libraryAsk => 'Ask Botler to file something';

  @override
  String get libraryEmpty =>
      'No notebooks yet. Ask Botler to start one for a trip, a project or a list.';

  @override
  String get libraryMain => 'Main notebook';

  @override
  String get libraryMainLine => 'What Botler keeps in mind about you';

  @override
  String get libraryNeedsConnection =>
      'This needs a connection. Try again when you are online.';

  @override
  String get libraryNotebooks => 'Notebooks';

  @override
  String get libraryOffline => 'Offline copy';

  @override
  String libraryOfflineSince(String when) {
    return 'Offline copy from $when';
  }

  @override
  String libraryOpenNotebook(String title) {
    return 'Open notebook $title';
  }

  @override
  String libraryOpenPage(String title) {
    return 'Open page $title';
  }

  @override
  String libraryPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String get libraryPinned => 'Pinned';

  @override
  String get libraryPinnedRecent => 'Pinned and recent';

  @override
  String get libraryQueued =>
      'No connection. The change is kept on your phone and will be sent once.';

  @override
  String get librarySearchClear => 'Clear';

  @override
  String get librarySearchFailed => 'Search did not work. Try again.';

  @override
  String get librarySearchHint => 'Search your notebooks';

  @override
  String get librarySearchMore =>
      'There are more matches. Add a word to narrow it down.';

  @override
  String get librarySearchNone => 'Nothing found.';

  @override
  String get librarySearchOffline =>
      'Search needs a connection. Your pages can still be read offline.';

  @override
  String get librarySearchPrompt =>
      'Type at least two letters, then press search.';

  @override
  String get librarySearchTitle => 'Search';

  @override
  String get libraryTitle => 'Notebooks';

  @override
  String get libraryUndo => 'Undo';

  @override
  String libraryUndoFor(String page) {
    return 'Undo Botler\'s change to $page';
  }

  @override
  String get libraryUpdateServer =>
      'The server is older than this app and cannot show pages yet. Update the server.';

  @override
  String get libraryUpdated => 'Botler updated';

  @override
  String get lockContinueWithout => 'Continue without a lock';

  @override
  String get lockNoScreenLock =>
      'This phone has no screen lock set up, so Botler cannot ask for a fingerprint, face or PIN.';

  @override
  String get lockReason => 'Open Botler';

  @override
  String get lockTitle => 'Botler is locked';

  @override
  String get lockUnlock => 'Unlock';

  @override
  String get markChangePicture => 'Choose another picture';

  @override
  String get markChoosePicture => 'Choose a picture';

  @override
  String markEditTitle(String name) {
    return 'Icon for $name';
  }

  @override
  String get markIconBaby => 'Baby';

  @override
  String get markIconBank => 'Bank';

  @override
  String get markIconBolt => 'Electricity';

  @override
  String get markIconBus => 'Transport';

  @override
  String get markIconCar => 'Car';

  @override
  String get markIconCard => 'Card';

  @override
  String get markIconCart => 'Groceries';

  @override
  String get markIconCash => 'Cash';

  @override
  String get markIconCoffee => 'Coffee';

  @override
  String get markIconCrypto => 'Crypto';

  @override
  String get markIconFamily => 'Family';

  @override
  String get markIconFlag => 'Flag';

  @override
  String get markIconFood => 'Food';

  @override
  String get markIconFuel => 'Fuel';

  @override
  String get markIconGame => 'Games';

  @override
  String get markIconGift => 'Gift';

  @override
  String get markIconGym => 'Gym';

  @override
  String get markIconHealth => 'Health';

  @override
  String get markIconHeart => 'Heart';

  @override
  String get markIconHome => 'Home';

  @override
  String get markIconInsurance => 'Insurance';

  @override
  String get markIconInvest => 'Investments';

  @override
  String get markIconLoan => 'Loan';

  @override
  String get markIconPet => 'Pet';

  @override
  String get markIconPhone => 'Phone';

  @override
  String get markIconPiggy => 'Piggy bank';

  @override
  String get markIconRent => 'Rent';

  @override
  String get markIconSavings => 'Savings';

  @override
  String get markIconSchool => 'School';

  @override
  String markIconSemantic(String name) {
    return 'Icon: $name';
  }

  @override
  String get markIconShopping => 'Shopping';

  @override
  String get markIconStar => 'Star';

  @override
  String get markIconSubscription => 'Subscription';

  @override
  String get markIconTax => 'Tax';

  @override
  String get markIconTools => 'Repairs';

  @override
  String get markIconTravel => 'Travel';

  @override
  String get markIconTv => 'TV';

  @override
  String get markIconWallet => 'Wallet';

  @override
  String get markIconWater => 'Water';

  @override
  String get markIconWifi => 'Internet';

  @override
  String get markIconWork => 'Work';

  @override
  String get markMenu => 'Change icon or picture';

  @override
  String get markNone => 'No icon';

  @override
  String get markPictureChosen => 'Your picture';

  @override
  String get markPictureFailed =>
      'That picture could not be used. Try another one.';

  @override
  String get markPictureNote =>
      'A picture you pick is for you only. Botler\'s assistant never sees it.';

  @override
  String get markRemove => 'Remove icon or picture';

  @override
  String get markSaved => 'Saved.';

  @override
  String markSemantic(String name) {
    return 'Icon of $name';
  }

  @override
  String get markTitle => 'Icon or picture';

  @override
  String get mdBold => 'Bold';

  @override
  String get mdCheckbox => 'Checkbox';

  @override
  String get mdHeading => 'Heading';

  @override
  String get mdLink => 'Link';

  @override
  String get mdList => 'List';

  @override
  String get mdPageLink => 'Link to a page';

  @override
  String get memoryCopied => 'Copied everything to the clipboard.';

  @override
  String get memoryCopyAll => 'Copy everything (notebook and money) as text';

  @override
  String get memoryMore => 'More';

  @override
  String get memoryPeopleHint => 'Mama, Ate Liza';

  @override
  String get memoryPeopleNote =>
      'Botler hides these names from the AI that writes its replies.';

  @override
  String get memorySaved => 'Saved.';

  @override
  String get memoryWipe => 'Wipe';

  @override
  String get memoryWipeBody =>
      'This deletes your notebook and its changes, and your conversations with Botler. Your private names, accounts, bills and the rest of your money stay.';

  @override
  String get memoryWipeButton => 'Wipe the notebook and conversations';

  @override
  String get memoryWipeTitle => 'Wipe everything Botler remembers?';

  @override
  String get memoryWipeType => 'Type WIPE to confirm';

  @override
  String get memoryWipeWord => 'WIPE';

  @override
  String get memoryWiped => 'Wiped.';

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
  String get menuHealth => 'Health';

  @override
  String get menuHealthLine => 'Food, weight, workouts and sleep';

  @override
  String get menuHistory => 'History';

  @override
  String get menuHistoryLine => 'Everything you spent, and undo';

  @override
  String get menuNotebook => 'Notebook';

  @override
  String get menuNotebookLine => 'What Botler keeps in mind about you';

  @override
  String get menuPayday => 'Payday';

  @override
  String get menuPaydayLine => 'Split your pay, and the rules for it';

  @override
  String get menuSettings => 'Settings';

  @override
  String get menuSettingsLine => 'Language, money, lock, notifications, look';

  @override
  String get menuSimulate => 'Time travel';

  @override
  String get menuSimulateLine => 'Your balances on any past or future day';

  @override
  String get menuTitle => 'Menu';

  @override
  String netGross(String amount) {
    return 'Balance $amount';
  }

  @override
  String get netGroupOwed => 'Owed now';

  @override
  String get netGroupSetAside => 'Set aside for later';

  @override
  String netHeldBill(String label, String date) {
    return '$label, due $date';
  }

  @override
  String netHeldBillLate(String label, String date) {
    return '$label, late since $date';
  }

  @override
  String netHeldGoal(String label) {
    return 'Kept for the goal: $label';
  }

  @override
  String get netHeldNothing => 'Nothing is held: all of it is net.';

  @override
  String netHeldRule(String label, String date) {
    return '$label, saved for the bill due $date';
  }

  @override
  String get netHeldTitle => 'Held in this wallet';

  @override
  String get netNetNow => 'Net now';

  @override
  String netShortfall(String amount) {
    return 'Short by $amount for bills due before payday';
  }

  @override
  String get netShowGross => 'Show the balance as counted';

  @override
  String get netShowNet => 'Show net balance';

  @override
  String netSpentSetAside(String amount) {
    return '$amount set aside here was already spent';
  }

  @override
  String get netTakenBy => 'Taken from this by';

  @override
  String netTakenMore(int count) {
    return '+$count more, open the account to see all';
  }

  @override
  String get netTotalTitle => 'Net, after bills and goals';

  @override
  String get netUnavailable =>
      'The net balance could not be worked out just now. Balances are shown as counted.';

  @override
  String get no => 'No';

  @override
  String get notebookByBotler => 'Botler';

  @override
  String get notebookBySeed => 'Tidy-up';

  @override
  String get notebookByYou => 'You';

  @override
  String get notebookChanges => 'Changes';

  @override
  String get notebookChangesEmpty => 'No changes yet.';

  @override
  String notebookChars(String count) {
    return '$count characters';
  }

  @override
  String get notebookConflictBody =>
      'Botler, or another phone, changed it after you opened it. Your text is still here. Copy it, or save it over the new version: the other change stays in Changes.';

  @override
  String get notebookConflictCopy => 'Copy my text';

  @override
  String get notebookConflictSave => 'Save mine';

  @override
  String get notebookConflictTitle => 'The notebook changed';

  @override
  String get notebookCopiedText => 'Copied your text.';

  @override
  String notebookCount(String count, String max) {
    return '$count of $max characters';
  }

  @override
  String get notebookCreate => 'Create';

  @override
  String get notebookDelete => 'Delete notebook';

  @override
  String get notebookDeleteBody =>
      'It is hidden and Botler stops using it. You can put it back from Deleted notebooks for 30 days.';

  @override
  String get notebookDeleteTitle => 'Delete this notebook?';

  @override
  String get notebookDeleted => 'Deleted notebooks';

  @override
  String get notebookDeletedDone => 'Deleted.';

  @override
  String get notebookDeletedEmpty => 'No deleted notebooks.';

  @override
  String get notebookDescribe => 'Name and summary';

  @override
  String get notebookDiscardBody => 'The changes you typed will be lost.';

  @override
  String get notebookDiscardTitle => 'Leave without saving?';

  @override
  String get notebookDiscardYes => 'Leave';

  @override
  String get notebookEdit => 'Edit';

  @override
  String get notebookEditHint =>
      'Write what Botler should keep in mind about you';

  @override
  String get notebookEditTitle => 'Edit your notebook';

  @override
  String get notebookEmpty =>
      'Nothing here yet. Tell Botler something to remember, or tap Edit.';

  @override
  String get notebookExport => 'Copy as Markdown';

  @override
  String notebookExportBig(String size) {
    return 'This notebook is about $size MB of text. Copying it may be slow.';
  }

  @override
  String get notebookExportClipFail =>
      'Could not copy to the clipboard. Try again.';

  @override
  String notebookExported(int count) {
    return 'Copied $count pages as Markdown.';
  }

  @override
  String get notebookExporting => 'Collecting the pages...';

  @override
  String get notebookFieldSummary => 'What is in it?';

  @override
  String get notebookFieldSummaryHint =>
      'One line, so Botler knows when to open it';

  @override
  String get notebookFieldTitle => 'Title';

  @override
  String get notebookGoBack => 'Back';

  @override
  String get notebookGone => 'This notebook is gone';

  @override
  String get notebookGoneBody => 'It was deleted, here or on another phone.';

  @override
  String get notebookKeepEditing => 'Keep editing';

  @override
  String notebookNameRemove(String name) {
    return 'Remove $name';
  }

  @override
  String get notebookNames => 'Private names';

  @override
  String get notebookNamesAdd => 'Add a name';

  @override
  String get notebookNamesAddButton => 'Add';

  @override
  String get notebookNew => 'New notebook';

  @override
  String get notebookNoPages =>
      'No pages yet. Ask Botler to write one, or add a page yourself.';

  @override
  String get notebookOffline =>
      'No connection. Your text is still here: try again when you are online.';

  @override
  String get notebookOpenFirst => 'Open the first page';

  @override
  String get notebookOthers => 'Other notebooks';

  @override
  String get notebookOthersEmpty =>
      'None yet. Botler keeps the essentials here and can start a notebook for a trip, a project or a list. Ask for one, or make it yourself.';

  @override
  String get notebookRestore => 'Restore';

  @override
  String get notebookRestoreBody =>
      'Your notebook becomes the text below. What it says now stays in Changes, so you can undo this.';

  @override
  String get notebookRestoreTitle => 'Put this text back?';

  @override
  String get notebookRestored => 'Restored.';

  @override
  String get notebookSectionEmpty => 'Nothing yet';

  @override
  String get notebookSeeding =>
      'Made from what Botler remembered before. It is tidied in the background, and you can change any of it.';

  @override
  String get notebookTitle => 'Notebook';

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
  String get pageAddedMark => 'Added since you last read';

  @override
  String pageBreadcrumb(String trail) {
    return 'Page $trail';
  }

  @override
  String get pageChangedALot =>
      'This page changed a lot since you last read it, so the new lines are not marked.';

  @override
  String get pageChangesLegend =>
      'Marked on the left: what was added since you last read.';

  @override
  String get pageContents => 'Contents';

  @override
  String get pageContentsEmpty => 'This page has no headings.';

  @override
  String get pageCopied => 'Copied the page.';

  @override
  String get pageCopyText => 'Copy the text';

  @override
  String get pageCreate => 'Create';

  @override
  String pageDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String get pageDelete => 'Delete page';

  @override
  String get pageDeleteBody =>
      'The page and its sub-pages are hidden. You can put them back for 30 days.';

  @override
  String get pageDeleteTitle => 'Delete this page?';

  @override
  String get pageDeleted => 'Deleted.';

  @override
  String get pageDeletedEmpty => 'No deleted pages.';

  @override
  String get pageDeletedTitle => 'Deleted pages';

  @override
  String get pageEditOffline =>
      'Reading an offline copy. Editing needs a connection.';

  @override
  String get pageEmpty =>
      'This page is empty. Tap Edit to write on it, or ask Botler.';

  @override
  String get pageGone => 'This page is gone';

  @override
  String get pageGoneBody => 'Botler, or another phone, deleted it.';

  @override
  String pageLinkMissing(String title) {
    return 'No page called $title';
  }

  @override
  String get pageLinkedFrom => 'Linked from';

  @override
  String pageLinkedFromRow(String page, String notebook) {
    return 'Open $page, in $notebook, which links here';
  }

  @override
  String get pageMove => 'Move to...';

  @override
  String get pageMoveDown => 'Move down';

  @override
  String get pageMoveHasKids =>
      'This page has sub-pages, so it can only go to the top level.';

  @override
  String get pageMoveHere => 'where it is now';

  @override
  String pageMoveTitle(String title) {
    return 'Move $title';
  }

  @override
  String get pageMoveTop => 'Top level of the notebook';

  @override
  String pageMoveUnder(String title) {
    return 'Under $title';
  }

  @override
  String get pageMoveUp => 'Move up';

  @override
  String get pageMoved => 'Moved.';

  @override
  String get pageNew => 'New page';

  @override
  String get pagePin => 'Pin';

  @override
  String get pageRename => 'Rename';

  @override
  String get pageRenamed => 'Renamed.';

  @override
  String pageRestoreFor(String title) {
    return 'Restore $title';
  }

  @override
  String get pageRestored => 'Put back.';

  @override
  String get pageSubpages => 'Sub-pages';

  @override
  String get pageTitleHint => 'Wi-Fi and the router';

  @override
  String get pageTitleLabel => 'Page title';

  @override
  String pageToggleClose(String title) {
    return 'Hide the sub-pages of $title';
  }

  @override
  String pageToggleOpen(String title) {
    return 'Show the sub-pages of $title';
  }

  @override
  String get pageUnpin => 'Unpin';

  @override
  String pageUpdatedBy(String who, String when) {
    return 'Updated by $who, $when';
  }

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
  String get paydayDeclined => 'Rule declined.';

  @override
  String paydayDeleteBody(String label) {
    return '“$label” will be deleted for good. Money you already recorded stays where it is.';
  }

  @override
  String get paydayDeleteButton => 'Delete this payday';

  @override
  String get paydayDeleteTitle => 'Delete this payday?';

  @override
  String paydayDeleteWithSplitsBody(String label) {
    return '“$label” has earlier splits. Delete the payday and its splits for good? Money you already recorded stays where it is.';
  }

  @override
  String get paydayDeleteYes => 'Delete it';

  @override
  String get paydayDeleted => 'Payday deleted.';

  @override
  String get paydayDifferent => 'Different every time';

  @override
  String get paydayEarlier => 'Earlier splits';

  @override
  String get paydayEditMenu => 'Change or delete this payday';

  @override
  String get paydayEditTitle => 'Change this payday';

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
  String get paydayOff => 'Switched off';

  @override
  String get paydayPayEmptyHint => 'Leave empty to use what you usually get';

  @override
  String paydayPayInvalid(String currency) {
    return 'Type the pay in $currency.';
  }

  @override
  String get paydayPayLabel =>
      'How much is the pay this time? (leave empty for the usual)';

  @override
  String paydayPayThisTime(String currency) {
    return 'How much is the pay this time? ($currency)';
  }

  @override
  String get paydayPlan => 'Plan the split';

  @override
  String paydayPlanTitle(String label, String date) {
    return 'Plan $label on $date';
  }

  @override
  String get paydayRuleAddButton => 'Add the rule';

  @override
  String paydayRuleDeleteBody(String rule) {
    return '“$rule” will be deleted for good. Splits already made keep their numbers.';
  }

  @override
  String get paydayRuleDeleteButton => 'Delete the rule';

  @override
  String get paydayRuleDeleteTitle => 'Delete this rule?';

  @override
  String get paydayRuleDeleteYes => 'Delete it';

  @override
  String get paydayRuleDeleted => 'Rule deleted.';

  @override
  String get paydayRuleExamples =>
      'Examples: “500 to GCash”, “10% of what is left to Maya”, “the rest to RCBC”.';

  @override
  String get paydayRuleHint => '20% to emergency fund';

  @override
  String get paydayRuleLabel => 'Say it in your own words';

  @override
  String get paydayRuleMenu => 'More about this rule';

  @override
  String get paydayRuleNameHint => 'Emergency fund';

  @override
  String get paydayRuleNameLabel => 'Name (optional)';

  @override
  String get paydayRuleStopped => 'Stopped';

  @override
  String get paydayRuleTitle => 'Add a rule';

  @override
  String get paydayRulesEmpty =>
      'No rules yet. Say what should happen to what is left, like “20% to emergency fund”.';

  @override
  String get paydayRulesTitle => 'Rules for the rest';

  @override
  String get paydaySplitReady =>
      'Your split is ready below. Check it, then approve.';

  @override
  String get paydayStop => 'Stop';

  @override
  String get paydayStopBody =>
      'It stops applying to new splits. You can delete it any time.';

  @override
  String get paydayStopTitle => 'Stop this rule?';

  @override
  String get paydayStopYes => 'Stop it';

  @override
  String get paydayStopped => 'Rule stopped.';

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
  String get photoMarkApprove => 'Use this picture';

  @override
  String get photoMarkDown => 'Move down';

  @override
  String get photoMarkFill => 'Fill';

  @override
  String get photoMarkGone =>
      'This photo is no longer on this phone. Send it again and ask again.';

  @override
  String get photoMarkLeft => 'Move left';

  @override
  String get photoMarkNote =>
      'Cut on your phone. Your original photo stays here; only the small cut picture is saved.';

  @override
  String get photoMarkPreview => 'How the picture will look';

  @override
  String get photoMarkRetry => 'Try again';

  @override
  String get photoMarkRight => 'Move right';

  @override
  String get photoMarkUp => 'Move up';

  @override
  String get photoMarkWhole => 'Whole';

  @override
  String get photoMarkWorking => 'Cutting the picture';

  @override
  String get photoMarkZoomIn => 'Zoom in';

  @override
  String get photoMarkZoomOut => 'Zoom out';

  @override
  String photoNoticeBody(String server) {
    return 'Your photo goes to $server as a picture, so the assistant can see what is in it. Names and numbers in a picture are not hidden the way they are in text, and Botler\'s server does not keep it ($server handles it under its own terms). You can change this in Settings.';
  }

  @override
  String get photoNoticeNo => 'Text only';

  @override
  String get photoNoticeTitle => 'Send the picture itself?';

  @override
  String get photoNoticeYes => 'Send pictures';

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
  String researchClosedLabel(String label) {
    return '$label, list of sources, closed';
  }

  @override
  String researchCounts(int searches, int reads) {
    String _temp0 = intl.Intl.pluralLogic(
      searches,
      locale: localeName,
      other: '$searches searches',
      one: '$searches search',
    );
    String _temp1 = intl.Intl.pluralLogic(
      reads,
      locale: localeName,
      other: '$reads pages',
      one: '$reads page',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String researchDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources',
      one: '$count source',
    );
    return 'Researched, $_temp0';
  }

  @override
  String get researchDoneNone => 'Researched';

  @override
  String get researchFailed => 'Research could not reach the web.';

  @override
  String researchOpenLabel(String label) {
    return '$label, list of sources, open';
  }

  @override
  String researchOpenSource(String title, String host) {
    return 'Open $title, $host';
  }

  @override
  String researchRunning(String question) {
    return 'Researching: $question';
  }

  @override
  String get researchRunningNone => 'Researching';

  @override
  String get researchStoppedCancelled =>
      'Stopped. This is what it found so far.';

  @override
  String get researchStoppedOther =>
      'It stopped early, so this is what it found so far.';

  @override
  String get researchStoppedTime =>
      'It ran out of time, so this is what it found so far.';

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
  String get resetScopeHealth => 'Health';

  @override
  String get resetScopeHealthLine =>
      'Food, weight, workouts, sleep and your Health setup';

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
  String ruleSavesFor(String bill) {
    return 'Saves for $bill';
  }

  @override
  String get ruleSavesForHelp =>
      'Pick the bill this money is for. On payday the split then pays that bill from what this rule saved, instead of taking it from your pay a second time.';

  @override
  String get ruleSavesForNone => 'Saves for a bill?';

  @override
  String get ruleSavesForNothing => 'Nothing';

  @override
  String get ruleSavesForSaved => 'Saved.';

  @override
  String get ruleSavesForSemantic => 'Choose the bill this rule saves for';

  @override
  String get ruleSavesForTitle => 'What does this rule save for?';

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
  String schedFromDate(String date) {
    return 'from $date';
  }

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
  String schedNotOnDates(String dates) {
    return 'not on $dates';
  }

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
  String schedUntilDate(String date) {
    return 'until $date';
  }

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
  String get settingsAiServer => 'AI server';

  @override
  String get settingsAiServerDefault => 'Server default';

  @override
  String get settingsAiServerHelp =>
      'Answers can differ a little between servers.';

  @override
  String settingsAiServerUnavailable(String server) {
    return '$server is not available on the server right now, so the default is used.';
  }

  @override
  String get settingsAppLanguage => 'App language';

  @override
  String get settingsClock12 => '12 hour';

  @override
  String get settingsClock24 => '24 hour';

  @override
  String get settingsClockAuto => 'Phone';

  @override
  String get settingsClockTitle => 'Clock';

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
  String get settingsDateOrderDmy => 'D M Y';

  @override
  String get settingsDateOrderMdy => 'M D Y';

  @override
  String get settingsDateOrderTitle => 'Date order';

  @override
  String get settingsDateOrderYmd => 'Y M D';

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
  String get settingsNetBody =>
      'Lead with what is left after bills due before the next payday and money kept for goals. The balance you counted stays smaller beneath it.';

  @override
  String get settingsNetTitle => 'Show net balance';

  @override
  String settingsPhotoHelpImage(String server) {
    return 'The assistant looks at the picture itself, so it can describe a product or read a layout. The picture goes to $server as it is: names and numbers in it are not hidden the way they are in text. Botler\'s server does not keep it; $server handles it under its own terms.';
  }

  @override
  String settingsPhotoHelpOther(String server, String chat) {
    return '$chat cannot look at pictures, so $server looks at them for the messages that have one. The rest of your chat stays on $chat. The picture goes to $server as it is: names and numbers in it are not hidden the way they are in text. Botler\'s server does not keep it; $server handles it under its own terms.';
  }

  @override
  String get settingsPhotoHelpText =>
      'The phone reads the words on the photo and only those words are sent. Names and numbers are hidden as usual.';

  @override
  String get settingsPhotoImage => 'Picture';

  @override
  String settingsPhotoNoVision(String server) {
    return '$server cannot look at pictures, so it only gets the text read from them, whatever you choose here.';
  }

  @override
  String get settingsPhotoText => 'Text only';

  @override
  String get settingsPhotosTitle => 'Photos for the assistant';

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
  String settingsTimeNow(String now) {
    return 'Now: $now';
  }

  @override
  String get settingsTimeTitle => 'Date and time';

  @override
  String get settingsTimeZone => 'Time zone';

  @override
  String get settingsTimeZoneHelp =>
      'Decides what today is and the hours you see. Your phone\'s own zone does not change it.';

  @override
  String get settingsTimeZoneNone => 'No time zone matches that.';

  @override
  String get settingsTimeZoneSearch => 'Search a city or a zone';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsToolbox => 'Toolbox';

  @override
  String get settingsToolboxBody => 'Scripts Botler saved on this phone';

  @override
  String get settingsVoice => 'Voice';

  @override
  String get settingsWeekStarts => 'Week starts on';

  @override
  String get signInAgainBody =>
      'What you wrote offline is kept on this phone. Sign in again to send it.';

  @override
  String get signInAgainButton => 'Sign in again';

  @override
  String get signInAgainTitle => 'Your sign in has ended';

  @override
  String get signInButton => 'Sign in with Google';

  @override
  String get signInTagline => 'Your money and your time, in one quiet chat.';

  @override
  String signOutWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes are',
      one: '1 change is',
    );
    return '$_temp0 still waiting to be sent. They stay on this phone and go out when you sign in again.';
  }

  @override
  String simAbout(String amount) {
    return 'about $amount';
  }

  @override
  String get simAccountsTitle => 'Accounts';

  @override
  String get simAhead1m => '1 month ahead';

  @override
  String get simAhead1y => '1 year ahead';

  @override
  String get simAhead5y => '5 years ahead';

  @override
  String simAmountFor(String name) {
    return 'Amount for $name';
  }

  @override
  String get simBack1m => '1 month back';

  @override
  String get simBack1y => '1 year back';

  @override
  String get simBandFuture => 'An estimate, not real money';

  @override
  String get simBandFutureLine =>
      'Worked out from today\'s balances and your plan.';

  @override
  String get simBandMixed => 'Real until today, an estimate after';

  @override
  String get simBandMixedLine => 'Numbers after today are not real money.';

  @override
  String simBandOffline(String date) {
    return 'Saved $date, no connection.';
  }

  @override
  String get simBandPast => 'What really happened';

  @override
  String get simBandPastLine =>
      'Your recorded balances, beside what your plan would have done.';

  @override
  String simBelowDay(String account, String date) {
    return '$account below zero on $date';
  }

  @override
  String get simBills => 'Bills';

  @override
  String simBreakdownLine(String name, String amount, int percent) {
    return '$name, $amount, $percent percent of spending, tap to show only these entries';
  }

  @override
  String simBreakdownLineNoShare(String name, String amount) {
    return '$name, $amount, tap to show only these entries';
  }

  @override
  String get simChangeSelf => 'Change something yourself';

  @override
  String simChartSemantics(String period, String amount, String source) {
    return '$period: $amount, $source. Swipe up or down to move between periods.';
  }

  @override
  String get simDefer => 'Deferrable bills wait for the next payday';

  @override
  String get simDetails => 'Details';

  @override
  String get simDone => 'Done';

  @override
  String get simEarlier => 'Earlier';

  @override
  String get simEdit => 'Edit';

  @override
  String get simEntriesOffline =>
      'Where the money went and the entries need a connection. Only the totals are saved on this phone.';

  @override
  String get simEntriesTitle => 'Entries';

  @override
  String get simError => 'Time travel could not load.';

  @override
  String simEverythingElse(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groups',
      one: '1 group',
    );
    return 'Everything else ($_temp0)';
  }

  @override
  String simFirstRecordEdge(String date) {
    return 'Nothing was recorded before $date.';
  }

  @override
  String simGapAbove(String amount) {
    return '$amount above the plan';
  }

  @override
  String simGapBelow(String amount) {
    return '$amount below the plan';
  }

  @override
  String get simGapNone => 'Right on the plan';

  @override
  String get simGoals => 'Goals';

  @override
  String get simGroupGone =>
      'That group is no longer listed, so every entry is shown.';

  @override
  String get simGroupOther => 'Other';

  @override
  String get simHeldTitle => 'What is held';

  @override
  String get simHidden => 'hidden';

  @override
  String get simIncludesEstimate =>
      'Includes what is still to come (estimate).';

  @override
  String get simInfoChart =>
      'One point for each period. A solid line was recorded, a dashed line is an estimate or a replay of your plan. Tap or drag to pick a period. A ring marks a period that goes low or below zero. The chart always shows balances as counted; net is in the numbers under it.';

  @override
  String get simInfoChartTitle => 'The chart';

  @override
  String get simInfoGap =>
      'How far the recorded balance ended above or below where your plan would have put it.';

  @override
  String get simInfoGapTitle => 'The gap to the plan';

  @override
  String get simInfoIntro =>
      'Pick any day, week, month or year, up to 5 years back or ahead, to see what your accounts held or will hold. Anything after today is an estimate from today\'s balances and your plan, never real money.';

  @override
  String get simInfoNet =>
      'What is left of an account at the end of an estimated period, after the bills due before the next payday, the money your payday rules set aside for later bills and the money kept for a goal. The past has no net, because what was held then was never recorded. Turn it on or off with Show net balance on Accounts.';

  @override
  String get simInfoNetTitle => 'Net at the end';

  @override
  String get simInfoTags =>
      'Recorded: it really happened. Plan replay: what your plan would have done in the past. Simulated: an estimate for the future. Not recorded: a payday or bill your plan expected that was never recorded. What-if: something you only pretended.';

  @override
  String get simInfoTagsTitle => 'The tags';

  @override
  String get simInfoTitle => 'How Time travel works';

  @override
  String get simInfoTooltip => 'What am I looking at?';

  @override
  String get simInfoWarn =>
      'An account under its minimum or below zero on a day, and a currency with no exchange rate, which is left out of the total.';

  @override
  String get simInfoWarnTitle => 'Warnings';

  @override
  String get simIntro =>
      'See what your accounts held on any past day, or will hold on a future one. Numbers after today are estimates. Use What if to try a change without saving anything.';

  @override
  String get simIntroGotIt => 'Got it';

  @override
  String get simJump => 'Jump further';

  @override
  String simLateDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return 'Bills paid $_temp0 late';
  }

  @override
  String get simLater => 'Later';

  @override
  String simLowDay(String account, String date) {
    return '$account under its minimum on $date';
  }

  @override
  String simMissed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paydays or bills were not recorded',
      one: '1 payday or bill was not recorded',
    );
    return '$_temp0';
  }

  @override
  String simMissingRates(String codes) {
    return 'No exchange rate for $codes: left out of the totals.';
  }

  @override
  String simMoveTo(String account) {
    return 'to $account';
  }

  @override
  String get simNetEnd => 'Net at the end';

  @override
  String get simNetMissing =>
      'Net is not available for this period. Balances are shown as counted.';

  @override
  String simNetMixed(String date) {
    return 'Net on $date, not today.';
  }

  @override
  String get simNetPast =>
      'Net is not recorded for the past, so only balances are shown.';

  @override
  String get simNoEntries => 'Nothing in this period.';

  @override
  String get simNoPlan =>
      'No paydays or bills yet, so the simulated line stays flat.';

  @override
  String get simNoRateShort => 'no exchange rate yet';

  @override
  String get simNoRecords => 'No records yet for these dates.';

  @override
  String get simNoTotal => 'No total';

  @override
  String get simNothingSpent => 'Nothing was spent in this period.';

  @override
  String get simPageFailed => 'Could not load more.';

  @override
  String get simPaydays => 'Paydays';

  @override
  String simPercent(int percent) {
    return '$percent%';
  }

  @override
  String simPeriod(String from, String to) {
    return '$from to $to';
  }

  @override
  String get simPickDate => 'Pick a date';

  @override
  String get simPlanExpected => 'Your plan expected to spend';

  @override
  String get simPresetDefer => 'Defer what can wait';

  @override
  String get simPresetDeferLine =>
      'Bills that can wait are paid after the next payday.';

  @override
  String get simPresetLate => 'Pay bills a week late';

  @override
  String get simPresetLateLine =>
      'Every bill is paid 7 days after its due date.';

  @override
  String get simPresetNoRules => 'No payday rules';

  @override
  String get simPresetNoRulesLine =>
      'Switch off every payday rule, so nothing is set aside.';

  @override
  String get simPresetPayDown => 'Pay 10% lower';

  @override
  String get simPresetPayDownLine =>
      'Every pay with a known amount is 10% lower.';

  @override
  String get simPresetPayUp => 'Pay 10% higher';

  @override
  String get simPresetPayUpLine =>
      'Every pay with a known amount is 10% higher.';

  @override
  String get simPresetSkipNext => 'Skip the next payday';

  @override
  String get simPresetSkipNextLine =>
      'See how you would do if your next pay does not come.';

  @override
  String get simPresets => 'Start with one of these';

  @override
  String get simPretend => 'Pretend money in or out';

  @override
  String get simPretendAccount => 'Which account?';

  @override
  String get simPretendAdd => 'Add';

  @override
  String simPretendDate(String date) {
    return 'On $date';
  }

  @override
  String get simPretendIn => 'Money in';

  @override
  String get simPretendLabel => 'What is it?';

  @override
  String simPretendMainNote(String code) {
    return 'Pretend amounts are in $code, your main currency.';
  }

  @override
  String get simPretendOut => 'Money out';

  @override
  String simPretendRange(String min, String max) {
    return 'Use an amount from $min to $max.';
  }

  @override
  String simPretendTooMany(int count) {
    return 'You can pretend up to $count entries at once. Remove one first.';
  }

  @override
  String get simRatesStale => 'Exchange rates are older than a day.';

  @override
  String get simReachEdge => 'Time travel reaches 5 years each way.';

  @override
  String get simReceived => 'Received';

  @override
  String get simReceivedSoFar => 'Received so far';

  @override
  String get simRecordedEnd => 'Recorded at the end';

  @override
  String get simRecordedToday => 'Recorded up to today';

  @override
  String simRemove(String name) {
    return 'Remove $name';
  }

  @override
  String get simReplayEnd => 'Plan replay at the end';

  @override
  String get simReset => 'Reset';

  @override
  String get simResetDone => 'What-if cleared. Your plan is back as it is.';

  @override
  String get simRules => 'Payday rules';

  @override
  String simSectionChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return '$_temp0';
  }

  @override
  String get simSeeOverTime => 'See over time';

  @override
  String get simShowAll => 'Show all';

  @override
  String get simShowLess => 'Show less';

  @override
  String simShowMore(int count) {
    return 'Show $count more';
  }

  @override
  String simShowingGroup(String name) {
    return 'Showing $name';
  }

  @override
  String simShownOf(int shown, int total) {
    return 'Showing $shown of $total';
  }

  @override
  String get simSimulatedEnd => 'Simulated at the end';

  @override
  String get simSkipPayday => 'Tap a payday that would not come:';

  @override
  String get simSpanHint =>
      'This period holds today. Pick an earlier or a later one to see the total from it to today.';

  @override
  String get simSpanIncludes => 'Includes the period you picked.';

  @override
  String get simSpanNet => 'Net (received minus spent)';

  @override
  String get simSpanNothing => 'Nothing was spent or received in this span.';

  @override
  String simSpanRange(String from, String to) {
    return '$from to $to';
  }

  @override
  String get simSpanTitle => 'Overall flow';

  @override
  String get simSpanToday => 'today';

  @override
  String get simSpanTodayCap => 'Today';

  @override
  String get simSpent => 'Spent';

  @override
  String get simSpentSoFar => 'Spent so far';

  @override
  String get simStillToCome => 'Still to come (estimate)';

  @override
  String get simStillToReceive => 'Still to be received (estimate)';

  @override
  String get simTagMissed => 'Not recorded';

  @override
  String get simTagPretend => 'What-if';

  @override
  String get simTagRecorded => 'Recorded';

  @override
  String get simTagReplay => 'Plan replay';

  @override
  String get simTagSimulated => 'Simulated';

  @override
  String get simTiming => 'Timing';

  @override
  String get simTitle => 'Time travel';

  @override
  String get simToday => 'Today';

  @override
  String get simUndo => 'Undo';

  @override
  String simUnknown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pays or bills have no amount yet and are not counted',
      one: '1 pay or bill has no amount yet and is not counted',
    );
    return '$_temp0';
  }

  @override
  String get simUntracked => 'Untracked: left without being recorded';

  @override
  String get simWhatIf => 'What if';

  @override
  String get simWhatIfLine =>
      'Nothing here is saved. It only changes the replay and the simulation.';

  @override
  String simWhatIfOn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return 'What-if on: $_temp0';
  }

  @override
  String get simWhatIfTitle => 'What if…';

  @override
  String simWhereLine(String code) {
    return 'In $code, your main currency.';
  }

  @override
  String get simWhereTitle => 'Where it went';

  @override
  String get simWholePeriod => 'Whole period (estimate)';

  @override
  String get simZoomDay => 'Day';

  @override
  String get simZoomMonth => 'Month';

  @override
  String get simZoomWeek => 'Week';

  @override
  String get simZoomYear => 'Year';

  @override
  String get splitAccountFallback => 'account';

  @override
  String get splitApproveButton => 'Approve split';

  @override
  String get splitApproved => 'Approved';

  @override
  String get splitApprovedDone => 'Split approved.';

  @override
  String get splitBillFallback => 'a bill';

  @override
  String splitBrokenLink(String rule, String bill, String reason) {
    return '$rule cannot save for $bill: $reason.';
  }

  @override
  String get splitClearAll => 'Delete all earlier splits';

  @override
  String get splitClearAllBody =>
      'Every recorded split, approved or not, is deleted for good. Your bills, rules and paydays stay.';

  @override
  String get splitClearAllTitle => 'Delete all earlier splits?';

  @override
  String get splitClearAllYes => 'Delete them all';

  @override
  String get splitCleared => 'Splits deleted.';

  @override
  String splitCopied(String amount) {
    return 'Copied $amount';
  }

  @override
  String get splitCopyTooltip => 'Copy the amount';

  @override
  String splitCoveredLine(String bill, String account) {
    return '$bill  ·  already in $account';
  }

  @override
  String get splitCutOrMove => 'You could cut or move:';

  @override
  String splitDeleteBody(String date, String amount) {
    return 'The split for payday $date ($amount) is deleted for good.';
  }

  @override
  String get splitDeleteButton => 'Delete this split';

  @override
  String get splitDeleteEntriesHelp => 'This changes your account balances.';

  @override
  String get splitDeleteEntriesSwitch =>
      'Also take its pay and transfers out of my balances';

  @override
  String get splitDeleteKeepsMoney =>
      'Money you already recorded or marked as sent stays in your accounts.';

  @override
  String get splitDeleteTitle => 'Delete this split?';

  @override
  String get splitDeleteYes => 'Delete it';

  @override
  String get splitDeleted => 'Split deleted.';

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
  String get splitFromElsewhereTitle => 'Not taken from this pay';

  @override
  String splitFundedLine(String bill, String rule) {
    return '$bill  ·  saved by $rule';
  }

  @override
  String get splitMarkSent => 'Mark sent';

  @override
  String get splitMarkedSent => 'Marked as sent.';

  @override
  String get splitMenu => 'More about this split';

  @override
  String splitPayday(String date) {
    return 'Payday $date';
  }

  @override
  String get splitPlanAgain => 'Plan again';

  @override
  String get splitSent => 'Sent';

  @override
  String splitShort(String gap) {
    return 'This pay is $gap short of what you set aside.';
  }

  @override
  String get splitTransfers => 'Transfers to make';

  @override
  String splitUnfundedLine(String bill) {
    return '$bill  ·  still needed from this pay';
  }

  @override
  String summaryMissingRates(int count) {
    return '$count currencies are not in this total: no exchange rate yet.';
  }

  @override
  String toolBlockedNamed(String what) {
    return 'Blocked: $what';
  }

  @override
  String toolFailedNamed(String what) {
    return 'Failed: $what';
  }

  @override
  String toolGroupChecked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count things',
      one: '$count thing',
    );
    return 'Checked $_temp0';
  }

  @override
  String get toolGroupChecking => 'Checking things';

  @override
  String toolGroupClosedLabel(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '$count step',
    );
    return '$label, $_temp0, closed';
  }

  @override
  String toolGroupOpenLabel(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '$count step',
    );
    return '$label, $_temp0, open';
  }

  @override
  String toolGroupOpenedPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'Opened $_temp0';
  }

  @override
  String get toolGroupOpeningPages => 'Opening pages';

  @override
  String toolGroupProgress(int done, int total) {
    return '$done of $total';
  }

  @override
  String toolGroupReadNotebooks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notebooks',
      one: '$count notebook',
    );
    return 'Read $_temp0';
  }

  @override
  String toolGroupReadPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'Read $_temp0';
  }

  @override
  String get toolGroupReadingNotebooks => 'Reading notebooks';

  @override
  String get toolGroupReadingPages => 'Reading pages';

  @override
  String toolGroupSearchedNotebooks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: '$count time',
    );
    return 'Searched notebooks $_temp0';
  }

  @override
  String toolGroupSearchedWeb(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: '$count time',
    );
    return 'Searched the web $_temp0';
  }

  @override
  String get toolGroupSearchingNotebooks => 'Searching notebooks';

  @override
  String get toolGroupSearchingWeb => 'Searching the web';

  @override
  String toolOpenedPage(String subject) {
    return 'Opened $subject';
  }

  @override
  String get toolOpenedPageNone => 'Opened a web page';

  @override
  String toolOpeningPage(String subject) {
    return 'Opening $subject';
  }

  @override
  String get toolOpeningPageNone => 'Opening a web page';

  @override
  String toolReadNotebook(String subject) {
    return 'Read notebook $subject';
  }

  @override
  String get toolReadNotebookNone => 'Read your notebooks';

  @override
  String toolReadPage(String subject) {
    return 'Read page $subject';
  }

  @override
  String get toolReadPageNone => 'Read a page';

  @override
  String toolReadingNotebook(String subject) {
    return 'Reading notebook $subject';
  }

  @override
  String get toolReadingNotebookNone => 'Reading your notebooks';

  @override
  String toolReadingPage(String subject) {
    return 'Reading page $subject';
  }

  @override
  String get toolReadingPageNone => 'Reading a page';

  @override
  String toolSearchedNotebooks(String subject) {
    return 'Searched notebooks for $subject';
  }

  @override
  String get toolSearchedNotebooksNone => 'Searched your notebooks';

  @override
  String toolSearchedWeb(String subject) {
    return 'Searched the web for $subject';
  }

  @override
  String get toolSearchedWebNone => 'Searched the web';

  @override
  String toolSearchingNotebooks(String subject) {
    return 'Searching notebooks for $subject';
  }

  @override
  String get toolSearchingNotebooksNone => 'Searching your notebooks';

  @override
  String toolSearchingWeb(String subject) {
    return 'Searching the web for $subject';
  }

  @override
  String get toolSearchingWebNone => 'Searching the web';

  @override
  String toolTook(String text, int seconds) {
    return '$text, $seconds s';
  }

  @override
  String toolUpdatedPage(String subject) {
    return 'Updated page $subject';
  }

  @override
  String get toolUpdatedPageNone => 'Updated a page';

  @override
  String toolUpdatingNotebook(String subject) {
    return 'Updating notebook $subject';
  }

  @override
  String toolUpdatingPage(String subject) {
    return 'Updating page $subject';
  }

  @override
  String get toolUpdatingPageNone => 'Updating a page';

  @override
  String toolboxChars(int count) {
    return '$count characters';
  }

  @override
  String toolboxCount(int count, int limit) {
    return '$count of $limit saved';
  }

  @override
  String get toolboxDelete => 'Delete';

  @override
  String toolboxDeleteBody(String name) {
    return '\"$name\" will be removed from this phone.';
  }

  @override
  String get toolboxDeleteTitle => 'Delete this script?';

  @override
  String get toolboxDeleted => 'Script deleted.';

  @override
  String get toolboxEmpty => 'Nothing saved yet.';

  @override
  String get toolboxFailed => 'The toolbox could not be read.';

  @override
  String get toolboxNote =>
      'Botler can run small scripts on this phone to calculate or work on pictures. They have no internet, only reach a scratch folder for each chat, and can never change your money or your data. Botler saves one here only when you ask or agree.';

  @override
  String get toolboxTitle => 'Toolbox';

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
  String get updCheckNow => 'Check for updates';

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
  String updPercent(int percent) {
    return '$percent%';
  }

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
    return 'Version $version is ready to install.';
  }

  @override
  String get updRowChecking => 'Checking for updates…';

  @override
  String get updRowFailed => 'Could not check for updates.';

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
  String get updRowUpToDate => 'You have the latest version.';

  @override
  String get updUseForNow => 'Use the app for now';

  @override
  String get updVerifying => 'Checking the download…';

  @override
  String get webMarkLooking => 'Looking for logos on the web';

  @override
  String get webMarkNone =>
      'I could not load a usable logo from the web. Ask me to try another site, or send a photo.';

  @override
  String get webMarkNote =>
      'Found on the web and cut on your phone. Pick the one you want; only the small cut picture is saved.';

  @override
  String webMarkOption(int n) {
    return 'Logo option $n';
  }

  @override
  String get yes => 'Yes';
}
