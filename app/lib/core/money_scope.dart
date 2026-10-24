// THE CURRENCY THE SCREENS SHOW AMOUNTS IN. PLACED ONCE ABOVE THE APP, SO A WIDGET WRITES context.money(minor) AND NEVER NAMES A CURRENCY.

// -- DEP-MODULES -- //
import 'package:flutter/widgets.dart';

// -- MODULES -- //
import 'money.dart';

// -- TYPES -- //

class MoneyScope extends InheritedWidget {
  const MoneyScope({required this.currency, required super.child, super.key});

  /// The ISO code of the person's currency.
  final String currency;

  static String codeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoneyScope>()?.currency ??
      defaultCurrency;

  @override
  bool updateShouldNotify(MoneyScope oldWidget) =>
      oldWidget.currency != currency;
}

extension MoneyContext on BuildContext {
  /// The person's MAIN currency code: the currency of the plan (bills in it, income, goals) and of every total.
  String get currencyCode => MoneyScope.codeOf(this);

  /// ₱1,234.50 in the main currency. Only for an amount that IS in the main currency (a total, the plan). An amount of a wallet or of
  /// a bill in another currency is shown with moneyIn and its own code, so a dollar is never written with a peso sign.
  String moneyMain(int minor) => formatMoney(minor, currencyCode);

  /// An amount in the currency it is in (a wallet, a bill, an entry), with that currency's symbol.
  String moneyIn(int minor, String currency) => formatMoney(minor, currency);

  /// What the person typed as minor units of the main currency, or null.
  int? parseAmountMain(String text) => parseMoney(text, currencyCode);

  /// What the person typed as minor units of the given currency, or null. A yen amount refuses a decimal point.
  int? parseAmountIn(String text, String currency) =>
      parseMoney(text, currency);

  /// For a text field: 18000 is "180.00", and 180 yen is "180", in the main currency.
  String plainAmountMain(int minor) => plainAmountIn(minor, currencyCode);
}

/// The amount for a text field in a given currency (see plainAmount in money.dart).
String plainAmountIn(int minor, String code) => plainAmount(minor, code);
