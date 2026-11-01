// PICKING THE MARK OF AN ACCOUNT OR A BILL: AN ICON FROM THE BUILT-IN SET, OR A PICTURE FROM THE PHONE'S GALLERY, OR NONE.
// The picture is cut to a small square and shrunk on the phone before it is sent with the save, so it travels in the same request as the rest
// (one request, safe to repeat, and it waits in the outbox like any other write). The assistant never sees a picture; it can set an icon or remove a picture.

// -- DEP-MODULES -- //
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/device.dart';
import '../../core/json.dart';
import '../../core/marks.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- FUNCTIONS -- //

/// The spoken and shown name of an icon key.
String markIconName(BuildContext context, String key) {
  final t = context.t;
  return switch (key) {
    'bank' => t.markIconBank,
    'wallet' => t.markIconWallet,
    'cash' => t.markIconCash,
    'card' => t.markIconCard,
    'piggy' => t.markIconPiggy,
    'savings' => t.markIconSavings,
    'home' => t.markIconHome,
    'rent' => t.markIconRent,
    'bolt' => t.markIconBolt,
    'water' => t.markIconWater,
    'wifi' => t.markIconWifi,
    'phone' => t.markIconPhone,
    'cart' => t.markIconCart,
    'food' => t.markIconFood,
    'fuel' => t.markIconFuel,
    'car' => t.markIconCar,
    'bus' => t.markIconBus,
    'health' => t.markIconHealth,
    'school' => t.markIconSchool,
    'family' => t.markIconFamily,
    'gift' => t.markIconGift,
    'travel' => t.markIconTravel,
    'shopping' => t.markIconShopping,
    'subscription' => t.markIconSubscription,
    'tv' => t.markIconTv,
    'game' => t.markIconGame,
    'insurance' => t.markIconInsurance,
    'tax' => t.markIconTax,
    'loan' => t.markIconLoan,
    'invest' => t.markIconInvest,
    'crypto' => t.markIconCrypto,
    'work' => t.markIconWork,
    'pet' => t.markIconPet,
    'baby' => t.markIconBaby,
    'tools' => t.markIconTools,
    'gym' => t.markIconGym,
    'coffee' => t.markIconCoffee,
    'heart' => t.markIconHeart,
    'star' => t.markIconStar,
    'flag' => t.markIconFlag,
    _ => key,
  };
}

/// A short fingerprint of a picture's bytes, so two different pictures never share a request key.
String _bytesKey(Uint8List? bytes) =>
    bytes == null ? '' : '${bytes.length}-${Object.hashAll(bytes)}';

/// Saves a mark on an account or a bill. Only the mark is sent (plus the version when the row has one), so nothing else about the row changes.
Future<void> saveMark(
  WidgetRef ref, {
  required String verb,
  required String idKey,
  required Json row,
  required MarkChoice choice,
  String? key,
}) async {
  final args = markArgs(choice, markOf(row));
  if (args.isEmpty) return;
  final version = row['version'];
  await ref.read(apiProvider).verb(verb, <String, Object?>{
    idKey: str(row['id']),
    if (version is int) 'expectVersion': version,
    ...args,
  }, key);
}

/// The sheet opened from an account's or a bill's own screen: pick an icon or a picture (or remove it), then Save. True when it was saved.
Future<bool> editMark(
  BuildContext context,
  WidgetRef ref, {
  required String verb,
  required String idKey,
  required Json row,
}) async {
  var choice = const MarkChoice.unchanged();
  final done = await showFormSheet<bool>(
    context,
    title: context.t.markEditTitle(str(row['name'])),
    builder: (sheet, close) => SheetScope(
      texts: const <String>[],
      builder: (_, s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MarkField(
            name: str(row['name']),
            current: markOf(row),
            onChanged: (c) => choice = c,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: s.once.running()
                ? null
                : () async {
                    // Nothing to send when the choice leaves the mark as it is: close without a request or a toast
                    if (markArgs(choice, markOf(row)).isEmpty) {
                      close(false);
                      return;
                    }
                    try {
                      // The intent names the choice, so another choice is a new request and a retry of this one is the same
                      final saved = await s.once.ok(
                        (key) => saveMark(
                          ref,
                          verb: verb,
                          idKey: idKey,
                          row: row,
                          choice: choice,
                          key: key,
                        ),
                        intent:
                            'mark:${choice.kind.name}:${choice.icon ?? _bytesKey(choice.bytes)}',
                      );
                      if (!saved) return;
                      close(true);
                    } catch (e) {
                      if (sheet.mounted) say(sheet, errorWords(e, sheet));
                    }
                  },
            child: Text(sheet.t.save),
          ),
        ],
      ),
    ),
  );
  return done == true;
}

