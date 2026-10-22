// THE TEXT OF THE APP IN THE PERSON'S LANGUAGE. A WIDGET WRITES context.t.someKey; THE WORDS ARE IN lib/l10n/parts (BUILT BY tool/l10n.dart).

// -- DEP-MODULES -- //
import 'package:flutter/widgets.dart';

// -- MODULES -- //
import 'app_localizations.dart';

export 'app_localizations.dart';

// -- TYPES -- //

extension L10nContext on BuildContext {
  /// The words in the app's language.
  AppLocalizations get t => AppLocalizations.of(this);
}

/// The words in a language without a BuildContext, for a notification made in the background.
AppLocalizations wordsFor(String language) =>
    lookupAppLocalizations(Locale(language == 'fil' ? 'fil' : 'en'));
