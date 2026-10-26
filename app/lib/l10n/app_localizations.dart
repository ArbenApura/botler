import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fil.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fil'),
  ];

  /// No description provided for @accountsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get accountsAdd;

  /// No description provided for @accountsAddInvalid.
  ///
  /// In en, this message translates to:
  /// **'Give it a name, and the minimum as an amount.'**
  String get accountsAddInvalid;

  /// No description provided for @accountsBelowMinimum.
  ///
  /// In en, this message translates to:
  /// **'Below the minimum you set'**
  String get accountsBelowMinimum;

  /// No description provided for @accountsBotlerThinks.
  ///
  /// In en, this message translates to:
  /// **'Botler thinks there is {amount}.'**
  String accountsBotlerThinks(String amount);

  /// No description provided for @accountsConfirmBig.
  ///
  /// In en, this message translates to:
  /// **'That is a big difference'**
  String get accountsConfirmBig;

  /// No description provided for @accountsConfirmBoth.
  ///
  /// In en, this message translates to:
  /// **'You counted {counted} and Botler expected {expected}.'**
  String accountsConfirmBoth(String counted, String expected);

  /// No description provided for @accountsConfirmCounted.
  ///
  /// In en, this message translates to:
  /// **'You counted {counted}.'**
  String accountsConfirmCounted(String counted);

  /// No description provided for @accountsConfirmLarge.
  ///
  /// In en, this message translates to:
  /// **'It is more than ten times different, so please check the digits.'**
  String get accountsConfirmLarge;

  /// No description provided for @accountsConfirmRight.
  ///
  /// In en, this message translates to:
  /// **'Is this right?'**
  String get accountsConfirmRight;

  /// No description provided for @accountsConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, that is right'**
  String get accountsConfirmYes;

  /// No description provided for @accountsCountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Type the amount in {currency}.'**
  String accountsCountInvalid(String currency);

  /// No description provided for @accountsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'How much is really there? ({currency})'**
  String accountsCountLabel(String currency);

  /// No description provided for @accountsCountTitle.
  ///
  /// In en, this message translates to:
  /// **'I counted {name}'**
  String accountsCountTitle(String name);

  /// No description provided for @accountsCounted.
  ///
  /// In en, this message translates to:
  /// **'Counted {when}'**
  String accountsCounted(String when);

  /// No description provided for @accountsCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get accountsCurrencyLabel;

  /// No description provided for @accountsCurrencyNote.
  ///
  /// In en, this message translates to:
  /// **'What is in this account is counted in this currency unless you pick another when you enter something.'**
  String get accountsCurrencyNote;

  /// No description provided for @accountsDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} days ago}}'**
  String accountsDaysAgo(int count);

  /// No description provided for @accountsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet. Add RCBC, GCash, Maya or cash.'**
  String get accountsEmpty;

  /// No description provided for @accountsKindBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get accountsKindBank;

  /// No description provided for @accountsKindCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get accountsKindCash;

  /// No description provided for @accountsKindEwallet.
  ///
  /// In en, this message translates to:
  /// **'E-wallet'**
  String get accountsKindEwallet;

  /// No description provided for @accountsKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get accountsKindOther;

  /// No description provided for @accountsMinimumLabel.
  ///
  /// In en, this message translates to:
  /// **'Keep at least ({currency}, optional)'**
  String accountsMinimumLabel(String currency);

  /// No description provided for @accountsMissingRate.
  ///
  /// In en, this message translates to:
  /// **'No exchange rate yet for {currencies}. It is not in the total.'**
  String accountsMissingRate(String currencies);

  /// No description provided for @accountsNameHint.
  ///
  /// In en, this message translates to:
  /// **'GCash'**
  String get accountsNameHint;

  /// No description provided for @accountsNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get accountsNameLabel;

  /// No description provided for @accountsNeverCounted.
  ///
  /// In en, this message translates to:
  /// **'Never counted'**
  String get accountsNeverCounted;

  /// No description provided for @accountsNoMainWallet.
  ///
  /// In en, this message translates to:
  /// **'Nothing in {currency} here, so the minimum is not checked.'**
  String accountsNoMainWallet(String currency);

  /// No description provided for @accountsNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Not saved.'**
  String get accountsNotSaved;

  /// No description provided for @accountsRatesAsOf.
  ///
  /// In en, this message translates to:
  /// **'Exchange rates as of {date}'**
  String accountsRatesAsOf(String date);

  /// No description provided for @accountsRatesFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update the rates. The last ones are still used.'**
  String get accountsRatesFailed;

  /// No description provided for @accountsRatesNone.
  ///
  /// In en, this message translates to:
  /// **'No exchange rates yet. Tap to get them.'**
  String get accountsRatesNone;

  /// No description provided for @accountsRatesOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection. Showing the last total.'**
  String get accountsRatesOffline;

  /// No description provided for @accountsRatesRefresh.
  ///
  /// In en, this message translates to:
  /// **'Update rates'**
  String get accountsRatesRefresh;

  /// No description provided for @accountsRatesStale.
  ///
  /// In en, this message translates to:
  /// **'Exchange rates are old (from {date}). Tap to update.'**
  String accountsRatesStale(String date);

  /// No description provided for @accountsRatesTooSoon.
  ///
  /// In en, this message translates to:
  /// **'The rates were just updated.'**
  String get accountsRatesTooSoon;

  /// No description provided for @accountsRatesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Exchange rates updated.'**
  String get accountsRatesUpdated;

  /// No description provided for @accountsSaveCount.
  ///
  /// In en, this message translates to:
  /// **'Save the count'**
  String get accountsSaveCount;

  /// No description provided for @accountsSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get accountsSaved;

  /// No description provided for @accountsSavedUntracked.
  ///
  /// In en, this message translates to:
  /// **'Saved. {amount} went untracked since the last count.'**
  String accountsSavedUntracked(String amount);

  /// No description provided for @accountsSubtotal.
  ///
  /// In en, this message translates to:
  /// **'About {amount} in all'**
  String accountsSubtotal(String amount);

  /// No description provided for @accountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountsTitle;

  /// No description provided for @accountsToday.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get accountsToday;

  /// No description provided for @accountsTotalTitle.
  ///
  /// In en, this message translates to:
  /// **'Everything you have'**
  String get accountsTotalTitle;

  /// No description provided for @accountsTotalUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The total needs exchange rates, and there are none yet.'**
  String get accountsTotalUnavailable;

  /// No description provided for @accountsWalletAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a currency'**
  String get accountsWalletAdd;

  /// No description provided for @accountsWalletAdded.
  ///
  /// In en, this message translates to:
  /// **'{currency} added.'**
  String accountsWalletAdded(String currency);

  /// No description provided for @accountsWalletsTitle.
  ///
  /// In en, this message translates to:
  /// **'Currencies in this account'**
  String get accountsWalletsTitle;

  /// No description provided for @accountsYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get accountsYesterday;

  /// No description provided for @acctBalanceNow.
  ///
  /// In en, this message translates to:
  /// **'Balance now'**
  String get acctBalanceNow;

  /// No description provided for @acctByAnyone.
  ///
  /// In en, this message translates to:
  /// **'Anyone'**
  String get acctByAnyone;

  /// No description provided for @acctByBotler.
  ///
  /// In en, this message translates to:
  /// **'Botler'**
  String get acctByBotler;

  /// No description provided for @acctByJob.
  ///
  /// In en, this message translates to:
  /// **'Jobs and sync'**
  String get acctByJob;

  /// No description provided for @acctByYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get acctByYou;

  /// No description provided for @acctDateClear.
  ///
  /// In en, this message translates to:
  /// **'Any date'**
  String get acctDateClear;

  /// No description provided for @acctDateRange.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get acctDateRange;

  /// No description provided for @acctEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get acctEmpty;

  /// No description provided for @acctExportCut.
  ///
  /// In en, this message translates to:
  /// **'Copied {rows} rows as {format}. {notice}'**
  String acctExportCut(int rows, String format, String notice);

  /// No description provided for @acctExportDone.
  ///
  /// In en, this message translates to:
  /// **'Copied {rows} rows as {format}.'**
  String acctExportDone(int rows, String format);

  /// No description provided for @acctLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Show older'**
  String get acctLoadMore;

  /// No description provided for @acctMenuCount.
  ///
  /// In en, this message translates to:
  /// **'I counted this'**
  String get acctMenuCount;

  /// No description provided for @acctMenuExport.
  ///
  /// In en, this message translates to:
  /// **'Export history'**
  String get acctMenuExport;

  /// No description provided for @acctMenuPurpose.
  ///
  /// In en, this message translates to:
  /// **'Edit label'**
  String get acctMenuPurpose;

  /// No description provided for @acctMenuReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to zero'**
  String get acctMenuReset;

  /// No description provided for @acctMenuSet.
  ///
  /// In en, this message translates to:
  /// **'Set balance'**
  String get acctMenuSet;

  /// No description provided for @acctOffline.
  ///
  /// In en, this message translates to:
  /// **'The history needs a connection.'**
  String get acctOffline;

  /// No description provided for @acctOpen.
  ///
  /// In en, this message translates to:
  /// **'See what happened'**
  String get acctOpen;

  /// No description provided for @acctSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get acctSearchHint;

  /// No description provided for @acctTabAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get acctTabAll;

  /// No description provided for @acctTabCounts.
  ///
  /// In en, this message translates to:
  /// **'Counts and resets'**
  String get acctTabCounts;

  /// No description provided for @acctTabIn.
  ///
  /// In en, this message translates to:
  /// **'Money in'**
  String get acctTabIn;

  /// No description provided for @acctTabOut.
  ///
  /// In en, this message translates to:
  /// **'Money out'**
  String get acctTabOut;

  /// No description provided for @acctTabUndone.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get acctTabUndone;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @agendaAddEvent.
  ///
  /// In en, this message translates to:
  /// **'Add an event'**
  String get agendaAddEvent;

  /// No description provided for @agendaAddRoutine.
  ///
  /// In en, this message translates to:
  /// **'Add a routine'**
  String get agendaAddRoutine;

  /// No description provided for @agendaAddTask.
  ///
  /// In en, this message translates to:
  /// **'Add a task'**
  String get agendaAddTask;

  /// No description provided for @agendaAlarm.
  ///
  /// In en, this message translates to:
  /// **'Alarm'**
  String get agendaAlarm;

  /// No description provided for @agendaAtTime.
  ///
  /// In en, this message translates to:
  /// **'At {time}'**
  String agendaAtTime(String time);

  /// No description provided for @agendaDaysAt.
  ///
  /// In en, this message translates to:
  /// **'{days} at {time}'**
  String agendaDaysAt(String days, String time);

  /// No description provided for @agendaDue.
  ///
  /// In en, this message translates to:
  /// **'Due {when}'**
  String agendaDue(String when);

  /// No description provided for @agendaEventNeeds.
  ///
  /// In en, this message translates to:
  /// **'Give it a name and a time.'**
  String get agendaEventNeeds;

  /// No description provided for @agendaEventSubmit.
  ///
  /// In en, this message translates to:
  /// **'Add the event'**
  String get agendaEventSubmit;

  /// No description provided for @agendaEventWhat.
  ///
  /// In en, this message translates to:
  /// **'What is it?'**
  String get agendaEventWhat;

  /// No description provided for @agendaEventsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No events in the next two weeks.'**
  String get agendaEventsEmpty;

  /// No description provided for @agendaEveryDayAt.
  ///
  /// In en, this message translates to:
  /// **'Every day at {time}'**
  String agendaEveryDayAt(String time);

  /// No description provided for @agendaEveryNDaysAt.
  ///
  /// In en, this message translates to:
  /// **'Every {n} days at {time}'**
  String agendaEveryNDaysAt(String n, String time);

  /// No description provided for @agendaFreqDaily.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get agendaFreqDaily;

  /// No description provided for @agendaFreqWeekly.
  ///
  /// In en, this message translates to:
  /// **'On some days'**
  String get agendaFreqWeekly;

  /// No description provided for @agendaMonthlyAt.
  ///
  /// In en, this message translates to:
  /// **'Every month on the {day}th at {time}'**
  String agendaMonthlyAt(String day, String time);

  /// No description provided for @agendaPickMoment.
  ///
  /// In en, this message translates to:
  /// **'Pick the day and time'**
  String get agendaPickMoment;

  /// No description provided for @agendaRemindMe.
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get agendaRemindMe;

  /// No description provided for @agendaReminderNeeds.
  ///
  /// In en, this message translates to:
  /// **'Say what for, and when.'**
  String get agendaReminderNeeds;

  /// No description provided for @agendaReminderWhat.
  ///
  /// In en, this message translates to:
  /// **'What for?'**
  String get agendaReminderWhat;

  /// No description provided for @agendaRemindersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reminders waiting.'**
  String get agendaRemindersEmpty;

  /// No description provided for @agendaRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get agendaRemove;

  /// No description provided for @agendaRoutineHint.
  ///
  /// In en, this message translates to:
  /// **'Take vitamins'**
  String get agendaRoutineHint;

  /// No description provided for @agendaRoutineNeeds.
  ///
  /// In en, this message translates to:
  /// **'Give it a name, and pick at least one day.'**
  String get agendaRoutineNeeds;

  /// No description provided for @agendaRoutineSubmit.
  ///
  /// In en, this message translates to:
  /// **'Add the routine'**
  String get agendaRoutineSubmit;

  /// No description provided for @agendaRoutinesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No routines. Try “gym every Monday, Wednesday and Friday at 6”.'**
  String get agendaRoutinesEmpty;

  /// No description provided for @agendaSetAlarm.
  ///
  /// In en, this message translates to:
  /// **'Set an alarm'**
  String get agendaSetAlarm;

  /// No description provided for @agendaStartTimer.
  ///
  /// In en, this message translates to:
  /// **'Start a timer'**
  String get agendaStartTimer;

  /// No description provided for @agendaTabEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get agendaTabEvents;

  /// No description provided for @agendaTabReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get agendaTabReminders;

  /// No description provided for @agendaTabRoutines.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get agendaTabRoutines;

  /// No description provided for @agendaTabTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get agendaTabTasks;

  /// No description provided for @agendaTaskDeadline.
  ///
  /// In en, this message translates to:
  /// **'Set a deadline (optional)'**
  String get agendaTaskDeadline;

  /// No description provided for @agendaTaskNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Say what the task is.'**
  String get agendaTaskNeedsTitle;

  /// No description provided for @agendaTaskSubmit.
  ///
  /// In en, this message translates to:
  /// **'Add the task'**
  String get agendaTaskSubmit;

  /// No description provided for @agendaTaskWhat.
  ///
  /// In en, this message translates to:
  /// **'What needs doing?'**
  String get agendaTaskWhat;

  /// No description provided for @agendaTasksEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing open. Add something you want to remember to do.'**
  String get agendaTasksEmpty;

  /// No description provided for @agendaTimerMinutes.
  ///
  /// In en, this message translates to:
  /// **'How many minutes?'**
  String get agendaTimerMinutes;

  /// No description provided for @agendaTimerRange.
  ///
  /// In en, this message translates to:
  /// **'Pick between 1 and 1440 minutes.'**
  String get agendaTimerRange;

  /// No description provided for @agendaTimerStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get agendaTimerStart;

  /// No description provided for @agendaTitle.
  ///
  /// In en, this message translates to:
  /// **'Agenda'**
  String get agendaTitle;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Botler'**
  String get appName;

  /// No description provided for @auditAcApprove.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get auditAcApprove;

  /// No description provided for @auditAcCount.
  ///
  /// In en, this message translates to:
  /// **'Counted'**
  String get auditAcCount;

  /// No description provided for @auditAcCreate.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get auditAcCreate;

  /// No description provided for @auditAcDataReset.
  ///
  /// In en, this message translates to:
  /// **'Data reset'**
  String get auditAcDataReset;

  /// No description provided for @auditAcDelete.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get auditAcDelete;

  /// No description provided for @auditAcExpire.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get auditAcExpire;

  /// No description provided for @auditAcReject.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get auditAcReject;

  /// No description provided for @auditAcReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get auditAcReset;

  /// No description provided for @auditAcUndo.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get auditAcUndo;

  /// No description provided for @auditAcUpdate.
  ///
  /// In en, this message translates to:
  /// **'Changed'**
  String get auditAcUpdate;

  /// No description provided for @auditBalanceAfter.
  ///
  /// In en, this message translates to:
  /// **'Balance after'**
  String get auditBalanceAfter;

  /// No description provided for @auditBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Entry {seq} no longer matches the one before it. Nothing was lost on this phone. Open Settings, Audit trail, and send the details to whoever runs your server.'**
  String auditBannerBody(int seq);

  /// No description provided for @auditBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'The audit trail does not add up'**
  String get auditBannerTitle;

  /// No description provided for @auditBotler.
  ///
  /// In en, this message translates to:
  /// **'Botler'**
  String get auditBotler;

  /// No description provided for @auditBotlerApproved.
  ///
  /// In en, this message translates to:
  /// **'Botler, approved by you'**
  String get auditBotlerApproved;

  /// No description provided for @auditChApp.
  ///
  /// In en, this message translates to:
  /// **'in the app'**
  String get auditChApp;

  /// No description provided for @auditChCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar sync (retired)'**
  String get auditChCalendar;

  /// No description provided for @auditChChat.
  ///
  /// In en, this message translates to:
  /// **'in chat'**
  String get auditChChat;

  /// No description provided for @auditChJob.
  ///
  /// In en, this message translates to:
  /// **'a job'**
  String get auditChJob;

  /// No description provided for @auditChOutbox.
  ///
  /// In en, this message translates to:
  /// **'offline, sent later'**
  String get auditChOutbox;

  /// No description provided for @auditChSystem.
  ///
  /// In en, this message translates to:
  /// **'the system'**
  String get auditChSystem;

  /// No description provided for @auditChWidget.
  ///
  /// In en, this message translates to:
  /// **'from the widget'**
  String get auditChWidget;

  /// No description provided for @auditChangeLine.
  ///
  /// In en, this message translates to:
  /// **'{field}: {before} to {after}'**
  String auditChangeLine(String field, String before, String after);

  /// No description provided for @auditChanges.
  ///
  /// In en, this message translates to:
  /// **'What changed'**
  String get auditChanges;

  /// No description provided for @auditChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get auditChecking;

  /// No description provided for @auditCopied.
  ///
  /// In en, this message translates to:
  /// **'Reference copied.'**
  String get auditCopied;

  /// No description provided for @auditCopyRef.
  ///
  /// In en, this message translates to:
  /// **'Copy reference'**
  String get auditCopyRef;

  /// No description provided for @auditEnSnapshot.
  ///
  /// In en, this message translates to:
  /// **'balance count'**
  String get auditEnSnapshot;

  /// No description provided for @auditEnTxn.
  ///
  /// In en, this message translates to:
  /// **'transaction'**
  String get auditEnTxn;

  /// No description provided for @auditJob.
  ///
  /// In en, this message translates to:
  /// **'A scheduled job'**
  String get auditJob;

  /// No description provided for @auditNone.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get auditNone;

  /// No description provided for @auditNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get auditNote;

  /// No description provided for @auditRefApproval.
  ///
  /// In en, this message translates to:
  /// **'approval'**
  String get auditRefApproval;

  /// No description provided for @auditRefRequest.
  ///
  /// In en, this message translates to:
  /// **'request'**
  String get auditRefRequest;

  /// No description provided for @auditRefTurn.
  ///
  /// In en, this message translates to:
  /// **'turn'**
  String get auditRefTurn;

  /// No description provided for @auditRefs.
  ///
  /// In en, this message translates to:
  /// **'References'**
  String get auditRefs;

  /// No description provided for @auditRowSemantics.
  ///
  /// In en, this message translates to:
  /// **'{what}, {who}, {when}, balance after {balance}'**
  String auditRowSemantics(
    String what,
    String who,
    String when,
    String balance,
  );

  /// No description provided for @auditSettingsBad.
  ///
  /// In en, this message translates to:
  /// **'Entry {seq} is out of order ({kind}).'**
  String auditSettingsBad(int seq, String kind);

  /// No description provided for @auditSettingsLine.
  ///
  /// In en, this message translates to:
  /// **'Every change to your money is written once and can never be edited or deleted.'**
  String get auditSettingsLine;

  /// No description provided for @auditSettingsOk.
  ///
  /// In en, this message translates to:
  /// **'Checked {count} entries, all in order. Last check {when}.'**
  String auditSettingsOk(int count, String when);

  /// No description provided for @auditSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Audit trail'**
  String get auditSettingsTitle;

  /// No description provided for @auditSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get auditSync;

  /// No description provided for @auditUnverified.
  ///
  /// In en, this message translates to:
  /// **'The history could not be checked just now.'**
  String get auditUnverified;

  /// No description provided for @auditWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get auditWhen;

  /// No description provided for @auditWhere.
  ///
  /// In en, this message translates to:
  /// **'Where'**
  String get auditWhere;

  /// No description provided for @auditWho.
  ///
  /// In en, this message translates to:
  /// **'Who'**
  String get auditWho;

  /// No description provided for @auditYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get auditYou;

  /// No description provided for @billsAboutLabel.
  ///
  /// In en, this message translates to:
  /// **'About how much? ({currency})'**
  String billsAboutLabel(String currency);

  /// No description provided for @billsAboutMain.
  ///
  /// In en, this message translates to:
  /// **'about {amount}'**
  String billsAboutMain(String amount);

  /// No description provided for @billsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a bill'**
  String get billsAdd;

  /// No description provided for @billsAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add the bill'**
  String get billsAddButton;

  /// No description provided for @billsAddInvalid.
  ///
  /// In en, this message translates to:
  /// **'Give it a name, an amount and an account.'**
  String get billsAddInvalid;

  /// No description provided for @billsAll.
  ///
  /// In en, this message translates to:
  /// **'All bills'**
  String get billsAll;

  /// No description provided for @billsAmountNotKnown.
  ///
  /// In en, this message translates to:
  /// **'amount not known yet'**
  String get billsAmountNotKnown;

  /// No description provided for @billsAmountUnknown.
  ///
  /// In en, this message translates to:
  /// **'amount?'**
  String get billsAmountUnknown;

  /// No description provided for @billsChargedLabel.
  ///
  /// In en, this message translates to:
  /// **'Really charged ({currency})'**
  String billsChargedLabel(String currency);

  /// No description provided for @billsChargedNote.
  ///
  /// In en, this message translates to:
  /// **'This bill is in {bill}, but you pay from a {wallet} wallet. Type what was really charged.'**
  String billsChargedNote(String bill, String wallet);

  /// No description provided for @billsComingUp.
  ///
  /// In en, this message translates to:
  /// **'Coming up'**
  String get billsComingUp;

  /// No description provided for @billsCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency of this bill'**
  String get billsCurrencyLabel;

  /// No description provided for @billsDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get billsDateLabel;

  /// No description provided for @billsDateNote.
  ///
  /// In en, this message translates to:
  /// **'This moves only this one. To change every date, change how it repeats below.'**
  String get billsDateNote;

  /// No description provided for @billsEditHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to change it'**
  String get billsEditHint;

  /// No description provided for @billsEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Change the bill'**
  String get billsEditTitle;

  /// No description provided for @billsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No bills yet. Add rent, internet, electricity...'**
  String get billsEmpty;

  /// No description provided for @billsHowMuchLabel.
  ///
  /// In en, this message translates to:
  /// **'How much? ({currency})'**
  String billsHowMuchLabel(String currency);

  /// No description provided for @billsMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark paid'**
  String get billsMarkPaid;

  /// No description provided for @billsMarkPaidFor.
  ///
  /// In en, this message translates to:
  /// **'Mark {name} paid'**
  String billsMarkPaidFor(String name);

  /// No description provided for @billsMarkedPaid.
  ///
  /// In en, this message translates to:
  /// **'Marked paid.'**
  String get billsMarkedPaid;

  /// No description provided for @billsMarkedPaidHint.
  ///
  /// In en, this message translates to:
  /// **'Marked paid. It came in {amount} under the usual: you could set that aside.'**
  String billsMarkedPaidHint(String amount);

  /// No description provided for @billsMissingRateTag.
  ///
  /// In en, this message translates to:
  /// **'no exchange rate yet'**
  String get billsMissingRateTag;

  /// No description provided for @billsMovedTag.
  ///
  /// In en, this message translates to:
  /// **'moved'**
  String get billsMovedTag;

  /// No description provided for @billsNameHint.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get billsNameHint;

  /// No description provided for @billsNameLabel.
  ///
  /// In en, this message translates to:
  /// **'What is it?'**
  String get billsNameLabel;

  /// No description provided for @billsNoChange.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed.'**
  String get billsNoChange;

  /// No description provided for @billsNothingDue.
  ///
  /// In en, this message translates to:
  /// **'Nothing is due in the next 4 months.'**
  String get billsNothingDue;

  /// No description provided for @billsOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get billsOverdue;

  /// No description provided for @billsPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get billsPaid;

  /// No description provided for @billsPaidFrom.
  ///
  /// In en, this message translates to:
  /// **'Paid from'**
  String get billsPaidFrom;

  /// No description provided for @billsPaidTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} paid'**
  String billsPaidTitle(String name);

  /// No description provided for @billsParentsShare.
  ///
  /// In en, this message translates to:
  /// **'This is my parents’ share'**
  String get billsParentsShare;

  /// No description provided for @billsParentsTag.
  ///
  /// In en, this message translates to:
  /// **'parents’ share'**
  String get billsParentsTag;

  /// No description provided for @billsPayInvalid.
  ///
  /// In en, this message translates to:
  /// **'Type the amount in {currency}.'**
  String billsPayInvalid(String currency);

  /// No description provided for @billsPayLabel.
  ///
  /// In en, this message translates to:
  /// **'How much was it this time? ({currency})'**
  String billsPayLabel(String currency);

  /// No description provided for @billsPutBack.
  ///
  /// In en, this message translates to:
  /// **'Put back as scheduled'**
  String get billsPutBack;

  /// No description provided for @billsPutBackDone.
  ///
  /// In en, this message translates to:
  /// **'Back to the schedule.'**
  String get billsPutBackDone;

  /// No description provided for @billsRepeatChangedNote.
  ///
  /// In en, this message translates to:
  /// **'You changed how it repeats, so every date follows the new rule.'**
  String get billsRepeatChangedNote;

  /// No description provided for @billsReserveNote.
  ///
  /// In en, this message translates to:
  /// **'The payday split keeps the money for this bill in your main currency. Paying from another wallet can take that wallet below zero.'**
  String get billsReserveNote;

  /// No description provided for @billsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get billsSave;

  /// No description provided for @billsSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get billsSaved;

  /// No description provided for @billsSavedOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection. It will be saved when you are back online.'**
  String get billsSavedOffline;

  /// No description provided for @billsScopeAll.
  ///
  /// In en, this message translates to:
  /// **'Every time from now on'**
  String get billsScopeAll;

  /// No description provided for @billsScopeThisOne.
  ///
  /// In en, this message translates to:
  /// **'Just this one ({date})'**
  String billsScopeThisOne(String date);

  /// No description provided for @billsScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Just this one, or every time?'**
  String get billsScopeTitle;

  /// No description provided for @billsSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip this date'**
  String get billsSkip;

  /// No description provided for @billsSkipBody.
  ///
  /// In en, this message translates to:
  /// **'It will not show up for that date. Ask Botler to put it back if you change your mind.'**
  String get billsSkipBody;

  /// No description provided for @billsSkipTitle.
  ///
  /// In en, this message translates to:
  /// **'Skip {name} on {date}?'**
  String billsSkipTitle(String name, String date);

  /// No description provided for @billsSkipYes.
  ///
  /// In en, this message translates to:
  /// **'Skip it'**
  String get billsSkipYes;

  /// No description provided for @billsSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped.'**
  String get billsSkipped;

  /// No description provided for @billsTitle.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get billsTitle;

  /// No description provided for @billsUsualSuffix.
  ///
  /// In en, this message translates to:
  /// **'{amount} (usual)'**
  String billsUsualSuffix(String amount);

  /// No description provided for @billsVaries.
  ///
  /// In en, this message translates to:
  /// **'The amount is different every time'**
  String get billsVaries;

  /// No description provided for @billsWalletLabel.
  ///
  /// In en, this message translates to:
  /// **'Paid in'**
  String get billsWalletLabel;

  /// No description provided for @calAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get calAdd;

  /// No description provided for @calAddBill.
  ///
  /// In en, this message translates to:
  /// **'A bill'**
  String get calAddBill;

  /// No description provided for @calAddEvent.
  ///
  /// In en, this message translates to:
  /// **'An event'**
  String get calAddEvent;

  /// No description provided for @calAddReminder.
  ///
  /// In en, this message translates to:
  /// **'A reminder'**
  String get calAddReminder;

  /// No description provided for @calAddTask.
  ///
  /// In en, this message translates to:
  /// **'A task'**
  String get calAddTask;

  /// No description provided for @calAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add to {date}'**
  String calAddTitle(String date);

  /// No description provided for @calAgendaDueThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Due this week'**
  String get calAgendaDueThisWeek;

  /// No description provided for @calAgendaEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the next 30 days.'**
  String get calAgendaEmpty;

  /// No description provided for @calAgendaMore.
  ///
  /// In en, this message translates to:
  /// **'Show 30 more days'**
  String get calAgendaMore;

  /// No description provided for @calAllDay.
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get calAllDay;

  /// No description provided for @calAllDayToggle.
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get calAllDayToggle;

  /// No description provided for @calAmountUnknown.
  ///
  /// In en, this message translates to:
  /// **'amount?'**
  String get calAmountUnknown;

  /// No description provided for @calBillDue.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String calBillDue(String date);

  /// No description provided for @calBillOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get calBillOverdue;

  /// No description provided for @calBillPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get calBillPaid;

  /// No description provided for @calBillWindow.
  ///
  /// In en, this message translates to:
  /// **'Pay any day {start} to {end}'**
  String calBillWindow(String start, String end);

  /// No description provided for @calCountBills.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 bill} other{{count} bills}}'**
  String calCountBills(int count);

  /// No description provided for @calCountEvents.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 event} other{{count} events}}'**
  String calCountEvents(int count);

  /// No description provided for @calCountPaydays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 payday} other{{count} paydays}}'**
  String calCountPaydays(int count);

  /// No description provided for @calCountReminders.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 reminder} other{{count} reminders}}'**
  String calCountReminders(int count);

  /// No description provided for @calCountRoutines.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 routine} other{{count} routines}}'**
  String calCountRoutines(int count);

  /// No description provided for @calCountTasks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 task} other{{count} tasks}}'**
  String calCountTasks(int count);

  /// No description provided for @calDayNothing.
  ///
  /// In en, this message translates to:
  /// **'nothing planned'**
  String get calDayNothing;

  /// No description provided for @calDaySemantics.
  ///
  /// In en, this message translates to:
  /// **'{date}, {parts}'**
  String calDaySemantics(String date, String parts);

  /// No description provided for @calError.
  ///
  /// In en, this message translates to:
  /// **'The calendar could not load.'**
  String get calError;

  /// No description provided for @calEstimate.
  ///
  /// In en, this message translates to:
  /// **'Estimate'**
  String get calEstimate;

  /// No description provided for @calForecastLow.
  ///
  /// In en, this message translates to:
  /// **'{account} may drop under its minimum'**
  String calForecastLow(String account);

  /// No description provided for @calForecastLowDay.
  ///
  /// In en, this message translates to:
  /// **'Low on {date}'**
  String calForecastLowDay(String date);

  /// No description provided for @calForecastNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing to estimate yet. Add an account and a bill first.'**
  String get calForecastNone;

  /// No description provided for @calForecastOk.
  ///
  /// In en, this message translates to:
  /// **'never under the minimum'**
  String get calForecastOk;

  /// No description provided for @calForecastSemantics.
  ///
  /// In en, this message translates to:
  /// **'Estimated money across accounts from {from} to {to}, {low}'**
  String calForecastSemantics(String from, String to, String low);

  /// No description provided for @calForecastTitle.
  ///
  /// In en, this message translates to:
  /// **'Where your money is heading'**
  String get calForecastTitle;

  /// No description provided for @calForecastTotal.
  ///
  /// In en, this message translates to:
  /// **'About {amount}'**
  String calForecastTotal(String amount);

  /// No description provided for @calForecastUnconverted.
  ///
  /// In en, this message translates to:
  /// **'{count} bills in other currencies are left out of this forecast because their exchange rate is missing.'**
  String calForecastUnconverted(int count);

  /// No description provided for @calForecastUnknown.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 bill has no amount yet, so it counts as nothing} other{{count} bills have no amount yet, so they count as nothing}}'**
  String calForecastUnknown(int count);

  /// No description provided for @calLayerBills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get calLayerBills;

  /// No description provided for @calLayerEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get calLayerEvents;

  /// No description provided for @calLayerPaydays.
  ///
  /// In en, this message translates to:
  /// **'Paydays'**
  String get calLayerPaydays;

  /// No description provided for @calLayerReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get calLayerReminders;

  /// No description provided for @calLayerRoutines.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get calLayerRoutines;

  /// No description provided for @calLayerTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get calLayerTasks;

  /// No description provided for @calLayersLabel.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get calLayersLabel;

  /// No description provided for @calMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark paid'**
  String get calMarkPaid;

  /// No description provided for @calMarkPaidBody.
  ///
  /// In en, this message translates to:
  /// **'This writes {amount} as an expense.'**
  String calMarkPaidBody(String amount);

  /// No description provided for @calMarkPaidTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark {name} paid?'**
  String calMarkPaidTitle(String name);

  /// No description provided for @calMore.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String calMore(int count);

  /// No description provided for @calNeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Give it a name first.'**
  String get calNeedTitle;

  /// No description provided for @calNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get calNext;

  /// No description provided for @calNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get calNow;

  /// No description provided for @calOffline.
  ///
  /// In en, this message translates to:
  /// **'Showing the last calendar this phone saw.'**
  String get calOffline;

  /// No description provided for @calPaidDone.
  ///
  /// In en, this message translates to:
  /// **'Marked paid.'**
  String get calPaidDone;

  /// No description provided for @calPaydayLabel.
  ///
  /// In en, this message translates to:
  /// **'Payday'**
  String get calPaydayLabel;

  /// No description provided for @calPaydaySplit.
  ///
  /// In en, this message translates to:
  /// **'Split your pay'**
  String get calPaydaySplit;

  /// No description provided for @calPaydaySplitDone.
  ///
  /// In en, this message translates to:
  /// **'Split done'**
  String get calPaydaySplitDone;

  /// No description provided for @calPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get calPrev;

  /// No description provided for @calReminderLabel.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get calReminderLabel;

  /// No description provided for @calRoutineLabel.
  ///
  /// In en, this message translates to:
  /// **'Routine'**
  String get calRoutineLabel;

  /// No description provided for @calSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get calSaved;

  /// No description provided for @calTaskLabel.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get calTaskLabel;

  /// No description provided for @calTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get calTimeLabel;

  /// No description provided for @calTitle.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calTitle;

  /// No description provided for @calToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get calToday;

  /// No description provided for @calViewAgenda.
  ///
  /// In en, this message translates to:
  /// **'Agenda'**
  String get calViewAgenda;

  /// No description provided for @calViewMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get calViewMonth;

  /// No description provided for @calViewWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get calViewWeek;

  /// No description provided for @calWeekOf.
  ///
  /// In en, this message translates to:
  /// **'Week of {date}'**
  String calWeekOf(String date);

  /// No description provided for @calWhatIsIt.
  ///
  /// In en, this message translates to:
  /// **'What is it?'**
  String get calWhatIsIt;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @changelogBuildHeader.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String changelogBuildHeader(String version);

  /// No description provided for @changelogGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get changelogGotIt;

  /// No description provided for @changelogRowHint.
  ///
  /// In en, this message translates to:
  /// **'Read the changes in the version you have now'**
  String get changelogRowHint;

  /// No description provided for @changelogRowTitle.
  ///
  /// In en, this message translates to:
  /// **'What is new in this version'**
  String get changelogRowTitle;

  /// No description provided for @changelogTitle.
  ///
  /// In en, this message translates to:
  /// **'What is new in {version}'**
  String changelogTitle(String version);

  /// No description provided for @chatAcrossAccounts.
  ///
  /// In en, this message translates to:
  /// **'Across your accounts'**
  String get chatAcrossAccounts;

  /// No description provided for @chatAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Add an expense'**
  String get chatAddExpense;

  /// No description provided for @chatAddExpenseHint.
  ///
  /// In en, this message translates to:
  /// **'You can still add an expense yourself.'**
  String get chatAddExpenseHint;

  /// No description provided for @chatApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get chatApprove;

  /// No description provided for @chatApproveRule.
  ///
  /// In en, this message translates to:
  /// **'Approve rule'**
  String get chatApproveRule;

  /// No description provided for @chatAssistantDown.
  ///
  /// In en, this message translates to:
  /// **'The assistant is not available right now.'**
  String get chatAssistantDown;

  /// No description provided for @chatCardElsewhere.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your answer in the chat it came from.'**
  String get chatCardElsewhere;

  /// No description provided for @chatCardExpired.
  ///
  /// In en, this message translates to:
  /// **'This request has expired.'**
  String get chatCardExpired;

  /// No description provided for @chatCardFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be done.'**
  String get chatCardFailed;

  /// No description provided for @chatChecked.
  ///
  /// In en, this message translates to:
  /// **'Checked {what}'**
  String chatChecked(String what);

  /// No description provided for @chatCheckedMany.
  ///
  /// In en, this message translates to:
  /// **'{what}, {count, plural, =1{1 more time} other{{count} more times}}'**
  String chatCheckedMany(String what, int count);

  /// No description provided for @chatCheckedMore.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String chatCheckedMore(int count);

  /// No description provided for @chatChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking {what}'**
  String chatChecking(String what);

  /// No description provided for @chatChooseScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Choose a screenshot'**
  String get chatChooseScreenshot;

  /// No description provided for @chatConfirmQuestion.
  ///
  /// In en, this message translates to:
  /// **'Is it {amount} on {account}?'**
  String chatConfirmQuestion(String amount, String account);

  /// No description provided for @chatEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get chatEarlier;

  /// No description provided for @chatEditCancel.
  ///
  /// In en, this message translates to:
  /// **'Stop editing'**
  String get chatEditCancel;

  /// No description provided for @chatEditing.
  ///
  /// In en, this message translates to:
  /// **'Editing your message'**
  String get chatEditing;

  /// No description provided for @chatGreeting.
  ///
  /// In en, this message translates to:
  /// **'What can I help with?'**
  String get chatGreeting;

  /// No description provided for @chatHintMessage.
  ///
  /// In en, this message translates to:
  /// **'Message Botler'**
  String get chatHintMessage;

  /// No description provided for @chatHowMuch.
  ///
  /// In en, this message translates to:
  /// **'How much was it?'**
  String get chatHowMuch;

  /// No description provided for @chatInForce.
  ///
  /// In en, this message translates to:
  /// **'In force'**
  String get chatInForce;

  /// No description provided for @chatJumpLatest.
  ///
  /// In en, this message translates to:
  /// **'Jump to the latest message'**
  String get chatJumpLatest;

  /// No description provided for @chatLogged.
  ///
  /// In en, this message translates to:
  /// **'Logged {amount} on {account}'**
  String chatLogged(String amount, String account);

  /// No description provided for @chatMarkedPaid.
  ///
  /// In en, this message translates to:
  /// **'Marked paid · {amount}'**
  String chatMarkedPaid(String amount);

  /// No description provided for @chatMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get chatMenu;

  /// No description provided for @chatMicBlocked.
  ///
  /// In en, this message translates to:
  /// **'This phone cannot listen right now. Check the microphone permission.'**
  String get chatMicBlocked;

  /// No description provided for @chatMsgActions.
  ///
  /// In en, this message translates to:
  /// **'Message actions'**
  String get chatMsgActions;

  /// No description provided for @chatMsgBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch from here'**
  String get chatMsgBranch;

  /// No description provided for @chatMsgCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied.'**
  String get chatMsgCopied;

  /// No description provided for @chatMsgCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get chatMsgCopy;

  /// No description provided for @chatMsgEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit and resend'**
  String get chatMsgEdit;

  /// No description provided for @chatNeedsAmounts.
  ///
  /// In en, this message translates to:
  /// **'How much is usually {names}? I need an amount to make the split.'**
  String chatNeedsAmounts(String names);

  /// No description provided for @chatNextBill.
  ///
  /// In en, this message translates to:
  /// **'Next bill: {name}, {day}'**
  String chatNextBill(String name, String day);

  /// No description provided for @chatNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'There was no answer to this one.'**
  String get chatNoAnswer;

  /// No description provided for @chatNoBill.
  ///
  /// In en, this message translates to:
  /// **'No bill coming up'**
  String get chatNoBill;

  /// No description provided for @chatNoEvent.
  ///
  /// In en, this message translates to:
  /// **'Nothing on your calendar today'**
  String get chatNoEvent;

  /// No description provided for @chatNotDone.
  ///
  /// In en, this message translates to:
  /// **'Not done'**
  String get chatNotDone;

  /// No description provided for @chatNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get chatNotNow;

  /// No description provided for @chatNoticeFailed.
  ///
  /// In en, this message translates to:
  /// **'The assistant could not finish that. Try again.'**
  String get chatNoticeFailed;

  /// No description provided for @chatNoticeOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection. Saved on your phone. It will be sent once, when you are back online.'**
  String get chatNoticeOffline;

  /// No description provided for @chatOffline.
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get chatOffline;

  /// No description provided for @chatPendingSnack.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} entry is waiting for a connection.} other{{count} entries are waiting for a connection.}}'**
  String chatPendingSnack(int count);

  /// No description provided for @chatPendingTooltip.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting to be sent'**
  String chatPendingTooltip(int count);

  /// No description provided for @chatPhotoEmpty.
  ///
  /// In en, this message translates to:
  /// **'I could not read any text on that photo.'**
  String get chatPhotoEmpty;

  /// No description provided for @chatPhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'The photo could not be read.'**
  String get chatPhotoFailed;

  /// No description provided for @chatPhotoRead.
  ///
  /// In en, this message translates to:
  /// **'Photo read ({count, plural, =1{{count} character} other{{count} characters}})'**
  String chatPhotoRead(int count);

  /// No description provided for @chatPhotoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Photo of a receipt'**
  String get chatPhotoTooltip;

  /// No description provided for @chatPleaseCheck.
  ///
  /// In en, this message translates to:
  /// **'Please check'**
  String get chatPleaseCheck;

  /// No description provided for @chatReceiptMessage.
  ///
  /// In en, this message translates to:
  /// **'Here is a receipt.'**
  String get chatReceiptMessage;

  /// No description provided for @chatRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded {amount}'**
  String chatRecorded(String amount);

  /// No description provided for @chatRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load your earlier chat.'**
  String get chatRestoreFailed;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatSpeak.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get chatSpeak;

  /// No description provided for @chatStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get chatStop;

  /// No description provided for @chatStopListening.
  ///
  /// In en, this message translates to:
  /// **'Stop listening'**
  String get chatStopListening;

  /// No description provided for @chatStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped.'**
  String get chatStopped;

  /// No description provided for @chatSuggestDue.
  ///
  /// In en, this message translates to:
  /// **'What is due this week?'**
  String get chatSuggestDue;

  /// No description provided for @chatSuggestExpense.
  ///
  /// In en, this message translates to:
  /// **'Log an expense'**
  String get chatSuggestExpense;

  /// No description provided for @chatSuggestExpenseText.
  ///
  /// In en, this message translates to:
  /// **'I spent '**
  String get chatSuggestExpenseText;

  /// No description provided for @chatSuggestToday.
  ///
  /// In en, this message translates to:
  /// **'What is on my calendar today?'**
  String get chatSuggestToday;

  /// No description provided for @chatSummaryOpen.
  ///
  /// In en, this message translates to:
  /// **'Money summary'**
  String get chatSummaryOpen;

  /// No description provided for @chatTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get chatTakePhoto;

  /// No description provided for @chatThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get chatThinking;

  /// No description provided for @chatThoughtFor.
  ///
  /// In en, this message translates to:
  /// **'Thought for {seconds} s'**
  String chatThoughtFor(int seconds);

  /// No description provided for @chatThoughtToggle.
  ///
  /// In en, this message translates to:
  /// **'Show or hide what the assistant thought'**
  String get chatThoughtToggle;

  /// No description provided for @chatToolFailed.
  ///
  /// In en, this message translates to:
  /// **'That did not work.'**
  String get chatToolFailed;

  /// No description provided for @chatUndoGone.
  ///
  /// In en, this message translates to:
  /// **'That entry can no longer be undone.'**
  String get chatUndoGone;

  /// No description provided for @chatUndoneLine.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get chatUndoneLine;

  /// No description provided for @chatUndoneSnack.
  ///
  /// In en, this message translates to:
  /// **'Undone.'**
  String get chatUndoneSnack;

  /// No description provided for @chatWaiting.
  ///
  /// In en, this message translates to:
  /// **'Working on it'**
  String get chatWaiting;

  /// No description provided for @chatWhichAccount.
  ///
  /// In en, this message translates to:
  /// **'Which account was {amount} from?'**
  String chatWhichAccount(String amount);

  /// No description provided for @chatWithPhoto.
  ///
  /// In en, this message translates to:
  /// **'{text}\n(with a photo)'**
  String chatWithPhoto(String text);

  /// No description provided for @chatWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing'**
  String get chatWriting;

  /// No description provided for @chatYesLogIt.
  ///
  /// In en, this message translates to:
  /// **'Yes, log it'**
  String get chatYesLogIt;

  /// No description provided for @chatYourAccount.
  ///
  /// In en, this message translates to:
  /// **'your account'**
  String get chatYourAccount;

  /// No description provided for @chatsArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get chatsArchive;

  /// No description provided for @chatsArchivedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing is archived.'**
  String get chatsArchivedEmpty;

  /// No description provided for @chatsArchivedOpen.
  ///
  /// In en, this message translates to:
  /// **'Archived chats'**
  String get chatsArchivedOpen;

  /// No description provided for @chatsArchivedTitle.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get chatsArchivedTitle;

  /// No description provided for @chatsBranchMark.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get chatsBranchMark;

  /// No description provided for @chatsBranchedFrom.
  ///
  /// In en, this message translates to:
  /// **'Branched from {title}'**
  String chatsBranchedFrom(String title);

  /// No description provided for @chatsBranchedNote.
  ///
  /// In en, this message translates to:
  /// **'Changes saved before this point stay saved. Undo them in History.'**
  String get chatsBranchedNote;

  /// No description provided for @chatsBranchedOpen.
  ///
  /// In en, this message translates to:
  /// **'Open the chat this branched from'**
  String get chatsBranchedOpen;

  /// No description provided for @chatsBranchedUntitled.
  ///
  /// In en, this message translates to:
  /// **'an earlier chat'**
  String get chatsBranchedUntitled;

  /// No description provided for @chatsBusy.
  ///
  /// In en, this message translates to:
  /// **'Botler is answering. Wait for it, or stop it, to change chats.'**
  String get chatsBusy;

  /// No description provided for @chatsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your conversations will show here.'**
  String get chatsEmpty;

  /// No description provided for @chatsGroupOlder.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get chatsGroupOlder;

  /// No description provided for @chatsGroupPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get chatsGroupPinned;

  /// No description provided for @chatsGroupToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get chatsGroupToday;

  /// No description provided for @chatsGroupWeek.
  ///
  /// In en, this message translates to:
  /// **'Previous 7 days'**
  String get chatsGroupWeek;

  /// No description provided for @chatsGroupYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get chatsGroupYesterday;

  /// No description provided for @chatsMore.
  ///
  /// In en, this message translates to:
  /// **'More about this chat'**
  String get chatsMore;

  /// No description provided for @chatsNew.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get chatsNew;

  /// No description provided for @chatsNoResults.
  ///
  /// In en, this message translates to:
  /// **'No chat matches that.'**
  String get chatsNoResults;

  /// No description provided for @chatsOpen.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatsOpen;

  /// No description provided for @chatsPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get chatsPin;

  /// No description provided for @chatsPinnedMark.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get chatsPinnedMark;

  /// No description provided for @chatsRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get chatsRename;

  /// No description provided for @chatsRenameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Give it a name of 1 to 80 characters.'**
  String get chatsRenameInvalid;

  /// No description provided for @chatsRenameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get chatsRenameLabel;

  /// No description provided for @chatsRenameSave.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get chatsRenameSave;

  /// No description provided for @chatsRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Name this chat'**
  String get chatsRenameTitle;

  /// No description provided for @chatsRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get chatsRestore;

  /// No description provided for @chatsRowLabel.
  ///
  /// In en, this message translates to:
  /// **'{title}, {when}'**
  String chatsRowLabel(String title, String when);

  /// No description provided for @chatsSearchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear the search'**
  String get chatsSearchClear;

  /// No description provided for @chatsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search your chats'**
  String get chatsSearchHint;

  /// No description provided for @chatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatsTitle;

  /// No description provided for @chatsUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get chatsUnpin;

  /// No description provided for @chatsUntitled.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get chatsUntitled;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @entryCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get entryCurrencyLabel;

  /// No description provided for @entryCurrencyOther.
  ///
  /// In en, this message translates to:
  /// **'Other…'**
  String get entryCurrencyOther;

  /// No description provided for @expenseAmountError.
  ///
  /// In en, this message translates to:
  /// **'Type the amount in {code}, like 180 or 1,250.50.'**
  String expenseAmountError(String code);

  /// No description provided for @expenseFromAccount.
  ///
  /// In en, this message translates to:
  /// **'From which account?'**
  String get expenseFromAccount;

  /// No description provided for @expenseHowMuch.
  ///
  /// In en, this message translates to:
  /// **'How much? ({code})'**
  String expenseHowMuch(String code);

  /// No description provided for @expenseLogIt.
  ///
  /// In en, this message translates to:
  /// **'Log it'**
  String get expenseLogIt;

  /// No description provided for @expenseLogged.
  ///
  /// In en, this message translates to:
  /// **'Logged {amount}.'**
  String expenseLogged(String amount);

  /// No description provided for @expenseNoteHint.
  ///
  /// In en, this message translates to:
  /// **'lunch'**
  String get expenseNoteHint;

  /// No description provided for @expenseNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'What was it for? (optional)'**
  String get expenseNoteLabel;

  /// No description provided for @expenseOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection. Saved on your phone, it will be sent once.'**
  String get expenseOffline;

  /// No description provided for @expensePickAccount.
  ///
  /// In en, this message translates to:
  /// **'Pick the account it came from.'**
  String get expensePickAccount;

  /// No description provided for @expenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Add an expense'**
  String get expenseTitle;

  /// No description provided for @goalsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a goal'**
  String get goalsAdd;

  /// No description provided for @goalsAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add the goal'**
  String get goalsAddButton;

  /// No description provided for @goalsAddInvalid.
  ///
  /// In en, this message translates to:
  /// **'Give it a name, a place, and amounts as numbers.'**
  String get goalsAddInvalid;

  /// No description provided for @goalsAim.
  ///
  /// In en, this message translates to:
  /// **' · aim {amount}'**
  String goalsAim(String amount);

  /// No description provided for @goalsEachPayday.
  ///
  /// In en, this message translates to:
  /// **'{amount} each payday'**
  String goalsEachPayday(String amount);

  /// No description provided for @goalsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No goals yet. What would you like to save for?'**
  String get goalsEmpty;

  /// No description provided for @goalsNameHint.
  ///
  /// In en, this message translates to:
  /// **'Emergency fund'**
  String get goalsNameHint;

  /// No description provided for @goalsNameLabel.
  ///
  /// In en, this message translates to:
  /// **'What are you saving for?'**
  String get goalsNameLabel;

  /// No description provided for @goalsOnlyRules.
  ///
  /// In en, this message translates to:
  /// **'Only what your rules give it'**
  String get goalsOnlyRules;

  /// No description provided for @goalsPerLabel.
  ///
  /// In en, this message translates to:
  /// **'Set aside each payday ({currency}, optional)'**
  String goalsPerLabel(String currency);

  /// No description provided for @goalsTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'The amount you want to reach ({currency}, optional)'**
  String goalsTargetLabel(String currency);

  /// No description provided for @goalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Savings goals'**
  String get goalsTitle;

  /// No description provided for @goalsWhere.
  ///
  /// In en, this message translates to:
  /// **'Where does it sit?'**
  String get goalsWhere;

  /// No description provided for @goalsYear.
  ///
  /// In en, this message translates to:
  /// **'In a year (24 paydays) that is {amount}.'**
  String goalsYear(String amount);

  /// No description provided for @histEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get histEntryTitle;

  /// No description provided for @historyAccountFallback.
  ///
  /// In en, this message translates to:
  /// **'account'**
  String get historyAccountFallback;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get historyEmpty;

  /// No description provided for @historyFixThis.
  ///
  /// In en, this message translates to:
  /// **'Fix this'**
  String get historyFixThis;

  /// No description provided for @historyMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get historyMore;

  /// No description provided for @historyMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved {from} → {to}'**
  String historyMoved(String from, String to);

  /// No description provided for @historyOtherCurrencies.
  ///
  /// In en, this message translates to:
  /// **'Also spent in {currencies}. Those are not added here.'**
  String historyOtherCurrencies(String currencies);

  /// No description provided for @historySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by note, category or amount'**
  String get historySearchHint;

  /// No description provided for @historySpentThisMonth.
  ///
  /// In en, this message translates to:
  /// **'Spent this month'**
  String get historySpentThisMonth;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyUndoneSaid.
  ///
  /// In en, this message translates to:
  /// **'Undone.'**
  String get historyUndoneSaid;

  /// No description provided for @historyUndoneTag.
  ///
  /// In en, this message translates to:
  /// **'undone'**
  String get historyUndoneTag;

  /// No description provided for @historyUntracked.
  ///
  /// In en, this message translates to:
  /// **'{amount} went untracked (found when you counted an account).'**
  String historyUntracked(String amount);

  /// No description provided for @lockReason.
  ///
  /// In en, this message translates to:
  /// **'Open Botler'**
  String get lockReason;

  /// No description provided for @lockTitle.
  ///
  /// In en, this message translates to:
  /// **'Botler is locked'**
  String get lockTitle;

  /// No description provided for @lockUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get lockUnlock;

  /// No description provided for @memoryAboutLabel.
  ///
  /// In en, this message translates to:
  /// **'A few lines about you'**
  String get memoryAboutLabel;

  /// No description provided for @memoryBefore.
  ///
  /// In en, this message translates to:
  /// **'Before: {text}'**
  String memoryBefore(String text);

  /// No description provided for @memoryChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get memoryChange;

  /// No description provided for @memoryChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change this memory'**
  String get memoryChangeTitle;

  /// No description provided for @memoryCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied everything to the clipboard.'**
  String get memoryCopied;

  /// No description provided for @memoryCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy everything (memory and money) as text'**
  String get memoryCopyAll;

  /// No description provided for @memoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet. Botler learns as you talk, or tell it: “remember that…”.'**
  String get memoryEmpty;

  /// No description provided for @memoryForget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get memoryForget;

  /// No description provided for @memoryForgetBody.
  ///
  /// In en, this message translates to:
  /// **'“{text}” will be deleted and will not come back.'**
  String memoryForgetBody(String text);

  /// No description provided for @memoryForgetTitle.
  ///
  /// In en, this message translates to:
  /// **'Forget this?'**
  String get memoryForgetTitle;

  /// No description provided for @memoryForgetYes.
  ///
  /// In en, this message translates to:
  /// **'Forget it'**
  String get memoryForgetYes;

  /// No description provided for @memoryForgotten.
  ///
  /// In en, this message translates to:
  /// **'Forgotten.'**
  String get memoryForgotten;

  /// No description provided for @memoryInSentence.
  ///
  /// In en, this message translates to:
  /// **'In a sentence'**
  String get memoryInSentence;

  /// No description provided for @memoryKeepOld.
  ///
  /// In en, this message translates to:
  /// **'Keep the old one'**
  String get memoryKeepOld;

  /// No description provided for @memoryLearned.
  ///
  /// In en, this message translates to:
  /// **'Learned from chat'**
  String get memoryLearned;

  /// No description provided for @memoryMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get memoryMore;

  /// No description provided for @memoryNotSure.
  ///
  /// In en, this message translates to:
  /// **'Botler is not sure'**
  String get memoryNotSure;

  /// No description provided for @memoryNow.
  ///
  /// In en, this message translates to:
  /// **'Now: {text}'**
  String memoryNow(String text);

  /// No description provided for @memoryPeopleHint.
  ///
  /// In en, this message translates to:
  /// **'Mama, Ate Liza'**
  String get memoryPeopleHint;

  /// No description provided for @memoryPeopleLabel.
  ///
  /// In en, this message translates to:
  /// **'Names to keep private (separate with commas)'**
  String get memoryPeopleLabel;

  /// No description provided for @memoryPeopleNote.
  ///
  /// In en, this message translates to:
  /// **'Botler hides these names from the AI that writes its replies.'**
  String get memoryPeopleNote;

  /// No description provided for @memoryPersonaHint.
  ///
  /// In en, this message translates to:
  /// **'Like a friendly older sister, short answers'**
  String get memoryPersonaHint;

  /// No description provided for @memoryPersonaLabel.
  ///
  /// In en, this message translates to:
  /// **'How should Botler talk?'**
  String get memoryPersonaLabel;

  /// No description provided for @memoryRememberTitle.
  ///
  /// In en, this message translates to:
  /// **'Remember something'**
  String get memoryRememberTitle;

  /// No description provided for @memoryRemembers.
  ///
  /// In en, this message translates to:
  /// **'What Botler remembers'**
  String get memoryRemembers;

  /// No description provided for @memorySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get memorySaved;

  /// No description provided for @memorySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search the memories'**
  String get memorySearchHint;

  /// No description provided for @memoryTalks.
  ///
  /// In en, this message translates to:
  /// **'How Botler talks to you'**
  String get memoryTalks;

  /// No description provided for @memoryTellSomething.
  ///
  /// In en, this message translates to:
  /// **'Tell Botler something to remember'**
  String get memoryTellSomething;

  /// No description provided for @memoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memoryTitle;

  /// No description provided for @memoryUseNew.
  ///
  /// In en, this message translates to:
  /// **'Use the new one'**
  String get memoryUseNew;

  /// No description provided for @memoryWhichRight.
  ///
  /// In en, this message translates to:
  /// **'Which is right?'**
  String get memoryWhichRight;

  /// No description provided for @memoryWipe.
  ///
  /// In en, this message translates to:
  /// **'Wipe'**
  String get memoryWipe;

  /// No description provided for @memoryWipeBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes all memories, summaries and your conversations with Botler. Your accounts, bills and money records stay. It cannot be undone.'**
  String get memoryWipeBody;

  /// No description provided for @memoryWipeButton.
  ///
  /// In en, this message translates to:
  /// **'Wipe what Botler remembers'**
  String get memoryWipeButton;

  /// No description provided for @memoryWipeTitle.
  ///
  /// In en, this message translates to:
  /// **'Wipe everything Botler remembers?'**
  String get memoryWipeTitle;

  /// No description provided for @memoryWipeType.
  ///
  /// In en, this message translates to:
  /// **'Type WIPE to confirm'**
  String get memoryWipeType;

  /// No description provided for @memoryWipeWord.
  ///
  /// In en, this message translates to:
  /// **'WIPE'**
  String get memoryWipeWord;

  /// No description provided for @memoryWiped.
  ///
  /// In en, this message translates to:
  /// **'Wiped.'**
  String get memoryWiped;

  /// No description provided for @memoryYouSaid.
  ///
  /// In en, this message translates to:
  /// **'You said'**
  String get memoryYouSaid;

  /// No description provided for @memoryYourData.
  ///
  /// In en, this message translates to:
  /// **'Your data'**
  String get memoryYourData;

  /// No description provided for @menuAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get menuAccounts;

  /// No description provided for @menuAccountsLine.
  ///
  /// In en, this message translates to:
  /// **'What is in each of your accounts'**
  String get menuAccountsLine;

  /// No description provided for @menuAgenda.
  ///
  /// In en, this message translates to:
  /// **'Agenda'**
  String get menuAgenda;

  /// No description provided for @menuAgendaLine.
  ///
  /// In en, this message translates to:
  /// **'Tasks, events, routines and reminders'**
  String get menuAgendaLine;

  /// No description provided for @menuBills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get menuBills;

  /// No description provided for @menuBillsLine.
  ///
  /// In en, this message translates to:
  /// **'What is due, and mark it paid'**
  String get menuBillsLine;

  /// No description provided for @menuCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get menuCalendar;

  /// No description provided for @menuCalendarLine.
  ///
  /// In en, this message translates to:
  /// **'Bills, paydays, events and routines by day'**
  String get menuCalendarLine;

  /// No description provided for @menuGoals.
  ///
  /// In en, this message translates to:
  /// **'Savings goals'**
  String get menuGoals;

  /// No description provided for @menuGoalsLine.
  ///
  /// In en, this message translates to:
  /// **'What you are saving for'**
  String get menuGoalsLine;

  /// No description provided for @menuHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get menuHistory;

  /// No description provided for @menuHistoryLine.
  ///
  /// In en, this message translates to:
  /// **'Everything you spent, and undo'**
  String get menuHistoryLine;

  /// No description provided for @menuMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get menuMemory;

  /// No description provided for @menuMemoryLine.
  ///
  /// In en, this message translates to:
  /// **'What Botler remembers, and how it talks'**
  String get menuMemoryLine;

  /// No description provided for @menuPayday.
  ///
  /// In en, this message translates to:
  /// **'Payday'**
  String get menuPayday;

  /// No description provided for @menuPaydayLine.
  ///
  /// In en, this message translates to:
  /// **'Split your pay, and the rules for it'**
  String get menuPaydayLine;

  /// No description provided for @menuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get menuSettings;

  /// No description provided for @menuSettingsLine.
  ///
  /// In en, this message translates to:
  /// **'Language, money, lock, notifications, look'**
  String get menuSettingsLine;

  /// No description provided for @menuTitle.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menuTitle;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @notifChannel.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get notifChannel;

  /// No description provided for @notifChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Bills, paydays, tasks and events'**
  String get notifChannelDescription;

  /// No description provided for @notifHiddenBody.
  ///
  /// In en, this message translates to:
  /// **'You have a reminder'**
  String get notifHiddenBody;

  /// No description provided for @outboxFailedDismiss.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get outboxFailedDismiss;

  /// No description provided for @outboxFailedLine.
  ///
  /// In en, this message translates to:
  /// **'{count} changes you made offline did not go through. Tap to see why.'**
  String outboxFailedLine(int count);

  /// No description provided for @outboxFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Changes the server refused'**
  String get outboxFailedTitle;

  /// No description provided for @paydayAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a payday'**
  String get paydayAdd;

  /// No description provided for @paydayAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add a rule'**
  String get paydayAddRule;

  /// No description provided for @paydayApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get paydayApprove;

  /// No description provided for @paydayComingUp.
  ///
  /// In en, this message translates to:
  /// **'Coming up'**
  String get paydayComingUp;

  /// No description provided for @paydayDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get paydayDecline;

  /// No description provided for @paydayDifferent.
  ///
  /// In en, this message translates to:
  /// **'Different every time'**
  String get paydayDifferent;

  /// No description provided for @paydayEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier splits'**
  String get paydayEarlier;

  /// No description provided for @paydayEmpty.
  ///
  /// In en, this message translates to:
  /// **'Tell Botler when you get paid.'**
  String get paydayEmpty;

  /// No description provided for @paydayIncomeAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'How much, usually? ({currency}, optional)'**
  String paydayIncomeAmountLabel(String currency);

  /// No description provided for @paydayIncomeDefault.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get paydayIncomeDefault;

  /// No description provided for @paydayIncomeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Give it a name, an account and the amount as a number.'**
  String get paydayIncomeInvalid;

  /// No description provided for @paydayIncomeLabel.
  ///
  /// In en, this message translates to:
  /// **'What do you call it?'**
  String get paydayIncomeLabel;

  /// No description provided for @paydayIncomeTitle.
  ///
  /// In en, this message translates to:
  /// **'When do you get paid?'**
  String get paydayIncomeTitle;

  /// No description provided for @paydayLandsIn.
  ///
  /// In en, this message translates to:
  /// **'It lands in'**
  String get paydayLandsIn;

  /// No description provided for @paydayMakeSplit.
  ///
  /// In en, this message translates to:
  /// **'Make the split'**
  String get paydayMakeSplit;

  /// No description provided for @paydayNeedsAmounts.
  ///
  /// In en, this message translates to:
  /// **'How much is {names} usually? Add the amount to the bill first.'**
  String paydayNeedsAmounts(String names);

  /// No description provided for @paydayNoEarlier.
  ///
  /// In en, this message translates to:
  /// **'No earlier splits yet.'**
  String get paydayNoEarlier;

  /// No description provided for @paydayNoneAhead.
  ///
  /// In en, this message translates to:
  /// **'No payday ahead yet.'**
  String get paydayNoneAhead;

  /// No description provided for @paydayPayInvalid.
  ///
  /// In en, this message translates to:
  /// **'Type the pay in {currency}.'**
  String paydayPayInvalid(String currency);

  /// No description provided for @paydayPayLabel.
  ///
  /// In en, this message translates to:
  /// **'How much is the pay this time? (leave empty for the usual)'**
  String get paydayPayLabel;

  /// No description provided for @paydayPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan the split'**
  String get paydayPlan;

  /// No description provided for @paydayPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan {label} on {date}'**
  String paydayPlanTitle(String label, String date);

  /// No description provided for @paydayRuleAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add the rule'**
  String get paydayRuleAddButton;

  /// No description provided for @paydayRuleExamples.
  ///
  /// In en, this message translates to:
  /// **'Examples: “500 to GCash”, “10% of what is left to Maya”, “the rest to RCBC”.'**
  String get paydayRuleExamples;

  /// No description provided for @paydayRuleHint.
  ///
  /// In en, this message translates to:
  /// **'20% to emergency fund'**
  String get paydayRuleHint;

  /// No description provided for @paydayRuleLabel.
  ///
  /// In en, this message translates to:
  /// **'Say it in your own words'**
  String get paydayRuleLabel;

  /// No description provided for @paydayRuleTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a rule'**
  String get paydayRuleTitle;

  /// No description provided for @paydayRulesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rules yet. Say what should happen to what is left, like “20% to emergency fund”.'**
  String get paydayRulesEmpty;

  /// No description provided for @paydayRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Rules for the rest'**
  String get paydayRulesTitle;

  /// No description provided for @paydayStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get paydayStop;

  /// No description provided for @paydayTitle.
  ///
  /// In en, this message translates to:
  /// **'Payday'**
  String get paydayTitle;

  /// No description provided for @paydayUsually.
  ///
  /// In en, this message translates to:
  /// **'Usually {amount}'**
  String paydayUsually(String amount);

  /// No description provided for @paydayWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your yes'**
  String get paydayWaiting;

  /// No description provided for @paydayYours.
  ///
  /// In en, this message translates to:
  /// **'Your paydays'**
  String get paydayYours;

  /// No description provided for @purposeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get purposeCustom;

  /// No description provided for @purposeCustomHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. School fund'**
  String get purposeCustomHint;

  /// No description provided for @purposeCustomLabel.
  ///
  /// In en, this message translates to:
  /// **'Your own label'**
  String get purposeCustomLabel;

  /// No description provided for @purposeEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Label for {name}'**
  String purposeEditTitle(String name);

  /// No description provided for @purposeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use up to 24 characters and no long numbers.'**
  String get purposeInvalid;

  /// No description provided for @purposeNone.
  ///
  /// In en, this message translates to:
  /// **'No label'**
  String get purposeNone;

  /// No description provided for @purposeSaved.
  ///
  /// In en, this message translates to:
  /// **'Label saved.'**
  String get purposeSaved;

  /// No description provided for @purposeSemantic.
  ///
  /// In en, this message translates to:
  /// **'Purpose: {purpose}'**
  String purposeSemantic(String purpose);

  /// No description provided for @purposeTitle.
  ///
  /// In en, this message translates to:
  /// **'What is this account for?'**
  String get purposeTitle;

  /// No description provided for @remBlockedExact.
  ///
  /// In en, this message translates to:
  /// **'Botler may not set exact alarms, so reminders can come late.'**
  String get remBlockedExact;

  /// No description provided for @remBlockedFailed.
  ///
  /// In en, this message translates to:
  /// **'The last try to set your reminders failed. It will try again.'**
  String get remBlockedFailed;

  /// No description provided for @remBlockedNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off for Botler, so reminders cannot show.'**
  String get remBlockedNotifications;

  /// No description provided for @remFix.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get remFix;

  /// No description provided for @resetBack.
  ///
  /// In en, this message translates to:
  /// **'Choose another part'**
  String get resetBack;

  /// No description provided for @resetBiometric.
  ///
  /// In en, this message translates to:
  /// **'Confirm with your fingerprint or screen lock first.'**
  String get resetBiometric;

  /// No description provided for @resetButton.
  ///
  /// In en, this message translates to:
  /// **'Erase now'**
  String get resetButton;

  /// No description provided for @resetChoose.
  ///
  /// In en, this message translates to:
  /// **'What do you want to erase?'**
  String get resetChoose;

  /// No description provided for @resetDone.
  ///
  /// In en, this message translates to:
  /// **'Done. {total} rows erased.'**
  String resetDone(int total);

  /// No description provided for @resetExpired.
  ///
  /// In en, this message translates to:
  /// **'The confirmation ran out. Choose the part again.'**
  String get resetExpired;

  /// No description provided for @resetExportFirst.
  ///
  /// In en, this message translates to:
  /// **'Copy the history first'**
  String get resetExportFirst;

  /// No description provided for @resetExported.
  ///
  /// In en, this message translates to:
  /// **'History copied. Paste it somewhere safe.'**
  String get resetExported;

  /// No description provided for @resetKeeps.
  ///
  /// In en, this message translates to:
  /// **'Kept: {what}.'**
  String resetKeeps(String what);

  /// No description provided for @resetLine.
  ///
  /// In en, this message translates to:
  /// **'Erase some or all of what Botler holds about you. Your sign-in, settings and phones stay.'**
  String get resetLine;

  /// No description provided for @resetNothing.
  ///
  /// In en, this message translates to:
  /// **'There is nothing to erase in this part.'**
  String get resetNothing;

  /// No description provided for @resetOnlineOnly.
  ///
  /// In en, this message translates to:
  /// **'Resetting needs a connection.'**
  String get resetOnlineOnly;

  /// No description provided for @resetScopeAudit.
  ///
  /// In en, this message translates to:
  /// **'Audit history'**
  String get resetScopeAudit;

  /// No description provided for @resetScopeAuditLine.
  ///
  /// In en, this message translates to:
  /// **'The record of who changed what. A single note of the reset stays.'**
  String get resetScopeAuditLine;

  /// No description provided for @resetScopeEverything.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get resetScopeEverything;

  /// No description provided for @resetScopeEverythingLine.
  ///
  /// In en, this message translates to:
  /// **'All of the above'**
  String get resetScopeEverythingLine;

  /// No description provided for @resetScopeMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory and chat'**
  String get resetScopeMemory;

  /// No description provided for @resetScopeMemoryLine.
  ///
  /// In en, this message translates to:
  /// **'What Botler remembers and your conversations'**
  String get resetScopeMemoryLine;

  /// No description provided for @resetScopeMoney.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get resetScopeMoney;

  /// No description provided for @resetScopeMoneyLine.
  ///
  /// In en, this message translates to:
  /// **'Accounts, transactions, bills, goals, rules, paydays and splits'**
  String get resetScopeMoneyLine;

  /// No description provided for @resetScopeSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get resetScopeSchedule;

  /// No description provided for @resetScopeScheduleLine.
  ///
  /// In en, this message translates to:
  /// **'Tasks, events, routines and reminders'**
  String get resetScopeScheduleLine;

  /// No description provided for @resetSection.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get resetSection;

  /// No description provided for @resetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset data'**
  String get resetTitle;

  /// No description provided for @resetTypeWord.
  ///
  /// In en, this message translates to:
  /// **'Type {word} to continue'**
  String resetTypeWord(String word);

  /// No description provided for @resetWillErase.
  ///
  /// In en, this message translates to:
  /// **'This will erase {total} rows:'**
  String resetWillErase(int total);

  /// No description provided for @resetWrongWord.
  ///
  /// In en, this message translates to:
  /// **'Type the word exactly as shown.'**
  String get resetWrongWord;

  /// No description provided for @resetZeroReason.
  ///
  /// In en, this message translates to:
  /// **'Starting again from zero'**
  String get resetZeroReason;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @schedBasisCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar weeks'**
  String get schedBasisCalendar;

  /// No description provided for @schedBasisDays.
  ///
  /// In en, this message translates to:
  /// **'Days 1 to 7, 8 to 14 and so on'**
  String get schedBasisDays;

  /// No description provided for @schedDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get schedDay;

  /// No description provided for @schedEvery1.
  ///
  /// In en, this message translates to:
  /// **'Every month'**
  String get schedEvery1;

  /// No description provided for @schedEvery12.
  ///
  /// In en, this message translates to:
  /// **'Every 12 months'**
  String get schedEvery12;

  /// No description provided for @schedEvery2.
  ///
  /// In en, this message translates to:
  /// **'Every 2 months'**
  String get schedEvery2;

  /// No description provided for @schedEvery3.
  ///
  /// In en, this message translates to:
  /// **'Every 3 months'**
  String get schedEvery3;

  /// No description provided for @schedEvery6.
  ///
  /// In en, this message translates to:
  /// **'Every 6 months'**
  String get schedEvery6;

  /// No description provided for @schedEveryDays.
  ///
  /// In en, this message translates to:
  /// **'Repeat every (days)'**
  String get schedEveryDays;

  /// No description provided for @schedEveryWeeks1.
  ///
  /// In en, this message translates to:
  /// **'Every week'**
  String get schedEveryWeeks1;

  /// No description provided for @schedEveryWeeks2.
  ///
  /// In en, this message translates to:
  /// **'Every 2 weeks'**
  String get schedEveryWeeks2;

  /// No description provided for @schedEveryWeeks3.
  ///
  /// In en, this message translates to:
  /// **'Every 3 weeks'**
  String get schedEveryWeeks3;

  /// No description provided for @schedEveryWeeks4.
  ///
  /// In en, this message translates to:
  /// **'Every 4 weeks'**
  String get schedEveryWeeks4;

  /// No description provided for @schedFirstDay.
  ///
  /// In en, this message translates to:
  /// **'First day'**
  String get schedFirstDay;

  /// No description provided for @schedFromDay.
  ///
  /// In en, this message translates to:
  /// **'From day'**
  String get schedFromDay;

  /// No description provided for @schedHow.
  ///
  /// In en, this message translates to:
  /// **'How often?'**
  String get schedHow;

  /// No description provided for @schedLast.
  ///
  /// In en, this message translates to:
  /// **'last'**
  String get schedLast;

  /// No description provided for @schedLastDay.
  ///
  /// In en, this message translates to:
  /// **'Last day'**
  String get schedLastDay;

  /// No description provided for @schedMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get schedMonth;

  /// No description provided for @schedNth1.
  ///
  /// In en, this message translates to:
  /// **'1st'**
  String get schedNth1;

  /// No description provided for @schedNth2.
  ///
  /// In en, this message translates to:
  /// **'2nd'**
  String get schedNth2;

  /// No description provided for @schedNth3.
  ///
  /// In en, this message translates to:
  /// **'3rd'**
  String get schedNth3;

  /// No description provided for @schedNth4.
  ///
  /// In en, this message translates to:
  /// **'4th'**
  String get schedNth4;

  /// No description provided for @schedNth5.
  ///
  /// In en, this message translates to:
  /// **'5th'**
  String get schedNth5;

  /// No description provided for @schedNthLast.
  ///
  /// In en, this message translates to:
  /// **'Last'**
  String get schedNthLast;

  /// No description provided for @schedOnDate.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get schedOnDate;

  /// No description provided for @schedPatEveryN.
  ///
  /// In en, this message translates to:
  /// **'Every few days'**
  String get schedPatEveryN;

  /// No description provided for @schedPatMonthlyDay.
  ///
  /// In en, this message translates to:
  /// **'On a day of the month'**
  String get schedPatMonthlyDay;

  /// No description provided for @schedPatNthWeekday.
  ///
  /// In en, this message translates to:
  /// **'On a weekday of the month (like the 1st Wednesday)'**
  String get schedPatNthWeekday;

  /// No description provided for @schedPatOnce.
  ///
  /// In en, this message translates to:
  /// **'One time only'**
  String get schedPatOnce;

  /// No description provided for @schedPatRange.
  ///
  /// In en, this message translates to:
  /// **'Between two days of the month'**
  String get schedPatRange;

  /// No description provided for @schedPatSemi.
  ///
  /// In en, this message translates to:
  /// **'Twice a month'**
  String get schedPatSemi;

  /// No description provided for @schedPatWeek.
  ///
  /// In en, this message translates to:
  /// **'In a week of the month'**
  String get schedPatWeek;

  /// No description provided for @schedPatWeekly.
  ///
  /// In en, this message translates to:
  /// **'Every week'**
  String get schedPatWeekly;

  /// No description provided for @schedPatYearly.
  ///
  /// In en, this message translates to:
  /// **'Once a year'**
  String get schedPatYearly;

  /// No description provided for @schedPayWindow.
  ///
  /// In en, this message translates to:
  /// **'Pay any day {start} to {end}'**
  String schedPayWindow(String start, String end);

  /// No description provided for @schedPickWeekday.
  ///
  /// In en, this message translates to:
  /// **'One weekday of that week'**
  String get schedPickWeekday;

  /// No description provided for @schedPickWindow.
  ///
  /// In en, this message translates to:
  /// **'Any day in that week'**
  String get schedPickWindow;

  /// No description provided for @schedPreviewNone.
  ///
  /// In en, this message translates to:
  /// **'No date found in the next two years.'**
  String get schedPreviewNone;

  /// No description provided for @schedPreviewOffline.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to see the next dates.'**
  String get schedPreviewOffline;

  /// No description provided for @schedPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'The next dates'**
  String get schedPreviewTitle;

  /// No description provided for @schedPreviewWindow.
  ///
  /// In en, this message translates to:
  /// **'{start} to {end}'**
  String schedPreviewWindow(String start, String end);

  /// No description provided for @schedRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get schedRepeat;

  /// No description provided for @schedSayEveryDay.
  ///
  /// In en, this message translates to:
  /// **'Every day from {date}'**
  String schedSayEveryDay(String date);

  /// No description provided for @schedSayEveryMonths.
  ///
  /// In en, this message translates to:
  /// **', every {n} months'**
  String schedSayEveryMonths(int n);

  /// No description provided for @schedSayEveryN.
  ///
  /// In en, this message translates to:
  /// **'Every {n} days from {date}'**
  String schedSayEveryN(int n, String date);

  /// No description provided for @schedSayMonthlyDay.
  ///
  /// In en, this message translates to:
  /// **'On the {day} of the month{every}'**
  String schedSayMonthlyDay(String day, String every);

  /// No description provided for @schedSayMonthlyLast.
  ///
  /// In en, this message translates to:
  /// **'On the last day of the month{every}'**
  String schedSayMonthlyLast(String every);

  /// No description provided for @schedSayNth.
  ///
  /// In en, this message translates to:
  /// **'Every {nth} {weekday} of the month{every}'**
  String schedSayNth(String nth, String weekday, String every);

  /// No description provided for @schedSayOnce.
  ///
  /// In en, this message translates to:
  /// **'One time only, on {date}'**
  String schedSayOnce(String date);

  /// No description provided for @schedSayRange.
  ///
  /// In en, this message translates to:
  /// **'Any day between the {from} and the {to}{every}'**
  String schedSayRange(String from, String to, String every);

  /// No description provided for @schedSayRangeToLast.
  ///
  /// In en, this message translates to:
  /// **'Any day from the {from} to the end of the month{every}'**
  String schedSayRangeToLast(String from, String every);

  /// No description provided for @schedSaySemi.
  ///
  /// In en, this message translates to:
  /// **'On the {first} and the {second} of each month'**
  String schedSaySemi(String first, String second);

  /// No description provided for @schedSayWeekWeekday.
  ///
  /// In en, this message translates to:
  /// **'The {weekday} of the {nth} week of the month ({span}){every}'**
  String schedSayWeekWeekday(
    String weekday,
    String nth,
    String span,
    String every,
  );

  /// No description provided for @schedSayWeekWindow.
  ///
  /// In en, this message translates to:
  /// **'Any day in the {nth} week of the month ({span}){every}'**
  String schedSayWeekWindow(String nth, String span, String every);

  /// No description provided for @schedSayWeekly.
  ///
  /// In en, this message translates to:
  /// **'Every {days}'**
  String schedSayWeekly(String days);

  /// No description provided for @schedSayWeeklyEvery.
  ///
  /// In en, this message translates to:
  /// **'Every {n} weeks on {days}'**
  String schedSayWeeklyEvery(int n, String days);

  /// No description provided for @schedSayYearly.
  ///
  /// In en, this message translates to:
  /// **'Once a year on {month} {day}'**
  String schedSayYearly(String month, int day);

  /// No description provided for @schedSecondDay.
  ///
  /// In en, this message translates to:
  /// **'Second day'**
  String get schedSecondDay;

  /// No description provided for @schedSpanCalendar.
  ///
  /// In en, this message translates to:
  /// **'calendar week'**
  String get schedSpanCalendar;

  /// No description provided for @schedSpanDays.
  ///
  /// In en, this message translates to:
  /// **'days {from} to {to}'**
  String schedSpanDays(int from, int to);

  /// No description provided for @schedSpanLast.
  ///
  /// In en, this message translates to:
  /// **'the last 7 days'**
  String get schedSpanLast;

  /// No description provided for @schedStartingOn.
  ///
  /// In en, this message translates to:
  /// **'Starting on'**
  String get schedStartingOn;

  /// No description provided for @schedToDay.
  ///
  /// In en, this message translates to:
  /// **'To day'**
  String get schedToDay;

  /// No description provided for @schedUnknown.
  ///
  /// In en, this message translates to:
  /// **'A schedule this version of the app cannot edit'**
  String get schedUnknown;

  /// No description provided for @schedWeekday.
  ///
  /// In en, this message translates to:
  /// **'Weekday'**
  String get schedWeekday;

  /// No description provided for @schedWeekendAfter.
  ///
  /// In en, this message translates to:
  /// **'Use the working day after'**
  String get schedWeekendAfter;

  /// No description provided for @schedWeekendBefore.
  ///
  /// In en, this message translates to:
  /// **'Use the working day before'**
  String get schedWeekendBefore;

  /// No description provided for @schedWeekendLabel.
  ///
  /// In en, this message translates to:
  /// **'If it falls on a weekend'**
  String get schedWeekendLabel;

  /// No description provided for @schedWeekendNone.
  ///
  /// In en, this message translates to:
  /// **'Keep the date'**
  String get schedWeekendNone;

  /// No description provided for @schedWhichOne.
  ///
  /// In en, this message translates to:
  /// **'Which one?'**
  String get schedWhichOne;

  /// No description provided for @schedWhichWeek.
  ///
  /// In en, this message translates to:
  /// **'Which week?'**
  String get schedWhichWeek;

  /// No description provided for @setBalanceBody.
  ///
  /// In en, this message translates to:
  /// **'Botler thinks it is {amount}. Nothing is deleted: the history stays and the difference is shown as a reset.'**
  String setBalanceBody(String amount);

  /// No description provided for @setBalanceConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It was {old}. The difference of {diff} is recorded as a reset, not as spending.'**
  String setBalanceConfirmBody(String old, String diff);

  /// No description provided for @setBalanceConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Set {name} to {amount}?'**
  String setBalanceConfirmTitle(String name, String amount);

  /// No description provided for @setBalanceConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'Set it'**
  String get setBalanceConfirmYes;

  /// No description provided for @setBalanceDone.
  ///
  /// In en, this message translates to:
  /// **'Balance set. The history keeps the old one.'**
  String get setBalanceDone;

  /// No description provided for @setBalanceNew.
  ///
  /// In en, this message translates to:
  /// **'New balance ({currency})'**
  String setBalanceNew(String currency);

  /// No description provided for @setBalanceOffline.
  ///
  /// In en, this message translates to:
  /// **'A reset needs a connection, so it is not available offline.'**
  String get setBalanceOffline;

  /// No description provided for @setBalanceReason.
  ///
  /// In en, this message translates to:
  /// **'Why? (short)'**
  String get setBalanceReason;

  /// No description provided for @setBalanceReasonNeeded.
  ///
  /// In en, this message translates to:
  /// **'Say why in a few words.'**
  String get setBalanceReasonNeeded;

  /// No description provided for @setBalanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Set the balance of {name}'**
  String setBalanceTitle(String name);

  /// No description provided for @settingsAiServer.
  ///
  /// In en, this message translates to:
  /// **'AI server'**
  String get settingsAiServer;

  /// No description provided for @settingsAiServerDefault.
  ///
  /// In en, this message translates to:
  /// **'Server default'**
  String get settingsAiServerDefault;

  /// No description provided for @settingsAiServerHelp.
  ///
  /// In en, this message translates to:
  /// **'Answers can differ a little between servers.'**
  String get settingsAiServerHelp;

  /// No description provided for @settingsAiServerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{server} is not available on the server right now, so the default is used.'**
  String settingsAiServerUnavailable(String server);

  /// No description provided for @settingsAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsAppLanguage;

  /// No description provided for @settingsCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settingsCurrency;

  /// No description provided for @settingsCurrencyChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get settingsCurrencyChange;

  /// No description provided for @settingsCurrencyConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your total will be shown in {name}. Your accounts keep the currencies they hold. Your income, goals, rules and minimum balances keep the same numbers, now read in {name}: nothing in them is converted. Your bills keep their own currency.'**
  String settingsCurrencyConfirmBody(String name);

  /// No description provided for @settingsCurrencyConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Change the currency to {code}?'**
  String settingsCurrencyConfirmTitle(String code);

  /// No description provided for @settingsCurrencyExample.
  ///
  /// In en, this message translates to:
  /// **'Example {amount}'**
  String settingsCurrencyExample(String amount);

  /// No description provided for @settingsCurrencyNone.
  ///
  /// In en, this message translates to:
  /// **'No currency matches that.'**
  String get settingsCurrencyNone;

  /// No description provided for @settingsCurrencySearch.
  ///
  /// In en, this message translates to:
  /// **'Search currencies'**
  String get settingsCurrencySearch;

  /// No description provided for @settingsHideBody.
  ///
  /// In en, this message translates to:
  /// **'A reminder says only “Botler”, so nobody sees it on your lock screen.'**
  String get settingsHideBody;

  /// No description provided for @settingsHideTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide the details in notifications'**
  String get settingsHideTitle;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @settingsLanguageFil.
  ///
  /// In en, this message translates to:
  /// **'Filipino'**
  String get settingsLanguageFil;

  /// No description provided for @settingsLead1440.
  ///
  /// In en, this message translates to:
  /// **'1 day before'**
  String get settingsLead1440;

  /// No description provided for @settingsLead15.
  ///
  /// In en, this message translates to:
  /// **'15 minutes before'**
  String get settingsLead15;

  /// No description provided for @settingsLead180.
  ///
  /// In en, this message translates to:
  /// **'3 hours before'**
  String get settingsLead180;

  /// No description provided for @settingsLead60.
  ///
  /// In en, this message translates to:
  /// **'1 hour before'**
  String get settingsLead60;

  /// No description provided for @settingsLeadAtTime.
  ///
  /// In en, this message translates to:
  /// **'At the time'**
  String get settingsLeadAtTime;

  /// No description provided for @settingsLeadLabel.
  ///
  /// In en, this message translates to:
  /// **'Remind me this long before'**
  String get settingsLeadLabel;

  /// No description provided for @settingsListenEn.
  ///
  /// In en, this message translates to:
  /// **'English (Philippines)'**
  String get settingsListenEn;

  /// No description provided for @settingsListenFil.
  ///
  /// In en, this message translates to:
  /// **'Filipino and Taglish'**
  String get settingsListenFil;

  /// No description provided for @settingsListenFor.
  ///
  /// In en, this message translates to:
  /// **'Listen for'**
  String get settingsListenFor;

  /// No description provided for @settingsLockNeeds.
  ///
  /// In en, this message translates to:
  /// **'The lock needs a fingerprint or face set up on this phone.'**
  String get settingsLockNeeds;

  /// No description provided for @settingsLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for my fingerprint or face to open Botler'**
  String get settingsLockTitle;

  /// No description provided for @settingsLook.
  ///
  /// In en, this message translates to:
  /// **'Look'**
  String get settingsLook;

  /// No description provided for @settingsLookDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsLookDark;

  /// No description provided for @settingsLookLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsLookLight;

  /// No description provided for @settingsLookPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get settingsLookPhone;

  /// No description provided for @settingsMonday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get settingsMonday;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsRatesLine.
  ///
  /// In en, this message translates to:
  /// **'Fetched {date} from {source}'**
  String settingsRatesLine(String date, String source);

  /// No description provided for @settingsRatesNone.
  ///
  /// In en, this message translates to:
  /// **'No rates yet'**
  String get settingsRatesNone;

  /// No description provided for @settingsRatesTap.
  ///
  /// In en, this message translates to:
  /// **'Tap to update'**
  String get settingsRatesTap;

  /// No description provided for @settingsRatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Exchange rates'**
  String get settingsRatesTitle;

  /// No description provided for @settingsReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get settingsReminders;

  /// No description provided for @settingsReplies.
  ///
  /// In en, this message translates to:
  /// **'Assistant replies'**
  String get settingsReplies;

  /// No description provided for @settingsRepliesAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto: English, and Filipino when you write it'**
  String get settingsRepliesAuto;

  /// No description provided for @settingsRepliesEn.
  ///
  /// In en, this message translates to:
  /// **'Always English'**
  String get settingsRepliesEn;

  /// No description provided for @settingsRepliesFil.
  ///
  /// In en, this message translates to:
  /// **'Always Filipino'**
  String get settingsRepliesFil;

  /// No description provided for @settingsRepliesTaglish.
  ///
  /// In en, this message translates to:
  /// **'Taglish'**
  String get settingsRepliesTaglish;

  /// No description provided for @settingsSectionLanguageMoney.
  ///
  /// In en, this message translates to:
  /// **'Language and money'**
  String get settingsSectionLanguageMoney;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// No description provided for @settingsSignOutBody.
  ///
  /// In en, this message translates to:
  /// **'Botler stays on the server. You can sign in again any time.'**
  String get settingsSignOutBody;

  /// No description provided for @settingsSignOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get settingsSignOutTitle;

  /// No description provided for @settingsSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get settingsSignedIn;

  /// No description provided for @settingsSunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get settingsSunday;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get settingsVoice;

  /// No description provided for @settingsWeekStarts.
  ///
  /// In en, this message translates to:
  /// **'Week starts on'**
  String get settingsWeekStarts;

  /// No description provided for @signInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInButton;

  /// No description provided for @signInTagline.
  ///
  /// In en, this message translates to:
  /// **'Your money and your time, in one quiet chat.'**
  String get signInTagline;

  /// No description provided for @splitAccountFallback.
  ///
  /// In en, this message translates to:
  /// **'account'**
  String get splitAccountFallback;

  /// No description provided for @splitApproveButton.
  ///
  /// In en, this message translates to:
  /// **'Approve split'**
  String get splitApproveButton;

  /// No description provided for @splitApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get splitApproved;

  /// No description provided for @splitApprovedDone.
  ///
  /// In en, this message translates to:
  /// **'Split approved.'**
  String get splitApprovedDone;

  /// No description provided for @splitCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied {amount}'**
  String splitCopied(String amount);

  /// No description provided for @splitCopyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy the amount'**
  String get splitCopyTooltip;

  /// No description provided for @splitCutOrMove.
  ///
  /// In en, this message translates to:
  /// **'You could cut or move:'**
  String get splitCutOrMove;

  /// No description provided for @splitForeignLine.
  ///
  /// In en, this message translates to:
  /// **'{name}: {amount} counted as {converted} ({rate})'**
  String splitForeignLine(
    String name,
    String amount,
    String converted,
    String rate,
  );

  /// No description provided for @splitForeignTitle.
  ///
  /// In en, this message translates to:
  /// **'Bills in other currencies'**
  String get splitForeignTitle;

  /// No description provided for @splitMarkSent.
  ///
  /// In en, this message translates to:
  /// **'Mark sent'**
  String get splitMarkSent;

  /// No description provided for @splitMarkedSent.
  ///
  /// In en, this message translates to:
  /// **'Marked as sent.'**
  String get splitMarkedSent;

  /// No description provided for @splitPayday.
  ///
  /// In en, this message translates to:
  /// **'Payday {date}'**
  String splitPayday(String date);

  /// No description provided for @splitSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get splitSent;

  /// No description provided for @splitShort.
  ///
  /// In en, this message translates to:
  /// **'This pay is {gap} short of what you set aside.'**
  String splitShort(String gap);

  /// No description provided for @splitTransfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers to make'**
  String get splitTransfers;

  /// No description provided for @summaryMissingRates.
  ///
  /// In en, this message translates to:
  /// **'{count} currencies are not in this total: no exchange rate yet.'**
  String summaryMissingRates(int count);

  /// No description provided for @transferArrivedLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount that arrived ({currency})'**
  String transferArrivedLabel(String currency);

  /// No description provided for @transferDone.
  ///
  /// In en, this message translates to:
  /// **'Moved.'**
  String get transferDone;

  /// No description provided for @transferFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Fee ({currency}, optional)'**
  String transferFeeLabel(String currency);

  /// No description provided for @transferFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get transferFrom;

  /// No description provided for @transferInvalid.
  ///
  /// In en, this message translates to:
  /// **'Check the amounts.'**
  String get transferInvalid;

  /// No description provided for @transferMove.
  ///
  /// In en, this message translates to:
  /// **'Move money'**
  String get transferMove;

  /// No description provided for @transferQueued.
  ///
  /// In en, this message translates to:
  /// **'Saved on the phone. It is sent when you are back online.'**
  String get transferQueued;

  /// No description provided for @transferRate.
  ///
  /// In en, this message translates to:
  /// **'Your rate: {rate}'**
  String transferRate(String rate);

  /// No description provided for @transferSame.
  ///
  /// In en, this message translates to:
  /// **'Pick two different wallets.'**
  String get transferSame;

  /// No description provided for @transferSentLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount sent ({currency})'**
  String transferSentLabel(String currency);

  /// No description provided for @transferSuggest.
  ///
  /// In en, this message translates to:
  /// **'Today\'\'s rate suggests about {amount}. Change it to what really arrived.'**
  String transferSuggest(String amount);

  /// No description provided for @transferTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get transferTo;

  /// No description provided for @uiError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get uiError;

  /// No description provided for @uiLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get uiLoading;

  /// No description provided for @uiNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get uiNotNow;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @updBannerSize.
  ///
  /// In en, this message translates to:
  /// **'About {size} MB to download.'**
  String updBannerSize(String size);

  /// No description provided for @updBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Update {version} is ready'**
  String updBannerTitle(String version);

  /// No description provided for @updDismiss.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get updDismiss;

  /// No description provided for @updDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent} percent'**
  String updDownloading(int percent);

  /// No description provided for @updFailDamaged.
  ///
  /// In en, this message translates to:
  /// **'The download was damaged. Try again.'**
  String get updFailDamaged;

  /// No description provided for @updFailInstaller.
  ///
  /// In en, this message translates to:
  /// **'The update did not finish. Try again.'**
  String get updFailInstaller;

  /// No description provided for @updFailNetwork.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your internet and try again.'**
  String get updFailNetwork;

  /// No description provided for @updFailPermission.
  ///
  /// In en, this message translates to:
  /// **'Allow Botler to install apps in Android settings, then come back and try again.'**
  String get updFailPermission;

  /// No description provided for @updFailServer.
  ///
  /// In en, this message translates to:
  /// **'The server could not give the update. Try again later.'**
  String get updFailServer;

  /// No description provided for @updFailSpace.
  ///
  /// In en, this message translates to:
  /// **'Not enough space on the phone. Free some space and try again.'**
  String get updFailSpace;

  /// No description provided for @updFailWrongBuild.
  ///
  /// In en, this message translates to:
  /// **'That download is not an update for this app. Nothing was installed.'**
  String get updFailWrongBuild;

  /// No description provided for @updInstalling.
  ///
  /// In en, this message translates to:
  /// **'Android is asking to install it. Tap Install there.'**
  String get updInstalling;

  /// No description provided for @updNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updNow;

  /// No description provided for @updOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Android settings'**
  String get updOpenSettings;

  /// No description provided for @updRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Botler {version} is needed to keep things working. It is about {size} MB.'**
  String updRequiredBody(String version, String size);

  /// No description provided for @updRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Update needed'**
  String get updRequiredTitle;

  /// No description provided for @updRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get updRetry;

  /// No description provided for @updRowAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is ready. Tap to update.'**
  String updRowAvailable(String version);

  /// No description provided for @updRowChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updRowChecking;

  /// No description provided for @updRowFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not check. Tap to try again.'**
  String get updRowFailed;

  /// No description provided for @updRowLine.
  ///
  /// In en, this message translates to:
  /// **'Version {version} (build {build})'**
  String updRowLine(String version, int build);

  /// No description provided for @updRowPending.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting to sync'**
  String updRowPending(int count);

  /// No description provided for @updRowPendingNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing waiting to sync'**
  String get updRowPendingNone;

  /// No description provided for @updRowTitle.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get updRowTitle;

  /// No description provided for @updRowUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date. Tap to check again.'**
  String get updRowUpToDate;

  /// No description provided for @updUseForNow.
  ///
  /// In en, this message translates to:
  /// **'Use the app for now'**
  String get updUseForNow;

  /// No description provided for @updVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking the download…'**
  String get updVerifying;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fil'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fil':
      return AppLocalizationsFil();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
