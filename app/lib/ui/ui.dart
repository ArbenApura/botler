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
class Amount extends StatelessWidget {
  const Amount(this.centavos, {this.style, super.key});

  final int centavos;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.headlineMedium;
    return Semantics(
      label: context.money(centavos),
      child: Text(
        context.money(centavos),
        style: base?.copyWith(fontFeatures: tabular),
      ),
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

/// Shows a future's loading, failure (with a retry) or data. The one place that knows how those three look.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    required this.value,
    required this.data,
    this.onRetry,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // A reload keeps the old rows on screen instead of flashing a spinner
    return value.when(
      skipLoadingOnReload: true,
      data: data,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
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
    );
  }
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
    this.maxLines = 1,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboard;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
}
