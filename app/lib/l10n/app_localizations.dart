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

  /// No description provided for @accountsRateLine.
  ///
  /// In en, this message translates to:
  /// **'1 {from} = {rate} {main}'**
  String accountsRateLine(String from, String rate, String main);

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

  /// No description provided for @activityUndoCreatedBody.
  ///
  /// In en, this message translates to:
  /// **'Botler made \"{page}\". Undoing it deletes the page. You can put it back for 30 days.'**
  String activityUndoCreatedBody(String page);

  /// No description provided for @activityUndoCreatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete the page Botler made?'**
  String get activityUndoCreatedTitle;

  /// No description provided for @activityUndoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The earlier text is no longer kept, so this cannot be undone.'**
  String get activityUndoUnavailable;

  /// No description provided for @activityUndoneDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted. You can put it back for 30 days.'**
  String get activityUndoneDeleted;

  /// No description provided for @activityUndoneRestored.
  ///
  /// In en, this message translates to:
  /// **'Put back the earlier text.'**
  String get activityUndoneRestored;

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

  /// No description provided for @chatPhotoChars.
  ///
  /// In en, this message translates to:
  /// **'{count} characters read'**
  String chatPhotoChars(int count);

  /// No description provided for @chatPhotoClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get chatPhotoClose;

  /// No description provided for @chatPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String chatPhotoCount(int current, int total);

  /// No description provided for @chatPhotoEditing.
  ///
  /// In en, this message translates to:
  /// **'Photos wait while you edit a message.'**
  String get chatPhotoEditing;

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

  /// No description provided for @chatPhotoItem.
  ///
  /// In en, this message translates to:
  /// **'Photo {number} ({count, plural, =1{{count} character} other{{count} characters}})'**
  String chatPhotoItem(int number, int count);

  /// No description provided for @chatPhotoMissing.
  ///
  /// In en, this message translates to:
  /// **'This photo is no longer on this phone.'**
  String get chatPhotoMissing;

  /// No description provided for @chatPhotoOnlyMessage.
  ///
  /// In en, this message translates to:
  /// **'Here are the photos.'**
  String get chatPhotoOnlyMessage;

  /// No description provided for @chatPhotoOpen.
  ///
  /// In en, this message translates to:
  /// **'Open photo {number} of {total}'**
  String chatPhotoOpen(int number, int total);

  /// No description provided for @chatPhotoRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove photo {number}'**
  String chatPhotoRemove(int number);

  /// No description provided for @chatPhotoTileReading.
  ///
  /// In en, this message translates to:
  /// **'Reading photo {number}'**
  String chatPhotoTileReading(int number);

  /// No description provided for @chatPhotoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Photo of a receipt'**
  String get chatPhotoTooltip;

  /// No description provided for @chatPhotoZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get chatPhotoZoomIn;

  /// No description provided for @chatPhotoZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get chatPhotoZoomOut;

  /// No description provided for @chatPhotosLimit.
  ///
  /// In en, this message translates to:
  /// **'At most {count} photos in one message.'**
  String chatPhotosLimit(int count);

  /// No description provided for @chatPhotosReading.
  ///
  /// In en, this message translates to:
  /// **'Reading the photos…'**
  String get chatPhotosReading;

  /// No description provided for @chatPhotosSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} photo could not be read and was left out.} other{{count} photos could not be read and were left out.}}'**
  String chatPhotosSkipped(int count);

  /// No description provided for @chatPhotosTrimmed.
  ///
  /// In en, this message translates to:
  /// **'The photos hold a lot of text, so only the first part of each is sent.'**
  String get chatPhotosTrimmed;

  /// No description provided for @chatPhotosWait.
  ///
  /// In en, this message translates to:
  /// **'Wait until the photos are read.'**
  String get chatPhotosWait;

  /// No description provided for @chatPicturePreparing.
  ///
  /// In en, this message translates to:
  /// **'Getting the pictures ready…'**
  String get chatPicturePreparing;

  /// No description provided for @chatPictureSkipped.
  ///
  /// In en, this message translates to:
  /// **'A picture could not be sent, so only its text goes.'**
  String get chatPictureSkipped;

  /// No description provided for @chatPicturesNoted.
  ///
  /// In en, this message translates to:
  /// **'This answer goes by the text read from the picture, not the picture itself.'**
  String get chatPicturesNoted;

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

  /// No description provided for @chatWithPhotos.
  ///
  /// In en, this message translates to:
  /// **'{text}\n({count, plural, =1{{count} photo attached} other{{count} photos attached}})'**
  String chatWithPhotos(String text, int count);

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

  /// No description provided for @drawerAccountShort.
  ///
  /// In en, this message translates to:
  /// **'Short by {amount}'**
  String drawerAccountShort(String amount);

  /// No description provided for @drawerAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get drawerAccounts;

  /// No description provided for @drawerAccountsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet.'**
  String get drawerAccountsEmpty;

  /// No description provided for @drawerAccountsError.
  ///
  /// In en, this message translates to:
  /// **'Accounts could not be loaded.'**
  String get drawerAccountsError;

  /// No description provided for @drawerAccountsOpen.
  ///
  /// In en, this message translates to:
  /// **'Open all accounts'**
  String get drawerAccountsOpen;

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

  /// No description provided for @fixQueued.
  ///
  /// In en, this message translates to:
  /// **'The new entry is saved on this phone and goes out when you are online. The old entry stays until you undo it.'**
  String get fixQueued;

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

  /// No description provided for @goalsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete for good'**
  String get goalsDelete;

  /// No description provided for @goalsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'“{name}” and any payday rules that point at it will be deleted for good. The money you saved for it stays where it is.'**
  String goalsDeleteBody(String name);

  /// No description provided for @goalsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this goal?'**
  String get goalsDeleteTitle;

  /// No description provided for @goalsDeleteYes.
  ///
  /// In en, this message translates to:
  /// **'Delete it'**
  String get goalsDeleteYes;

  /// No description provided for @goalsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted.'**
  String get goalsDeleted;

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

  /// No description provided for @goalsMenu.
  ///
  /// In en, this message translates to:
  /// **'More about this goal'**
  String get goalsMenu;

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
  /// **'In a year ({count} paydays) that is {amount}.'**
  String goalsYear(int count, String amount);

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

  /// No description provided for @libraryActionsFor.
  ///
  /// In en, this message translates to:
  /// **'More for {title}'**
  String libraryActionsFor(String title);

  /// No description provided for @libraryActivity.
  ///
  /// In en, this message translates to:
  /// **'Botler\'s recent changes'**
  String get libraryActivity;

  /// No description provided for @libraryActivityAll.
  ///
  /// In en, this message translates to:
  /// **'Show all {count}'**
  String libraryActivityAll(int count);

  /// No description provided for @libraryActivityFewer.
  ///
  /// In en, this message translates to:
  /// **'Show fewer'**
  String get libraryActivityFewer;

  /// No description provided for @libraryActivityLine.
  ///
  /// In en, this message translates to:
  /// **'Botler changed {page} in {notebook}'**
  String libraryActivityLine(String page, String notebook);

  /// No description provided for @libraryAgoDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String libraryAgoDays(int count);

  /// No description provided for @libraryAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String libraryAgoHours(int count);

  /// No description provided for @libraryAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String libraryAgoMinutes(int count);

  /// No description provided for @libraryAgoNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get libraryAgoNow;

  /// No description provided for @libraryAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask Botler to file something'**
  String get libraryAsk;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Botler will fill this as you talk.'**
  String get libraryEmpty;

  /// No description provided for @libraryMain.
  ///
  /// In en, this message translates to:
  /// **'Main notebook'**
  String get libraryMain;

  /// No description provided for @libraryMainLine.
  ///
  /// In en, this message translates to:
  /// **'What Botler keeps in mind about you'**
  String get libraryMainLine;

  /// No description provided for @libraryNeedsConnection.
  ///
  /// In en, this message translates to:
  /// **'This needs a connection. Try again when you are online.'**
  String get libraryNeedsConnection;

  /// No description provided for @libraryNotebooks.
  ///
  /// In en, this message translates to:
  /// **'Notebooks'**
  String get libraryNotebooks;

  /// No description provided for @libraryOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline copy'**
  String get libraryOffline;

  /// No description provided for @libraryOfflineSince.
  ///
  /// In en, this message translates to:
  /// **'Offline copy from {when}'**
  String libraryOfflineSince(String when);

  /// No description provided for @libraryOpenNotebook.
  ///
  /// In en, this message translates to:
  /// **'Open notebook {title}'**
  String libraryOpenNotebook(String title);

  /// No description provided for @libraryOpenPage.
  ///
  /// In en, this message translates to:
  /// **'Open page {title}'**
  String libraryOpenPage(String title);

  /// No description provided for @libraryPageCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String libraryPageCount(int count);

  /// No description provided for @libraryPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get libraryPinned;

  /// No description provided for @libraryPinnedRecent.
  ///
  /// In en, this message translates to:
  /// **'Pinned and recent'**
  String get libraryPinnedRecent;

  /// No description provided for @libraryQueued.
  ///
  /// In en, this message translates to:
  /// **'No connection. The change is kept on your phone and will be sent once.'**
  String get libraryQueued;

  /// No description provided for @librarySearchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get librarySearchClear;

  /// No description provided for @librarySearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search did not work. Try again.'**
  String get librarySearchFailed;

  /// No description provided for @librarySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search your notebooks'**
  String get librarySearchHint;

  /// No description provided for @librarySearchMore.
  ///
  /// In en, this message translates to:
  /// **'There are more matches. Add a word to narrow it down.'**
  String get librarySearchMore;

  /// No description provided for @librarySearchNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing found.'**
  String get librarySearchNone;

  /// No description provided for @librarySearchOffline.
  ///
  /// In en, this message translates to:
  /// **'Search needs a connection. Your pages can still be read offline.'**
  String get librarySearchOffline;

  /// No description provided for @librarySearchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Type at least two letters, then press search.'**
  String get librarySearchPrompt;

  /// No description provided for @librarySearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get librarySearchTitle;

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Notebooks'**
  String get libraryTitle;

  /// No description provided for @libraryUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get libraryUndo;

  /// No description provided for @libraryUndoFor.
  ///
  /// In en, this message translates to:
  /// **'Undo Botler\'s change to {page}'**
  String libraryUndoFor(String page);

  /// No description provided for @libraryUpdateServer.
  ///
  /// In en, this message translates to:
  /// **'The server is older than this app and cannot show pages yet. Update the server.'**
  String get libraryUpdateServer;

  /// No description provided for @libraryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Botler updated'**
  String get libraryUpdated;

  /// No description provided for @lockContinueWithout.
  ///
  /// In en, this message translates to:
  /// **'Continue without a lock'**
  String get lockContinueWithout;

  /// No description provided for @lockNoScreenLock.
  ///
  /// In en, this message translates to:
  /// **'This phone has no screen lock set up, so Botler cannot ask for a fingerprint, face or PIN.'**
  String get lockNoScreenLock;

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

  /// No description provided for @markChangePicture.
  ///
  /// In en, this message translates to:
  /// **'Choose another picture'**
  String get markChangePicture;

  /// No description provided for @markChoosePicture.
  ///
  /// In en, this message translates to:
  /// **'Choose a picture'**
  String get markChoosePicture;

  /// No description provided for @markEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Icon for {name}'**
  String markEditTitle(String name);

  /// No description provided for @markIconBaby.
  ///
  /// In en, this message translates to:
  /// **'Baby'**
  String get markIconBaby;

  /// No description provided for @markIconBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get markIconBank;

  /// No description provided for @markIconBolt.
  ///
  /// In en, this message translates to:
  /// **'Electricity'**
  String get markIconBolt;

  /// No description provided for @markIconBus.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get markIconBus;

  /// No description provided for @markIconCar.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get markIconCar;

  /// No description provided for @markIconCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get markIconCard;

  /// No description provided for @markIconCart.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get markIconCart;

  /// No description provided for @markIconCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get markIconCash;

  /// No description provided for @markIconCoffee.
  ///
  /// In en, this message translates to:
  /// **'Coffee'**
  String get markIconCoffee;

  /// No description provided for @markIconCrypto.
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get markIconCrypto;

  /// No description provided for @markIconFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get markIconFamily;

  /// No description provided for @markIconFlag.
  ///
  /// In en, this message translates to:
  /// **'Flag'**
  String get markIconFlag;

  /// No description provided for @markIconFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get markIconFood;

  /// No description provided for @markIconFuel.
  ///
  /// In en, this message translates to:
  /// **'Fuel'**
  String get markIconFuel;

  /// No description provided for @markIconGame.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get markIconGame;

  /// No description provided for @markIconGift.
  ///
  /// In en, this message translates to:
  /// **'Gift'**
  String get markIconGift;

  /// No description provided for @markIconGym.
  ///
  /// In en, this message translates to:
  /// **'Gym'**
  String get markIconGym;

  /// No description provided for @markIconHealth.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get markIconHealth;

  /// No description provided for @markIconHeart.
  ///
  /// In en, this message translates to:
  /// **'Heart'**
  String get markIconHeart;

  /// No description provided for @markIconHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get markIconHome;

  /// No description provided for @markIconInsurance.
  ///
  /// In en, this message translates to:
  /// **'Insurance'**
  String get markIconInsurance;

  /// No description provided for @markIconInvest.
  ///
  /// In en, this message translates to:
  /// **'Investments'**
  String get markIconInvest;

  /// No description provided for @markIconLoan.
  ///
  /// In en, this message translates to:
  /// **'Loan'**
  String get markIconLoan;

  /// No description provided for @markIconPet.
  ///
  /// In en, this message translates to:
  /// **'Pet'**
  String get markIconPet;

  /// No description provided for @markIconPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get markIconPhone;

  /// No description provided for @markIconPiggy.
  ///
  /// In en, this message translates to:
  /// **'Piggy bank'**
  String get markIconPiggy;

  /// No description provided for @markIconRent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get markIconRent;

  /// No description provided for @markIconSavings.
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get markIconSavings;

  /// No description provided for @markIconSchool.
  ///
  /// In en, this message translates to:
  /// **'School'**
  String get markIconSchool;

  /// No description provided for @markIconSemantic.
  ///
  /// In en, this message translates to:
  /// **'Icon: {name}'**
  String markIconSemantic(String name);

  /// No description provided for @markIconShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get markIconShopping;

  /// No description provided for @markIconStar.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get markIconStar;

  /// No description provided for @markIconSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get markIconSubscription;

  /// No description provided for @markIconTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get markIconTax;

  /// No description provided for @markIconTools.
  ///
  /// In en, this message translates to:
  /// **'Repairs'**
  String get markIconTools;

  /// No description provided for @markIconTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get markIconTravel;

  /// No description provided for @markIconTv.
  ///
  /// In en, this message translates to:
  /// **'TV'**
  String get markIconTv;

  /// No description provided for @markIconWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get markIconWallet;

  /// No description provided for @markIconWater.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get markIconWater;

  /// No description provided for @markIconWifi.
  ///
  /// In en, this message translates to:
  /// **'Internet'**
  String get markIconWifi;

  /// No description provided for @markIconWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get markIconWork;

  /// No description provided for @markMenu.
  ///
  /// In en, this message translates to:
  /// **'Change icon or picture'**
  String get markMenu;

  /// No description provided for @markNone.
  ///
  /// In en, this message translates to:
  /// **'No icon'**
  String get markNone;

  /// No description provided for @markPictureChosen.
  ///
  /// In en, this message translates to:
  /// **'Your picture'**
  String get markPictureChosen;

  /// No description provided for @markPictureFailed.
  ///
  /// In en, this message translates to:
  /// **'That picture could not be used. Try another one.'**
  String get markPictureFailed;

  /// No description provided for @markPictureNote.
  ///
  /// In en, this message translates to:
  /// **'A picture you pick is for you only. Botler\'s assistant never sees it.'**
  String get markPictureNote;

  /// No description provided for @markRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove icon or picture'**
  String get markRemove;

  /// No description provided for @markSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get markSaved;

  /// No description provided for @markSemantic.
  ///
  /// In en, this message translates to:
  /// **'Icon of {name}'**
  String markSemantic(String name);

  /// No description provided for @markTitle.
  ///
  /// In en, this message translates to:
  /// **'Icon or picture'**
  String get markTitle;

  /// No description provided for @mdBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get mdBold;

  /// No description provided for @mdCheckbox.
  ///
  /// In en, this message translates to:
  /// **'Checkbox'**
  String get mdCheckbox;

  /// No description provided for @mdHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get mdHeading;

  /// No description provided for @mdLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get mdLink;

  /// No description provided for @mdList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get mdList;

  /// No description provided for @mdPageLink.
  ///
  /// In en, this message translates to:
  /// **'Link to a page'**
  String get mdPageLink;

  /// No description provided for @memoryCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied everything to the clipboard.'**
  String get memoryCopied;

  /// No description provided for @memoryCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy everything (notebook and money) as text'**
  String get memoryCopyAll;

  /// No description provided for @memoryMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get memoryMore;

  /// No description provided for @memoryPeopleHint.
  ///
  /// In en, this message translates to:
  /// **'Mama, Ate Liza'**
  String get memoryPeopleHint;

  /// No description provided for @memoryPeopleNote.
  ///
  /// In en, this message translates to:
  /// **'Botler hides these names from the AI that writes its replies.'**
  String get memoryPeopleNote;

  /// No description provided for @memorySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get memorySaved;

  /// No description provided for @memoryWipe.
  ///
  /// In en, this message translates to:
  /// **'Wipe'**
  String get memoryWipe;

  /// No description provided for @memoryWipeBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes your notebook and its changes, and your conversations with Botler. Your private names, accounts, bills and the rest of your money stay.'**
  String get memoryWipeBody;

  /// No description provided for @memoryWipeButton.
  ///
  /// In en, this message translates to:
  /// **'Wipe the notebook and conversations'**
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

  /// No description provided for @menuNotebook.
  ///
  /// In en, this message translates to:
  /// **'Notebook'**
  String get menuNotebook;

  /// No description provided for @menuNotebookLine.
  ///
  /// In en, this message translates to:
  /// **'What Botler keeps in mind about you'**
  String get menuNotebookLine;

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

  /// No description provided for @menuSimulate.
  ///
  /// In en, this message translates to:
  /// **'Time travel'**
  String get menuSimulate;

  /// No description provided for @menuSimulateLine.
  ///
  /// In en, this message translates to:
  /// **'Your balances on any past or future day'**
  String get menuSimulateLine;

  /// No description provided for @menuTitle.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menuTitle;

  /// No description provided for @netGross.
  ///
  /// In en, this message translates to:
  /// **'Balance {amount}'**
  String netGross(String amount);

  /// No description provided for @netHeldBill.
  ///
  /// In en, this message translates to:
  /// **'{label}, due {date}'**
  String netHeldBill(String label, String date);

  /// No description provided for @netHeldGoal.
  ///
  /// In en, this message translates to:
  /// **'Kept for the goal: {label}'**
  String netHeldGoal(String label);

  /// No description provided for @netHeldNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing is held: all of it is net.'**
  String get netHeldNothing;

  /// No description provided for @netHeldRule.
  ///
  /// In en, this message translates to:
  /// **'{label}, saved for the bill due {date}'**
  String netHeldRule(String label, String date);

  /// No description provided for @netHeldTitle.
  ///
  /// In en, this message translates to:
  /// **'Held in this wallet'**
  String get netHeldTitle;

  /// No description provided for @netNetNow.
  ///
  /// In en, this message translates to:
  /// **'Net now'**
  String get netNetNow;

  /// No description provided for @netShortfall.
  ///
  /// In en, this message translates to:
  /// **'Short by {amount} for bills due before payday'**
  String netShortfall(String amount);

  /// No description provided for @netShowGross.
  ///
  /// In en, this message translates to:
  /// **'Show the balance as counted'**
  String get netShowGross;

  /// No description provided for @netShowNet.
  ///
  /// In en, this message translates to:
  /// **'Show net balance'**
  String get netShowNet;

  /// No description provided for @netTakenBy.
  ///
  /// In en, this message translates to:
  /// **'Taken from this by'**
  String get netTakenBy;

  /// No description provided for @netTakenMore.
  ///
  /// In en, this message translates to:
  /// **'+{count} more, open the account to see all'**
  String netTakenMore(int count);

  /// No description provided for @netTotalTitle.
  ///
  /// In en, this message translates to:
  /// **'Net, after bills and goals'**
  String get netTotalTitle;

  /// No description provided for @netUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The net balance could not be worked out just now. Balances are shown as counted.'**
  String get netUnavailable;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @notebookByBotler.
  ///
  /// In en, this message translates to:
  /// **'Botler'**
  String get notebookByBotler;

  /// No description provided for @notebookBySeed.
  ///
  /// In en, this message translates to:
  /// **'Tidy-up'**
  String get notebookBySeed;

  /// No description provided for @notebookByYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get notebookByYou;

  /// No description provided for @notebookChanges.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get notebookChanges;

  /// No description provided for @notebookChangesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No changes yet.'**
  String get notebookChangesEmpty;

  /// No description provided for @notebookChars.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String notebookChars(String count);

  /// No description provided for @notebookConflictBody.
  ///
  /// In en, this message translates to:
  /// **'Botler, or another phone, changed it after you opened it. Your text is still here. Copy it, or save it over the new version: the other change stays in Changes.'**
  String get notebookConflictBody;

  /// No description provided for @notebookConflictCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy my text'**
  String get notebookConflictCopy;

  /// No description provided for @notebookConflictSave.
  ///
  /// In en, this message translates to:
  /// **'Save mine'**
  String get notebookConflictSave;

  /// No description provided for @notebookConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'The notebook changed'**
  String get notebookConflictTitle;

  /// No description provided for @notebookCopiedText.
  ///
  /// In en, this message translates to:
  /// **'Copied your text.'**
  String get notebookCopiedText;

  /// No description provided for @notebookCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} characters'**
  String notebookCount(String count, String max);

  /// No description provided for @notebookCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get notebookCreate;

  /// No description provided for @notebookDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete notebook'**
  String get notebookDelete;

  /// No description provided for @notebookDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'It is hidden and Botler stops using it. You can put it back from Deleted notebooks for 30 days.'**
  String get notebookDeleteBody;

  /// No description provided for @notebookDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this notebook?'**
  String get notebookDeleteTitle;

  /// No description provided for @notebookDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted notebooks'**
  String get notebookDeleted;

  /// No description provided for @notebookDeletedDone.
  ///
  /// In en, this message translates to:
  /// **'Deleted.'**
  String get notebookDeletedDone;

  /// No description provided for @notebookDeletedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No deleted notebooks.'**
  String get notebookDeletedEmpty;

  /// No description provided for @notebookDescribe.
  ///
  /// In en, this message translates to:
  /// **'Name and summary'**
  String get notebookDescribe;

  /// No description provided for @notebookDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'The changes you typed will be lost.'**
  String get notebookDiscardBody;

  /// No description provided for @notebookDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave without saving?'**
  String get notebookDiscardTitle;

  /// No description provided for @notebookDiscardYes.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get notebookDiscardYes;

  /// No description provided for @notebookEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get notebookEdit;

  /// No description provided for @notebookEditHint.
  ///
  /// In en, this message translates to:
  /// **'Write what Botler should keep in mind about you'**
  String get notebookEditHint;

  /// No description provided for @notebookEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit your notebook'**
  String get notebookEditTitle;

  /// No description provided for @notebookEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet. Tell Botler something to remember, or tap Edit.'**
  String get notebookEmpty;

  /// No description provided for @notebookExport.
  ///
  /// In en, this message translates to:
  /// **'Copy as Markdown'**
  String get notebookExport;

  /// No description provided for @notebookExportBig.
  ///
  /// In en, this message translates to:
  /// **'This notebook is about {size} MB of text. Copying it may be slow.'**
  String notebookExportBig(String size);

  /// No description provided for @notebookExportClipFail.
  ///
  /// In en, this message translates to:
  /// **'Could not copy to the clipboard. Try again.'**
  String get notebookExportClipFail;

  /// No description provided for @notebookExported.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} pages as Markdown.'**
  String notebookExported(int count);

  /// No description provided for @notebookExporting.
  ///
  /// In en, this message translates to:
  /// **'Collecting the pages...'**
  String get notebookExporting;

  /// No description provided for @notebookFieldSummary.
  ///
  /// In en, this message translates to:
  /// **'What is in it?'**
  String get notebookFieldSummary;

  /// No description provided for @notebookFieldSummaryHint.
  ///
  /// In en, this message translates to:
  /// **'One line, so Botler knows when to open it'**
  String get notebookFieldSummaryHint;

  /// No description provided for @notebookFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get notebookFieldTitle;

  /// No description provided for @notebookGoBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get notebookGoBack;

  /// No description provided for @notebookGone.
  ///
  /// In en, this message translates to:
  /// **'This notebook is gone'**
  String get notebookGone;

  /// No description provided for @notebookGoneBody.
  ///
  /// In en, this message translates to:
  /// **'It was deleted, here or on another phone.'**
  String get notebookGoneBody;

  /// No description provided for @notebookKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get notebookKeepEditing;

  /// No description provided for @notebookNameRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String notebookNameRemove(String name);

  /// No description provided for @notebookNames.
  ///
  /// In en, this message translates to:
  /// **'Private names'**
  String get notebookNames;

  /// No description provided for @notebookNamesAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a name'**
  String get notebookNamesAdd;

  /// No description provided for @notebookNamesAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get notebookNamesAddButton;

  /// No description provided for @notebookNew.
  ///
  /// In en, this message translates to:
  /// **'New notebook'**
  String get notebookNew;

  /// No description provided for @notebookNoPages.
  ///
  /// In en, this message translates to:
  /// **'No pages yet. Ask Botler to write one, or add a page yourself.'**
  String get notebookNoPages;

  /// No description provided for @notebookOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection. Your text is still here: try again when you are online.'**
  String get notebookOffline;

  /// No description provided for @notebookOpenFirst.
  ///
  /// In en, this message translates to:
  /// **'Open the first page'**
  String get notebookOpenFirst;

  /// No description provided for @notebookOthers.
  ///
  /// In en, this message translates to:
  /// **'Other notebooks'**
  String get notebookOthers;

  /// No description provided for @notebookOthersEmpty.
  ///
  /// In en, this message translates to:
  /// **'None yet. Botler keeps the essentials here and can start a notebook for a trip, a project or a list. Ask for one, or make it yourself.'**
  String get notebookOthersEmpty;

  /// No description provided for @notebookRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get notebookRestore;

  /// No description provided for @notebookRestoreBody.
  ///
  /// In en, this message translates to:
  /// **'Your notebook becomes the text below. What it says now stays in Changes, so you can undo this.'**
  String get notebookRestoreBody;

  /// No description provided for @notebookRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Put this text back?'**
  String get notebookRestoreTitle;

  /// No description provided for @notebookRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored.'**
  String get notebookRestored;

  /// No description provided for @notebookSectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get notebookSectionEmpty;

  /// No description provided for @notebookSeeding.
  ///
  /// In en, this message translates to:
  /// **'Made from what Botler remembered before. It is tidied in the background, and you can change any of it.'**
  String get notebookSeeding;

  /// No description provided for @notebookTitle.
  ///
  /// In en, this message translates to:
  /// **'Notebook'**
  String get notebookTitle;

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

  /// No description provided for @pageAddedMark.
  ///
  /// In en, this message translates to:
  /// **'Added since you last read'**
  String get pageAddedMark;

  /// No description provided for @pageBreadcrumb.
  ///
  /// In en, this message translates to:
  /// **'Page {trail}'**
  String pageBreadcrumb(String trail);

  /// No description provided for @pageChangedALot.
  ///
  /// In en, this message translates to:
  /// **'This page changed a lot since you last read it, so the new lines are not marked.'**
  String get pageChangedALot;

  /// No description provided for @pageChangesLegend.
  ///
  /// In en, this message translates to:
  /// **'Marked on the left: what was added since you last read.'**
  String get pageChangesLegend;

  /// No description provided for @pageContents.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get pageContents;

  /// No description provided for @pageContentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'This page has no headings.'**
  String get pageContentsEmpty;

  /// No description provided for @pageCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied the page.'**
  String get pageCopied;

  /// No description provided for @pageCopyText.
  ///
  /// In en, this message translates to:
  /// **'Copy the text'**
  String get pageCopyText;

  /// No description provided for @pageCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get pageCreate;

  /// No description provided for @pageDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day left} other{{count} days left}}'**
  String pageDaysLeft(int count);

  /// No description provided for @pageDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete page'**
  String get pageDelete;

  /// No description provided for @pageDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'The page and its sub-pages are hidden. You can put them back for 30 days.'**
  String get pageDeleteBody;

  /// No description provided for @pageDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this page?'**
  String get pageDeleteTitle;

  /// No description provided for @pageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted.'**
  String get pageDeleted;

  /// No description provided for @pageDeletedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No deleted pages.'**
  String get pageDeletedEmpty;

  /// No description provided for @pageDeletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleted pages'**
  String get pageDeletedTitle;

  /// No description provided for @pageEditOffline.
  ///
  /// In en, this message translates to:
  /// **'Reading an offline copy. Editing needs a connection.'**
  String get pageEditOffline;

  /// No description provided for @pageEmpty.
  ///
  /// In en, this message translates to:
  /// **'This page is empty. Tap Edit to write on it, or ask Botler.'**
  String get pageEmpty;

  /// No description provided for @pageGone.
  ///
  /// In en, this message translates to:
  /// **'This page is gone'**
  String get pageGone;

  /// No description provided for @pageGoneBody.
  ///
  /// In en, this message translates to:
  /// **'Botler, or another phone, deleted it.'**
  String get pageGoneBody;

  /// No description provided for @pageLinkMissing.
  ///
  /// In en, this message translates to:
  /// **'No page called {title}'**
  String pageLinkMissing(String title);

  /// No description provided for @pageLinkedFrom.
  ///
  /// In en, this message translates to:
  /// **'Linked from'**
  String get pageLinkedFrom;

  /// No description provided for @pageLinkedFromRow.
  ///
  /// In en, this message translates to:
  /// **'Open {page}, in {notebook}, which links here'**
  String pageLinkedFromRow(String page, String notebook);

  /// No description provided for @pageMove.
  ///
  /// In en, this message translates to:
  /// **'Move to...'**
  String get pageMove;

  /// No description provided for @pageMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get pageMoveDown;

  /// No description provided for @pageMoveHasKids.
  ///
  /// In en, this message translates to:
  /// **'This page has sub-pages, so it can only go to the top level.'**
  String get pageMoveHasKids;

  /// No description provided for @pageMoveHere.
  ///
  /// In en, this message translates to:
  /// **'where it is now'**
  String get pageMoveHere;

  /// No description provided for @pageMoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Move {title}'**
  String pageMoveTitle(String title);

  /// No description provided for @pageMoveTop.
  ///
  /// In en, this message translates to:
  /// **'Top level of the notebook'**
  String get pageMoveTop;

  /// No description provided for @pageMoveUnder.
  ///
  /// In en, this message translates to:
  /// **'Under {title}'**
  String pageMoveUnder(String title);

  /// No description provided for @pageMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get pageMoveUp;

  /// No description provided for @pageMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved.'**
  String get pageMoved;

  /// No description provided for @pageNew.
  ///
  /// In en, this message translates to:
  /// **'New page'**
  String get pageNew;

  /// No description provided for @pagePin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pagePin;

  /// No description provided for @pageRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get pageRename;

  /// No description provided for @pageRenamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed.'**
  String get pageRenamed;

  /// No description provided for @pageRestoreFor.
  ///
  /// In en, this message translates to:
  /// **'Restore {title}'**
  String pageRestoreFor(String title);

  /// No description provided for @pageRestored.
  ///
  /// In en, this message translates to:
  /// **'Put back.'**
  String get pageRestored;

  /// No description provided for @pageSubpages.
  ///
  /// In en, this message translates to:
  /// **'Sub-pages'**
  String get pageSubpages;

  /// No description provided for @pageTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi and the router'**
  String get pageTitleHint;

  /// No description provided for @pageTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Page title'**
  String get pageTitleLabel;

  /// No description provided for @pageToggleClose.
  ///
  /// In en, this message translates to:
  /// **'Hide the sub-pages of {title}'**
  String pageToggleClose(String title);

  /// No description provided for @pageToggleOpen.
  ///
  /// In en, this message translates to:
  /// **'Show the sub-pages of {title}'**
  String pageToggleOpen(String title);

  /// No description provided for @pageUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get pageUnpin;

  /// No description provided for @pageUpdatedBy.
  ///
  /// In en, this message translates to:
  /// **'Updated by {who}, {when}'**
  String pageUpdatedBy(String who, String when);

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

  /// No description provided for @paydayDeclined.
  ///
  /// In en, this message translates to:
  /// **'Rule declined.'**
  String get paydayDeclined;

  /// No description provided for @paydayDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'“{label}” will be deleted for good. Money you already recorded stays where it is.'**
  String paydayDeleteBody(String label);

  /// No description provided for @paydayDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete this payday'**
  String get paydayDeleteButton;

  /// No description provided for @paydayDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this payday?'**
  String get paydayDeleteTitle;

  /// No description provided for @paydayDeleteWithSplitsBody.
  ///
  /// In en, this message translates to:
  /// **'“{label}” has earlier splits. Delete the payday and its splits for good? Money you already recorded stays where it is.'**
  String paydayDeleteWithSplitsBody(String label);

  /// No description provided for @paydayDeleteYes.
  ///
  /// In en, this message translates to:
  /// **'Delete it'**
  String get paydayDeleteYes;

  /// No description provided for @paydayDeleted.
  ///
  /// In en, this message translates to:
  /// **'Payday deleted.'**
  String get paydayDeleted;

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

  /// No description provided for @paydayEditMenu.
  ///
  /// In en, this message translates to:
  /// **'Change or delete this payday'**
  String get paydayEditMenu;

  /// No description provided for @paydayEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Change this payday'**
  String get paydayEditTitle;

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

  /// No description provided for @paydayOff.
  ///
  /// In en, this message translates to:
  /// **'Switched off'**
  String get paydayOff;

  /// No description provided for @paydayPayEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use what you usually get'**
  String get paydayPayEmptyHint;

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

  /// No description provided for @paydayPayThisTime.
  ///
  /// In en, this message translates to:
  /// **'How much is the pay this time? ({currency})'**
  String paydayPayThisTime(String currency);

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

  /// No description provided for @paydayRuleDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'“{rule}” will be deleted for good. Splits already made keep their numbers.'**
  String paydayRuleDeleteBody(String rule);

  /// No description provided for @paydayRuleDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete the rule'**
  String get paydayRuleDeleteButton;

  /// No description provided for @paydayRuleDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this rule?'**
  String get paydayRuleDeleteTitle;

  /// No description provided for @paydayRuleDeleteYes.
  ///
  /// In en, this message translates to:
  /// **'Delete it'**
  String get paydayRuleDeleteYes;

  /// No description provided for @paydayRuleDeleted.
  ///
  /// In en, this message translates to:
  /// **'Rule deleted.'**
  String get paydayRuleDeleted;

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

  /// No description provided for @paydayRuleMenu.
  ///
  /// In en, this message translates to:
  /// **'More about this rule'**
  String get paydayRuleMenu;

  /// No description provided for @paydayRuleNameHint.
  ///
  /// In en, this message translates to:
  /// **'Emergency fund'**
  String get paydayRuleNameHint;

  /// No description provided for @paydayRuleNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get paydayRuleNameLabel;

  /// No description provided for @paydayRuleStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get paydayRuleStopped;

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

  /// No description provided for @paydaySplitReady.
  ///
  /// In en, this message translates to:
  /// **'Your split is ready below. Check it, then approve.'**
  String get paydaySplitReady;

  /// No description provided for @paydayStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get paydayStop;

  /// No description provided for @paydayStopBody.
  ///
  /// In en, this message translates to:
  /// **'It stops applying to new splits. You can delete it any time.'**
  String get paydayStopBody;

  /// No description provided for @paydayStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop this rule?'**
  String get paydayStopTitle;

  /// No description provided for @paydayStopYes.
  ///
  /// In en, this message translates to:
  /// **'Stop it'**
  String get paydayStopYes;

  /// No description provided for @paydayStopped.
  ///
  /// In en, this message translates to:
  /// **'Rule stopped.'**
  String get paydayStopped;

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

  /// No description provided for @photoNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'Your photo goes to {server} as a picture, so the assistant can see what is in it. Names and numbers in a picture are not hidden the way they are in text, and Botler\'s server does not keep it ({server} handles it under its own terms). You can change this in Settings.'**
  String photoNoticeBody(String server);

  /// No description provided for @photoNoticeNo.
  ///
  /// In en, this message translates to:
  /// **'Text only'**
  String get photoNoticeNo;

  /// No description provided for @photoNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Send the picture itself?'**
  String get photoNoticeTitle;

  /// No description provided for @photoNoticeYes.
  ///
  /// In en, this message translates to:
  /// **'Send pictures'**
  String get photoNoticeYes;

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

  /// No description provided for @ruleSavesFor.
  ///
  /// In en, this message translates to:
  /// **'Saves for {bill}'**
  String ruleSavesFor(String bill);

  /// No description provided for @ruleSavesForHelp.
  ///
  /// In en, this message translates to:
  /// **'Pick the bill this money is for. On payday the split then pays that bill from what this rule saved, instead of taking it from your pay a second time.'**
  String get ruleSavesForHelp;

  /// No description provided for @ruleSavesForNone.
  ///
  /// In en, this message translates to:
  /// **'Saves for a bill?'**
  String get ruleSavesForNone;

  /// No description provided for @ruleSavesForNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing'**
  String get ruleSavesForNothing;

  /// No description provided for @ruleSavesForSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get ruleSavesForSaved;

  /// No description provided for @ruleSavesForSemantic.
  ///
  /// In en, this message translates to:
  /// **'Choose the bill this rule saves for'**
  String get ruleSavesForSemantic;

  /// No description provided for @ruleSavesForTitle.
  ///
  /// In en, this message translates to:
  /// **'What does this rule save for?'**
  String get ruleSavesForTitle;

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

  /// No description provided for @schedFromDate.
  ///
  /// In en, this message translates to:
  /// **'from {date}'**
  String schedFromDate(String date);

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

  /// No description provided for @schedNotOnDates.
  ///
  /// In en, this message translates to:
  /// **'not on {dates}'**
  String schedNotOnDates(String dates);

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

  /// No description provided for @schedUntilDate.
  ///
  /// In en, this message translates to:
  /// **'until {date}'**
  String schedUntilDate(String date);

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

  /// No description provided for @settingsNetBody.
  ///
  /// In en, this message translates to:
  /// **'Lead with what is left after bills due before the next payday and money kept for goals. The balance you counted stays smaller beneath it.'**
  String get settingsNetBody;

  /// No description provided for @settingsNetTitle.
  ///
  /// In en, this message translates to:
  /// **'Show net balance'**
  String get settingsNetTitle;

  /// No description provided for @settingsPhotoHelpImage.
  ///
  /// In en, this message translates to:
  /// **'The assistant looks at the picture itself, so it can describe a product or read a layout. The picture goes to {server} as it is: names and numbers in it are not hidden the way they are in text. Botler\'s server does not keep it; {server} handles it under its own terms.'**
  String settingsPhotoHelpImage(String server);

  /// No description provided for @settingsPhotoHelpOther.
  ///
  /// In en, this message translates to:
  /// **'{chat} cannot look at pictures, so {server} looks at them for the messages that have one. The rest of your chat stays on {chat}. The picture goes to {server} as it is: names and numbers in it are not hidden the way they are in text. Botler\'s server does not keep it; {server} handles it under its own terms.'**
  String settingsPhotoHelpOther(String server, String chat);

  /// No description provided for @settingsPhotoHelpText.
  ///
  /// In en, this message translates to:
  /// **'The phone reads the words on the photo and only those words are sent. Names and numbers are hidden as usual.'**
  String get settingsPhotoHelpText;

  /// No description provided for @settingsPhotoImage.
  ///
  /// In en, this message translates to:
  /// **'Picture'**
  String get settingsPhotoImage;

  /// No description provided for @settingsPhotoNoVision.
  ///
  /// In en, this message translates to:
  /// **'{server} cannot look at pictures, so it only gets the text read from them, whatever you choose here.'**
  String settingsPhotoNoVision(String server);

  /// No description provided for @settingsPhotoText.
  ///
  /// In en, this message translates to:
  /// **'Text only'**
  String get settingsPhotoText;

  /// No description provided for @settingsPhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos for the assistant'**
  String get settingsPhotosTitle;

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

  /// No description provided for @signInAgainBody.
  ///
  /// In en, this message translates to:
  /// **'What you wrote offline is kept on this phone. Sign in again to send it.'**
  String get signInAgainBody;

  /// No description provided for @signInAgainButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get signInAgainButton;

  /// No description provided for @signInAgainTitle.
  ///
  /// In en, this message translates to:
  /// **'Your sign in has ended'**
  String get signInAgainTitle;

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

  /// No description provided for @signOutWaiting.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change is} other{{count} changes are}} still waiting to be sent. They stay on this phone and go out when you sign in again.'**
  String signOutWaiting(int count);

  /// No description provided for @simAbout.
  ///
  /// In en, this message translates to:
  /// **'about {amount}'**
  String simAbout(String amount);

  /// No description provided for @simAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get simAccountsTitle;

  /// No description provided for @simAhead1m.
  ///
  /// In en, this message translates to:
  /// **'1 month ahead'**
  String get simAhead1m;

  /// No description provided for @simAhead1y.
  ///
  /// In en, this message translates to:
  /// **'1 year ahead'**
  String get simAhead1y;

  /// No description provided for @simAhead5y.
  ///
  /// In en, this message translates to:
  /// **'5 years ahead'**
  String get simAhead5y;

  /// No description provided for @simAmountFor.
  ///
  /// In en, this message translates to:
  /// **'Amount for {name}'**
  String simAmountFor(String name);

  /// No description provided for @simBack1m.
  ///
  /// In en, this message translates to:
  /// **'1 month back'**
  String get simBack1m;

  /// No description provided for @simBack1y.
  ///
  /// In en, this message translates to:
  /// **'1 year back'**
  String get simBack1y;

  /// No description provided for @simBandFuture.
  ///
  /// In en, this message translates to:
  /// **'An estimate, not real money'**
  String get simBandFuture;

  /// No description provided for @simBandFutureLine.
  ///
  /// In en, this message translates to:
  /// **'Worked out from today\'s balances and your plan.'**
  String get simBandFutureLine;

  /// No description provided for @simBandMixed.
  ///
  /// In en, this message translates to:
  /// **'Real until today, an estimate after'**
  String get simBandMixed;

  /// No description provided for @simBandMixedLine.
  ///
  /// In en, this message translates to:
  /// **'Numbers after today are not real money.'**
  String get simBandMixedLine;

  /// No description provided for @simBandOffline.
  ///
  /// In en, this message translates to:
  /// **'Saved {date}, no connection.'**
  String simBandOffline(String date);

  /// No description provided for @simBandPast.
  ///
  /// In en, this message translates to:
  /// **'What really happened'**
  String get simBandPast;

  /// No description provided for @simBandPastLine.
  ///
  /// In en, this message translates to:
  /// **'Your recorded balances, beside what your plan would have done.'**
  String get simBandPastLine;

  /// No description provided for @simBelowDay.
  ///
  /// In en, this message translates to:
  /// **'{account} below zero on {date}'**
  String simBelowDay(String account, String date);

  /// No description provided for @simBills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get simBills;

  /// No description provided for @simBreakdownLine.
  ///
  /// In en, this message translates to:
  /// **'{name}, {amount}, {percent} percent of spending, tap to show only these entries'**
  String simBreakdownLine(String name, String amount, int percent);

  /// No description provided for @simBreakdownLineNoShare.
  ///
  /// In en, this message translates to:
  /// **'{name}, {amount}, tap to show only these entries'**
  String simBreakdownLineNoShare(String name, String amount);

  /// No description provided for @simChangeSelf.
  ///
  /// In en, this message translates to:
  /// **'Change something yourself'**
  String get simChangeSelf;

  /// No description provided for @simChartSemantics.
  ///
  /// In en, this message translates to:
  /// **'{period}: {amount}, {source}. Swipe up or down to move between periods.'**
  String simChartSemantics(String period, String amount, String source);

  /// No description provided for @simDefer.
  ///
  /// In en, this message translates to:
  /// **'Deferrable bills wait for the next payday'**
  String get simDefer;

  /// No description provided for @simDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get simDetails;

  /// No description provided for @simDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get simDone;

  /// No description provided for @simEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get simEarlier;

  /// No description provided for @simEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get simEdit;

  /// No description provided for @simEntriesOffline.
  ///
  /// In en, this message translates to:
  /// **'Where the money went and the entries need a connection. Only the totals are saved on this phone.'**
  String get simEntriesOffline;

  /// No description provided for @simEntriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get simEntriesTitle;

  /// No description provided for @simError.
  ///
  /// In en, this message translates to:
  /// **'Time travel could not load.'**
  String get simError;

  /// No description provided for @simEverythingElse.
  ///
  /// In en, this message translates to:
  /// **'Everything else ({count, plural, =1{1 group} other{{count} groups}})'**
  String simEverythingElse(int count);

  /// No description provided for @simFirstRecordEdge.
  ///
  /// In en, this message translates to:
  /// **'Nothing was recorded before {date}.'**
  String simFirstRecordEdge(String date);

  /// No description provided for @simGapAbove.
  ///
  /// In en, this message translates to:
  /// **'{amount} above the plan'**
  String simGapAbove(String amount);

  /// No description provided for @simGapBelow.
  ///
  /// In en, this message translates to:
  /// **'{amount} below the plan'**
  String simGapBelow(String amount);

  /// No description provided for @simGapNone.
  ///
  /// In en, this message translates to:
  /// **'Right on the plan'**
  String get simGapNone;

  /// No description provided for @simGoals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get simGoals;

  /// No description provided for @simGroupGone.
  ///
  /// In en, this message translates to:
  /// **'That group is no longer listed, so every entry is shown.'**
  String get simGroupGone;

  /// No description provided for @simGroupOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get simGroupOther;

  /// No description provided for @simHidden.
  ///
  /// In en, this message translates to:
  /// **'hidden'**
  String get simHidden;

  /// No description provided for @simIncludesEstimate.
  ///
  /// In en, this message translates to:
  /// **'Includes what is still to come (estimate).'**
  String get simIncludesEstimate;

  /// No description provided for @simInfoChart.
  ///
  /// In en, this message translates to:
  /// **'One point for each period. A solid line was recorded, a dashed line is an estimate or a replay of your plan. Tap or drag to pick a period. A ring marks a period that goes low or below zero.'**
  String get simInfoChart;

  /// No description provided for @simInfoChartTitle.
  ///
  /// In en, this message translates to:
  /// **'The chart'**
  String get simInfoChartTitle;

  /// No description provided for @simInfoGap.
  ///
  /// In en, this message translates to:
  /// **'How far the recorded balance ended above or below where your plan would have put it.'**
  String get simInfoGap;

  /// No description provided for @simInfoGapTitle.
  ///
  /// In en, this message translates to:
  /// **'The gap to the plan'**
  String get simInfoGapTitle;

  /// No description provided for @simInfoIntro.
  ///
  /// In en, this message translates to:
  /// **'Pick any day, week, month or year, up to 5 years back or ahead, to see what your accounts held or will hold. Anything after today is an estimate from today\'s balances and your plan, never real money.'**
  String get simInfoIntro;

  /// No description provided for @simInfoTags.
  ///
  /// In en, this message translates to:
  /// **'Recorded: it really happened. Plan replay: what your plan would have done in the past. Simulated: an estimate for the future. Not recorded: a payday or bill your plan expected that was never recorded. What-if: something you only pretended.'**
  String get simInfoTags;

  /// No description provided for @simInfoTagsTitle.
  ///
  /// In en, this message translates to:
  /// **'The tags'**
  String get simInfoTagsTitle;

  /// No description provided for @simInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'How Time travel works'**
  String get simInfoTitle;

  /// No description provided for @simInfoTooltip.
  ///
  /// In en, this message translates to:
  /// **'What am I looking at?'**
  String get simInfoTooltip;

  /// No description provided for @simInfoWarn.
  ///
  /// In en, this message translates to:
  /// **'An account under its minimum or below zero on a day, and a currency with no exchange rate, which is left out of the total.'**
  String get simInfoWarn;

  /// No description provided for @simInfoWarnTitle.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get simInfoWarnTitle;

  /// No description provided for @simIntro.
  ///
  /// In en, this message translates to:
  /// **'See what your accounts held on any past day, or will hold on a future one. Numbers after today are estimates. Use What if to try a change without saving anything.'**
  String get simIntro;

  /// No description provided for @simIntroGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get simIntroGotIt;

  /// No description provided for @simJump.
  ///
  /// In en, this message translates to:
  /// **'Jump further'**
  String get simJump;

  /// No description provided for @simLateDays.
  ///
  /// In en, this message translates to:
  /// **'Bills paid {count, plural, =1{1 day} other{{count} days}} late'**
  String simLateDays(int count);

  /// No description provided for @simLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get simLater;

  /// No description provided for @simLowDay.
  ///
  /// In en, this message translates to:
  /// **'{account} under its minimum on {date}'**
  String simLowDay(String account, String date);

  /// No description provided for @simMissed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 payday or bill was not recorded} other{{count} paydays or bills were not recorded}}'**
  String simMissed(int count);

  /// No description provided for @simMissingRates.
  ///
  /// In en, this message translates to:
  /// **'No exchange rate for {codes}: left out of the totals.'**
  String simMissingRates(String codes);

  /// No description provided for @simMoveTo.
  ///
  /// In en, this message translates to:
  /// **'to {account}'**
  String simMoveTo(String account);

  /// No description provided for @simNoEntries.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this period.'**
  String get simNoEntries;

  /// No description provided for @simNoPlan.
  ///
  /// In en, this message translates to:
  /// **'No paydays or bills yet, so the simulated line stays flat.'**
  String get simNoPlan;

  /// No description provided for @simNoRateShort.
  ///
  /// In en, this message translates to:
  /// **'no exchange rate yet'**
  String get simNoRateShort;

  /// No description provided for @simNoRecords.
  ///
  /// In en, this message translates to:
  /// **'No records yet for these dates.'**
  String get simNoRecords;

  /// No description provided for @simNoTotal.
  ///
  /// In en, this message translates to:
  /// **'No total'**
  String get simNoTotal;

  /// No description provided for @simNothingSpent.
  ///
  /// In en, this message translates to:
  /// **'Nothing was spent in this period.'**
  String get simNothingSpent;

  /// No description provided for @simPageFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load more.'**
  String get simPageFailed;

  /// No description provided for @simPaydays.
  ///
  /// In en, this message translates to:
  /// **'Paydays'**
  String get simPaydays;

  /// No description provided for @simPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String simPercent(int percent);

  /// No description provided for @simPeriod.
  ///
  /// In en, this message translates to:
  /// **'{from} to {to}'**
  String simPeriod(String from, String to);

  /// No description provided for @simPickDate.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get simPickDate;

  /// No description provided for @simPlanExpected.
  ///
  /// In en, this message translates to:
  /// **'Your plan expected to spend'**
  String get simPlanExpected;

  /// No description provided for @simPresetDefer.
  ///
  /// In en, this message translates to:
  /// **'Defer what can wait'**
  String get simPresetDefer;

  /// No description provided for @simPresetDeferLine.
  ///
  /// In en, this message translates to:
  /// **'Bills that can wait are paid after the next payday.'**
  String get simPresetDeferLine;

  /// No description provided for @simPresetLate.
  ///
  /// In en, this message translates to:
  /// **'Pay bills a week late'**
  String get simPresetLate;

  /// No description provided for @simPresetLateLine.
  ///
  /// In en, this message translates to:
  /// **'Every bill is paid 7 days after its due date.'**
  String get simPresetLateLine;

  /// No description provided for @simPresetNoRules.
  ///
  /// In en, this message translates to:
  /// **'No payday rules'**
  String get simPresetNoRules;

  /// No description provided for @simPresetNoRulesLine.
  ///
  /// In en, this message translates to:
  /// **'Switch off every payday rule, so nothing is set aside.'**
  String get simPresetNoRulesLine;

  /// No description provided for @simPresetPayDown.
  ///
  /// In en, this message translates to:
  /// **'Pay 10% lower'**
  String get simPresetPayDown;

  /// No description provided for @simPresetPayDownLine.
  ///
  /// In en, this message translates to:
  /// **'Every pay with a known amount is 10% lower.'**
  String get simPresetPayDownLine;

  /// No description provided for @simPresetPayUp.
  ///
  /// In en, this message translates to:
  /// **'Pay 10% higher'**
  String get simPresetPayUp;

  /// No description provided for @simPresetPayUpLine.
  ///
  /// In en, this message translates to:
  /// **'Every pay with a known amount is 10% higher.'**
  String get simPresetPayUpLine;

  /// No description provided for @simPresetSkipNext.
  ///
  /// In en, this message translates to:
  /// **'Skip the next payday'**
  String get simPresetSkipNext;

  /// No description provided for @simPresetSkipNextLine.
  ///
  /// In en, this message translates to:
  /// **'See how you would do if your next pay does not come.'**
  String get simPresetSkipNextLine;

  /// No description provided for @simPresets.
  ///
  /// In en, this message translates to:
  /// **'Start with one of these'**
  String get simPresets;

  /// No description provided for @simPretend.
  ///
  /// In en, this message translates to:
  /// **'Pretend money in or out'**
  String get simPretend;

  /// No description provided for @simPretendAccount.
  ///
  /// In en, this message translates to:
  /// **'Which account?'**
  String get simPretendAccount;

  /// No description provided for @simPretendAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get simPretendAdd;

  /// No description provided for @simPretendDate.
  ///
  /// In en, this message translates to:
  /// **'On {date}'**
  String simPretendDate(String date);

  /// No description provided for @simPretendIn.
  ///
  /// In en, this message translates to:
  /// **'Money in'**
  String get simPretendIn;

  /// No description provided for @simPretendLabel.
  ///
  /// In en, this message translates to:
  /// **'What is it?'**
  String get simPretendLabel;

  /// No description provided for @simPretendMainNote.
  ///
  /// In en, this message translates to:
  /// **'Pretend amounts are in {code}, your main currency.'**
  String simPretendMainNote(String code);

  /// No description provided for @simPretendOut.
  ///
  /// In en, this message translates to:
  /// **'Money out'**
  String get simPretendOut;

  /// No description provided for @simPretendRange.
  ///
  /// In en, this message translates to:
  /// **'Use an amount from {min} to {max}.'**
  String simPretendRange(String min, String max);

  /// No description provided for @simPretendTooMany.
  ///
  /// In en, this message translates to:
  /// **'You can pretend up to {count} entries at once. Remove one first.'**
  String simPretendTooMany(int count);

  /// No description provided for @simRatesStale.
  ///
  /// In en, this message translates to:
  /// **'Exchange rates are older than a day.'**
  String get simRatesStale;

  /// No description provided for @simReachEdge.
  ///
  /// In en, this message translates to:
  /// **'Time travel reaches 5 years each way.'**
  String get simReachEdge;

  /// No description provided for @simReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get simReceived;

  /// No description provided for @simReceivedSoFar.
  ///
  /// In en, this message translates to:
  /// **'Received so far'**
  String get simReceivedSoFar;

  /// No description provided for @simRecordedEnd.
  ///
  /// In en, this message translates to:
  /// **'Recorded at the end'**
  String get simRecordedEnd;

  /// No description provided for @simRecordedToday.
  ///
  /// In en, this message translates to:
  /// **'Recorded up to today'**
  String get simRecordedToday;

  /// No description provided for @simRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String simRemove(String name);

  /// No description provided for @simReplayEnd.
  ///
  /// In en, this message translates to:
  /// **'Plan replay at the end'**
  String get simReplayEnd;

  /// No description provided for @simReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get simReset;

  /// No description provided for @simResetDone.
  ///
  /// In en, this message translates to:
  /// **'What-if cleared. Your plan is back as it is.'**
  String get simResetDone;

  /// No description provided for @simRules.
  ///
  /// In en, this message translates to:
  /// **'Payday rules'**
  String get simRules;

  /// No description provided for @simSectionChanges.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change} other{{count} changes}}'**
  String simSectionChanges(int count);

  /// No description provided for @simSeeOverTime.
  ///
  /// In en, this message translates to:
  /// **'See over time'**
  String get simSeeOverTime;

  /// No description provided for @simShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get simShowAll;

  /// No description provided for @simShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get simShowLess;

  /// No description provided for @simShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show {count} more'**
  String simShowMore(int count);

  /// No description provided for @simShowingGroup.
  ///
  /// In en, this message translates to:
  /// **'Showing {name}'**
  String simShowingGroup(String name);

  /// No description provided for @simShownOf.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total}'**
  String simShownOf(int shown, int total);

  /// No description provided for @simSimulatedEnd.
  ///
  /// In en, this message translates to:
  /// **'Simulated at the end'**
  String get simSimulatedEnd;

  /// No description provided for @simSkipPayday.
  ///
  /// In en, this message translates to:
  /// **'Tap a payday that would not come:'**
  String get simSkipPayday;

  /// No description provided for @simSpanHint.
  ///
  /// In en, this message translates to:
  /// **'This period holds today. Pick an earlier or a later one to see the total from it to today.'**
  String get simSpanHint;

  /// No description provided for @simSpanIncludes.
  ///
  /// In en, this message translates to:
  /// **'Includes the period you picked.'**
  String get simSpanIncludes;

  /// No description provided for @simSpanNet.
  ///
  /// In en, this message translates to:
  /// **'Net (received minus spent)'**
  String get simSpanNet;

  /// No description provided for @simSpanNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing was spent or received in this span.'**
  String get simSpanNothing;

  /// No description provided for @simSpanRange.
  ///
  /// In en, this message translates to:
  /// **'{from} to {to}'**
  String simSpanRange(String from, String to);

  /// No description provided for @simSpanTitle.
  ///
  /// In en, this message translates to:
  /// **'Overall flow'**
  String get simSpanTitle;

  /// No description provided for @simSpanToday.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get simSpanToday;

  /// No description provided for @simSpanTodayCap.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get simSpanTodayCap;

  /// No description provided for @simSpent.
  ///
  /// In en, this message translates to:
  /// **'Spent'**
  String get simSpent;

  /// No description provided for @simSpentSoFar.
  ///
  /// In en, this message translates to:
  /// **'Spent so far'**
  String get simSpentSoFar;

  /// No description provided for @simStillToCome.
  ///
  /// In en, this message translates to:
  /// **'Still to come (estimate)'**
  String get simStillToCome;

  /// No description provided for @simStillToReceive.
  ///
  /// In en, this message translates to:
  /// **'Still to be received (estimate)'**
  String get simStillToReceive;

  /// No description provided for @simTagMissed.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get simTagMissed;

  /// No description provided for @simTagPretend.
  ///
  /// In en, this message translates to:
  /// **'What-if'**
  String get simTagPretend;

  /// No description provided for @simTagRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get simTagRecorded;

  /// No description provided for @simTagReplay.
  ///
  /// In en, this message translates to:
  /// **'Plan replay'**
  String get simTagReplay;

  /// No description provided for @simTagSimulated.
  ///
  /// In en, this message translates to:
  /// **'Simulated'**
  String get simTagSimulated;

  /// No description provided for @simTiming.
  ///
  /// In en, this message translates to:
  /// **'Timing'**
  String get simTiming;

  /// No description provided for @simTitle.
  ///
  /// In en, this message translates to:
  /// **'Time travel'**
  String get simTitle;

  /// No description provided for @simToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get simToday;

  /// No description provided for @simUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get simUndo;

  /// No description provided for @simUnknown.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pay or bill has no amount yet and is not counted} other{{count} pays or bills have no amount yet and are not counted}}'**
  String simUnknown(int count);

  /// No description provided for @simUntracked.
  ///
  /// In en, this message translates to:
  /// **'Untracked: left without being recorded'**
  String get simUntracked;

  /// No description provided for @simWhatIf.
  ///
  /// In en, this message translates to:
  /// **'What if'**
  String get simWhatIf;

  /// No description provided for @simWhatIfLine.
  ///
  /// In en, this message translates to:
  /// **'Nothing here is saved. It only changes the replay and the simulation.'**
  String get simWhatIfLine;

  /// No description provided for @simWhatIfOn.
  ///
  /// In en, this message translates to:
  /// **'What-if on: {count, plural, =1{1 change} other{{count} changes}}'**
  String simWhatIfOn(int count);

  /// No description provided for @simWhatIfTitle.
  ///
  /// In en, this message translates to:
  /// **'What if…'**
  String get simWhatIfTitle;

  /// No description provided for @simWhereLine.
  ///
  /// In en, this message translates to:
  /// **'In {code}, your main currency.'**
  String simWhereLine(String code);

  /// No description provided for @simWhereTitle.
  ///
  /// In en, this message translates to:
  /// **'Where it went'**
  String get simWhereTitle;

  /// No description provided for @simWholePeriod.
  ///
  /// In en, this message translates to:
  /// **'Whole period (estimate)'**
  String get simWholePeriod;

  /// No description provided for @simZoomDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get simZoomDay;

  /// No description provided for @simZoomMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get simZoomMonth;

  /// No description provided for @simZoomWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get simZoomWeek;

  /// No description provided for @simZoomYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get simZoomYear;

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

  /// No description provided for @splitBillFallback.
  ///
  /// In en, this message translates to:
  /// **'a bill'**
  String get splitBillFallback;

  /// No description provided for @splitBrokenLink.
  ///
  /// In en, this message translates to:
  /// **'{rule} cannot save for {bill}: {reason}.'**
  String splitBrokenLink(String rule, String bill, String reason);

  /// No description provided for @splitClearAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all earlier splits'**
  String get splitClearAll;

  /// No description provided for @splitClearAllBody.
  ///
  /// In en, this message translates to:
  /// **'Every recorded split, approved or not, is deleted for good. Your bills, rules and paydays stay.'**
  String get splitClearAllBody;

  /// No description provided for @splitClearAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all earlier splits?'**
  String get splitClearAllTitle;

  /// No description provided for @splitClearAllYes.
  ///
  /// In en, this message translates to:
  /// **'Delete them all'**
  String get splitClearAllYes;

  /// No description provided for @splitCleared.
  ///
  /// In en, this message translates to:
  /// **'Splits deleted.'**
  String get splitCleared;

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

  /// No description provided for @splitCoveredLine.
  ///
  /// In en, this message translates to:
  /// **'{bill}  ·  already in {account}'**
  String splitCoveredLine(String bill, String account);

  /// No description provided for @splitCutOrMove.
  ///
  /// In en, this message translates to:
  /// **'You could cut or move:'**
  String get splitCutOrMove;

  /// No description provided for @splitDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'The split for payday {date} ({amount}) is deleted for good.'**
  String splitDeleteBody(String date, String amount);

  /// No description provided for @splitDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete this split'**
  String get splitDeleteButton;

  /// No description provided for @splitDeleteEntriesHelp.
  ///
  /// In en, this message translates to:
  /// **'This changes your account balances.'**
  String get splitDeleteEntriesHelp;

  /// No description provided for @splitDeleteEntriesSwitch.
  ///
  /// In en, this message translates to:
  /// **'Also take its pay and transfers out of my balances'**
  String get splitDeleteEntriesSwitch;

  /// No description provided for @splitDeleteKeepsMoney.
  ///
  /// In en, this message translates to:
  /// **'Money you already recorded or marked as sent stays in your accounts.'**
  String get splitDeleteKeepsMoney;

  /// No description provided for @splitDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this split?'**
  String get splitDeleteTitle;

  /// No description provided for @splitDeleteYes.
  ///
  /// In en, this message translates to:
  /// **'Delete it'**
  String get splitDeleteYes;

  /// No description provided for @splitDeleted.
  ///
  /// In en, this message translates to:
  /// **'Split deleted.'**
  String get splitDeleted;

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

  /// No description provided for @splitFromElsewhereTitle.
  ///
  /// In en, this message translates to:
  /// **'Not taken from this pay'**
  String get splitFromElsewhereTitle;

  /// No description provided for @splitFundedLine.
  ///
  /// In en, this message translates to:
  /// **'{bill}  ·  saved by {rule}'**
  String splitFundedLine(String bill, String rule);

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

  /// No description provided for @splitMenu.
  ///
  /// In en, this message translates to:
  /// **'More about this split'**
  String get splitMenu;

  /// No description provided for @splitPayday.
  ///
  /// In en, this message translates to:
  /// **'Payday {date}'**
  String splitPayday(String date);

  /// No description provided for @splitPlanAgain.
  ///
  /// In en, this message translates to:
  /// **'Plan again'**
  String get splitPlanAgain;

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

  /// No description provided for @splitUnfundedLine.
  ///
  /// In en, this message translates to:
  /// **'{bill}  ·  still needed from this pay'**
  String splitUnfundedLine(String bill);

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

  /// No description provided for @updCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get updCheckNow;

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

  /// No description provided for @updPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String updPercent(int percent);

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
  /// **'Version {version} is ready to install.'**
  String updRowAvailable(String version);

  /// No description provided for @updRowChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updRowChecking;

  /// No description provided for @updRowFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not check for updates.'**
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
  /// **'You have the latest version.'**
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