// -- PICKER -- //

/// The badge, the picture buttons and the grid of icons. Reports the choice on every change; [current] is what the row has now.
class MarkField extends StatefulWidget {
  const MarkField({
    required this.name,
    required this.current,
    required this.onChanged,
    super.key,
  });

  final String name;
  final Mark current;
  final ValueChanged<MarkChoice> onChanged;

  @override
  State<MarkField> createState() => _MarkFieldState();
}

class _MarkFieldState extends State<MarkField> {
  // -- STATES -- //

  MarkChoice _choice = const MarkChoice.unchanged();
  bool _busy = false;

  // -- FUNCTIONS -- //

  void _set(MarkChoice c) {
    setState(() => _choice = c);
    widget.onChanged(c);
  }

  /// The mark the badge shows now: the choice if there is one, otherwise what the row has.
  Mark get _shown => switch (_choice.kind) {
    MarkKind.unchanged => widget.current,
    MarkKind.icon => Mark(icon: _choice.icon),
    MarkKind.picture || MarkKind.none => const Mark(),
  };

  bool get _hasMark =>
      _choice.kind == MarkKind.picture ||
      (_choice.kind != MarkKind.none && !_shown.isEmpty);

  Future<void> _pick() async {
    if (_busy) return;
    final t = context.t;
    setState(() => _busy = true);
    try {
      final paths = await pickPhotos(PhotoSource.gallery, room: 1);
      if (paths.isEmpty) return;
      final bytes = await prepareMarkPicture(paths.first);
      if (!mounted) return;
      if (bytes == null) {
        say(context, t.markPictureFailed);
        return;
      }
      _set(MarkChoice.picture(bytes));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final picture = _choice.kind == MarkKind.picture;
    final selected = _choice.kind == MarkKind.icon
        ? _choice.icon
        : _choice.kind == MarkKind.unchanged
        ? widget.current.icon
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            MarkBadge(
              name: widget.name,
              mark: _shown,
              size: 56,
              preview: picture ? _choice.bytes : null,
              announce: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: _busy ? null : _pick,
                    child: Text(
                      picture || widget.current.imageId != null
                          ? t.markChangePicture
                          : t.markChoosePicture,
                    ),
                  ),
                  if (_hasMark)
                    TextButton(
                      onPressed: () => _set(const MarkChoice.none()),
                      child: Text(t.markRemove),
                    ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Text(t.markPictureNote, style: TextStyle(color: c.muted)),
        ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            for (final key in kIconKeys)
              _IconTile(
                iconKey: key,
                selected: selected == key,
                onTap: () => _set(MarkChoice.icon(key)),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// One icon of the grid: a 48 dp target.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.iconKey,
    required this.selected,
    required this.onTap,
  });

  final String iconKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = Mark(icon: iconKey).iconData;
    if (data == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      selected: selected,
      label: context.t.markIconSemantic(markIconName(context, iconKey)),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : null,
              border: Border.all(color: selected ? c.accent : c.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              data,
              size: 24,
              color: selected ? c.accentText : c.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the mark sheet for an account row and refreshes the lists that show it once saved.
Future<void> editAccountMark(
  BuildContext context,
  WidgetRef ref,
  Json account,
) async {
  final saved = await editMark(
    context,
    ref,
    verb: 'account_update',
    idKey: 'accountId',
    row: account,
  );
  if (!saved) return;
  ref
    ..invalidate(balancesProvider)
    ..invalidate(syncProvider);
  if (context.mounted) say(context, context.t.markSaved);
}
