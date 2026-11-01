// SMALL PIECES SHARED BY THE ACCOUNTS AND BILLS SCREENS: A TINTED STATUS PILL AND A 48 DP ACTION ROW WITH AN ICON AND A CHEVRON.
// Tints are a status token at a low alpha, so both modes stay readable and no literal colour is written here.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../theme/tokens.dart';

// -- CONSTANTS -- //

/// How strong the tint behind a status is. One value, so both screens agree.
const double tintAlpha = 0.14;

/// The smallest height of a tappable row.
const double _rowHeight = 48;

// -- TYPES -- //

/// A short status in a rounded pill: an icon and a line, tinted with a status colour. Wraps its text when it is long.
class InfoPill extends StatelessWidget {
  const InfoPill({
    required this.text,
    required this.color,
    this.icon,
    super.key,
  });

  final String text;

  /// A status colour from the tokens (warning, success, muted...).
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: tintAlpha),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-width line with a leading icon and a chevron that does one thing when tapped. Says its label once to a screen reader.
class ActionRow extends StatelessWidget {
  const ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// What a screen reader says when it differs from the visible text.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _rowHeight),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 20, color: c.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: TextStyle(color: c.ink)),
              ),
              Icon(Icons.chevron_right, size: 20, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}
