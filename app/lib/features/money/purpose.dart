// THE PURPOSE LABEL OF AN ACCOUNT (BTL-20261023-0427): WHAT THE ACCOUNT IS DEDICATED TO, SHOWN AS A SMALL CHIP AND PICKED FROM PRESETS OR TYPED.
// The label is plain text, stored as typed (the presets are English words, not translated). It is cosmetic: it never changes a balance or a rule.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- CONSTANTS -- //

/// The longest label the server accepts.
const int kPurposeMax = 24;

/// The labels offered as chips. A label typed by the person is kept as typed.
const List<String> kPurposePresets = <String>[
  'Emergency',
  'Savings',
  'Daily spending',
  'Bills',
  'Travel',
  'Investments',
  'Education',
  'Debt payoff',
  'Gadgets',
  'Family',
  'Business',
  'Giving',
  'Taxes',
  'Holiday',
  'Allowance',
];

// -- FUNCTIONS -- //

/// The label of an account map, or null when it has none (an older server sends no key at all).
String? purposeOf(Json? account) {
  final v = account?['purpose'];
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// A typed label ready to send: trimmed, and null when blank (which clears it).
String? cleanPurpose(String text) {
  final t = text.trim();
  return t.isEmpty ? null : t;
}

/// The same rules the server checks: at most [kPurposeMax] characters and no run of four or more digits.
bool purposeValid(String? purpose) {
  if (purpose == null) return true;
  if (purpose.length > kPurposeMax) return false;
  return !RegExp(r'\d{4}')
      .hasMatch(purpose.replaceAll(RegExp(r'[\s\-./]'), ''));
}

/// Saves a label (or clears it with null) on an account. Only the label is sent, so nothing else about the account changes.
Future<void> savePurpose(
  WidgetRef ref,
  String accountId,
  String? purpose, {
  String? key,
}) async {
  await ref.read(apiProvider).verb('account_update', <String, Object?>{
    'accountId': accountId,
    'purpose': purpose,
  }, key);
  ref.invalidate(balancesProvider);
}

/// The sheet opened from an account's own screen: pick or type a label, then Save.
Future<void> editPurpose(
  BuildContext context,
  WidgetRef ref,
  Json account,
) async {
  var value = purposeOf(account);
  final done = await showFormSheet<bool>(
    context,
    title: context.t.purposeEditTitle(str(account['name'])),
    builder: (sheet, close) => SheetScope(
      texts: const <String>[],
      builder: (_, s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PurposeField(value: value, onChanged: (v) => value = v),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: s.once.running()
                ? null
                : () async {
                    if (!purposeValid(value)) {
                      say(sheet, sheet.t.purposeInvalid);
                      return;
                    }
                    try {
                      // The intent names the label, so a changed label is a new request and a retry of this one is the same
                      final saved = await s.once.ok(
                        (key) => savePurpose(
                          ref,
                          str(account['id']),
                          value,
                          key: key,
                        ),
                        intent: 'purpose:${value ?? ''}',
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
  if (done == true && context.mounted) say(context, context.t.purposeSaved);
}

// -- DISPLAY -- //

/// The label as a small chip. Not tappable: it sits inside a card or a header and takes no room when there is no label.
class PurposeChip extends StatelessWidget {
  const PurposeChip(this.purpose, {super.key});

  final String? purpose;

  @override
  Widget build(BuildContext context) {
    final p = purpose?.trim() ?? '';
    if (p.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Semantics(
      label: context.t.purposeSemantic(p),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.chip,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Text(
              p,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: c.muted),
            ),
          ),
        ),
      ),
    );
  }
}

// -- PICKER -- //

/// Preset chips, a Custom entry with a text field, and "No label". Reports the label (null when none) on every change.
class PurposeField extends StatefulWidget {
  const PurposeField({required this.value, required this.onChanged, super.key});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  State<PurposeField> createState() => _PurposeFieldState();
}

class _PurposeFieldState extends State<PurposeField> {
  // -- STATES -- //

  late String? _value = widget.value;
  late bool _custom =
      widget.value != null && !kPurposePresets.contains(widget.value);
  late final TextEditingController _text = TextEditingController(
    text: _custom ? widget.value : '',
  );

  // -- LIFECYCLES -- //

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  // -- FUNCTIONS -- //

  void _set(String? v, {required bool custom}) {
    setState(() {
      _value = v;
      _custom = custom;
    });
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t.purposeTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: Text(t.purposeNone),
              selected: _value == null && !_custom,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => _set(null, custom: false),
            ),
            for (final p in kPurposePresets)
              ChoiceChip(
                label: Text(p),
                selected: !_custom && _value == p,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => _set(p, custom: false),
              ),
            ChoiceChip(
              label: Text(t.purposeCustom),
              selected: _custom,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => _set(cleanPurpose(_text.text), custom: true),
            ),
          ],
        ),
        if (_custom)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Field(
              controller: _text,
              label: t.purposeCustomLabel,
              hint: t.purposeCustomHint,
              capitalization: TextCapitalization.sentences,
              maxLength: kPurposeMax,
              onChanged: (v) => _set(cleanPurpose(v), custom: true),
            ),
          )
        else
          const SizedBox(height: 12),
      ],
    );
  }
}
