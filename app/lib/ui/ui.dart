// A SMALL KIT OF PAPER-STYLE PIECES USED BY EVERY SCREEN: A CARD, A SECTION TITLE, AN AMOUNT, A LOADING-OR-ERROR WRAPPER, A FORM SHEET AND A MESSAGE.
// Every tappable thing is at least 48 dp. Every colour comes from the tokens. One primary button per view: the others are plain.

// -- DEP-MODULES -- //
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../core/api.dart';
import '../core/money_scope.dart';
import '../l10n/l10n.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'skeleton.dart';

// -- EXPORTS -- //
// Screens get the skeleton pieces with the rest of the kit
export 'skeleton.dart';

// -- FUNCTIONS -- //

/// The padding of a scrolling page: 16 on every side, plus the system bar at the bottom so the last row can scroll clear of it.
EdgeInsets pagePadding(BuildContext context) => EdgeInsets.fromLTRB(
  16,
  16,
  16,
  16 + MediaQuery.viewPaddingOf(context).bottom,
);

/// The words to show for a failure. Pass the [context] to get the app's language; without one the phone's language is used.
String errorWords(Object e, [BuildContext? context]) {
  if (e is ApiException) return e.message;
  final words = context != null
      ? context.t
      : wordsFor(ui.PlatformDispatcher.instance.locale.languageCode);
  return words.uiError;
}

void say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A large rounded card on the paper.
class PaperCard extends StatelessWidget {
  const PaperCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: card,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: context.colors.muted),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A money amount in light, tabular figures. Negative amounts are not red: a balance below zero is not an error.
/// [currency] is the currency the amount is in (a wallet, a bill); left out it is the person's main currency. A dollar is never written with a peso sign.
class Amount extends StatelessWidget {
  const Amount(this.centavos, {this.currency, this.style, super.key});

  final int centavos;
  final String? currency;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.headlineMedium;
    final text = currency == null
        ? context.moneyMain(centavos)
        : context.moneyIn(centavos, currency!);
    return Semantics(
      label: text,
      child: Text(text, style: base?.copyWith(fontFeatures: tabular)),
    );
  }
}

class Note extends StatelessWidget {
  const Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.colors.muted),
      ),
    ),
  );
}

/// Fixed keys for the three looks, so loading to data fades once and a reload never remounts the data (a form keeps what was typed).
const ValueKey<String> _loadingKey = ValueKey<String>('async.loading');
const ValueKey<String> _dataKey = ValueKey<String>('async.data');
const ValueKey<String> _errorKey = ValueKey<String>('async.error');

/// How long loading, data and failure fade into one another.
const Duration _fade = Duration(milliseconds: 180);

/// Shows a future's loading (a skeleton of the real content), failure (with a retry) or data. The one place that knows how those three look.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    required this.value,
    required this.data,
    this.onRetry,
    this.skeleton = const SkeletonRows(),
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  /// What stands in for the data while it loads. Make it the same shape and size as the loaded content so nothing jumps.
  final Widget skeleton;

  @override
  Widget build(BuildContext context) {
    // A reload keeps the old rows on screen instead of flashing a skeleton
    final Widget body = value.when(
      skipLoadingOnReload: true,
      data: (d) => KeyedSubtree(key: _dataKey, child: data(d)),
      loading: () => KeyedSubtree(key: _loadingKey, child: skeleton),
      error: (e, _) => KeyedSubtree(
        key: _errorKey,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(errorWords(e, context), textAlign: TextAlign.center),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: Text(context.t.retry)),
            ],
          ),
        ),
      ),
    );
    return AnimatedSwitcher(
      duration: _fade,
      // Pinned to the top, with the parent's constraints passed on, so a tall page keeps its height and a list keeps its place
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.topCenter,
        children: <Widget>[...previous, ?current],
      ),
      child: body,
    );
  }
}

/// A loading page: the skeleton inside the same padding a loaded scrolling page has, and not scrollable.
class SkeletonPage extends StatelessWidget {
  const SkeletonPage({required this.child, this.padding, super.key});

  final Widget child;

  /// Defaults to the padding of a scrolling page. A screen with its own padding passes the same.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const NeverScrollableScrollPhysics(),
    padding: padding ?? pagePadding(context),
    child: child,
  );
}

/// A bottom sheet with a title, content, and one primary action.
Future<T?> showFormSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, void Function(T? result) close)
  builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.colors.paper,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(sheet).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 16),
            builder(sheet, (r) => Navigator.of(sheet).pop(r)),
          ],
        ),
      ),
    ),
  );
}

/// Asks a plain yes or no. [danger] colours the yes button as a warning, never with the accent.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String yes,
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: context.colors.surface,
      title: Text(title),
      content: Text(body),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(d).pop(false),
          child: Text(d.t.uiNotNow),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: context.colors.danger,
                  foregroundColor: context.colors.paper,
                )
              : null,
          onPressed: () => Navigator.of(d).pop(true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// A text field with its own label, used in every form so they look alike.
class Field extends StatelessWidget {
  const Field({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboard,
    this.capitalization = TextCapitalization.sentences,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboard;

  /// Sentences by default so free text starts with a capital. Names pass `words`, a typed code passes `characters`.
  final TextCapitalization capitalization;
  final int maxLines;

  /// Stops typing past this many characters, with no counter shown.
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: keyboard,
      textCapitalization: capitalization,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: maxLength == null ? null : '',
      ),
    ),
  );
}
