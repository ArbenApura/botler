// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Filipino Pilipino (`fil`).
class AppLocalizationsFil extends AppLocalizations {
  AppLocalizationsFil([String locale = 'fil']) : super(locale);

  @override
  String get accountsAdd => 'Magdagdag ng account';

  @override
  String get accountsAddInvalid =>
      'Lagyan ng pangalan, at ang minimum bilang halaga.';

  @override
  String get accountsBelowMinimum => 'Mas mababa sa minimum na itinakda mo';

  @override
  String accountsBotlerThinks(String amount) {
    return 'Sa tantiya ni Botler, may $amount.';
  }

  @override
  String get accountsConfirmBig => 'Malaki ang pagkakaiba';

  @override
  String accountsConfirmBoth(String counted, String expected) {
    return 'Nabilang mo ay $counted at ang inaasahan ni Botler ay $expected.';
  }

  @override
  String accountsConfirmCounted(String counted) {
    return 'Nabilang mo ay $counted.';
  }

  @override
  String get accountsConfirmLarge =>
      'Mahigit sampung beses ang pagkakaiba, kaya pakisuri ang mga numero.';

  @override
  String get accountsConfirmRight => 'Tama ba ito?';

  @override
  String get accountsConfirmYes => 'Oo, tama iyon';

  @override
  String accountsCountInvalid(String currency) {
    return 'I-type ang halaga sa $currency.';
  }

  @override
  String accountsCountLabel(String currency) {
    return 'Magkano talaga ang nandoon? ($currency)';
  }

  @override
  String accountsCountTitle(String name) {
    return 'Binilang ko ang $name';
  }

  @override
  String get accountsCurrencyLabel => 'Pera';

  @override
  String get accountsCurrencyNote =>
      'Sa perang ito binibilang ang laman ng account na ito maliban kung pumili ka ng iba kapag may inilagay ka.';

  @override
  String get accountsEmpty =>
      'Wala pang account. Idagdag ang RCBC, GCash, Maya o cash.';

  @override
  String get accountsKindBank => 'Bangko';

  @override
  String get accountsKindCash => 'Cash';

  @override
  String get accountsKindEwallet => 'E-wallet';

  @override
  String get accountsKindOther => 'Iba pa';

  @override
  String accountsMinimumLabel(String currency) {
    return 'Panatilihin ng hindi bababa sa ($currency, opsyonal)';
  }

  @override
  String accountsMissingRate(String currencies) {
    return 'Wala pang palitan para sa $currencies. Wala ito sa kabuuan.';
  }

  @override
  String get accountsNameHint => 'GCash';

  @override
  String get accountsNameLabel => 'Pangalan';

  @override
  String accountsNoMainWallet(String currency) {
    return 'Walang $currency dito, kaya hindi sinusuri ang minimum.';
  }

  @override
  String get accountsNotSaved => 'Hindi na-save.';

  @override
  String accountsRateLine(String from, String rate, String main) {
    return '1 $from = $rate $main';
  }

  @override
  String accountsRatesAsOf(String date) {
    return 'Palitan ng pera noong $date';
  }

  @override
  String get accountsRatesFailed =>
      'Hindi ma-update ang palitan. Gagamitin pa rin ang huli.';

  @override
  String get accountsRatesNone =>
      'Wala pang palitan ng pera. I-tap para kunin.';

  @override
  String get accountsRatesOffline =>
      'Walang koneksyon. Ipinapakita ang huling kabuuan.';

  @override
  String get accountsRatesRefresh => 'I-update ang palitan';

  @override
  String accountsRatesStale(String date) {
    return 'Luma na ang palitan ng pera (noong $date). I-tap para i-update.';
  }

  @override
  String get accountsRatesTooSoon => 'Kaka-update lang ng palitan.';

  @override
  String get accountsRatesUpdated => 'Na-update ang palitan ng pera.';

  @override
  String get accountsSaveCount => 'I-save ang bilang';

  @override
  String get accountsSaved => 'Na-save.';

  @override
  String accountsSavedUntracked(String amount) {
    return 'Na-save. $amount ang hindi nasubaybayan mula sa huling bilang.';
  }

  @override
  String accountsSubtotal(String amount) {
    return 'Mga $amount lahat';
  }

  @override
  String get accountsTitle => 'Mga account';

  @override
  String get accountsTotalTitle => 'Lahat ng meron ka';

  @override
  String get accountsTotalUnavailable =>
      'Kailangan ng palitan ng pera ang kabuuan, at wala pa nito.';

  @override
  String get accountsWalletAdd => 'Magdagdag ng pera';

  @override
  String accountsWalletAdded(String currency) {
    return 'Nadagdag ang $currency.';
  }

  @override
  String get accountsWalletsTitle => 'Mga pera sa account na ito';

  @override
  String get acctBalanceNow => 'Balanse ngayon';

  @override
  String get acctByAnyone => 'Kahit sino';

  @override
  String get acctByBotler => 'Botler';

  @override
  String get acctByJob => 'Mga job at sync';

  @override
  String get acctByYou => 'Ikaw';

  @override
  String get acctDateClear => 'Kahit anong petsa';

  @override
  String get acctDateRange => 'Mga petsa';

  @override
  String get acctEmpty => 'Wala pa rito.';

  @override
  String acctExportCut(int rows, String format, String notice) {
    return 'Nakopya ang $rows hilera bilang $format. $notice';
  }

  @override
  String acctExportDone(int rows, String format) {
    return 'Nakopya ang $rows hilera bilang $format.';
  }

  @override
  String get acctLoadMore => 'Ipakita ang mas luma';

  @override
  String get acctMenuCount => 'Binilang ko ito';

  @override
  String get acctMenuExport => 'I-export ang history';

  @override
  String get acctMenuPurpose => 'Baguhin ang label';

  @override
  String get acctMenuReset => 'I-reset sa zero';

  @override
  String get acctMenuSet => 'Itakda ang balanse';

  @override
  String get acctOffline => 'Kailangan ng koneksyon ang history.';

  @override
  String get acctOpen => 'Tingnan ang nangyari';

  @override
  String get acctSearchHint => 'Maghanap sa mga tala';

  @override
  String get acctTabAll => 'Lahat';

  @override
  String get acctTabCounts => 'Bilang at reset';

  @override
  String get acctTabIn => 'Pumasok';

  @override
  String get acctTabOut => 'Lumabas';

  @override
  String get acctTabUndone => 'Binawi';

  @override
  String activityUndoCreatedBody(String page) {
    return 'Ginawa ni Botler ang \"$page\". Buburahin ng pag-undo ang pahina. Maibabalik mo ito sa loob ng 30 araw.';
  }

  @override
  String get activityUndoCreatedTitle =>
      'Buburahin ang pahinang ginawa ni Botler?';

  @override
  String get activityUndoUnavailable =>
      'Hindi na nakaimbak ang naunang teksto, kaya hindi na ito ma-undo.';

  @override
  String get activityUndoneDeleted =>
      'Nabura. Maibabalik mo ito sa loob ng 30 araw.';

  @override
  String get activityUndoneRestored => 'Naibalik ang naunang teksto.';

  @override
  String get add => 'Idagdag';

  @override
  String get agendaAddEvent => 'Magdagdag ng event';

  @override
  String get agendaAddRoutine => 'Magdagdag ng routine';

  @override
  String get agendaAddTask => 'Magdagdag ng task';

  @override
  String get agendaAlarm => 'Alarm';

  @override
  String agendaAtTime(String time) {
    return 'Ng $time';
  }

  @override
  String agendaDaysAt(String days, String time) {
    return '$days ng $time';
  }

  @override
  String agendaDue(String when) {
    return 'Due sa $when';
  }

  @override
  String get agendaEventNeeds => 'Lagyan ng pangalan at oras.';

  @override
  String get agendaEventSubmit => 'Idagdag ang event';

  @override
  String get agendaEventWhat => 'Ano ito?';

  @override
  String get agendaEventsEmpty => 'Walang event sa susunod na dalawang linggo.';

  @override
  String agendaEveryDayAt(String time) {
    return 'Araw-araw ng $time';
  }

  @override
  String agendaEveryNDaysAt(String n, String time) {
    return 'Bawat $n araw ng $time';
  }

  @override
  String get agendaFreqDaily => 'Araw-araw';

  @override
  String get agendaFreqWeekly => 'Sa ilang araw';

  @override
  String agendaMonthlyAt(String day, String time) {
    return 'Tuwing ika-$day ng buwan ng $time';
  }

  @override
  String get agendaPickMoment => 'Piliin ang araw at oras';

  @override
  String get agendaRemindMe => 'Paalalahanan ako';

  @override
  String get agendaReminderNeeds => 'Sabihin kung para saan, at kailan.';

  @override
  String get agendaReminderWhat => 'Para saan?';

  @override
  String get agendaRemindersEmpty => 'Walang naghihintay na paalala.';

  @override
  String get agendaRemove => 'Alisin';

  @override
  String get agendaRoutineHint => 'Uminom ng vitamins';

  @override
  String get agendaRoutineNeeds =>
      'Lagyan ng pangalan, at pumili ng kahit isang araw.';

  @override
  String get agendaRoutineSubmit => 'Idagdag ang routine';

  @override
  String get agendaRoutinesEmpty =>
      'Walang routine. Subukan: “gym tuwing Lunes, Miyerkules at Biyernes ng 6”.';

  @override
  String get agendaSetAlarm => 'Magtakda ng alarm';

  @override
  String get agendaStartTimer => 'Magsimula ng timer';

  @override
  String get agendaTabEvents => 'Mga event';

  @override
  String get agendaTabReminders => 'Mga paalala';

  @override
  String get agendaTabRoutines => 'Mga routine';

  @override
  String get agendaTabTasks => 'Mga task';

  @override
  String get agendaTaskDeadline => 'Magtakda ng deadline (opsyonal)';

  @override
  String get agendaTaskNeedsTitle => 'Sabihin kung ano ang task.';

  @override
  String get agendaTaskSubmit => 'Idagdag ang task';

  @override
  String get agendaTaskWhat => 'Ano ang kailangang gawin?';

  @override
  String get agendaTasksEmpty =>
      'Walang nakabinbin. Magdagdag ng gusto mong tandaang gawin.';

  @override
  String get agendaTimerMinutes => 'Ilang minuto?';

  @override
  String get agendaTimerRange => 'Pumili ng 1 hanggang 1440 minuto.';

  @override
  String get agendaTimerStart => 'Simulan';

  @override
  String get agendaTitle => 'Agenda';

  @override
  String get appName => 'Botler';

  @override
  String get auditAcApprove => 'Inaprubahan';

  @override
  String get auditAcCount => 'Binilang';

  @override
  String get auditAcCreate => 'Idinagdag';

  @override
  String get auditAcDataReset => 'Pag-reset ng data';

  @override
  String get auditAcDelete => 'Inalis';

  @override
  String get auditAcExpire => 'Nag-expire';

  @override
  String get auditAcReject => 'Tinanggihan';

  @override
  String get auditAcReset => 'Na-reset';

  @override
  String get auditAcUndo => 'Binawi';

  @override
  String get auditAcUpdate => 'Binago';

  @override
  String get auditBalanceAfter => 'Balanse pagkatapos';

  @override
  String auditBannerBody(int seq) {
    return 'Hindi na tugma ang entry $seq sa nauna rito. Walang nawala sa phone na ito. Buksan ang Settings, Audit trail, at ipadala ang detalye sa nagpapatakbo ng server mo.';
  }

  @override
  String get auditBannerTitle => 'Hindi tugma ang audit trail';

  @override
  String get auditBotler => 'Botler';

  @override
  String get auditBotlerApproved => 'Botler, inaprubahan mo';

  @override
  String get auditChApp => 'sa app';

  @override
  String get auditChCalendar => 'Calendar sync (retired)';

  @override
  String get auditChChat => 'sa chat';

  @override
  String get auditChJob => 'isang job';

  @override
  String get auditChOutbox => 'offline, ipinadala mamaya';

  @override
  String get auditChSystem => 'ang sistema';

  @override
  String get auditChWidget => 'mula sa widget';

  @override
  String auditChangeLine(String field, String before, String after) {
    return '$field: $before naging $after';
  }

  @override
  String get auditChanges => 'Ano ang nagbago';

  @override
  String get auditChecking => 'Sinusuri...';

  @override
  String get auditCopied => 'Nakopya ang reference.';

  @override
  String get auditCopyRef => 'Kopyahin ang reference';

  @override
  String get auditEnSnapshot => 'bilang ng balanse';

  @override
  String get auditEnTxn => 'transaksyon';

  @override
  String get auditJob => 'Isang naka-iskedyul na job';

  @override
  String get auditNone => 'wala';

  @override
  String get auditNote => 'Tala';

  @override
  String get auditRefApproval => 'approval';

  @override
  String get auditRefRequest => 'request';

  @override
  String get auditRefTurn => 'turn';

  @override
  String get auditRefs => 'Mga reference';

  @override
  String auditRowSemantics(
    String what,
    String who,
    String when,
    String balance,
  ) {
    return '$what, $who, $when, balanse pagkatapos $balance';
  }

  @override
  String auditSettingsBad(int seq, String kind) {
    return 'Wala sa ayos ang entry $seq ($kind).';
  }

  @override
  String get auditSettingsLine =>
      'Bawat pagbabago sa pera mo ay isinusulat nang isang beses at hindi na mababago o mabubura.';

  @override
  String auditSettingsOk(int count, String when) {
    return 'Sinuri ang $count entry, maayos lahat. Huling check: $when.';
  }

  @override
  String get auditSettingsTitle => 'Audit trail';

  @override
  String get auditSync => 'Sync';

  @override
  String get auditUnverified => 'Hindi ma-check ang history ngayon.';

  @override
  String get auditWhen => 'Kailan';

  @override
  String get auditWhere => 'Saan';

  @override
  String get auditWho => 'Sino';

  @override
  String get auditYou => 'Ikaw';

  @override
  String billsAboutLabel(String currency) {
    return 'Magkano kaya? ($currency)';
  }

  @override
  String billsAboutMain(String amount) {
    return 'mga $amount';
  }

  @override
  String get billsAdd => 'Magdagdag ng bill';

  @override
  String get billsAddButton => 'Idagdag ang bill';

  @override
  String get billsAddInvalid => 'Lagyan ng pangalan, halaga at account.';

  @override
  String get billsAll => 'Lahat ng bill';

  @override
  String get billsAmountNotKnown => 'hindi pa alam ang halaga';

  @override
  String get billsAmountUnknown => 'halaga?';

  @override
  String billsChargedLabel(String currency) {
    return 'Talagang siningil ($currency)';
  }

  @override
  String billsChargedNote(String bill, String wallet) {
    return 'Nasa $bill ang bill na ito, pero sa $wallet wallet ka nagbabayad. I-type ang talagang siningil.';
  }

  @override
  String get billsComingUp => 'Paparating';

  @override
  String get billsCurrencyLabel => 'Pera ng bill na ito';

  @override
  String get billsDateLabel => 'Petsa ng due';

  @override
  String get billsDateNote =>
      'Ito lang ang lilipat. Para baguhin ang lahat ng petsa, baguhin ang pag-uulit sa ibaba.';

  @override
  String get billsEditHint => 'I-tap para baguhin';

  @override
  String get billsEditTitle => 'Baguhin ang bill';

  @override
  String get billsEmpty =>
      'Wala pang bill. Idagdag ang upa, internet, kuryente...';

  @override
  String billsHowMuchLabel(String currency) {
    return 'Magkano? ($currency)';
  }

  @override
  String get billsMarkPaid => 'Markahang bayad na';

  @override
  String billsMarkPaidFor(String name) {
    return 'Markahang bayad na ang $name';
  }

  @override
  String get billsMarkedPaid => 'Namarkahang bayad na.';

  @override
  String billsMarkedPaidHint(String amount) {
    return 'Namarkahang bayad na. $amount ang baba nito sa karaniwan: puwede mo itong itabi.';
  }

  @override
  String get billsMissingRateTag => 'wala pang palitan';

  @override
  String get billsMovedTag => 'inilipat';

  @override
  String get billsNameHint => 'Upa sa bahay';

  @override
  String get billsNameLabel => 'Ano ito?';

  @override
  String get billsNoChange => 'Walang nabago.';

  @override
  String get billsNothingDue => 'Walang due sa susunod na 4 na buwan.';

  @override
  String get billsOverdue => 'Lampas na sa due';

  @override
  String get billsPaid => 'Bayad na';

  @override
  String get billsPaidFrom => 'Babayaran mula sa';

  @override
  String billsPaidTitle(String name) {
    return 'Bayad na ang $name';
  }

  @override
  String get billsParentsShare => 'Ito ang parte ng mga magulang ko';

  @override
  String get billsParentsTag => 'bahagi ng magulang';

  @override
  String billsPayInvalid(String currency) {
    return 'I-type ang halaga sa $currency.';
  }

  @override
  String billsPayLabel(String currency) {
    return 'Magkano ito ngayon? ($currency)';
  }

  @override
  String get billsPutBack => 'Ibalik ayon sa iskedyul';

  @override
  String get billsPutBackDone => 'Balik na sa iskedyul.';

  @override
  String get billsRepeatChangedNote =>
      'Binago mo ang pag-uulit, kaya susunod ang lahat ng petsa sa bagong patakaran.';

  @override
  String get billsReserveNote =>
      'Sa pangunahing pera mo itinatabi ng payday split ang pera para sa bill na ito. Kapag sa ibang wallet ka nagbayad, puwedeng bumaba sa zero ang wallet na iyon.';

  @override
  String get billsSave => 'I-save';

  @override
  String get billsSaved => 'Na-save na.';

  @override
  String get billsSavedOffline =>
      'Walang koneksyon. Ma-save ito kapag may koneksyon ka na.';

  @override
  String get billsScopeAll => 'Lahat ng susunod na petsa';

  @override
  String billsScopeThisOne(String date) {
    return 'Ito lang ($date)';
  }

  @override
  String get billsScopeTitle => 'Ito lang ba, o tuwing babayaran?';

  @override
  String get billsSkip => 'Laktawan ang petsang ito';

  @override
  String get billsSkipBody =>
      'Hindi ito lalabas sa petsang iyon. Sabihin kay Botler na ibalik ito kung magbago ang isip mo.';

  @override
  String billsSkipTitle(String name, String date) {
    return 'Laktawan ang $name sa $date?';
  }

  @override
  String get billsSkipYes => 'Laktawan';

  @override
  String get billsSkipped => 'Nilaktawan.';

  @override
  String get billsThisMonth => 'Ngayong buwan';

  @override
  String get billsThisWeek => 'Ngayong linggo';

  @override
  String get billsTitle => 'Mga bill';

  @override
  String billsUsualSuffix(String amount) {
    return '$amount (karaniwan)';
  }

  @override
  String get billsVaries => 'Iba-iba ang halaga tuwing magbabayad';

  @override
  String get billsViewMonth => 'Buwan';

  @override
  String get billsViewWeek => 'Linggo';

  @override
  String get billsWalletLabel => 'Binayaran sa';

  @override
  String get calAdd => 'Magdagdag';

  @override
  String get calAddBill => 'Isang bill';

  @override
  String get calAddEvent => 'Isang event';

  @override
  String get calAddReminder => 'Isang paalala';

  @override
  String get calAddTask => 'Isang gawain';

  @override
  String calAddTitle(String date) {
    return 'Idagdag sa $date';
  }

