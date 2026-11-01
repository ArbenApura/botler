// SMALL PIECES OF THE AGENDA TABS: ONE CARD ROW WITH A LEADING AND A TRAILING SLOT, AND THE SPACING AROUND A LIST AND ITS ADD BUTTONS.
// Every row is a card with the same gap under it, so no tab stacks its rows flush against each other or against the buttons.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- CONSTANTS -- //

/// The vertical gap between two rows, and between the list and what follows it.
const double rowGap = 8;

/// The gap between the last row and the add buttons.
const double addGap = 12;

// -- TYPES -- //

/// One agenda row as a card: [leading], a title with an optional quiet [subtitle], and [trailing]. When [onTap] is given the whole card is the target.
class AgendaRow extends StatelessWidget {
  const AgendaRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.struck = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Draws the title crossed out and quiet, for something that is switched off.
  final bool struck;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: rowGap),
      child: PaperCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTap + 8),
          child: Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading ?? const SizedBox.shrink(),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: text.titleMedium?.copyWith(
                          color: struck ? c.muted : c.ink,
                          decoration: struck
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle ?? '',
                            style: text.bodySmall?.copyWith(color: c.muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 4),
                trailing ?? const SizedBox.shrink(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A round soft icon badge for the leading slot of a row.
class RowBadge extends StatelessWidget {
  const RowBadge(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 20, color: c.accentText),
      ),
    );
  }
}
