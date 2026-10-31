// THE PURE RULES OF THE WHAT-IF SHEET: A PERCENT CHANGE OF AN AMOUNT AND THE LIMITS OF A PRETEND ENTRY. NO CLOCK, NO SCREEN.
// Amounts are integer minor units (centavos). Nothing here uses a float.

// -- CONSTANTS -- //

/// The most pretend entries one what-if holds.
const int maxPretendEntries = 50;

/// The smallest and largest pretend amount, in minor units.
const int minPretendAmount = 1;
const int maxPretendAmount = 1000000000000;

// -- FUNCTIONS -- //

/// [amount] changed by [percent] (10 means 10% more, -10 means 10% less), in whole minor units, a half rounded up, so 1050 cents less 10% is 945 and 5 cents more 10% is 6, the same on the phone as on the server.
int scaleByPercent(int amount, int percent) {
  // Floor division after adding half of the divisor is "round half up"; Dart's ~/ truncates, so a negative inexact quotient steps down one
  final n = amount * (100 + percent) + 50;
  final q = n ~/ 100;
  return n < 0 && n % 100 != 0 ? q - 1 : q;
}

/// Whether a pretend [amount] (minor units) is inside the allowed range.
bool pretendAmountOk(int amount) =>
    amount >= minPretendAmount && amount <= maxPretendAmount;
