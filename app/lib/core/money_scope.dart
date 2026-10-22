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
  /// The person's currency code.
  String get currencyCode => MoneyScope.codeOf(this);

  /// ₱1,234.50 in the person's currency.
  String money(int minor) => formatMoney(minor, currencyCode);

  /// What the person typed as minor units, or null.
  int? parseAmount(String text) => parseMoney(text, currencyCode);

  /// For a text field: 18000 is "180.00", and 180 yen is "180".
  String plainAmount(int minor) => plainAmountIn(minor, currencyCode);
}

/// The amount for a text field in a given currency (see plainAmount in money.dart).
String plainAmountIn(int minor, String code) => plainAmount(minor, code);