  @override
  String get calAgendaDueThisWeek => 'Due ngayong linggo';

  @override
  String get calAgendaEmpty => 'Wala sa susunod na 30 araw.';

  @override
  String get calAgendaMore => 'Magpakita ng 30 araw pa';

  @override
  String get calAllDay => 'Buong araw';

  @override
  String get calAllDayToggle => 'Buong araw';

  @override
  String get calAmountUnknown => 'halaga?';

  @override
  String calBillDue(String date) {
    return 'Due sa $date';
  }

  @override
  String get calBillOverdue => 'Lampas na';

  @override
  String get calBillPaid => 'Bayad na';

  @override
  String calBillWindow(String start, String end) {
    return 'Magbayad kahit anong araw, $start hanggang $end';
  }

  @override
  String calCountBills(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bill',
      one: '1 bill',
    );
    return '$_temp0';
  }

  @override
  String calCountEvents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count event',
      one: '1 event',
    );
    return '$_temp0';
  }

  @override
  String calCountPaydays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sweldo',
      one: '1 sweldo',
    );
    return '$_temp0';
  }

  @override
  String calCountReminders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paalala',
      one: '1 paalala',
    );
    return '$_temp0';
  }

  @override
  String calCountRoutines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count routine',
      one: '1 routine',
    );
    return '$_temp0';
  }

  @override
  String calCountTasks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gawain',
      one: '1 gawain',
    );
    return '$_temp0';
  }

  @override
  String calCountWorkouts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count na workout',
      one: '1 workout',
    );
    return '$_temp0';
  }

  @override
  String get calDayNothing => 'walang nakaplano';

  @override
  String calDaySemantics(String date, String parts) {
    return '$date, $parts';
  }

  @override
  String get calError => 'Hindi ma-load ang kalendaryo.';

  @override
  String get calEstimate => 'Tantiya';

  @override
  String calForecastLow(String account) {
    return 'Maaaring bumaba ang $account sa minimum nito';
  }

  @override
  String calForecastLowDay(String date) {
    return 'Mababa sa $date';
  }

  @override
  String get calForecastNone =>
      'Wala pang matatantiya. Magdagdag muna ng account at bill.';

  @override
  String get calForecastOk => 'hindi bababa sa minimum';

  @override
  String calForecastSemantics(String from, String to, String low) {
    return 'Tantiyang pera sa lahat ng account mula $from hanggang $to, $low';
  }

  @override
  String get calForecastTitle => 'Saan papunta ang pera mo';

  @override
  String calForecastTotal(String amount) {
    return 'Mga $amount';
  }

  @override
  String calForecastUnconverted(int count) {
    return '$count bill sa ibang pera ang wala sa forecast na ito dahil wala pa silang palitan.';
  }

  @override
  String calForecastUnknown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bill ang wala pang halaga, kaya zero ang bilang nila',
      one: '1 bill ang wala pang halaga, kaya zero ang bilang nito',
    );
    return '$_temp0';
  }

  @override
  String get calLayerBills => 'Mga bill';

  @override
  String get calLayerEvents => 'Mga event';

  @override
  String get calLayerPaydays => 'Sweldo';

  @override
  String get calLayerReminders => 'Mga paalala';

  @override
  String get calLayerRoutines => 'Mga routine';

  @override
  String get calLayerTasks => 'Mga gawain';

  @override
  String get calLayerWorkouts => 'Mga workout';

  @override
  String get calLayersLabel => 'Ipakita';

  @override
  String get calMarkPaid => 'I-mark na bayad';

  @override
  String calMarkPaidBody(String amount) {
    return 'Magsusulat ito ng $amount bilang gastos.';
  }

  @override
  String calMarkPaidTitle(String name) {
    return 'I-mark na bayad ang $name?';
  }

  @override
  String calMore(int count) {
    return '+$count';
  }

  @override
  String get calNeedTitle => 'Bigyan muna ng pangalan.';

  @override
  String get calNext => 'Susunod';

  @override
  String get calNow => 'Ngayon';

  @override
  String get calOffline =>
      'Ipinapakita ang huling kalendaryong nakita ng phone na ito.';

  @override
  String get calPaidDone => 'Namarkahang bayad na.';

  @override
  String get calPaydayLabel => 'Sweldo';

  @override
  String get calPaydaySplit => 'Hatiin ang sweldo mo';

  @override
  String get calPaydaySplitDone => 'Nahati na';

  @override
  String get calPrev => 'Nakaraan';

  @override
  String get calReminderLabel => 'Paalala';

  @override
  String get calRoutineLabel => 'Routine';

  @override
  String get calSaved => 'Nai-save na.';

  @override
  String get calTaskLabel => 'Gawain';

  @override
  String get calTimeLabel => 'Oras';

  @override
  String get calTitle => 'Kalendaryo';

  @override
  String get calToday => 'Ngayon';

  @override
  String get calViewAgenda => 'Agenda';

  @override
  String get calViewMonth => 'Buwan';

  @override
  String get calViewWeek => 'Linggo';

  @override
  String calWeekOf(String date) {
    return 'Linggo ng $date';
  }

  @override
  String get calWhatIsIt => 'Ano ito?';

  @override
  String get calWorkoutLabel => 'Workout';

  @override
  String get cancel => 'Kanselahin';

  @override
  String changelogBuildHeader(String version) {
    return 'Bersyon $version';
  }

  @override
  String get changelogGotIt => 'Sige';

  @override
  String get changelogRowHint =>
      'Basahin ang mga pagbabago sa bersyong gamit mo ngayon';

  @override
  String get changelogRowTitle => 'Ano ang bago sa bersyong ito';

  @override
  String changelogTitle(String version) {
    return 'Ano ang bago sa $version';
  }

  @override
  String get chatAcrossAccounts => 'Sa lahat ng account mo';

  @override
  String get chatAddExpense => 'Magdagdag ng expense';

  @override
  String get chatAddExpenseHint =>
      'Maaari ka pa ring magdagdag ng expense nang mag-isa.';

  @override
  String get chatApprove => 'Aprubahan';

  @override
  String get chatApproveRule => 'Aprubahan ang patakaran';

  @override
  String get chatAssistantDown => 'Hindi available ang assistant ngayon.';

  @override
  String get chatCardElsewhere =>
      'Naghihintay ng sagot mo sa chat na pinagmulan nito.';

  @override
  String get chatCardExpired => 'Nag-expire na ang hiling na ito.';

  @override
  String get chatCardFailed => 'Hindi ito nagawa.';

  @override
  String chatChecked(String what) {
    return 'Sinuri: $what';
  }

  @override
  String chatCheckedMany(String what, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pa',
      one: '1 pa',
    );
    return '$what, $_temp0';
  }

  @override
  String chatCheckedMore(int count) {
    return '+$count';
  }

  @override
  String chatChecking(String what) {
    return 'Sinusuri ang $what';
  }

  @override
  String get chatChooseScreenshot => 'Pumili ng screenshot';

  @override
  String chatConfirmQuestion(String amount, String account) {
    return '$amount ba ito sa $account?';
  }

  @override
  String get chatContextAtLast => 'Sa huling sagot';

  @override
  String get chatContextDanger =>
      'Halos puno na. Ibuod na ngayon para may espasyo ang susunod na sagot.';

  @override
  String get chatContextExplain =>
      'Habang humahaba ang usapan, kusang binubuod ang mga naunang mensahe. Walang nawawala at wala kang kailangang gawin.';

  @override
  String get chatContextFailed => 'Hindi nabuod. Subukan ulit.';

  @override
  String chatContextFull(int percent) {
    return '$percent porsyento na ang puno';
  }

  @override
  String get chatContextLastSummary => 'Huling buod';

  @override
  String get chatContextMonth => 'Ngayong buwan, lahat ng usapan';

  @override
  String chatContextMonthShare(int percent) {
    return '$percent porsyento ng buwanang limitasyon';
  }

  @override
  String get chatContextNever => 'Wala pa';

  @override
  String get chatContextOffline => 'Kailangan ng koneksyon para makapagbuod.';

  @override
  String get chatContextShort =>
      'Masyado pang maikli para buurin. Kailangan pa ng ilang mensahe.';

  @override
  String get chatContextSummarize => 'Ibuod na ngayon';

  @override
  String get chatContextSummarized =>
      'Nabuod na. Mag-a-update ang bilog sa susunod mong mensahe.';

  @override
  String get chatContextSummarizing => 'Binubuod';

  @override
  String get chatContextTitle => 'Context';

  @override
  String chatContextTooltip(int percent) {
    return 'Context, $percent porsyento na ang puno';
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

    return 'Nagamit ang $usedString sa $windowString token';
  }

  @override
  String get chatContextWarn =>
      'Malapit nang mapuno. Mas gumagaan ang mga susunod na sagot kapag ibinuod na ngayon.';

  @override
  String get chatEarlier => 'Mas maaga';

  @override
  String get chatEarlierNotFinished =>
      'Hindi natapos ang naunang mensahe, kaya inihinto ang mga naghihintay.';

  @override
  String get chatEditCancel => 'Ihinto ang pag-edit';

  @override
  String get chatEditing => 'Ine-edit ang mensahe mo';

  @override
  String get chatGreeting => 'Ano ang maitutulong ko?';

  @override
  String get chatHintMessage => 'Mag-message kay Botler';

  @override
  String get chatHowMuch => 'Magkano ito?';

  @override
  String get chatInForce => 'Umiiral';

  @override
  String get chatJumpLatest => 'Pumunta sa pinakabagong mensahe';

  @override
  String chatLogged(String amount, String account) {
    return 'Naitala ang $amount sa $account';
  }

  @override
  String chatMarkedPaid(String amount) {
    return 'Namarkahang bayad · $amount';
  }

  @override
  String get chatMenu => 'Menu';

  @override
  String get chatMicBlocked =>
      'Hindi makapakinig ang phone ngayon. Tingnan ang pahintulot sa mikropono.';

  @override
  String get chatMsgActions => 'Mga aksyon sa mensahe';

  @override
  String get chatMsgBranch => 'Sumanga mula rito';

  @override
  String get chatMsgCopied => 'Nakopya na.';

  @override
  String get chatMsgCopy => 'Kopyahin';

  @override
  String get chatMsgEdit => 'I-edit at ipadala ulit';

  @override
  String chatNeedsAmounts(String names) {
    return 'Magkano karaniwan ang $names? Kailangan ko ng halaga para magawa ang hati.';
  }

  @override
  String chatNextBill(String name, String day) {
    return 'Susunod na bill: $name, $day';
  }

  @override
  String get chatNoAnswer => 'Walang naging sagot dito.';

  @override
  String get chatNoBill => 'Walang paparating na bill';

  @override
  String get chatNoEvent => 'Walang nakatakda sa kalendaryo mo ngayon';

  @override
  String get chatNotDone => 'Hindi ginawa';

  @override
  String get chatNotNow => 'Mamaya na';

  @override
  String get chatNotebookAlready => 'Nasa notebook mo na ito';

  @override
  String chatNotebookChanged(String what) {
    return 'Binago ang $what';
  }

  @override
  String get chatNotebookChangedPlain => 'Binago ang mga notebook mo';

  @override
  String chatNotebookMade(String what) {
    return 'Ginawa ang $what';
  }

  @override
  String chatNotebookRemoved(String what) {
    return 'Binura ang $what';
  }

  @override
  String chatNotebookRestored(String what) {
    return 'Ibinalik ang $what';
  }

  @override
  String chatNotebookSaved(String where) {
    return 'Nai-save sa notebook mo · $where';
  }

  @override
  String get chatNotebookSavedPlain => 'Nai-save sa notebook mo';

  @override
  String get chatNoticeFailed =>
      'Hindi natapos ng assistant iyon. Subukan ulit.';

  @override
  String get chatNoticeOffline =>
      'Walang koneksyon. Nakatabi sa iyong phone. Ipapadala ito nang isang beses kapag online ka na ulit.';

  @override
  String get chatOffline => 'offline';

  @override
  String get chatOutputShowAll => 'Ipakita lahat';

  @override
  String get chatOutputShowLess => 'Ipakita nang kaunti';

  @override
  String chatPageSaved(String page, String notebook) {
    return 'Nai-save sa $page sa $notebook';
  }

  @override
  String get chatPasteNothing => 'Walang larawan sa clipboard.';

  @override
  String get chatPastePhoto => 'I-paste ang litrato';

  @override
  String chatPendingSnack(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entry ang naghihintay ng koneksyon.',
      one: '$count entry ang naghihintay ng koneksyon.',
    );
    return '$_temp0';
  }

  @override
  String chatPendingTooltip(int count) {
    return '$count naghihintay na maipadala';
  }

  @override
  String chatPhotoChars(int count) {
    return '$count karakter ang nabasa';
  }

  @override
  String get chatPhotoClose => 'Isara';

  @override
  String chatPhotoCount(int current, int total) {
    return '$current sa $total';
  }

  @override
  String get chatPhotoEditing =>
      'Maghihintay ang mga litrato habang nag-e-edit ka ng mensahe.';

  @override
  String get chatPhotoEmpty => 'Wala akong mabasang teksto sa litratong iyon.';

  @override
  String get chatPhotoFailed => 'Hindi mabasa ang litrato.';

  @override
  String chatPhotoItem(int number, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count karakter',
      one: '$count karakter',
    );
    return 'Litrato $number ($_temp0)';
  }

  @override
  String get chatPhotoMissing => 'Wala na ang litratong ito sa phone na ito.';

  @override
  String get chatPhotoOnlyMessage => 'Heto ang mga litrato.';

  @override
  String chatPhotoOpen(int number, int total) {
    return 'Buksan ang litrato $number sa $total';
  }

  @override
  String chatPhotoRemove(int number) {
    return 'Alisin ang litrato $number';
  }

  @override
  String chatPhotoTileReading(int number) {
    return 'Binabasa ang litrato $number';
  }

  @override
  String get chatPhotoTooltip => 'Litrato ng resibo';

  @override
  String get chatPhotoZoomIn => 'I-zoom in';

  @override
  String get chatPhotoZoomOut => 'I-zoom out';

  @override
  String chatPhotosLimit(int count) {
    return 'Hanggang $count litrato lang sa isang mensahe.';
  }

  @override
  String get chatPhotosReading => 'Binabasa ang mga litrato…';

  @override
  String chatPhotosSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count litrato ang hindi nabasa at hindi isinama.',
      one: '$count litrato ang hindi nabasa at hindi isinama.',
    );
    return '$_temp0';
  }

  @override
  String get chatPhotosTrimmed =>
      'Mahaba ang teksto ng mga litrato, kaya unang bahagi lang ng bawat isa ang ipapadala.';

  @override
  String get chatPictureSkipped =>
      'Hindi maipadala ang isang larawan, kaya teksto lang nito ang ipapadala.';

  @override
  String get chatPicturesNoted =>
      'Ang sagot na ito ay batay sa tekstong nabasa mula sa larawan, hindi sa mismong larawan.';

  @override
  String get chatPleaseCheck => 'Pakisuri';

  @override
  String get chatQueueClear => 'Burahin';

  @override
  String get chatQueueEdit => 'I-edit ang mensaheng naghihintay';

  @override
  String get chatQueueFull =>
      'Masyadong maraming mensahe ang naghihintay. Hintaying maipadala ang isa.';

  @override
  String chatQueuePaused(int count) {
    return '$count ang naghihintay';
  }

  @override
  String get chatQueuePhotosFull =>
      'Masyadong maraming litrato ang naghihintay. Hintaying maipadala ang isang mensahe.';

  @override
  String get chatQueueRemove => 'Alisin ang mensaheng naghihintay';

  @override
  String get chatQueueSendNow => 'Ipadala na';

  @override
  String get chatQueueWaiting => 'Naghihintay';

  @override
  String chatRanScript(String output) {
    return 'Nagpatakbo ng script: $output';
  }

  @override
  String get chatRanScriptQuiet => 'Nagpatakbo ng script sa phone mo';

  @override
  String get chatReceiptMessage => 'Heto ang resibo.';

  @override
  String chatRecorded(String amount) {
    return 'Naitala ang $amount';
  }

  @override
  String get chatRestoreFailed => 'Hindi ma-load ang dati mong chat.';

  @override
  String get chatRunningScript => 'Nagpapatakbo ng script sa phone mo';

  @override
  String get chatSavingNotebook => 'Ina-update ang mga notebook mo';

  @override
  String get chatScriptFailed => 'Hindi natapos ang script';

  @override
  String get chatSend => 'Ipadala';

  @override
  String get chatSpeak => 'Magsalita';

  @override
  String get chatStillFinishing => 'Tinatapos pa ang naunang mensahe…';

  @override
  String get chatStop => 'Ihinto';

  @override
  String get chatStopListening => 'Ihinto ang pakikinig';

  @override
  String get chatStopped => 'Itinigil.';

  @override
  String get chatSuggestDue => 'Ano ang due ngayong linggo?';

  @override
  String get chatSuggestExpense => 'Mag-log ng gastos';

  @override
  String get chatSuggestExpenseText => 'Gumastos ako ng ';

  @override
  String get chatSuggestToday => 'Ano ang nasa kalendaryo ko ngayon?';

  @override
  String get chatSummaryOpen => 'Buod ng pera';

  @override
  String get chatTakePhoto => 'Kumuha ng litrato';

  @override
  String get chatThinking => 'Nag-iisip';

  @override
  String chatThoughtFor(int seconds) {
    return 'Nag-isip nang $seconds s';
  }

  @override
  String get chatThoughtToggle => 'Ipakita o itago ang naisip ng assistant';

  @override
  String get chatToolFailed => 'Hindi iyon umubra.';

  @override
  String get chatUndoGone => 'Hindi na maibabalik ang entry na iyon.';

  @override
  String get chatUndoneLine => 'Naibalik';

  @override
  String get chatUndoneSnack => 'Naibalik.';

  @override
  String get chatUsedToolbox => 'Ginamit ang toolbox mo';

  @override
  String get chatUsingToolbox => 'Binubuksan ang toolbox mo';

  @override
  String get chatWaiting => 'Inaasikaso na';

  @override
  String chatWhichAccount(String amount) {
    return 'Saang account galing ang $amount?';
  }

  @override
  String chatWithPhotos(String text, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count litrato',
      one: '$count litrato',
    );
    return '$text\n($_temp0)';
  }

  @override
  String get chatWriting => 'Sumusulat';

  @override
  String get chatYesLogIt => 'Oo, itala ito';

  @override
  String get chatYourAccount => 'iyong account';

  @override
  String get chatsArchive => 'I-archive';

  @override
  String get chatsArchivedEmpty => 'Walang naka-archive.';

  @override
  String get chatsArchivedOpen => 'Mga naka-archive na chat';

  @override
  String get chatsArchivedTitle => 'Naka-archive';

  @override
  String get chatsBranchMark => 'Sanga';

  @override
  String chatsBranchedFrom(String title) {
    return 'Sanga mula sa $title';
  }

  @override
  String get chatsBranchedNote =>
      'Nananatiling naka-save ang mga pagbabago bago ang puntong ito. I-undo ang mga ito sa History.';

  @override
  String get chatsBranchedOpen => 'Buksan ang chat na pinagmulan nito';

  @override
  String get chatsBranchedUntitled => 'mas naunang chat';

  @override
  String get chatsEmpty => 'Dito lalabas ang mga usapan mo.';

  @override
  String get chatsGroupOlder => 'Mas luma';

  @override
  String get chatsGroupPinned => 'Naka-pin';

  @override
  String get chatsGroupToday => 'Ngayon';

  @override
  String get chatsGroupWeek => 'Nakaraang 7 araw';

  @override
  String get chatsGroupYesterday => 'Kahapon';

  @override
  String get chatsLimit =>
      'Tatlong chat na ang gumagana. Hintayin munang matapos ang isa, tapos ipadala ulit ito.';

  @override
  String get chatsMore => 'Iba pa tungkol sa chat na ito';

  @override
  String get chatsNeedsOk => 'Kailangan ang OK mo';

  @override
  String get chatsNew => 'Bagong chat';

  @override
  String get chatsNewAnswer => 'Bagong sagot';

  @override
  String get chatsNoResults => 'Walang chat na tumutugma.';

  @override
  String get chatsOpen => 'Mga chat';

  @override
  String get chatsPin => 'I-pin';

  @override
  String get chatsPinnedMark => 'Naka-pin';

  @override
  String get chatsRename => 'Palitan ang pangalan';

  @override
  String get chatsRenameInvalid =>
      'Maglagay ng pangalan na 1 hanggang 80 titik.';

  @override
  String get chatsRenameLabel => 'Pangalan';

  @override
  String get chatsRenameSave => 'I-save ang pangalan';

  @override
  String get chatsRenameTitle => 'Pangalanan ang chat';

  @override
  String get chatsRestore => 'Ibalik';

  @override
  String chatsRowLabel(String title, String when) {
    return '$title, $when';
  }

  @override
  String get chatsSearchClear => 'Burahin ang hinahanap';

  @override
  String get chatsSearchHint => 'Hanapin sa mga chat mo';

  @override
  String get chatsTitle => 'Mga chat';

  @override
  String get chatsUnpin => 'Alisin sa pin';

  @override
  String get chatsUntitled => 'Bagong usapan';

  @override
  String get chatsWorking => 'Ginagawa pa';

  @override
  String get close => 'Isara';

  @override
  String get delete => 'Burahin';

  @override
  String get done => 'Tapos na';

  @override
  String drawerAccountShort(String amount) {
    return 'Kulang ng $amount';
  }

  @override
  String get drawerAccounts => 'Mga account';

  @override
  String get drawerAccountsEmpty => 'Wala pang account.';

  @override
  String get drawerAccountsError => 'Hindi ma-load ang mga account.';

  @override
  String get drawerAccountsOpen => 'Buksan ang lahat ng account';

  @override
  String get entryCurrencyLabel => 'Pera';

  @override
  String get entryCurrencyOther => 'Iba pa…';

  @override
  String expenseAmountError(String code) {
    return 'I-type ang halaga sa $code, tulad ng 180 o 1,250.50.';
  }

  @override
  String get expenseFromAccount => 'Mula sa anong account?';

  @override
  String expenseHowMuch(String code) {
    return 'Magkano? ($code)';
  }

  @override
  String get expenseLogIt => 'Itala';

  @override
  String expenseLogged(String amount) {
    return 'Naitala ang $amount.';
  }

  @override
  String get expenseNoteHint => 'tanghalian';

  @override
  String get expenseNoteLabel => 'Para saan ito? (opsyonal)';

  @override
  String get expenseOffline =>
      'Walang koneksyon. Naka-save sa telepono mo at ipapadala nang isang beses.';

  @override
  String get expensePickAccount => 'Piliin ang account na pinanggalingan nito.';

  @override
  String get expenseTitle => 'Magdagdag ng gastos';

  @override
  String get fileGone => 'Wala na ang file na ito sa phone.';

  @override
  String fileOpen(String name, String size) {
    return '$name, $size. I-tap para i-save o i-share.';
  }

  @override
  String filePicture(String name) {
    return 'Larawan $name';
  }

  @override
  String get fileSave => 'I-save sa phone';

  @override
  String get fileSaveFailed => 'Hindi mabuksan ang share sheet.';

  @override
  String get fileSaved => 'Na-save sa phone mo.';

  @override
  String get fileShare => 'I-share o buksan gamit ang…';

  @override
  String get fixQueued =>
      'Nakasave sa phone na ito ang bagong entry at ipapadala kapag may koneksyon ka na. Mananatili ang lumang entry hangga\'t hindi mo ito ina-undo.';

  @override
  String get goalsAdd => 'Magdagdag ng goal';

  @override
  String get goalsAddButton => 'Idagdag ang goal';

  @override
  String get goalsAddInvalid =>
      'Lagyan ng pangalan, lugar, at mga halaga bilang numero.';

  @override
  String goalsAim(String amount) {
    return ' · target $amount';
  }

  @override
  String get goalsDelete => 'Burahin nang tuluyan';

  @override
  String goalsDeleteBody(String name) {
    return 'Buburahin nang tuluyan ang “$name” at ang anumang payday rule na tumutukoy dito. Mananatili kung nasaan ang perang naipon mo para dito.';
  }

  @override
  String get goalsDeleteTitle => 'Burahin ang goal na ito?';

  @override
  String get goalsDeleteYes => 'Burahin';

  @override
  String get goalsDeleted => 'Nabura na.';

  @override
  String goalsEachPayday(String amount) {
    return '$amount bawat payday';
  }

  @override
  String get goalsEmpty => 'Wala pang goal. Para saan mo gustong mag-ipon?';

  @override
  String get goalsMenu => 'Higit pa tungkol sa goal na ito';

  @override
  String get goalsNameHint => 'Pondo para sa emergency';

  @override
  String get goalsNameLabel => 'Para saan ka nag-iipon?';

  @override
  String get goalsOnlyRules => 'Tanging ibinibigay lang ng mga rule mo';

  @override
  String goalsPerLabel(String currency) {
    return 'Itabi bawat payday ($currency, opsyonal)';
  }

  @override
  String goalsTargetLabel(String currency) {
    return 'Ang halagang gusto mong maabot ($currency, opsyonal)';
  }

  @override
  String get goalsTitle => 'Mga ipon na goal';

  @override
  String get goalsWhere => 'Saan ito nakalagay?';

  @override
  String goalsYear(int count, String amount) {
    return 'Sa isang taon ($count payday) ito ay $amount.';
  }

  @override
  String get healthAbout => 'Mga';

  @override
  String healthAboutTime(String time) {
    return 'Mga $time';
  }

  @override
  String get healthAcceptWeek => 'Tanggapin ang linggong ito';

  @override
  String get healthActivityFeet => 'Madalas nakatayo';

  @override
  String get healthActivitySitting => 'Madalas nakaupo';

  @override
  String get healthActivityVery => 'Napakagalaw';

  @override
  String get healthActivityWalking => 'Medyo naglalakad';

  @override
  String get healthAddByHand => 'Ilagay nang mano-mano';

  @override
  String get healthAddFood => 'Magdagdag ng pagkain';

  @override
  String get healthAddKcal => 'Calorie (kcal)';

  @override
  String get healthAddName => 'Ano ang kinain mo?';

  @override
  String get healthAddNeeds => 'Ilagay ang pangalan at calorie.';

  @override
  String get healthAddProtein => 'Protina sa gramo (opsyonal)';

  @override
  String get healthAddSleep => 'Magdagdag ng tulog';

  @override
  String get healthAddToToday => 'Idagdag ngayong araw';

  @override
  String get healthAddWeight => 'Magdagdag ng timbang';

  @override
  String get healthAskBotler => 'Tanungin si Botler';

  @override
  String get healthBack => 'Bumalik';

  @override
  String healthBedtimeSteady(String time) {
    return 'Nanatili ang oras ng tulog mo sa loob ng mga $time.';
  }

  @override
  String get healthByBotler => 'Gawa ni Botler';

  @override
  String get healthCalories => 'Calorie';

  @override
  String get healthCameraBarcode => 'Barcode';

  @override
  String get healthCameraDenied =>
      'Kailangan ni Botler ang camera para rito. Payagan ito sa settings ng telepono, o ilagay ang pagkain nang mano-mano.';

  @override
  String get healthCameraGallery => 'Pumili sa gallery';

  @override
  String healthCameraHintAngle(String count, String total) {
    return 'Anggulo $count sa $total. Kumuha pa, o pindutin ang Tapos na.';
  }

  @override
  String get healthCameraHintBarcode =>
      'Itutok sa barcode. Kusa itong babasahin.';

  @override
  String get healthCameraHintLabel => 'Ipasok ang buong label sa frame.';

  @override
  String get healthCameraHintMeal =>
      'Kunan mula sa itaas. Nakakatulong ang pangalawang anggulo.';

  @override
  String get healthCameraLabel => 'Label';

  @override
  String get healthCameraMeal => 'Pagkain';

  @override
  String get healthCameraOffline =>
      'Kailangan ng internet para mabasa ang litrato, at walang na-save. Puwede mong ilagay ang pagkain nang mano-mano.';

  @override
  String get healthCameraOfflineTitle => 'Kailangan nito ng internet';

  @override
  String get healthCameraTake => 'Kumuha ng litrato';

  @override
  String get healthCarbs => 'Carbohydrates';

  @override
  String get healthChartEmpty =>
      'Dalawang timbang ang kailangan para sa linya. Puwede kahit anong oras, pero mas madaling ikumpara kung parehong oras araw-araw.';

  @override
  String healthChartLabel(String from, String to) {
    return 'Timbang mo mula $from kilo hanggang $to kilo sa takbo';
  }

  @override
  String get healthCheckInLine => 'May bagong calorie target na titingnan';

  @override
  String get healthCheckInReady => 'Handa na ang weekly check-in mo';

  @override
  String get healthCheckInTitle => 'Weekly check-in';

  @override
  String healthCheckInWhy(String burn) {
    return 'Mukhang mga $burn kada araw ang nasusunog ng katawan mo. Pinapanatili nito ang takbo mo patungo sa goal sa bilis na pinili mo.';
  }

  @override
  String get healthClose => 'Isara';

  @override
  String get healthCorrectBusy => 'Tinitingnan ulit ni Botler';

  @override
  String get healthCorrectHint => 'Tinola iyan, at kalahating tasa ng kanin';

  @override
  String get healthCorrectLabel => 'Ano ba talaga ito?';

  @override
  String get healthCorrectLine =>
      'Sabihin kay Botler kung ano talaga ito, at titingnan niya ulit ang litrato mo. Susuriin mo ang resulta bago may ma-save.';

  @override
  String get healthCorrectSend => 'Ipaayos kay Botler';

  @override
  String get healthCorrectTitle => 'Mali ba?';

  @override
  String healthCouldBe(String low, String high) {
    return 'Puwedeng $low hanggang $high';
  }

  @override
  String get healthDataCredit =>
      'Galing ang datos ng pagkain sa USDA FoodData Central at Open Food Facts. Tantiya lang ang mga lutong Pinoy.';

  @override
  String get healthDayComplete => 'Kumpleto na ang araw';

  @override
  String get healthDayCompleteLine =>
      'I-on kapag naitala na lahat ng kinain mo';

  @override
  String get healthDayDone => 'tapos';

  @override
  String get healthDayPlanned => 'nakaplano';

  @override
  String get healthDayRest => 'pahinga';

  @override
  String healthDayState(String day, String state) {
    return '$day, $state';
  }

  @override
  String get healthDayToday => 'ngayon';

  @override
  String get healthDetailTitle => 'Detalye ngayong araw';

  @override
  String get healthDetails => 'Detalye';

  @override
  String get healthDiscard => 'Itapon';

  @override
  String get healthDiscardBody =>
      'Hindi ise-save ang pagkaing nabasa mula sa litrato.';

  @override
  String get healthDistanceField => 'Layo sa km (hindi kailangan)';

  @override
  String get healthDone => 'Tapos na';

  @override
  String healthDown(String kg) {
    return 'Bumaba ng $kg kg';
  }

  @override
  String get healthEasier => 'Gawing mas madali';

  @override
  String healthEatenKcal(String kcal) {
    return '$kcal kcal ang nakain';
  }

  @override
  String healthEatenOf(String eaten, String target) {
    return '$eaten ang nakain sa $target';
  }

  @override
  String healthExerciseOf(String index, String count) {
    return 'Ehersisyo $index sa $count';
  }

  @override
  String get healthFat => 'Taba';

  @override
  String get healthFibre => 'Fiber';

  @override
  String get healthFieldActivity => 'Gaano ka kagalaw sa karaniwang araw?';

  @override
  String get healthFieldGoalWeight => 'Target na timbang sa kilo';

  @override
  String get healthFieldHeight => 'Taas sa sentimetro';

  @override
  String get healthFieldHeightHint => 'Halimbawa, 168';

  @override
  String get healthFieldSex => 'Kasarian, para lang sa unang tantiya';

  @override
  String get healthFieldWeight => 'Timbang ngayon sa kilo';

  @override
  String get healthFieldWeightHint => 'Halimbawa, 74';

  @override
  String get healthFieldYear => 'Taon ng kapanganakan';

  @override
  String get healthFieldYearHint => 'Halimbawa, 1995';

  @override
  String get healthFinishLater => 'Tapusin mamaya';

  @override
  String get healthFinishSet => 'Tapusin ang set';

  @override
  String get healthFinishWorkout => 'Tapusin ang workout';

  @override
  String get healthFlash => 'Flash';

  @override
  String healthForecastAround(String kg, String date) {
    return '$kg kg sa bandang $date';
  }

  @override
  String get healthForecastAway => 'Lumalayo ang takbo mo sa goal mo';

  @override
  String get healthForecastFar => 'Malayo pa ang goal mo sa bilis na ito';

  @override
  String get healthForecastFlat => 'Hindi nagbabago ang takbo mo';

  @override
  String get healthForecastLine =>
      'Tantiya ayon sa bilis mo nitong mga huling linggo';

  @override
  String get healthForecastNoDate =>
      'Wala pang petsang maibibigay ngayon, at ayos lang iyon.';

  @override
  String get healthForecastReached => 'Nasa goal ka na';

  @override
  String healthFromFoods(String count) {
    return 'Mula sa $count pagkain. Tantiya lang ang mga bilang.';
  }

  @override
  String get healthGoalGain => 'Magdagdag';

  @override
  String get healthGoalLose => 'Magbawas ng timbang';

  @override
  String get healthGoalMaintain => 'Panatilihin';

  @override
  String get healthGoalTrack => 'Itala lang';

  @override
  String healthGrams(String value) {
    return '$value g';
  }

  @override
  String healthGramsOf(String value, String target) {
    return '$value sa $target g';
  }

  @override
  String get healthHalf => 'Kalahati';

  @override
  String get healthHarder => 'Gawing mas mahirap';

  @override
  String get healthHowMuch => 'Gaano karami ang kinain mo?';

  @override
  String get healthIsThisIt => 'Ito ba?';

  @override
  String healthKcal(String value) {
    return '$value kcal';
  }

  @override
  String get healthKcalEaten => 'kcal ang nakain';

  @override
  String get healthKcalLeft => 'kcal ang natitira';

  @override
  String get healthKcalOver => 'kcal';

  @override
  String healthKeepKcal(String kcal) {
    return 'Panatilihin ang $kcal';
  }

  @override
  String get healthKindRun => 'Takbo';

  @override
  String get healthKindWalk => 'Lakad';

  @override
  String healthKnownFor(String known, String total) {
    return 'Alam sa $known ng $total pagkain';
  }

  @override
  String healthLabelBasis(String grams) {
    return 'Para sa $grams g ang mga bilang na ito';
  }

  @override
  String get healthLabelFits => 'Tugma ang calorie sa protina, carbs at taba';

  @override
  String get healthLabelNoFit =>
      'Pakitingnan: hindi tugma ang calorie sa protina, carbs at taba';

  @override
  String get healthLastNightTitle => 'Kagabi';

  @override
  String healthLeftKcal(String kcal) {
    return 'Mga $kcal kcal ang natitira';
  }

  @override
  String healthLeftWordsAbout(String kcal) {
    return 'Mga $kcal kcal';
  }

  @override
  String get healthLess => 'Bawasan';

  @override
  String healthLevelUp(String names) {
    return 'Sa susunod: $names';
  }

  @override
  String get healthLogFood => 'Itala ang pagkain';

  @override
  String get healthLogWalkTitle => 'I-log ang lakad o takbo';

  @override
  String get healthLowIntake =>
      'Napakakaunti ng kinakain mo ngayong linggo. Mahirap ito sa katawan. Makakatulong na kausapin ang doktor o isang pinagkakatiwalaan mo.';

  @override
  String healthMacroLine(String protein, String carbs, String fat) {
    return 'Protina $protein g · Carbs $carbs g · Taba $fat g';
  }

  @override
  String get healthMacroSplit => 'Saan galing ang mga calorie';

  @override
  String get healthMealBreakfast => 'Almusal';

  @override
  String get healthMealDinner => 'Hapunan';

  @override
  String get healthMealFoods => 'Mga pagkain sa kainang ito';

  @override
  String get healthMealLunch => 'Tanghalian';

  @override
  String get healthMealMerienda => 'Merienda';

  @override
  String healthMealOfDay(String percent) {
    return '$percent% ng target mo ngayon';
  }

  @override
  String get healthMealPhoto => 'Ang litrato ng pagkain mo';

  @override
  String get healthMealSnack => 'Meryenda';

  @override
  String healthMilligrams(String value) {
    return '$value mg';
  }

  @override
  String get healthMinutesBad => 'Ilagay ang minuto, gaya ng 30';

  @override
  String get healthMinutesField => 'Minuto';

  @override
  String healthMinutesLabel(String done, String goal) {
    return '$done sa $goal minutong gumagalaw ngayong linggo';
  }

  @override
  String get healthMinutesMoving => 'minutong gumagalaw';

  @override
  String healthMinutesOf(String done, String goal) {
    return '$done sa $goal';
  }

  @override
  String get healthMore => 'Dagdagan';

  @override
  String healthMoveTo(String time) {
    return 'Ilipat sa $time';
  }

  @override
  String healthNeedsMove(String title, String day) {
    return 'Kailangang ilipat ang $title sa $day';
  }

  @override
  String get healthNeedsMoveLine => 'Nagbago ang libreng oras mo.';

  @override
  String get healthNewWeek => 'Planuhin ulit';

  @override
  String get healthNext => 'Susunod';

  @override
  String healthNextAt(String day, String time) {
    return '$day, $time';
  }

  @override
  String get healthNextWeek => 'Susunod na linggo';

  @override
  String healthNoFit(String titles) {
    return 'Walang libreng oras para sa: $titles';
  }

  @override
  String get healthNoRoom =>
      'Walang oras na kasya sa araw na iyon. Puwede mo itong laktawan.';

  @override
  String get healthNotFoundLine =>
      'Kunan ng litrato ang nutrition label. Babasahin ito ni Botler at tatandaan ang produkto sa susunod.';

  @override
  String get healthNotFoundTitle => 'Wala pa ang produktong ito sa datos';

  @override
  String get healthNotMedical =>
      'Pangkalahatang gabay ang bigay ni Botler, hindi payong medikal. Kung may kondisyon ka o umiinom ng gamot, kumonsulta muna sa doktor.';

  @override
  String get healthNotThisProduct => 'Hindi ito ang produkto';

  @override
  String get healthOffCredit =>
      'May datos mula sa Open Food Facts, sa ilalim ng Open Database License. Puwedeng baguhin ng kahit sino ang datos na ito, kaya pakitingnan kung tama.';

  @override
  String get healthOilLine =>
      'Mahirap makita ang mantika, at ito ang pinakamalaking dagdag sa calorie.';

  @override
  String get healthOilLots => 'Mga dalawang kutsara';

  @override
  String get healthOilName => 'Mantika';

  @override
  String get healthOilNone => 'Walang dagdag na mantika';

  @override
  String get healthOilQuestion => 'Niluto ba ito sa mantika?';

  @override
  String get healthOilSome => 'Mga isang kutsara';

  @override
  String get healthOneServing => 'Isa';

  @override
  String get healthOverBy => 'Sobra nang mga';

  @override
  String get healthPaceFastest => 'Pinakamabilis na pinapayagan';

  @override
  String get healthPaceGentle => 'Dahan-dahan';

  @override
  String get healthPaceSteady => 'Katamtaman';

  @override
  String get healthPaceTitle => 'Gaano kabilis?';

  @override
  String get healthPainNote =>
      'Kung may masakit, tumigil at palitan ito. Kung bumabalik ang sakit, magpatingin sa clinician.';

  @override
  String healthPathNext(String high, String next) {
    return 'Abutin ang $high sa lahat ng set at susunod na ang $next.';
  }

  @override
  String get healthPathTop =>
      'Ito na ang pinakamahirap na bersyon dito. Dahan-dahan lang.';

  @override
  String healthPatternLine(String kcal) {
    return 'Pagkatapos ng mga gabing wala pang 6 na oras, mga $kcal kcal ang nadagdag sa kinain mo. Maaaring hindi lang ito ang dahilan.';
  }

  @override
  String get healthPatternTitle => 'Isang pattern na dapat pansinin';

  @override
  String healthPer100(String kcal) {
    return '$kcal kcal bawat 100 g';
  }

  @override
  String get healthPhotoFailedLine =>
      'Walang nakitang pagkain si Botler, at walang na-save. Subukan ulit na kita ang buong plato at mas maliwanag.';

  @override
  String get healthPhotoFailedTitle => 'Hindi gumana ang litrato';

  @override
  String get healthPhotoLabel => 'Ang litrato mo';

  @override
  String get healthPhotoSettingTitle =>
      'Pribado ang mga litrato sa settings mo';

  @override
  String get healthPlanNextWeek => 'I-plano ang susunod na linggo';

  @override
  String get healthPlanRest => 'Pahinga';

  @override
  String healthPlanWhen(String minutes, String time) {
    return '$minutes min, $time';
  }

  @override
  String healthPreviewKcal(String kcal) {
    return 'Mga $kcal kcal sa isang araw';
  }

  @override
  String healthPreviewReach(String kg, String date) {
    return 'Mga $kg kg sa isang linggo, at maaabot ang target bandang $date. Gaganda ang tantiyang ito habang nagtatala ka.';
  }

  @override
  String get healthPreviewTitle => 'Ibig sabihin nito para sa iyo';

  @override
  String get healthProgramWarning =>
      'May tumatakbong ibang programa. Idadagdag nito ang mga session sa bawat linggo.';

  @override
  String healthProgramWeek(String week, String weeks) {
    return 'Linggo $week sa $weeks';
  }

  @override
  String get healthProgramsNone =>
      'Pumili kapag handa ka na. Parehong walang kailangang gamit.';

  @override
  String get healthProtein => 'Protina';

  @override
  String healthProteinShort(String value) {
    return '$value g protina';
  }

  @override
  String get healthReadLabel => 'Basahin ang label';

  @override
  String get healthReadingLine =>
      'Hinahanap ang mga pagkain at tinitingnan ang sustansya.';

  @override
  String get healthReadingTitle => 'Pagkain mo';

  @override
  String get healthReadyLine =>
      'Kung oo ang sagot mo sa alinman dito, kausapin muna ang isang clinician.';

  @override
  String get healthReadyNo => 'Hindi muna';

  @override
  String get healthReadyTitle => 'Bago ka magsimula';

  @override
  String get healthReadyYes => 'Lahat hindi, simulan';

  @override
  String get healthRecent => 'Ngayong linggo';

  @override
  String get healthRecentWeights => 'Mga huling timbang';

  @override
  String get healthRemove => 'Alisin';

  @override
  String get healthRemoveWeight => 'Tanggalin ang timbang na ito';

  @override
  String get healthRemoveWeightBody => 'Aalis na ito sa trend mo nang tuluyan.';

  @override
  String get healthRepsAsk => 'Ilan ang nagawa mo?';

  @override
  String get healthRestDay => 'Araw ng pahinga';

  @override
  String healthRestLeft(String time) {
    return 'Pahinga, $time pa';
  }

  @override
  String get healthRestLine =>
      'Walang plano ngayon. Bilang pa rin ang lakad kung gusto mo.';

  @override
  String get healthResume => 'Balik sa workout mo';

  @override
  String get healthReviewAsk => 'Tanungin si Botler';

  @override
  String get healthReviewDone => 'Sige';

  @override
  String healthReviewFood(String days, String kcal) {
    return 'Naka-log ang pagkain sa $days araw, mga $kcal kcal bawat araw';
  }

  @override
  String healthReviewMoved(String minutes, String days) {
    return '$minutes minutong gumagalaw, $days araw ng strength';
  }

  @override
  String get healthReviewNoFood => 'Walang buong araw ng pagkain na naka-log';

  @override
  String healthReviewSleep(String time) {
    return 'Mga $time na tulog bawat gabi';
  }

  @override
  String get healthReviewTitle => 'Ang linggo mo';

  @override
  String healthRingLabel(String percent) {
    return '$percent porsyento ng calorie target';
  }

  @override
  String healthRunSteps(String run, String walk, String repeat) {
    return 'Takbo $run, lakad $walk, $repeat beses';
  }

  @override
  String healthRunTotal(String minutes) {
    return 'Mga $minutes minuto lahat';
  }

  @override
  String get healthRunWarm =>
      'Maglakad muna ng 5 minuto at 5 minuto pagkatapos.';

  @override
  String get healthSatFat => 'Saturated fat';

  @override
  String get healthSave => 'I-save';

  @override
  String get healthSaveMeal => 'I-save ang pagkain';

  @override
  String get healthSaveSleep => 'I-save ang tulog';

  @override
  String get healthSavedOffline =>
      'Naka-save sa telepono. Ipapadala ito pagbalik ng internet.';

  @override
  String healthScaleToday(String kg) {
    return 'Timbang ngayon: $kg kg. Karamihan sa araw-araw na pagbabago ay tubig lang, kaya ang linya ang mahalaga.';
  }

  @override
  String get healthScanBarcode => 'Mag-scan ng barcode';

  @override
  String get healthSecondsAsk => 'Ilang segundo?';

  @override
  String healthSecondsShort(String seconds) {
    return '$seconds s';
  }

  @override
  String healthSessionMinutes(String title, String minutes) {
    return '$title, $minutes minuto';
  }

  @override
  String healthSetDoneLabel(String index, String value) {
    return 'Set $index, $value tapos';
  }

  @override
  String healthSetOpenLabel(String index, String value) {
    return 'Set $index, abutin ang $value';
  }

  @override
  String healthSetsOfHolds(String sets, String low, String high) {
    return '$sets hold ng $low hanggang $high segundo.';
  }

  @override
  String healthSetsOfReps(String sets, String low, String high) {
    return '$sets set ng $low hanggang $high.';
  }

  @override
  String get healthSetupAboutLine =>
      'Itatama ito ng totoong takbo ng timbang mo pagkalipas ng ilang linggo, kaya ayos na ang malapit.';

  @override
  String get healthSetupAboutTitle => 'Ilang detalye muna';

  @override
  String get healthSetupGoalTitle => 'Ano ang gusto mong gawin?';

  @override
  String get healthSetupPrompt => 'Tapusin ang setup ng Kalusugan';

  @override
  String get healthSetupPromptLine =>
      'Isang minuto lang, o sabihin kay Botler sa chat';

  @override
  String get healthSetupTitle => 'I-set up ang Kalusugan';

  @override
  String get healthSevenNights => 'Huling 7 gabi';

  @override
  String get healthSexFemale => 'Babae';

  @override
  String get healthSexMale => 'Lalaki';

  @override
  String get healthSexSkip => 'Laktawan';

  @override
  String get healthSkip => 'Laktawan';

  @override
  String get healthSleepBars => 'Oras ng tulog nitong mga huling gabi';

  @override
  String get healthSleepChart =>
      'Oras ng tulog at gising nitong mga huling gabi';

  @override
  String get healthSleepEmpty =>
      'Wala pang naka-log na tulog. Sabihin sa chat ang \"natulog ako 11 hanggang 6\", o idagdag dito.';

  @override
  String get healthSleepFrom => 'Natulog';

  @override
  String get healthSleepTitle => 'Tulog';

  @override
  String get healthSleepTo => 'Gumising';

  @override
  String get healthSodium => 'Sodium';

  @override
  String get healthSourceEstimate => 'Tantiya ng AI';

  @override
  String get healthSourceFilipino => 'Listahang Pinoy';

  @override
  String get healthSourceLabel => 'Mula sa label';

  @override
  String get healthSourceSaved => 'Naka-save';

  @override
  String get healthSourceYours => 'Bilang mo';

  @override
  String get healthStart => 'Simulan';

  @override
  String healthStartProgram(String name) {
    return 'Simulan ang $name';
  }

  @override
  String healthStartSession(String title) {
    return 'Simulan ang $title';
  }

  @override
  String get healthStartWalk => 'I-log ang lakad';

  @override
  String get healthSteady => 'Hindi nagbago';

  @override
  String healthStepOf(String step) {
    return '$step sa 2';
  }

  @override
  String get healthStopProgram => 'Itigil ang programang ito';

  @override
  String get healthStrengthDays => 'araw ng strength';

  @override
  String healthStrengthLabel(String done, String goal) {
    return '$done sa $goal araw ng strength ngayong linggo';
  }

  @override
  String get healthSugar => 'Asukal';

  @override
  String get healthSuggestFood =>
      'Subukang mag-log ng ilan pang buong araw para makatulong ang mga numero.';

  @override
  String get healthSuggestKeep => 'Ituloy mo lang ang ginagawa mo.';

  @override
  String get healthSuggestMove => 'Subukan ang isa pang lakad ngayong linggo.';

  @override
  String get healthSuggestSleep =>
      'Subukang matulog nang mas maaga nang kaunti ngayong linggo.';

  @override
  String get healthSuggestWeigh =>
      'Subukang magtimbang nang mas madalas para mas malinaw ang takbo.';

  @override
  String get healthSwap => 'Palitan';

  @override
  String get healthTakeAnother => 'Kumuha ng panibagong litrato';

  @override
  String healthTileEaten(String kcal) {
    return 'Mga $kcal kcal';
  }

  @override
  String healthTileFreeToday(String from, String to) {
    return 'Libre ngayon mula $from hanggang $to';
  }

  @override
  String get healthTileLastNight => 'Kagabi';

  @override
  String healthTileLeft(String kcal) {
    return 'Mga $kcal pa ang natitira';
  }

  @override
  String get healthTileNoFree => 'Wala nang libreng oras ngayon';

  @override
  String get healthTileNoPlan => 'Walang plano';

  @override
  String healthTileOfTarget(String eaten, String target) {
    return '$eaten sa $target kcal';
  }

  @override
  String healthTileOver(String kcal) {
    return 'Mga $kcal ang sobra';
  }

  @override
  String get healthTileSleep => 'Tulog';

  @override
  String get healthTileSleepEmpty => 'Sabihin kay Botler ang tulog mo';

  @override
  String get healthTileToday => 'Ngayon';

  @override
  String get healthTileTodayEmpty => 'Wala pang naitala';

  @override
  String get healthTileTrain => 'Ehersisyo';

  @override
  String get healthTileTrainEmpty => 'Magplano ng linggo ayon sa trabaho mo';

  @override
  String get healthTileWeek => 'Linggo ko';

  @override
  String get healthTileWeekEmpty => 'Ilagay ang oras ng trabaho';

  @override
  String get healthTileWeight => 'Timbang';

  @override
  String get healthTileWeightEmpty => 'Ilagay ang unang timbang mo';

  @override
  String get healthTitle => 'Kalusugan';

  @override
  String healthTodayAt(String time) {
    return 'Ngayon, $time';
  }

  @override
  String get healthTodayDone => 'Tapos na ngayon';

  @override
  String get healthTodayEmptyLine =>
      'Kunan ng litrato ang pagkain mo, o sabihin kay Botler ang kinain mo.';

  @override
  String healthTodayProgram(String name) {
    return 'Tumatakbo ang $name';
  }

  @override
  String get healthTodayProgramLine =>
      'Wala pang nakatakda ngayon. I-plano ang susunod na linggo at ilalagay ni Botler ang mga session sa paligid ng araw mo.';

  @override
  String get healthTodayRoutine => 'Ang routine mo ngayon';

  @override
  String healthTodayRoutineItem(String time, String title) {
    return '$time, $title';
  }

  @override
  String get healthTodayRoutineLine =>
      'Galing sa mga routine mo. I-log pagkatapos para mabilang dito.';

  @override
  String get healthTodayRunning => 'May session na tumatakbo';

  @override
  String get healthTodayRunningLine => 'Ituloy kung saan ka huminto.';

  @override
  String get healthTotalWeight =>
      'Tinimbang mo ba? Kabuuang timbang sa gramo (opsyonal)';

  @override
  String get healthTrainTitle => 'Ehersisyo';

  @override
  String healthTryKcal(String kcal) {
    return 'Subukan ang $kcal kcal bawat araw';
  }

  @override
  String get healthTwoServings => 'Dalawa';

  @override
  String get healthUndo => 'Bawiin';

  @override
  String get healthUnknown => 'Hindi alam';

  @override
  String healthUp(String kg) {
    return 'Tumaas ng $kg kg';
  }

  @override
  String healthUseKcal(String kcal) {
    return 'Gamitin ang $kcal';
  }

  @override
  String get healthVitamins => 'Mga bitamina at mineral';

  @override
  String get healthWalkSave => 'I-save';

  @override
  String get healthWeekAccepted =>
      'Naka-set na ang linggo mo. May paalala bago ang bawat isa.';

  @override
  String get healthWeekAddBlock => 'Magdagdag ng oras';

  @override
  String get healthWeekAddOnce => 'Magdagdag ng pagbabago para sa isang araw';

  @override
  String get healthWeekAwake => 'Oras na gising';

  @override
  String get healthWeekAwakeFrom => 'Baguhin ang oras ng gising';

  @override
  String get healthWeekAwakeTo => 'Baguhin ang oras ng tulog';

  @override
  String healthWeekBusyLine(String ranges) {
    return 'Abala $ranges';
  }

  @override
  String get healthWeekCopy => 'Kopyahin sa Martes hanggang Biyernes';

  @override
  String get healthWeekFree => 'Libre buong araw';

  @override
  String get healthWeekFrom => 'Mula';

  @override
  String get healthWeekIntro =>
      'Nakaplano ayon sa trabaho at kalendaryo mo. Walang mase-set hangga\'t di mo tinatanggap.';

  @override
  String get healthWeekLegendBusy => 'Abala';

  @override
  String get healthWeekLegendFree => 'Libre';

  @override
  String get healthWeekLegendWork => 'Trabaho';

  @override
  String get healthWeekLine =>
      'Dito ibinabatay ni Botler ang ehersisyo at paalala. Puwede mo ring sabihin na lang sa chat.';

  @override
  String healthWeekMinutes(String minutes) {
    return '$minutes minuto';
  }

  @override
  String get healthWeekOff => 'Walang pasok';

  @override
  String get healthWeekOnce => 'Ngayon lang';

  @override
  String get healthWeekOverlap =>
      'May dalawang oras sa araw na ito na nagtatagpo. Baguhin ang isa para hindi magpatong.';

  @override
  String healthWeekRange(String from, String to) {
    return '$from hanggang $to';
  }

  @override
  String get healthWeekReady => 'Handa na ang bagong linggo ng workouts';

  @override
  String get healthWeekReadyLine =>
      'Walang mase-set hangga\'t di mo tinatanggap';

  @override
  String get healthWeekSameTime =>
      'Hindi puwedeng magsimula at magtapos sa parehong minuto.';

  @override
  String get healthWeekSave => 'I-save ang linggo ko';

  @override
  String get healthWeekSaved => 'Na-save ang linggo mo.';

  @override
  String get healthWeekTitle => 'Linggo ko';

  @override
  String get healthWeekTo => 'Hanggang';

  @override
  String get healthWeekTravel => 'Biyahe papunta at pauwi';

  @override
  String get healthWeekWorking => 'May pasok ako sa araw na ito';

  @override
  String get healthWeightBad => 'Ilagay ang timbang mo sa kilo, gaya ng 74.2';

  @override
  String get healthWeightKg => 'Timbang sa kg';

  @override
  String get healthWeightQueued =>
      'Naka-save sa phone na ito. Maa-upload pagbalik ng internet.';

  @override
  String get healthWeightSpark => 'Takbo ng timbang mo';

  @override
  String get healthWeightTitle => 'Timbang';

  @override
  String get healthWeightToday => 'Timbang mo ngayon';

  @override
  String healthWindDownBy(String time) {
    return 'Mag-wind down bago mag-$time';
  }

  @override
  String get healthWindDownNoEarly => 'Walang maagang simula bukas';

  @override
  String get healthWindDownNone => 'Paalala sa wind-down';

  @override
  String get healthWindDownSwitch => 'Paalala sa wind-down';

  @override
  String healthWindDownWhy(String time) {
    return 'Magsisimula ka ng $time bukas';
  }

  @override
  String get healthWokeToday => 'Gumising ngayon';

  @override
  String get healthWorkingOnIt => 'Inaasikaso na';

  @override
  String healthWorkoutMinutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get healthWorkoutSaved => 'Naka-save. Salamat sa pagpunta.';

  @override
  String get healthYourPath => 'Ang landas mo';

  @override
  String get healthYourPrograms => 'Mga programa mo';

  @override
  String get healthYourTrend => 'Takbo ng timbang mo';

  @override
  String get histEntryTitle => 'Mga detalye';

  @override
  String get historyAccountFallback => 'account';

  @override
  String get historyEmpty => 'Wala pa rito.';

  @override
  String get historyFixThis => 'Ayusin ito';

  @override
  String get historyMore => 'Higit pa';

  @override
  String historyMoved(String from, String to) {
    return 'Inilipat mula $from → $to';
  }

  @override
  String historyOtherCurrencies(String currencies) {
    return 'May gastos din sa $currencies. Hindi ito idinagdag dito.';
  }

  @override
  String get historySearchHint => 'Hanapin ayon sa tala, kategorya o halaga';

  @override
  String get historySpentThisMonth => 'Nagastos ngayong buwan';

  @override
  String get historyTitle => 'Kasaysayan';

  @override
  String get historyUndoneSaid => 'Nabawi na.';

  @override
  String get historyUndoneTag => 'binawi';

  @override
  String historyUntracked(String amount) {
    return '$amount ang hindi nasubaybayan (nakita noong binilang mo ang isang account).';
  }

  @override
  String libraryActionsFor(String title) {
    return 'Iba pang gawin sa $title';
  }

  @override
  String get libraryActivity => 'Mga kamakailang pagbabago ni Botler';

  @override
  String libraryActivityAll(int count) {
    return 'Ipakita lahat ($count)';
  }

  @override
  String get libraryActivityFewer => 'Ipakita ang kaunti';

  @override
  String libraryActivityLine(String page, String notebook) {
    return 'Binago ni Botler ang $page sa $notebook';
  }

  @override
  String libraryAgoDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count araw ang nakalipas',
      one: '1 araw ang nakalipas',
    );
    return '$_temp0';
  }

  @override
  String libraryAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count oras ang nakalipas',
      one: '1 oras ang nakalipas',
    );
    return '$_temp0';
  }

  @override
  String libraryAgoMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minuto ang nakalipas',
      one: '1 minuto ang nakalipas',
    );
    return '$_temp0';
  }

  @override
  String get libraryAgoNow => 'ngayon lang';

  @override
  String get libraryAsk => 'Utusan si Botler na mag-ayos ng laman';

  @override
  String get libraryEmpty =>
      'Wala pang notebook. Ipasimula kay Botler ang isa para sa biyahe, proyekto o listahan.';

  @override
  String get libraryMain => 'Pangunahing kuwaderno';

  @override
  String get libraryMainLine => 'Ang inaalala ni Botler tungkol sa iyo';

  @override
  String get libraryNeedsConnection =>
      'Kailangan nito ng koneksyon. Subukan muli kapag online ka na.';

  @override
  String get libraryNotebooks => 'Mga kuwaderno';

  @override
  String get libraryOffline => 'Kopyang offline';

  @override
  String libraryOfflineSince(String when) {
    return 'Kopyang offline mula $when';
  }

  @override
  String libraryOpenNotebook(String title) {
    return 'Buksan ang kuwaderno $title';
  }

  @override
  String libraryOpenPage(String title) {
    return 'Buksan ang pahina $title';
  }

  @override
  String libraryPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pahina',
      one: '1 pahina',
    );
    return '$_temp0';
  }

  @override
  String get libraryPinned => 'Naka-pin';

  @override
  String get libraryPinnedRecent => 'Naka-pin at kamakailan';

  @override
  String get libraryQueued =>
      'Walang koneksyon. Itinabi sa telepono mo ang pagbabago at ipapadala ito nang isang beses.';

  @override
  String get librarySearchClear => 'Burahin';

  @override
  String get librarySearchFailed =>
      'Hindi gumana ang paghahanap. Subukan ulit.';

  @override
  String get librarySearchHint => 'Maghanap sa mga kuwaderno mo';

  @override
  String get librarySearchMore =>
      'May iba pang tugma. Magdagdag ng salita para paliitin.';

  @override
  String get librarySearchNone => 'Walang nakita.';

  @override
  String get librarySearchOffline =>
      'Kailangan ng koneksyon ang paghahanap. Mababasa mo pa rin ang mga pahina offline.';

  @override
  String get librarySearchPrompt =>
      'Mag-type ng hindi bababa sa dalawang titik, saka pindutin ang hanapin.';

  @override
  String get librarySearchTitle => 'Hanapin';

  @override
  String get libraryTitle => 'Mga kuwaderno';

  @override
  String get libraryUndo => 'I-undo';

  @override
  String libraryUndoFor(String page) {
    return 'I-undo ang pagbabago ni Botler sa $page';
  }

  @override
  String get libraryUpdateServer =>
      'Mas luma ang server kaysa sa app na ito at hindi pa nito maipapakita ang mga pahina. I-update ang server.';

  @override
  String get libraryUpdated => 'Binago ni Botler';

  @override
  String get lockContinueWithout => 'Magpatuloy nang walang lock';

  @override
  String get lockNoScreenLock =>
      'Walang screen lock ang phone na ito, kaya hindi makahingi ang Botler ng fingerprint, mukha o PIN.';

  @override
  String get lockReason => 'Buksan ang Botler';

  @override
  String get lockTitle => 'Naka-lock ang Botler';

  @override
  String get lockUnlock => 'I-unlock';

  @override
  String get markChangePicture => 'Pumili ng ibang larawan';

  @override
  String get markChoosePicture => 'Pumili ng larawan';

  @override
  String markEditTitle(String name) {
    return 'Icon ng $name';
  }

  @override
  String get markIconBaby => 'Sanggol';

  @override
  String get markIconBank => 'Bangko';

  @override
  String get markIconBolt => 'Kuryente';

  @override
  String get markIconBus => 'Sakay';

  @override
  String get markIconCar => 'Kotse';

  @override
  String get markIconCard => 'Card';

  @override
  String get markIconCart => 'Grocery';

  @override
  String get markIconCash => 'Pera';

  @override
  String get markIconCoffee => 'Kape';

  @override
  String get markIconCrypto => 'Crypto';

  @override
  String get markIconFamily => 'Pamilya';

  @override
  String get markIconFlag => 'Bandila';

  @override
  String get markIconFood => 'Pagkain';

  @override
  String get markIconFuel => 'Gasolina';

  @override
  String get markIconGame => 'Laro';

  @override
  String get markIconGift => 'Regalo';

  @override
  String get markIconGym => 'Gym';

  @override
  String get markIconHealth => 'Kalusugan';

  @override
  String get markIconHeart => 'Puso';

  @override
  String get markIconHome => 'Bahay';

  @override
  String get markIconInsurance => 'Insurance';

  @override
  String get markIconInvest => 'Puhunan';

  @override
  String get markIconLoan => 'Utang';

  @override
  String get markIconPet => 'Alaga';

  @override
  String get markIconPhone => 'Telepono';

  @override
  String get markIconPiggy => 'Alkansya';

  @override
  String get markIconRent => 'Upa';

  @override
  String get markIconSavings => 'Ipon';

  @override
  String get markIconSchool => 'Paaralan';

  @override
  String markIconSemantic(String name) {
    return 'Icon: $name';
  }

  @override
  String get markIconShopping => 'Pamimili';

  @override
  String get markIconStar => 'Bituin';

  @override
  String get markIconSubscription => 'Subscription';

  @override
  String get markIconTax => 'Buwis';

  @override
  String get markIconTools => 'Pagkukumpuni';

  @override
  String get markIconTravel => 'Biyahe';

  @override
  String get markIconTv => 'TV';

  @override
  String get markIconWallet => 'Pitaka';

  @override
  String get markIconWater => 'Tubig';

  @override
  String get markIconWifi => 'Internet';

  @override
  String get markIconWork => 'Trabaho';

  @override
  String get markMenu => 'Baguhin ang icon o larawan';

  @override
  String get markNone => 'Walang icon';

  @override
  String get markPictureChosen => 'Ang larawan mo';

  @override
  String get markPictureFailed =>
      'Hindi magamit ang larawang iyon. Subukan ang iba.';

  @override
  String get markPictureNote =>
      'Ang larawang pipiliin mo ay para sa iyo lang. Hindi ito nakikita ng assistant ng Botler.';

  @override
  String get markRemove => 'Alisin ang icon o larawan';

  @override
  String get markSaved => 'Na-save.';

  @override
  String markSemantic(String name) {
    return 'Icon ng $name';
  }

  @override
  String get markTitle => 'Icon o larawan';

  @override
  String get mdBold => 'Makapal';

  @override
  String get mdCheckbox => 'Checkbox';

  @override
  String get mdHeading => 'Pamagat';

  @override
  String get mdLink => 'Link';

  @override
  String get mdList => 'Listahan';

  @override
  String get mdPageLink => 'Link sa pahina';

  @override
  String get memoryCopied => 'Nakopya ang lahat sa clipboard.';

  @override
  String get memoryCopyAll =>
      'Kopyahin ang lahat (kuwaderno at pera) bilang teksto';

  @override
  String get memoryMore => 'Higit pa';

  @override
  String get memoryPeopleHint => 'Mama, Ate Liza';

  @override
  String get memoryPeopleNote =>
      'Itinatago ni Botler ang mga pangalang ito sa AI na sumusulat ng mga sagot niya.';

  @override
  String get memorySaved => 'Nai-save na.';

  @override
  String get memoryWipe => 'Burahin';

  @override
  String get memoryWipeBody =>
      'Buburahin nito ang kuwaderno mo at ang mga pagbabago nito, at ang mga usapan ninyo ni Botler. Mananatili ang mga pribadong pangalan, mga account, bill at ang iba pa sa pera mo.';

  @override
  String get memoryWipeButton => 'Burahin ang kuwaderno at mga usapan';

  @override
  String get memoryWipeTitle => 'Burahin ang lahat ng natatandaan ni Botler?';

  @override
  String get memoryWipeType => 'I-type ang WIPE para kumpirmahin';

  @override
  String get memoryWipeWord => 'WIPE';

  @override
  String get memoryWiped => 'Nabura na.';

  @override
  String get menuAccounts => 'Mga account';

  @override
  String get menuAccountsLine => 'Ang laman ng bawat account mo';

  @override
  String get menuAgenda => 'Agenda';

  @override
  String get menuAgendaLine => 'Mga gawain, event, routine at paalala';

  @override
  String get menuBills => 'Mga bill';

  @override
  String get menuBillsLine => 'Ang mga due, at i-mark na bayad na';

  @override
  String get menuCalendar => 'Kalendaryo';

  @override
  String get menuCalendarLine => 'Mga bill, sweldo, event at routine kada araw';

  @override
  String get menuGoals => 'Mga ipon';

  @override
  String get menuGoalsLine => 'Ang iniipon mo';

  @override
  String get menuHealth => 'Kalusugan';

  @override
  String get menuHealthLine => 'Pagkain, timbang, ehersisyo at tulog';

  @override
  String get menuHistory => 'Kasaysayan';

  @override
  String get menuHistoryLine => 'Lahat ng ginastos mo, at i-undo';

  @override
  String get menuNotebook => 'Kuwaderno';

  @override
  String get menuNotebookLine =>
      'Ang itinatago ni Botler sa isip tungkol sa iyo';

  @override
  String get menuPayday => 'Sweldo';

  @override
  String get menuPaydayLine =>
      'Hatiin ang sweldo mo, at ang mga patakaran nito';

  @override
  String get menuSettings => 'Mga setting';

  @override
  String get menuSettingsLine => 'Wika, pera, lock, notification, itsura';

  @override
  String get menuSimulate => 'Time travel';

  @override
  String get menuSimulateLine =>
      'Ang pera mo sa kahit anong araw, nakaraan o darating';

  @override
  String get menuTitle => 'Menu';

  @override
  String netGross(String amount) {
    return 'Balanse $amount';
  }

  @override
  String get netGroupOwed => 'Dapat bayaran na';

  @override
  String get netGroupSetAside => 'Nakatabi para sa susunod';

  @override
  String netHeldBill(String label, String date) {
    return '$label, due sa $date';
  }

  @override
  String netHeldBillLate(String label, String date) {
    return '$label, huli na mula $date';
  }

  @override
  String netHeldGoal(String label) {
    return 'Nakalaan para sa goal: $label';
  }

  @override
  String get netHeldNothing => 'Walang nakalaan: net lahat ito.';

  @override
  String netHeldRule(String label, String date) {
    return '$label, inipon para sa bayarin na due sa $date';
  }

  @override
  String get netHeldTitle => 'Nakalaan sa wallet na ito';

  @override
  String get netNetNow => 'Net ngayon';

  @override
  String netShortfall(String amount) {
    return 'Kulang ng $amount para sa mga bayarin bago ang sahod';
  }

  @override
  String get netShowGross => 'Ipakita ang balanseng binilang';

  @override
  String get netShowNet => 'Ipakita ang net na balanse';

  @override
  String netSpentSetAside(String amount) {
    return '$amount na nakatabi rito ay nagastos na';
  }

  @override
  String get netTakenBy => 'Kinuha rito ng';

  @override
  String netTakenMore(int count) {
    return '+$count pa, buksan ang account para makita lahat';
  }

  @override
  String get netTotalTitle => 'Net, pagkatapos ng bayarin at goal';

  @override
  String get netUnavailable =>
      'Hindi makuha ang net na balanse ngayon. Ipinapakita ang balanseng binilang.';

  @override
  String get no => 'Hindi';

  @override
  String get notebookByBotler => 'Botler';

  @override
  String get notebookBySeed => 'Pag-aayos';

  @override
  String get notebookByYou => 'Ikaw';

  @override
  String get notebookChanges => 'Mga pagbabago';

  @override
  String get notebookChangesEmpty => 'Wala pang pagbabago.';

  @override
  String notebookChars(String count) {
    return '$count karakter';
  }

  @override
  String get notebookConflictBody =>
      'Binago ito ni Botler, o ng ibang telepono, pagkabukas mo. Nandito pa rin ang isinulat mo. Kopyahin ito, o i-save sa ibabaw ng bagong bersyon: mananatili sa Mga pagbabago ang kabilang pagbabago.';

  @override
  String get notebookConflictCopy => 'Kopyahin ang akin';

  @override
  String get notebookConflictSave => 'I-save ang akin';

  @override
  String get notebookConflictTitle => 'Nagbago ang kuwaderno';

  @override
  String get notebookCopiedText => 'Nakopya ang isinulat mo.';

  @override
  String notebookCount(String count, String max) {
    return '$count sa $max na character';
  }

  @override
  String get notebookCreate => 'Gumawa';

  @override
  String get notebookDelete => 'Burahin ang kuwaderno';

  @override
  String get notebookDeleteBody =>
      'Itatago ito at hihinto si Botler sa paggamit nito. Maibabalik mo ito mula sa Mga binurang kuwaderno sa loob ng 30 araw.';

  @override
  String get notebookDeleteTitle => 'Burahin ang kuwaderno na ito?';

  @override
  String get notebookDeleted => 'Mga binurang kuwaderno';

  @override
  String get notebookDeletedDone => 'Nabura na.';

  @override
  String get notebookDeletedEmpty => 'Walang binurang kuwaderno.';

  @override
  String get notebookDescribe => 'Pangalan at buod';

  @override
  String get notebookDiscardBody => 'Mawawala ang mga pagbabagong tinype mo.';

  @override
  String get notebookDiscardTitle => 'Aalis nang hindi nagse-save?';

  @override
  String get notebookDiscardYes => 'Umalis';

  @override
  String get notebookEdit => 'Baguhin';

  @override
  String get notebookEditHint =>
      'Isulat ang dapat tandaan ni Botler tungkol sa iyo';

  @override
  String get notebookEditTitle => 'Baguhin ang kuwaderno mo';

  @override
  String get notebookEmpty =>
      'Wala pa rito. Sabihan si Botler ng dapat tandaan, o i-tap ang Baguhin.';

  @override
  String get notebookExport => 'Kopyahin bilang Markdown';

  @override
  String notebookExportBig(String size) {
    return 'Humigit-kumulang $size MB ng teksto ang notebook na ito. Maaaring matagalan ang pag-copy.';
  }

  @override
  String get notebookExportClipFail =>
      'Hindi makopya sa clipboard. Subukan ulit.';

  @override
  String notebookExported(int count) {
    return 'Nakopya ang $count pahina bilang Markdown.';
  }

  @override
  String get notebookExporting => 'Kinokolekta ang mga pahina...';

  @override
  String get notebookFieldSummary => 'Ano ang laman nito?';

  @override
  String get notebookFieldSummaryHint =>
      'Isang linya, para alam ni Botler kung kailan ito bubuksan';

  @override
  String get notebookFieldTitle => 'Pamagat';

  @override
  String get notebookGoBack => 'Bumalik';

  @override
  String get notebookGone => 'Wala na ang kuwadernong ito';

  @override
  String get notebookGoneBody => 'Binura ito, dito o sa ibang telepono.';

  @override
  String get notebookKeepEditing => 'Ituloy ang pag-edit';

  @override
  String notebookNameRemove(String name) {
    return 'Alisin si $name';
  }

  @override
  String get notebookNames => 'Mga pribadong pangalan';

  @override
  String get notebookNamesAdd => 'Magdagdag ng pangalan';

  @override
  String get notebookNamesAddButton => 'Idagdag';

  @override
  String get notebookNew => 'Bagong kuwaderno';

  @override
  String get notebookNoPages =>
      'Wala pang pahina. Ipasulat kay Botler ang una, o magdagdag ka ng pahina.';

  @override
  String get notebookOffline =>
      'Walang koneksyon. Nandito pa rin ang isinulat mo: subukan ulit kapag online ka na.';

  @override
  String get notebookOpenFirst => 'Buksan ang unang pahina';

  @override
  String get notebookOthers => 'Iba pang kuwaderno';

  @override
  String get notebookOthersEmpty =>
      'Wala pa. Dito sa pangunahin ang mahahalaga; makakagawa si Botler ng kuwaderno para sa biyahe, proyekto o listahan. Hilingin mo, o gumawa ka mismo.';

  @override
  String get notebookRestore => 'Ibalik';

  @override
  String get notebookRestoreBody =>
      'Magiging ang tekstong nasa ibaba ang kuwaderno mo. Mananatili sa Mga pagbabago ang laman nito ngayon, kaya puwede mo itong bawiin.';

  @override
  String get notebookRestoreTitle => 'Ibalik ang tekstong ito?';

  @override
  String get notebookRestored => 'Naibalik na.';

  @override
  String get notebookSectionEmpty => 'Wala pa';

  @override
  String get notebookSeeding =>
      'Ginawa mula sa dating natatandaan ni Botler. Inaayos ito sa background, at puwede mong baguhin ang kahit alin dito.';

  @override
  String get notebookTitle => 'Kuwaderno';

  @override
  String get notifChannel => 'Mga paalala';

  @override
  String get notifChannelDescription => 'Mga bill, sweldo, gawain at event';

  @override
  String get notifHiddenBody => 'May paalala ka';

  @override
  String get outboxFailedDismiss => 'Sige';

  @override
  String outboxFailedLine(int count) {
    return '$count pagbabagong ginawa mo habang offline ang hindi tumuloy. I-tap para makita kung bakit.';
  }

  @override
  String get outboxFailedTitle => 'Mga pagbabagong tinanggihan ng server';

  @override
  String get pageAddedMark => 'Idinagdag mula nang huli mong basahin';

  @override
  String pageBreadcrumb(String trail) {
    return 'Pahina $trail';
  }

  @override
  String get pageChangedALot =>
      'Marami nang nagbago sa pahinang ito mula nang huli mong basahin, kaya hindi namarkahan ang mga bagong linya.';

  @override
  String get pageChangesLegend =>
      'Namarkahan sa kaliwa: ang idinagdag mula nang huli mong basahin.';

  @override
  String get pageContents => 'Nilalaman';

  @override
  String get pageContentsEmpty => 'Walang mga heading ang pahinang ito.';

  @override
  String get pageCopied => 'Nakopya ang pahina.';

  @override
  String get pageCopyText => 'Kopyahin ang teksto';

  @override
  String get pageCreate => 'Gawin';

  @override
  String pageDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count araw na lang',
      one: '1 araw na lang',
    );
    return '$_temp0';
  }

  @override
  String get pageDelete => 'Burahin ang pahina';

  @override
  String get pageDeleteBody =>
      'Itatago ang pahina at ang mga sub-pahina nito. Maibabalik mo ito sa loob ng 30 araw.';

  @override
  String get pageDeleteTitle => 'Burahin ang pahinang ito?';

  @override
  String get pageDeleted => 'Nabura na.';

  @override
  String get pageDeletedEmpty => 'Walang binurang pahina.';

  @override
  String get pageDeletedTitle => 'Mga binurang pahina';

  @override
  String get pageEditOffline =>
      'Kopyang offline ang binabasa mo. Kailangan ng koneksyon para magbago.';

  @override
  String get pageEmpty =>
      'Walang laman ang pahinang ito. I-tap ang Baguhin para magsulat, o ipasulat kay Botler.';

  @override
  String get pageGone => 'Wala na ang pahinang ito';

  @override
  String get pageGoneBody => 'Binura ito ni Botler, o ng ibang telepono.';

  @override
  String pageLinkMissing(String title) {
    return 'Walang pahinang $title';
  }

  @override
  String get pageLinkedFrom => 'Naka-link mula sa';

  @override
  String pageLinkedFromRow(String page, String notebook) {
    return 'Buksan ang $page, sa $notebook, na may link dito';
  }

  @override
  String get pageMove => 'Ilipat sa...';

  @override
  String get pageMoveDown => 'Ibaba';

  @override
  String get pageMoveHasKids =>
      'May mga sub-pahina ang pahinang ito, kaya sa pinakataas na antas lang ito mailalagay.';

  @override
  String get pageMoveHere => 'kinalalagyan ngayon';

  @override
  String pageMoveTitle(String title) {
    return 'Ilipat ang $title';
  }

  @override
  String get pageMoveTop => 'Pinakataas na antas ng kuwaderno';

  @override
  String pageMoveUnder(String title) {
    return 'Sa ilalim ng $title';
  }

  @override
  String get pageMoveUp => 'Itaas';

  @override
  String get pageMoved => 'Nailipat.';

  @override
  String get pageNew => 'Bagong pahina';

  @override
  String get pagePin => 'I-pin';

  @override
  String get pageRename => 'Palitan ang pangalan';

  @override
  String get pageRenamed => 'Napalitan na ang pangalan.';

  @override
  String pageRestoreFor(String title) {
    return 'Ibalik ang $title';
  }

  @override
  String get pageRestored => 'Naibalik.';

  @override
  String get pageSubpages => 'Mga sub-pahina';

  @override
  String get pageTitleHint => 'Wi-Fi at ang router';

  @override
  String get pageTitleLabel => 'Pamagat ng pahina';

  @override
  String pageToggleClose(String title) {
    return 'Itago ang mga sub-pahina ng $title';
  }

  @override
  String pageToggleOpen(String title) {
    return 'Ipakita ang mga sub-pahina ng $title';
  }

  @override
  String get pageUnpin => 'Alisin ang pin';

  @override
  String pageUpdatedBy(String who, String when) {
    return 'Binago ni $who, $when';
  }

  @override
  String get paydayAdd => 'Magdagdag ng payday';

  @override
  String get paydayAddRule => 'Magdagdag ng rule';

  @override
  String get paydayApprove => 'Aprubahan';

  @override
  String get paydayComingUp => 'Paparating';

  @override
  String get paydayDecline => 'Tanggihan';

  @override
  String get paydayDeclined => 'Tinanggihan ang rule.';

  @override
  String paydayDeleteBody(String label) {
    return 'Buburahin nang tuluyan ang “$label”. Mananatili kung nasaan ang perang naitala mo na.';
  }

  @override
  String get paydayDeleteButton => 'Burahin ang payday na ito';

  @override
  String get paydayDeleteTitle => 'Buburahin ang payday na ito?';

  @override
  String paydayDeleteWithSplitsBody(String label) {
    return 'May mga naunang split ang “$label”. Buburahin nang tuluyan ang payday at ang mga split nito? Mananatili kung nasaan ang perang naitala mo na.';
  }

  @override
  String get paydayDeleteYes => 'Burahin';

  @override
  String get paydayDeleted => 'Nabura ang payday.';

  @override
  String get paydayDifferent => 'Iba-iba tuwing sweldo';

  @override
  String get paydayEarlier => 'Mga naunang split';

  @override
  String get paydayEditMenu => 'Baguhin o burahin ang payday na ito';

  @override
  String get paydayEditTitle => 'Baguhin ang payday na ito';

  @override
  String get paydayEmpty => 'Sabihin kay Botler kung kailan ka sumusweldo.';

  @override
  String paydayIncomeAmountLabel(String currency) {
    return 'Magkano karaniwan? ($currency, opsyonal)';
  }

  @override
  String get paydayIncomeDefault => 'Sahod';

  @override
  String get paydayIncomeInvalid =>
      'Lagyan ng pangalan, account at ang halaga bilang numero.';

  @override
  String get paydayIncomeLabel => 'Ano ang tawag mo rito?';

  @override
  String get paydayIncomeTitle => 'Kailan ka sumusweldo?';

  @override
  String get paydayLandsIn => 'Papasok ito sa';

  @override
  String get paydayMakeSplit => 'Gawin ang split';

  @override
  String paydayNeedsAmounts(String names) {
    return 'Magkano karaniwan ang $names? Ilagay muna ang halaga sa bill.';
  }

  @override
  String get paydayNoEarlier => 'Wala pang naunang split.';

  @override
  String get paydayNoneAhead => 'Wala pang paparating na payday.';

  @override
  String get paydayOff => 'Naka-off';

  @override
  String get paydayPayEmptyHint =>
      'Iwanang walang laman para gamitin ang karaniwan mong sahod';

  @override
  String paydayPayInvalid(String currency) {
    return 'I-type ang sweldo sa $currency.';
  }

  @override
  String get paydayPayLabel =>
      'Magkano ang sweldo ngayon? (iwanang walang laman para sa karaniwan)';

  @override
  String paydayPayThisTime(String currency) {
    return 'Magkano ang sahod ngayon? ($currency)';
  }

  @override
  String get paydayPlan => 'I-plano ang split';

  @override
  String paydayPlanTitle(String label, String date) {
    return 'I-plano ang $label sa $date';
  }

  @override
  String get paydayRuleAddButton => 'Idagdag ang rule';

  @override
  String paydayRuleDeleteBody(String rule) {
    return 'Buburahin nang tuluyan ang “$rule”. Mananatili ang mga numero ng mga split na nagawa na.';
  }

  @override
  String get paydayRuleDeleteButton => 'Burahin ang rule';

  @override
  String get paydayRuleDeleteTitle => 'Buburahin ang rule na ito?';

  @override
  String get paydayRuleDeleteYes => 'Burahin';

  @override
  String get paydayRuleDeleted => 'Nabura ang rule.';

  @override
  String get paydayRuleExamples =>
      'Mga halimbawa: “500 sa GCash”, “10% ng matitira sa Maya”, “ang natitira sa RCBC”.';

  @override
  String get paydayRuleHint => '20% sa emergency fund';

  @override
  String get paydayRuleLabel => 'Sabihin sa sarili mong salita';

  @override
  String get paydayRuleMenu => 'Iba pa tungkol sa rule na ito';

  @override
  String get paydayRuleNameHint => 'Emergency fund';

  @override
  String get paydayRuleNameLabel => 'Pangalan (opsyonal)';

  @override
  String get paydayRuleStopped => 'Itinigil';

  @override
  String get paydayRuleTitle => 'Magdagdag ng rule';

  @override
  String get paydayRulesEmpty =>
      'Wala pang rule. Sabihin kung ano ang gagawin sa matitira, tulad ng “20% sa emergency fund”.';

  @override
  String get paydayRulesTitle => 'Mga rule para sa matitira';

  @override
  String get paydaySplitReady =>
      'Handa na ang split mo sa ibaba. Suriin, saka aprubahan.';

  @override
  String get paydayStop => 'Itigil';

  @override
  String get paydayStopBody =>
      'Hindi na ito gagamitin sa mga bagong split. Puwede mo itong burahin anumang oras.';

  @override
  String get paydayStopTitle => 'Ihihinto ang rule na ito?';

  @override
  String get paydayStopYes => 'Ihinto';

  @override
  String get paydayStopped => 'Inihinto ang rule.';

  @override
  String get paydayTitle => 'Payday';

  @override
  String paydayUsually(String amount) {
    return 'Karaniwang $amount';
  }

  @override
  String get paydayWaiting => 'Naghihintay ng oo mo';

  @override
  String get paydayYours => 'Mga payday mo';

  @override
  String get photoMarkApprove => 'Gamitin ang larawang ito';

  @override
  String get photoMarkDown => 'Ilipat pababa';

  @override
  String get photoMarkFill => 'Punuin';

  @override
  String get photoMarkGone =>
      'Wala na ang litratong ito sa phone. Ipadala ulit at hilingin ulit.';

  @override
  String get photoMarkLeft => 'Ilipat pakaliwa';

  @override
  String get photoMarkNote =>
      'Ginupit sa phone mo. Nananatili rito ang orihinal na litrato mo; ang maliit na ginupit na larawan lang ang sine-save.';

  @override
  String get photoMarkPreview => 'Ganito magiging itsura ng larawan';

  @override
  String get photoMarkRetry => 'Subukan ulit';

  @override
  String get photoMarkRight => 'Ilipat pakanan';

  @override
  String get photoMarkUp => 'Ilipat pataas';

  @override
  String get photoMarkWhole => 'Buo';

  @override
  String get photoMarkWorking => 'Ginugupit ang larawan';

  @override
  String get photoMarkZoomIn => 'Palakihin';

  @override
  String get photoMarkZoomOut => 'Paliitin';

  @override
  String photoNoticeBody(String server) {
    return 'Mapupunta sa $server ang litrato mo bilang larawan, para makita ng assistant kung ano ang laman nito. Hindi nakatago ang mga pangalan at numero sa larawan gaya sa teksto, at hindi ito iniimbak ng server ng Botler (ang $server ang humahawak nito ayon sa sarili nitong mga tuntunin). Mababago mo ito sa Settings.';
  }

  @override
  String get photoNoticeNo => 'Teksto lang';

  @override
  String get photoNoticeTitle => 'Ipadala ang mismong larawan?';

  @override
  String get photoNoticeYes => 'Ipadala ang mga larawan';

  @override
  String get purposeCustom => 'Sarili kong label';

  @override
  String get purposeCustomHint => 'hal. Pang-eskuwela';

  @override
  String get purposeCustomLabel => 'Sarili mong label';

  @override
  String purposeEditTitle(String name) {
    return 'Label ng $name';
  }

  @override
  String get purposeInvalid =>
      'Hanggang 24 na titik at walang mahabang numero.';

  @override
  String get purposeNone => 'Walang label';

  @override
  String get purposeSaved => 'Na-save ang label.';

  @override
  String purposeSemantic(String purpose) {
    return 'Layunin: $purpose';
  }

  @override
  String get purposeTitle => 'Para saan ang account na ito?';

  @override
  String get remBlockedExact =>
      'Baka hindi makapag-set ng eksaktong alarm ang Botler, kaya maaaring mahuli ang mga paalala.';

  @override
  String get remBlockedFailed =>
      'Hindi naitakda ang mga paalala sa huling subok. Susubukan ulit.';

  @override
  String get remBlockedNotifications =>
      'Naka-off ang mga notification ng Botler, kaya hindi lalabas ang mga paalala.';

  @override
  String get remFix => 'Buksan ang settings';

  @override
  String researchClosedLabel(String label) {
    return '$label, listahan ng mga pinagmulan, nakasara';
  }

  @override
  String researchCounts(int searches, int reads) {
    String _temp0 = intl.Intl.pluralLogic(
      searches,
      locale: localeName,
      other: '$searches paghahanap',
    );
    String _temp1 = intl.Intl.pluralLogic(
      reads,
      locale: localeName,
      other: '$reads pahina',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String researchDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pinagmulan',
    );
    return 'Nasaliksik, $_temp0';
  }

  @override
  String get researchDoneNone => 'Nasaliksik';

  @override
  String get researchFailed => 'Hindi naabot ng pananaliksik ang web.';

  @override
  String researchOpenLabel(String label) {
    return '$label, listahan ng mga pinagmulan, bukas';
  }

  @override
  String researchOpenSource(String title, String host) {
    return 'Buksan ang $title, $host';
  }

  @override
  String researchRunning(String question) {
    return 'Nagsasaliksik: $question';
  }

  @override
  String get researchRunningNone => 'Nagsasaliksik';

  @override
  String get researchStoppedCancelled =>
      'Huminto. Ito ang nakita nito hanggang ngayon.';

  @override
  String get researchStoppedOther =>
      'Maaga itong huminto, kaya ito ang nakita nito hanggang ngayon.';

  @override
  String get researchStoppedTime =>
      'Naubusan ng oras, kaya ito ang nakita nito hanggang ngayon.';

  @override
  String get resetBack => 'Pumili ng ibang bahagi';

  @override
  String get resetBiometric =>
      'Kumpirmahin muna gamit ang fingerprint o screen lock.';

  @override
  String get resetButton => 'Burahin na';

  @override
  String get resetChoose => 'Ano ang gusto mong burahin?';

  @override
  String resetDone(int total) {
    return 'Tapos na. $total hilera ang nabura.';
  }

  @override
  String get resetExpired =>
      'Nag-expire na ang kumpirmasyon. Piliin ulit ang bahagi.';

  @override
  String get resetExportFirst => 'Kopyahin muna ang history';

  @override
  String get resetExported =>
      'Nakopya ang history. I-paste ito sa ligtas na lugar.';

  @override
  String resetKeeps(String what) {
    return 'Mananatili: $what.';
  }

  @override
  String get resetLine =>
      'Burahin ang ilan o lahat ng hawak ni Botler tungkol sa iyo. Mananatili ang sign-in, settings at mga phone mo.';

  @override
  String get resetNothing => 'Walang buburahin sa bahaging ito.';

  @override
  String get resetOnlineOnly => 'Kailangan ng koneksyon sa pag-reset.';

  @override
  String get resetScopeAudit => 'Audit history';

  @override
  String get resetScopeAuditLine =>
      'Ang tala kung sino ang nagbago ng ano. Mananatili ang isang tala ng reset.';

  @override
  String get resetScopeEverything => 'Lahat';

  @override
  String get resetScopeEverythingLine => 'Lahat ng nasa itaas';

  @override
  String get resetScopeHealth => 'Kalusugan';

  @override
  String get resetScopeHealthLine =>
      'Pagkain, timbang, ehersisyo, tulog at ang setup ng Kalusugan';

  @override
  String get resetScopeMemory => 'Memorya at chat';

  @override
  String get resetScopeMemoryLine =>
      'Ang naaalala ni Botler at ang mga usapan ninyo';

  @override
  String get resetScopeMoney => 'Pera';

  @override
  String get resetScopeMoneyLine =>
      'Mga account, transaksyon, bill, goal, rule, sweldo at hati';

  @override
  String get resetScopeSchedule => 'Iskedyul';

  @override
  String get resetScopeScheduleLine => 'Mga gawain, event, routine at paalala';

  @override
  String get resetSection => 'Mapanganib na bahagi';

  @override
  String get resetTitle => 'I-reset ang data';

  @override
  String resetTypeWord(String word) {
    return 'I-type ang $word para magpatuloy';
  }

  @override
  String resetWillErase(int total) {
    return 'Buburahin nito ang $total hilera:';
  }

  @override
  String get resetWrongWord => 'I-type nang eksakto ang salita.';

  @override
  String get resetZeroReason => 'Magsisimula ulit sa zero';

  @override
  String get retry => 'Subukan muli';

  @override
  String ruleSavesFor(String bill) {
    return 'Inilalaan para sa $bill';
  }

  @override
  String get ruleSavesForHelp =>
      'Piliin ang bill na pupuntahan ng perang ito. Sa araw ng sahod, babayaran ng split ang bill na iyon mula sa naipon ng rule na ito, sa halip na kunin ulit sa sahod mo.';

  @override
  String get ruleSavesForNone => 'Ilaan para sa isang bill?';

  @override
  String get ruleSavesForNothing => 'Wala';

  @override
  String get ruleSavesForSaved => 'Na-save.';

  @override
  String get ruleSavesForSemantic =>
      'Piliin ang bill na pinag-iipunan ng rule na ito';

  @override
  String get ruleSavesForTitle => 'Para saan inilalaan ang rule na ito?';

  @override
  String get save => 'I-save';

  @override
  String get schedBasisCalendar => 'Mga linggo sa kalendaryo';

  @override
  String get schedBasisDays => 'Araw 1 hanggang 7, 8 hanggang 14, at iba pa';

  @override
  String get schedDay => 'Araw';

  @override
  String get schedEvery1 => 'Bawat buwan';

  @override
  String get schedEvery12 => 'Bawat 12 buwan';

  @override
  String get schedEvery2 => 'Bawat 2 buwan';

  @override
  String get schedEvery3 => 'Bawat 3 buwan';

  @override
  String get schedEvery6 => 'Bawat 6 na buwan';

  @override
  String get schedEveryDays => 'Ulitin tuwing (araw)';

  @override
  String get schedEveryWeeks1 => 'Bawat linggo';

  @override
  String get schedEveryWeeks2 => 'Bawat 2 linggo';

  @override
  String get schedEveryWeeks3 => 'Bawat 3 linggo';

  @override
  String get schedEveryWeeks4 => 'Bawat 4 na linggo';

  @override
  String get schedFirstDay => 'Unang araw';

  @override
  String schedFromDate(String date) {
    return 'mula $date';
  }

  @override
  String get schedFromDay => 'Mula sa araw';

  @override
  String get schedHow => 'Gaano kadalas?';

  @override
  String get schedLast => 'huling';

  @override
  String get schedLastDay => 'Huling araw';

  @override
  String get schedMonth => 'Buwan';

  @override
  String schedNotOnDates(String dates) {
    return 'hindi sa $dates';
  }

  @override
  String get schedNth1 => 'Una';

  @override
  String get schedNth2 => 'Ikalawa';

  @override
  String get schedNth3 => 'Ikatlo';

  @override
  String get schedNth4 => 'Ikaapat';

  @override
  String get schedNth5 => 'Ikalima';

  @override
  String get schedNthLast => 'Huli';

  @override
  String get schedOnDate => 'Sa';

  @override
  String get schedPatEveryN => 'Bawat ilang araw';

  @override
  String get schedPatMonthlyDay => 'Sa isang araw ng buwan';

  @override
  String get schedPatNthWeekday =>
      'Sa isang araw ng linggo sa buwan (gaya ng unang Miyerkules)';

  @override
  String get schedPatOnce => 'Isang beses lang';

  @override
  String get schedPatRange => 'Sa pagitan ng dalawang araw ng buwan';

  @override
  String get schedPatSemi => 'Dalawang beses sa isang buwan';

  @override
  String get schedPatWeek => 'Sa isang linggo ng buwan';

  @override
  String get schedPatWeekly => 'Bawat linggo';

  @override
  String get schedPatYearly => 'Minsan sa isang taon';

  @override
  String schedPayWindow(String start, String end) {
    return 'Magbayad kahit anong araw, $start hanggang $end';
  }

  @override
  String get schedPickWeekday => 'Isang araw ng linggong iyon';

  @override
  String get schedPickWindow => 'Kahit anong araw sa linggong iyon';

  @override
  String get schedPreviewNone =>
      'Walang petsang nakita sa susunod na dalawang taon.';

  @override
  String get schedPreviewOffline =>
      'Mag-connect sa internet para makita ang mga susunod na petsa.';

  @override
  String get schedPreviewTitle => 'Ang mga susunod na petsa';

  @override
  String schedPreviewWindow(String start, String end) {
    return '$start hanggang $end';
  }

  @override
  String get schedRepeat => 'Ulitin';

  @override
  String schedSayEveryDay(String date) {
    return 'Araw-araw mula $date';
  }

  @override
  String schedSayEveryMonths(int n) {
    return ', bawat $n buwan';
  }

  @override
  String schedSayEveryN(int n, String date) {
    return 'Tuwing $n araw mula $date';
  }

  @override
  String schedSayMonthlyDay(String day, String every) {
    return 'Sa $day ng buwan$every';
  }

  @override
  String schedSayMonthlyLast(String every) {
    return 'Sa huling araw ng buwan$every';
  }

  @override
  String schedSayNth(String nth, String weekday, String every) {
    return 'Tuwing $nth $weekday ng buwan$every';
  }

  @override
  String schedSayOnce(String date) {
    return 'Isang beses lang, sa $date';
  }

  @override
  String schedSayRange(String from, String to, String every) {
    return 'Kahit anong araw sa pagitan ng $from at $to$every';
  }

  @override
  String schedSayRangeToLast(String from, String every) {
    return 'Kahit anong araw mula $from hanggang katapusan ng buwan$every';
  }

  @override
  String schedSaySemi(String first, String second) {
    return 'Sa $first at $second ng bawat buwan';
  }

  @override
  String schedSayWeekWeekday(
    String weekday,
    String nth,
    String span,
    String every,
  ) {
    return 'Ang $weekday ng $nth linggo ng buwan ($span)$every';
  }

  @override
  String schedSayWeekWindow(String nth, String span, String every) {
    return 'Kahit anong araw sa $nth linggo ng buwan ($span)$every';
  }

  @override
  String schedSayWeekly(String days) {
    return 'Tuwing $days';
  }

  @override
  String schedSayWeeklyEvery(int n, String days) {
    return 'Tuwing $n linggo, sa $days';
  }

  @override
  String schedSayYearly(String month, int day) {
    return 'Minsan sa isang taon, $month $day';
  }

  @override
  String get schedSecondDay => 'Ikalawang araw';

  @override
  String get schedSpanCalendar => 'linggo sa kalendaryo';

  @override
  String schedSpanDays(int from, int to) {
    return 'araw $from hanggang $to';
  }

  @override
  String get schedSpanLast => 'ang huling 7 araw';

  @override
  String get schedStartingOn => 'Simula sa';

  @override
  String get schedToDay => 'Hanggang sa araw';

  @override
  String get schedUnknown =>
      'Isang schedule na hindi kayang i-edit ng bersyong ito ng app';

  @override
  String schedUntilDate(String date) {
    return 'hanggang $date';
  }

  @override
  String get schedWeekday => 'Araw ng linggo';

  @override
  String get schedWeekendAfter => 'Gamitin ang araw ng trabaho pagkatapos nito';

  @override
  String get schedWeekendBefore => 'Gamitin ang araw ng trabaho bago nito';

  @override
  String get schedWeekendLabel => 'Kung tumapat sa weekend';

  @override
  String get schedWeekendNone => 'Panatilihin ang petsa';

  @override
  String get schedWhichOne => 'Alin?';

  @override
  String get schedWhichWeek => 'Aling linggo?';

  @override
  String setBalanceBody(String amount) {
    return 'Akala ni Botler ay $amount. Walang buburahin: nananatili ang history at ang pagkakaiba ay ipapakita bilang reset.';
  }

  @override
  String setBalanceConfirmBody(String old, String diff) {
    return 'Dati ay $old. Ang pagkakaiba na $diff ay itatala bilang reset, hindi bilang gastos.';
  }

  @override
  String setBalanceConfirmTitle(String name, String amount) {
    return 'Itakda ang $name sa $amount?';
  }

  @override
  String get setBalanceConfirmYes => 'Itakda';

  @override
  String get setBalanceDone =>
      'Naitakda na ang balanse. Itinatago ng history ang dati.';

  @override
  String setBalanceNew(String currency) {
    return 'Bagong balanse ($currency)';
  }

  @override
  String get setBalanceOffline =>
      'Kailangan ng koneksyon ang reset, kaya hindi ito magagamit offline.';

  @override
  String get setBalanceReason => 'Bakit? (maikli)';

  @override
  String get setBalanceReasonNeeded => 'Sabihin kung bakit sa ilang salita.';

  @override
  String setBalanceTitle(String name) {
    return 'Itakda ang balanse ng $name';
  }

  @override
  String get settingsAiServer => 'AI server';

  @override
  String get settingsAiServerDefault => 'Default ng server';

  @override
  String get settingsAiServerHelp =>
      'Maaaring bahagyang magkaiba ang sagot ng bawat server.';

  @override
  String settingsAiServerUnavailable(String server) {
    return 'Hindi available ang $server sa server ngayon, kaya ang default ang gamit.';
  }

  @override
  String get settingsAppLanguage => 'Wika ng app';

  @override
  String get settingsClock12 => '12 oras';

  @override
  String get settingsClock24 => '24 oras';

  @override
  String get settingsClockAuto => 'Telepono';

  @override
  String get settingsClockTitle => 'Orasan';

  @override
  String get settingsCurrency => 'Pera';

  @override
  String get settingsCurrencyChange => 'Palitan';

  @override
  String settingsCurrencyConfirmBody(String name) {
    return 'Sa $name na ipapakita ang kabuuan mo. Nananatili sa account ang mga pera nito. Pareho pa rin ang numero ng kita, goal, rule at minimum na balanse mo pero babasahin na sa $name: walang kino-convert sa mga ito. Nananatili sa sarili nilang pera ang mga bill mo.';
  }

  @override
  String settingsCurrencyConfirmTitle(String code) {
    return 'Gawing $code ang pera?';
  }

  @override
  String settingsCurrencyExample(String amount) {
    return 'Halimbawa $amount';
  }

  @override
  String get settingsCurrencyNone => 'Walang pera na tugma diyan.';

  @override
  String get settingsCurrencySearch => 'Maghanap ng pera';

  @override
  String get settingsDateOrderDmy => 'A B T';

  @override
  String get settingsDateOrderMdy => 'B A T';

  @override
  String get settingsDateOrderTitle => 'Ayos ng petsa';

  @override
  String get settingsDateOrderYmd => 'T B A';

  @override
  String get settingsHideBody =>
      '“Botler” lang ang sinasabi ng paalala, kaya walang makakakita nito sa lock screen mo.';

  @override
  String get settingsHideTitle => 'Itago ang detalye sa mga notification';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageFil => 'Filipino';

  @override
  String get settingsLead1440 => '1 araw bago';

  @override
  String get settingsLead15 => '15 minuto bago';

  @override
  String get settingsLead180 => '3 oras bago';

  @override
  String get settingsLead60 => '1 oras bago';

  @override
  String get settingsLeadAtTime => 'Sa mismong oras';

  @override
  String get settingsLeadLabel => 'Paalalahanan ako nang mas maaga ng';

  @override
  String get settingsListenEn => 'English (Pilipinas)';

  @override
  String get settingsListenFil => 'Filipino at Taglish';

  @override
  String get settingsListenFor => 'Pakinggan ang';

  @override
  String get settingsLockNeeds =>
      'Kailangan ng lock ng naka-set up na fingerprint o mukha sa phone na ito.';

  @override
  String get settingsLockTitle =>
      'Hingin ang fingerprint o mukha ko para buksan ang Botler';

  @override
  String get settingsLook => 'Itsura';

  @override
  String get settingsLookDark => 'Madilim';

  @override
  String get settingsLookLight => 'Maliwanag';

  @override
  String get settingsLookPhone => 'Phone';

  @override
  String get settingsMonday => 'Lunes';

  @override
  String get settingsNetBody =>
      'Una ang matitira pagkatapos ng mga bayarin bago ang susunod na sahod at ng perang nakalaan sa mga goal. Nasa ilalim, mas maliit, ang balanseng binilang mo.';

  @override
  String get settingsNetTitle => 'Ipakita ang net na balanse';

  @override
  String settingsPhotoHelpImage(String server) {
    return 'Titingnan ng assistant ang mismong larawan, kaya kaya nitong ilarawan ang isang produkto o basahin ang ayos ng isang dokumento. Ang larawan ay napupunta sa $server nang buo: hindi nakatago ang mga pangalan at numero rito gaya sa teksto. Hindi ito iniimbak ng server ng Botler; ang $server ang humahawak nito ayon sa sarili nitong mga tuntunin.';
  }

  @override
  String settingsPhotoHelpOther(String server, String chat) {
    return 'Hindi makakita ng larawan ang $chat, kaya ang $server ang tumitingin sa mga mensaheng may larawan. Nasa $chat pa rin ang natitirang chat mo. Ang larawan ay napupunta sa $server nang buo: hindi nakatago ang mga pangalan at numero rito gaya sa teksto. Hindi ito iniimbak ng server ng Botler; ang $server ang humahawak nito ayon sa sarili nitong mga tuntunin.';
  }

  @override
  String get settingsPhotoHelpText =>
      'Binabasa ng phone ang mga salita sa litrato at ang mga salitang iyon lang ang ipinapadala. Nakatago pa rin ang mga pangalan at numero gaya ng dati.';

  @override
  String get settingsPhotoImage => 'Larawan';

  @override
  String settingsPhotoNoVision(String server) {
    return 'Hindi makakita ng larawan ang $server, kaya teksto lang mula rito ang natatanggap nito, anuman ang piliin mo rito.';
  }

  @override
  String get settingsPhotoText => 'Teksto lang';

  @override
  String get settingsPhotosTitle => 'Mga litrato para sa assistant';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String settingsRatesLine(String date, String source) {
    return 'Kinuha noong $date mula sa $source';
  }

  @override
  String get settingsRatesNone => 'Wala pang palitan';

  @override
  String get settingsRatesTap => 'I-tap para i-update';

  @override
  String get settingsRatesTitle => 'Palitan ng pera';

  @override
  String get settingsReminders => 'Mga paalala';

  @override
  String get settingsReplies => 'Sagot ng assistant';

  @override
  String get settingsRepliesAuto =>
      'Auto: English, at Filipino kapag Filipino ang sinulat mo';

  @override
  String get settingsRepliesEn => 'Laging English';

  @override
  String get settingsRepliesFil => 'Laging Filipino';

  @override
  String get settingsRepliesTaglish => 'Taglish';

  @override
  String get settingsSectionLanguageMoney => 'Wika at pera';

  @override
  String get settingsSignOut => 'Mag-sign out';

  @override
  String get settingsSignOutBody =>
      'Nananatili ang Botler sa server. Puwede kang mag-sign in ulit anumang oras.';

  @override
  String get settingsSignOutTitle => 'Mag-sign out?';

  @override
  String get settingsSignedIn => 'Naka-sign in';

  @override
  String get settingsSunday => 'Linggo';

  @override
  String settingsTimeNow(String now) {
    return 'Ngayon: $now';
  }

  @override
  String get settingsTimeTitle => 'Petsa at oras';

  @override
  String get settingsTimeZone => 'Time zone';

  @override
  String get settingsTimeZoneHelp =>
      'Dito nakabatay kung anong araw ngayon at ang mga oras na nakikita mo. Hindi ito binabago ng sariling zone ng telepono mo.';

  @override
  String get settingsTimeZoneNone => 'Walang time zone na tugma diyan.';

  @override
  String get settingsTimeZoneSearch => 'Maghanap ng lungsod o zone';

  @override
  String get settingsTitle => 'Mga setting';

  @override
  String get settingsToolbox => 'Toolbox';

  @override
  String get settingsToolboxBody =>
      'Mga script na sine-save ni Botler sa phone na ito';

  @override
  String get settingsVoice => 'Boses';

  @override
  String get settingsWeekStarts => 'Nagsisimula ang linggo sa';

  @override
  String get signInAgainBody =>
      'Nasa phone na ito ang mga isinulat mo habang offline. Mag-sign in ulit para maipadala ang mga ito.';

  @override
  String get signInAgainButton => 'Mag-sign in ulit';

  @override
  String get signInAgainTitle => 'Natapos na ang iyong sign in';

  @override
  String get signInButton => 'Mag-sign in gamit ang Google';

  @override
  String get signInTagline => 'Ang pera at oras mo, sa isang tahimik na chat.';

  @override
  String signOutWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagbabago ang',
      one: '1 pagbabago ang',
    );
    return '$_temp0 naghihintay pang maipadala. Mananatili ang mga ito sa phone na ito at ipapadala kapag nag-sign in ka ulit.';
  }

  @override
  String simAbout(String amount) {
    return 'mga $amount';
  }

  @override
  String get simAccountsTitle => 'Mga account';

  @override
  String get simAhead1m => '1 buwan pasulong';

  @override
  String get simAhead1y => '1 taon pasulong';

  @override
  String get simAhead5y => '5 taon pasulong';

  @override
  String simAmountFor(String name) {
    return 'Halaga para sa $name';
  }

  @override
  String get simBack1m => '1 buwan pabalik';

  @override
  String get simBack1y => '1 taon pabalik';

  @override
  String get simBandFuture => 'Tantiya lang, hindi totoong pera';

  @override
  String get simBandFutureLine => 'Galing sa balanse ngayon at sa plano mo.';

  @override
  String get simBandMixed => 'Totoo hanggang ngayon, tantiya pagkatapos';

  @override
  String get simBandMixedLine =>
      'Hindi totoong pera ang mga bilang pagkatapos ng ngayon.';

  @override
  String simBandOffline(String date) {
    return 'Naka-save noong $date, walang koneksyon.';
  }

  @override
  String get simBandPast => 'Ang totoong nangyari';

  @override
  String get simBandPastLine =>
      'Ang mga naitalang balanse mo, katabi ng gagawin sana ng plano mo.';

  @override
  String simBelowDay(String account, String date) {
    return '$account bababa sa zero sa $date';
  }

  @override
  String get simBills => 'Mga bill';

  @override
  String simBreakdownLine(String name, String amount, int percent) {
    return '$name, $amount, $percent porsyento ng gastos, i-tap para ipakita lang ang mga entry nito';
  }

  @override
  String simBreakdownLineNoShare(String name, String amount) {
    return '$name, $amount, i-tap para ipakita lang ang mga entry nito';
  }

  @override
  String get simChangeSelf => 'Magbago ng sarili';

  @override
  String simChartSemantics(String period, String amount, String source) {
    return '$period: $amount, $source. Mag-swipe pataas o pababa para lumipat.';
  }

  @override
  String get simDefer =>
      'Maghihintay ang deferrable bills sa susunod na sweldo';

  @override
  String get simDetails => 'Detalye';

  @override
  String get simDone => 'Tapos';

  @override
  String get simEarlier => 'Mas maaga';

  @override
  String get simEdit => 'Baguhin';

  @override
  String get simEntriesOffline =>
      'Kailangan ng koneksyon ang kung saan napunta ang pera at ang mga entry. Ang mga kabuuan lang ang naka-save sa phone na ito.';

  @override
  String get simEntriesTitle => 'Mga entry';

  @override
  String get simError => 'Hindi ma-load ang time travel.';

  @override
  String simEverythingElse(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grupo',
      one: '1 grupo',
    );
    return 'Ang natitira ($_temp0)';
  }

  @override
  String simFirstRecordEdge(String date) {
    return 'Walang naitala bago ang $date.';
  }

  @override
  String simGapAbove(String amount) {
    return '$amount lampas sa plano';
  }

  @override
  String simGapBelow(String amount) {
    return '$amount kulang sa plano';
  }

  @override
  String get simGapNone => 'Saktong-sakto sa plano';

  @override
  String get simGoals => 'Mga goal';

  @override
  String get simGroupGone =>
      'Wala na ang grupong iyon sa listahan, kaya ipinapakita ang lahat ng entry.';

  @override
  String get simGroupOther => 'Iba pa';

  @override
  String get simHidden => 'nakatago';

  @override
  String get simIncludesEstimate => 'Kasama ang darating pa (tantiya).';

  @override
  String get simInfoChart =>
      'Isang tuldok sa bawat panahon. Ang tuloy-tuloy na linya ay naitala, ang putol-putol ay tantiya o replay ng plano mo. I-tap o i-drag para pumili ng panahon. Ang bilog ay panahong bumababa o mas mababa sa zero.';

  @override
  String get simInfoChartTitle => 'Ang chart';

  @override
  String get simInfoGap =>
      'Gaano kataas o kababa ang naitalang balanse kumpara sa kung saan ito ilalagay ng plano mo.';

  @override
  String get simInfoGapTitle => 'Ang agwat sa plano';

  @override
  String get simInfoIntro =>
      'Pumili ng kahit anong araw, linggo, buwan o taon, hanggang 5 taon pabalik o pasulong, para makita ang laman o ang magiging laman ng mga account mo. Tantiya lang ang lahat pagkatapos ng ngayon, galing sa balanse ngayon at sa plano mo, hindi totoong pera.';

  @override
  String get simInfoTags =>
      'Naitala: nangyari talaga. Replay ng plano: ang gagawin sana ng plano mo noon. Simulation: tantiya sa hinaharap. Hindi naitala: sweldo o bill na inasahan ng plano pero hindi naitala. What-if: kunwari mo lang.';

  @override
  String get simInfoTagsTitle => 'Ang mga tag';

  @override
  String get simInfoTitle => 'Paano gumagana ang Time travel';

  @override
  String get simInfoTooltip => 'Ano ang tinitingnan ko?';

  @override
  String get simInfoWarn =>
      'Account na kulang sa minimum o bababa sa zero sa isang araw, at pera na walang palitan, na hindi kasama sa kabuuan.';

  @override
  String get simInfoWarnTitle => 'Mga babala';

  @override
  String get simIntro =>
      'Tingnan ang laman ng mga account mo sa kahit anong nakaraang araw, o ang magiging laman sa darating. Tantiya ang mga bilang pagkatapos ng ngayon. Gamitin ang What if para sumubok ng pagbabago nang walang sine-save.';

  @override
  String get simIntroGotIt => 'Sige';

  @override
  String get simJump => 'Lumundag nang mas malayo';

  @override
  String simLateDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count araw',
      one: '1 araw',
    );
    return 'Bills bayad nang $_temp0 na huli';
  }

  @override
  String get simLater => 'Mas huli';

  @override
  String simLowDay(String account, String date) {
    return '$account kulang sa minimum sa $date';
  }

  @override
  String simMissed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sweldo o bill ang hindi naitala',
      one: '1 sweldo o bill ang hindi naitala',
    );
    return '$_temp0';
  }

  @override
  String simMissingRates(String codes) {
    return 'Walang palitan para sa $codes: hindi kasama sa kabuuan.';
  }

  @override
  String simMoveTo(String account) {
    return 'papunta sa $account';
  }

  @override
  String get simNoEntries => 'Walang laman ang panahong ito.';

  @override
  String get simNoPlan =>
      'Wala pang sweldo o bill, kaya patag ang linya ng simulation.';

  @override
  String get simNoRateShort => 'wala pang palitan';

  @override
  String get simNoRecords => 'Wala pang naitala para sa mga petsang ito.';

  @override
  String get simNoTotal => 'Walang kabuuan';

  @override
  String get simNothingSpent => 'Walang nagastos sa panahong ito.';

  @override
  String get simPageFailed => 'Hindi ma-load ang iba pa.';

  @override
  String get simPaydays => 'Mga sweldo';

  @override
  String simPercent(int percent) {
    return '$percent%';
  }

  @override
  String simPeriod(String from, String to) {
    return '$from hanggang $to';
  }

  @override
  String get simPickDate => 'Pumili ng petsa';

  @override
  String get simPlanExpected => 'Inasahan ng plano mong gastusin';

  @override
  String get simPresetDefer => 'Ipagpaliban ang puwedeng maghintay';

  @override
  String get simPresetDeferLine =>
      'Ang mga bill na puwedeng maghintay ay babayaran pagkatapos ng susunod na sweldo.';

  @override
  String get simPresetLate => 'Bayaran ang bills nang isang linggong huli';

  @override
  String get simPresetLateLine =>
      'Lahat ng bill ay binabayaran 7 araw pagkatapos ng due date.';

  @override
  String get simPresetNoRules => 'Walang payday rule';

  @override
  String get simPresetNoRulesLine =>
      'Patayin ang bawat payday rule, para walang itatabi.';

  @override
  String get simPresetPayDown => 'Sweldo 10% mas mababa';

  @override
  String get simPresetPayDownLine =>
      'Bawat sweldong may alam na halaga ay 10% mas mababa.';

  @override
  String get simPresetPayUp => 'Sweldo 10% mas mataas';

  @override
  String get simPresetPayUpLine =>
      'Bawat sweldong may alam na halaga ay 10% mas mataas.';

  @override
  String get simPresetSkipNext => 'Laktawan ang susunod na sweldo';

  @override
  String get simPresetSkipNextLine =>
      'Tingnan kung kumusta ka kung hindi darating ang susunod na sweldo.';

  @override
  String get simPresets => 'Magsimula sa isa dito';

  @override
  String get simPretend => 'Kunwaring pumasok o lumabas na pera';

  @override
  String get simPretendAccount => 'Aling account?';

  @override
  String get simPretendAdd => 'Idagdag';

  @override
  String simPretendDate(String date) {
    return 'Sa $date';
  }

  @override
  String get simPretendIn => 'Pumasok';

  @override
  String get simPretendLabel => 'Para saan ito?';

  @override
  String simPretendMainNote(String code) {
    return 'Nasa $code, ang pangunahing pera mo, ang mga kunwaring halaga.';
  }

  @override
  String get simPretendOut => 'Lumabas';

  @override
  String simPretendRange(String min, String max) {
    return 'Gumamit ng halagang mula $min hanggang $max.';
  }

  @override
  String simPretendTooMany(int count) {
    return 'Hanggang $count na pagpapanggap lang ang puwede nang sabay. Mag-alis muna ng isa.';
  }

  @override
  String get simRatesStale => 'Mahigit isang araw na ang palitan.';

  @override
  String get simReachEdge =>
      'Hanggang 5 taon lang pabalik at pasulong ang time travel.';

  @override
  String get simReceived => 'Natanggap';

  @override
  String get simReceivedSoFar => 'Natanggap na';

  @override
  String get simRecordedEnd => 'Naitala sa dulo';

  @override
  String get simRecordedToday => 'Naitala hanggang ngayon';

  @override
  String simRemove(String name) {
    return 'Alisin ang $name';
  }

  @override
  String get simReplayEnd => 'Replay ng plano sa dulo';

  @override
  String get simReset => 'I-reset';

  @override
  String get simResetDone => 'Naalis ang what-if. Ang plano mo ay nasa dati.';

  @override
  String get simRules => 'Mga payday rule';

  @override
  String simSectionChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagbabago',
      one: '1 pagbabago',
    );
    return '$_temp0';
  }

  @override
  String get simSeeOverTime => 'Tingnan sa paglipas ng panahon';

  @override
  String get simShowAll => 'Ipakita lahat';

  @override
  String get simShowLess => 'Ipakita ang mas kaunti';

  @override
  String simShowMore(int count) {
    return 'Ipakita ang $count pa';
  }

  @override
  String simShowingGroup(String name) {
    return 'Ipinapakita: $name';
  }

  @override
  String simShownOf(int shown, int total) {
    return 'Ipinapakita ang $shown sa $total';
  }

  @override
  String get simSimulatedEnd => 'Simulation sa dulo';

  @override
  String get simSkipPayday => 'I-tap ang sweldong hindi darating:';

  @override
  String get simSpanHint =>
      'Nasa panahong ito ang ngayon. Pumili ng mas maaga o mas huli para makita ang kabuuan mula roon hanggang ngayon.';

  @override
  String get simSpanIncludes => 'Kasama ang panahong pinili mo.';

  @override
  String get simSpanNet => 'Netong halaga (natanggap bawas nagastos)';

  @override
  String get simSpanNothing => 'Walang nagastos o natanggap sa saklaw na ito.';

  @override
  String simSpanRange(String from, String to) {
    return '$from hanggang $to';
  }

  @override
  String get simSpanTitle => 'Kabuuang daloy';

  @override
  String get simSpanToday => 'ngayon';

  @override
  String get simSpanTodayCap => 'Ngayon';

  @override
  String get simSpent => 'Nagastos';

  @override
  String get simSpentSoFar => 'Nagastos na';

  @override
  String get simStillToCome => 'Darating pa (tantiya)';

  @override
  String get simStillToReceive => 'Matatanggap pa (tantiya)';

  @override
  String get simTagMissed => 'Hindi naitala';

  @override
  String get simTagPretend => 'What-if';

  @override
  String get simTagRecorded => 'Naitala';

  @override
  String get simTagReplay => 'Replay ng plano';

  @override
  String get simTagSimulated => 'Simulation';

  @override
  String get simTiming => 'Oras';

  @override
  String get simTitle => 'Time travel';

  @override
  String get simToday => 'Ngayon';

  @override
  String get simUndo => 'Ibalik';

  @override
  String simUnknown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sweldo o bill ang wala pang halaga at hindi kasama',
      one: '1 sweldo o bill ang wala pang halaga at hindi kasama',
    );
    return '$_temp0';
  }

  @override
  String get simUntracked => 'Hindi naitala: umalis nang walang tala';

  @override
  String get simWhatIf => 'What if';

  @override
  String get simWhatIfLine =>
      'Walang nase-save dito. Ang replay at ang simulation lang ang nagbabago.';

  @override
  String simWhatIfOn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagbabago',
      one: '1 pagbabago',
    );
    return 'May what-if: $_temp0';
  }

  @override
  String get simWhatIfTitle => 'What if…';

  @override
  String simWhereLine(String code) {
    return 'Sa $code, ang pangunahing pera mo.';
  }

  @override
  String get simWhereTitle => 'Saan napunta';

  @override
  String get simWholePeriod => 'Buong panahon (tantiya)';

  @override
  String get simZoomDay => 'Araw';

  @override
  String get simZoomMonth => 'Buwan';

  @override
  String get simZoomWeek => 'Linggo';

  @override
  String get simZoomYear => 'Taon';

  @override
  String get splitAccountFallback => 'account';

  @override
  String get splitApproveButton => 'Aprubahan ang split';

  @override
  String get splitApproved => 'Naaprubahan';

  @override
  String get splitApprovedDone => 'Naaprubahan ang split.';

  @override
  String get splitBillFallback => 'isang bill';

  @override
  String splitBrokenLink(String rule, String bill, String reason) {
    return 'Hindi maipon ng $rule para sa $bill: $reason.';
  }

  @override
  String get splitClearAll => 'Burahin ang lahat ng naunang split';

  @override
  String get splitClearAllBody =>
      'Buburahin nang tuluyan ang bawat naitalang split, aprubado man o hindi. Mananatili ang mga bill, rule at payday mo.';

  @override
  String get splitClearAllTitle => 'Buburahin ang lahat ng naunang split?';

  @override
  String get splitClearAllYes => 'Burahin lahat';

  @override
  String get splitCleared => 'Nabura ang mga split.';

  @override
  String splitCopied(String amount) {
    return 'Nakopya ang $amount';
  }

  @override
  String get splitCopyTooltip => 'Kopyahin ang halaga';

  @override
  String splitCoveredLine(String bill, String account) {
    return '$bill  ·  nasa $account na';
  }

  @override
  String get splitCutOrMove => 'Puwede mong bawasan o ilipat:';

  @override
  String splitDeleteBody(String date, String amount) {
    return 'Buburahin nang tuluyan ang split para sa payday na $date ($amount).';
  }

  @override
  String get splitDeleteButton => 'Burahin ang split na ito';

  @override
  String get splitDeleteEntriesHelp =>
      'Magbabago ang mga balanse ng account mo.';

  @override
  String get splitDeleteEntriesSwitch =>
      'Alisin din sa mga balanse ko ang sahod at mga transfer nito';

  @override
  String get splitDeleteKeepsMoney =>
      'Mananatili sa mga account mo ang perang naitala mo na o minarkahang naipadala.';

  @override
  String get splitDeleteTitle => 'Buburahin ang split na ito?';

  @override
  String get splitDeleteYes => 'Burahin';

  @override
  String get splitDeleted => 'Nabura ang split.';

  @override
  String splitForeignLine(
    String name,
    String amount,
    String converted,
    String rate,
  ) {
    return '$name: $amount ay binilang na $converted ($rate)';
  }

  @override
  String get splitForeignTitle => 'Mga bill sa ibang pera';

  @override
  String get splitFromElsewhereTitle => 'Hindi kinuha sa sahod na ito';

  @override
  String splitFundedLine(String bill, String rule) {
    return '$bill  ·  naipon ng $rule';
  }

  @override
  String get splitMarkSent => 'Markahang naipadala';

  @override
  String get splitMarkedSent => 'Namarkahang naipadala na.';

  @override
  String get splitMenu => 'Iba pa tungkol sa split na ito';

  @override
  String splitPayday(String date) {
    return 'Payday $date';
  }

  @override
  String get splitPlanAgain => 'Planuhin ulit';

  @override
  String get splitSent => 'Naipadala';

  @override
  String splitShort(String gap) {
    return 'Kulang ng $gap ang sweldong ito sa itinabi mo.';
  }

  @override
  String get splitTransfers => 'Mga ililipat';

  @override
  String splitUnfundedLine(String bill) {
    return '$bill  ·  kailangan pa mula sa sahod na ito';
  }

  @override
  String summaryMissingRates(int count) {
    return '$count pera ang wala sa kabuuang ito: wala pa silang palitan.';
  }

  @override
  String toolBlockedNamed(String what) {
    return 'Hinarang: $what';
  }

  @override
  String toolFailedNamed(String what) {
    return 'Hindi umubra: $what';
  }

  @override
  String toolGroupChecked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bagay',
    );
    return 'Nasuri ang $_temp0';
  }

  @override
  String get toolGroupChecking => 'Sinusuri ang mga bagay';

  @override
  String toolGroupClosedLabel(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hakbang',
    );
    return '$label, $_temp0, nakasara';
  }

  @override
  String toolGroupOpenLabel(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hakbang',
    );
    return '$label, $_temp0, bukas';
  }

  @override
  String toolGroupOpenedPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pahina',
    );
    return 'Nabuksan ang $_temp0';
  }

  @override
  String get toolGroupOpeningPages => 'Binubuksan ang mga pahina';

  @override
  String toolGroupProgress(int done, int total) {
    return '$done sa $total';
  }

  @override
  String toolGroupReadNotebooks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notebook',
    );
    return 'Nabasa ang $_temp0';
  }

  @override
  String toolGroupReadPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pahina',
    );
    return 'Nabasa ang $_temp0';
  }

  @override
  String get toolGroupReadingNotebooks => 'Binabasa ang mga notebook';

  @override
  String get toolGroupReadingPages => 'Binabasa ang mga pahina';

  @override
  String toolGroupSearchedNotebooks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count beses',
    );
    return 'Naghanap sa mga notebook nang $_temp0';
  }

  @override
  String toolGroupSearchedWeb(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count beses',
    );
    return 'Naghanap sa web nang $_temp0';
  }

  @override
  String get toolGroupSearchingNotebooks => 'Naghahanap sa mga notebook';

  @override
  String get toolGroupSearchingWeb => 'Naghahanap sa web';

  @override
  String toolOpenedPage(String subject) {
    return 'Nabuksan ang $subject';
  }

  @override
  String get toolOpenedPageNone => 'Nagbukas ng web page';

  @override
  String toolOpeningPage(String subject) {
    return 'Binubuksan ang $subject';
  }

  @override
  String get toolOpeningPageNone => 'Binubuksan ang isang web page';

  @override
  String toolReadNotebook(String subject) {
    return 'Nabasa ang notebook na $subject';
  }

  @override
  String get toolReadNotebookNone => 'Nabasa ang mga notebook mo';

  @override
  String toolReadPage(String subject) {
    return 'Nabasa ang pahinang $subject';
  }

  @override
  String get toolReadPageNone => 'Nabasa ang isang pahina';

  @override
  String toolReadingNotebook(String subject) {
    return 'Binabasa ang notebook na $subject';
  }

  @override
  String get toolReadingNotebookNone => 'Binabasa ang mga notebook mo';

  @override
  String toolReadingPage(String subject) {
    return 'Binabasa ang pahinang $subject';
  }

  @override
  String get toolReadingPageNone => 'Binabasa ang isang pahina';

  @override
  String toolSearchedNotebooks(String subject) {
    return 'Hinanap ang $subject sa mga notebook';
  }

  @override
  String get toolSearchedNotebooksNone => 'Naghanap sa mga notebook mo';

  @override
  String toolSearchedWeb(String subject) {
    return 'Naghanap sa web ng $subject';
  }

  @override
  String get toolSearchedWebNone => 'Naghanap sa web';

  @override
  String toolSearchingNotebooks(String subject) {
    return 'Hinahanap ang $subject sa mga notebook';
  }

  @override
  String get toolSearchingNotebooksNone => 'Naghahanap sa mga notebook mo';

  @override
  String toolSearchingWeb(String subject) {
    return 'Naghahanap sa web ng $subject';
  }

  @override
  String get toolSearchingWebNone => 'Naghahanap sa web';

  @override
  String toolTook(String text, int seconds) {
    return '$text, $seconds s';
  }

  @override
  String toolUpdatedPage(String subject) {
    return 'Na-update ang pahinang $subject';
  }

  @override
  String get toolUpdatedPageNone => 'Na-update ang isang pahina';

  @override
  String toolUpdatingNotebook(String subject) {
    return 'Ina-update ang notebook na $subject';
  }

  @override
  String toolUpdatingPage(String subject) {
    return 'Ina-update ang pahinang $subject';
  }

  @override
  String get toolUpdatingPageNone => 'Ina-update ang isang pahina';

  @override
  String toolboxChars(int count) {
    return '$count na character';
  }

  @override
  String toolboxCount(int count, int limit) {
    return '$count sa $limit ang naka-save';
  }

  @override
  String get toolboxDelete => 'Burahin';

  @override
  String toolboxDeleteBody(String name) {
    return 'Aalisin ang \"$name\" sa phone na ito.';
  }

  @override
  String get toolboxDeleteTitle => 'Burahin ang script na ito?';

  @override
  String get toolboxDeleted => 'Nabura ang script.';

  @override
  String get toolboxEmpty => 'Wala pang naka-save.';

  @override
  String get toolboxFailed => 'Hindi mabasa ang toolbox.';

  @override
  String get toolboxNote =>
      'Puwedeng magpatakbo si Botler ng maliliit na script sa phone na ito para magkuwenta o gumawa sa mga larawan. Walang internet ang mga ito, sa scratch folder lang ng bawat chat sila nakakaabot, at hindi nila mababago ang pera o data mo. Magse-save lang si Botler dito kapag hiniling o sinang-ayunan mo.';

  @override
  String get toolboxTitle => 'Toolbox';

  @override
  String transferArrivedLabel(String currency) {
    return 'Halagang dumating ($currency)';
  }

  @override
  String get transferDone => 'Nailipat.';

  @override
  String transferFeeLabel(String currency) {
    return 'Bayad ($currency, opsyonal)';
  }

  @override
  String get transferFrom => 'Mula';

  @override
  String get transferInvalid => 'Tingnan ang mga halaga.';

  @override
  String get transferMove => 'Maglipat ng pera';

  @override
  String get transferQueued =>
      'Naka-save sa phone. Ipapadala ito kapag may koneksyon ka na ulit.';

  @override
  String transferRate(String rate) {
    return 'Rate mo: $rate';
  }

  @override
  String get transferSame => 'Pumili ng dalawang magkaibang wallet.';

  @override
  String transferSentLabel(String currency) {
    return 'Halagang ipinadala ($currency)';
  }

  @override
  String transferSuggest(String amount) {
    return 'Ayon sa rate ngayon, mga $amount. Palitan ito ng talagang dumating.';
  }

  @override
  String get transferTo => 'Papunta';

  @override
  String get uiError => 'May nangyaring mali. Subukan ulit.';

  @override
  String get uiLoading => 'Naglo-load';

  @override
  String get uiNotNow => 'Mamaya na';

  @override
  String get undo => 'I-undo';

  @override
  String updBannerSize(String size) {
    return 'Mga $size MB ang idadownload.';
  }

  @override
  String updBannerTitle(String version) {
    return 'Handa na ang update $version';
  }

  @override
  String get updCheckNow => 'Tingnan ang mga update';

  @override
  String get updDismiss => 'Mamaya na';

  @override
  String updDownloading(int percent) {
    return 'Dinadownload, $percent porsyento';
  }

  @override
  String get updFailDamaged => 'Nasira ang download. Subukan ulit.';

  @override
  String get updFailInstaller => 'Hindi natapos ang update. Subukan ulit.';

  @override
  String get updFailNetwork =>
      'Walang koneksyon. Tingnan ang internet at subukan ulit.';

  @override
  String get updFailPermission =>
      'Payagan ang Botler na mag-install ng apps sa settings ng Android, saka bumalik at subukan ulit.';

  @override
  String get updFailServer =>
      'Hindi maibigay ng server ang update. Subukan ulit mamaya.';

  @override
  String get updFailSpace =>
      'Kulang ang espasyo sa phone. Magbakante at subukan ulit.';

  @override
  String get updFailWrongBuild =>
      'Hindi update ng app na ito ang na-download. Walang na-install.';

  @override
  String get updInstalling =>
      'Humihingi ng pahintulot ang Android para i-install. I-tap ang Install doon.';

  @override
  String get updNow => 'I-update na';

  @override
  String get updOpenSettings => 'Buksan ang settings ng Android';

  @override
  String updPercent(int percent) {
    return '$percent%';
  }

  @override
  String updRequiredBody(String version, String size) {
    return 'Kailangan ang Botler $version para tuloy-tuloy ang takbo. Mga $size MB ito.';
  }

  @override
  String get updRequiredTitle => 'Kailangan ng update';

  @override
  String get updRetry => 'Subukan ulit';

  @override
  String updRowAvailable(String version) {
    return 'Handa nang i-install ang bersyon $version.';
  }

  @override
  String get updRowChecking => 'Tinitingnan ang mga update…';

  @override
  String get updRowFailed => 'Hindi matingnan ang mga update.';

  @override
  String updRowLine(String version, int build) {
    return 'Bersyon $version (build $build)';
  }

  @override
  String updRowPending(int count) {
    return '$count ang naghihintay na i-sync';
  }

  @override
  String get updRowPendingNone => 'Walang naghihintay na i-sync';

  @override
  String get updRowTitle => 'Bersyon ng app';

  @override
  String get updRowUpToDate => 'Pinakabago na ang bersyon mo.';

  @override
  String get updUseForNow => 'Gamitin muna ang app';

  @override
  String get updVerifying => 'Sinisiyasat ang download…';

  @override
  String get webMarkLooking => 'Naghahanap ng logo sa web';

  @override
  String get webMarkNone =>
      'Walang nagamit na logo mula sa web. Hilingin mong subukan ang ibang site, o magpadala ng litrato.';

  @override
  String get webMarkNote =>
      'Nakita sa web at ginupit sa phone mo. Piliin ang gusto mo; ang maliit na ginupit na larawan lang ang sine-save.';

  @override
  String webMarkOption(int n) {
    return 'Pagpipiliang logo $n';
  }

  @override
  String get yes => 'Oo';
}
