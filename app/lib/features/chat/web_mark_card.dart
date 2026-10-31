// THE PART OF AN APPROVAL CARD FOR "FIND A LOGO ON THE WEB FOR THIS ACCOUNT OR BILL" (BTL-20261031-1334): THE PHONE DOWNLOADS THE CANDIDATES ITSELF, TRIMS AND FITS EACH ONE,
// SHOWS THEM, LETS THE PERSON PICK, ZOOM AND MOVE, AND SENDS THE SMALL PICTURE WITH THE APPROVAL. The server never fetches or sees the candidates.

// -- DEP-MODULES -- //
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/photo_crop.dart';
import '../../core/web_logo.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/mark_badge.dart';
import 'photo_mark_card.dart';

// -- CONSTANTS -- //

/// The verb a web picture card carries.
const String webMarkVerb = 'mark_from_web';

const double _previewSize = 96;
const double _optionSize = 56;

// -- TYPES -- //

/// The names and sources of a pending web picture card, or null when [action] is another kind of card.
({String name, String? domain, List<String> urls, CropFit fit})? webMarkOf(
  Json? action,
) {
  if (action == null || str(action['verb']) != webMarkVerb) return null;
  final args = asJson(action['args']);
  final domain = str(args['domain']);
  final urls = args['urls'];
  return (
    name: str(args['name']),
    domain: domain.isEmpty ? null : domain,
    urls: urls is List<Object?>
        ? urls.whereType<String>().toList()
        : <String>[],
    fit: args['fit'] == 'cover' ? CropFit.cover : CropFit.contain,
  );
}

/// The candidates of one card, found once when the card first shows and kept until the app restarts (a card scrolled away and back is not
/// downloaded again). Empty when nothing usable was found.
final webCandidatesProvider = FutureProvider.autoDispose
    .family<List<WebLogoCandidate>, String>((ref, actionId) async {
      final link = ref.keepAlive();
      final card = await ref.watch(pendingCardProvider(actionId).future);
      final want = webMarkOf(card);
      if (want == null) {
        link.close();
        return <WebLogoCandidate>[];
      }
      final found = await findLogoCandidates(
        domain: want.domain,
        urls: want.urls,
        client: ref.watch(webClientProvider),
        resolver: ref.watch(webResolverProvider),
      );
      // Only a find that has pictures is kept while the card scrolls away and back; an empty one (no connection at that moment) is asked
      // again the next time, and the pictures are let go when the card is answered
      if (found.isEmpty) link.close();
      return found;
    });

class WebMarkEditor extends ConsumerStatefulWidget {
  const WebMarkEditor({
    required this.actionId,
    required this.name,
    required this.fit,
    required this.deciding,
    required this.onApprove,
    required this.onReject,
    super.key,
  });

  final String actionId;
  final String name;
  final CropFit fit;
  final bool deciding;
  final void Function(Uint8List picture) onApprove;
  final VoidCallback onReject;

  @override
  ConsumerState<WebMarkEditor> createState() => _WebMarkEditorState();
}

class _WebMarkEditorState extends ConsumerState<WebMarkEditor> {
  // -- STATES -- //

  int _selected = 0;
  // What the person adjusted, by candidate position
  final Map<int, CropPlan> _plans = <int, CropPlan>{};

  // -- FUNCTIONS -- //

  CropPlan _planOf(List<WebLogoCandidate> all, int i) =>
      _plans[i] ?? _start(all[i]);

  // The small pictures already cut, by candidate and plan, so a rebuild does not cut them all again
  final Map<String, Uint8List?> _cuts = <String, Uint8List?>{};

  Uint8List? _cut(List<WebLogoCandidate> all, int i, CropPlan plan) =>
      _cuts.putIfAbsent(
        '$i|${plan.x}|${plan.y}|${plan.width}|${plan.height}|${plan.fit}',
        () => all[i].source.cut(plan),
      );

  /// Applies the fit the assistant asked for (contain is the automatic trim already): "cover" fills the badge from the middle of the trimmed box.
  CropPlan _start(WebLogoCandidate c) =>
      widget.fit == CropFit.cover ? c.plan.withFit(CropFit.cover) : c.plan;

  void _change(int i, CropPlan next) => setState(() => _plans[i] = next);

  // -- WIDGETS -- //

  Widget _nudge(IconData icon, String label, VoidCallback? onTap) => IconButton(
    icon: Icon(icon),
    tooltip: label,
    onPressed: widget.deciding ? null : onTap,
  );

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final found = ref.watch(webCandidatesProvider(widget.actionId));
    return found.when(
      loading: () => Row(
        children: <Widget>[
          Semantics(
            label: t.webMarkLooking,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(t.webMarkLooking, style: TextStyle(color: c.muted)),
          ),
        ],
      ),
      error: (_, _) => _none(t, c),
      data: (all) {
        if (all.isEmpty) return _none(t, c);
        final i = _selected.clamp(0, all.length - 1);
        final plan = _planOf(all, i);
        final picture = _cut(all, i, plan);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Semantics(
                  label: t.photoMarkPreview,
                  image: true,
                  excludeSemantics: true,
                  child: picture != null
                      ? MarkBadge(
                          name: widget.name,
                          preview: picture,
                          size: _previewSize,
                        )
                      : SizedBox(
                          width: _previewSize,
                          height: _previewSize,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: c.muted,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t.webMarkNote, style: TextStyle(color: c.muted)),
                ),
              ],
            ),
            if (all.length > 1) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (var k = 0; k < all.length; k++)
                    _option(t, c, all, k, k == i),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Wrap(
              children: <Widget>[
                _nudge(
                  Icons.zoom_in,
                  t.photoMarkZoomIn,
                  () => _change(i, plan.zoomed(cropZoomStep)),
                ),
                _nudge(
                  Icons.zoom_out,
                  t.photoMarkZoomOut,
                  () => _change(i, plan.zoomed(1 / cropZoomStep)),
                ),
                _nudge(
                  Icons.arrow_back,
                  t.photoMarkLeft,
                  () => _change(i, plan.moved(-cropMoveStep, 0)),
                ),
                _nudge(
                  Icons.arrow_forward,
                  t.photoMarkRight,
                  () => _change(i, plan.moved(cropMoveStep, 0)),
                ),
                _nudge(
                  Icons.arrow_upward,
                  t.photoMarkUp,
                  () => _change(i, plan.moved(0, -cropMoveStep)),
                ),
                _nudge(
                  Icons.arrow_downward,
                  t.photoMarkDown,
                  () => _change(i, plan.moved(0, cropMoveStep)),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: Text(t.photoMarkFill),
                  selected: plan.fit == CropFit.cover,
                  onSelected: widget.deciding
                      ? null
                      : (_) => _change(i, plan.withFit(CropFit.cover)),
                ),
                ChoiceChip(
                  label: Text(t.photoMarkWhole),
                  selected: plan.fit == CropFit.contain,
                  onSelected: widget.deciding
                      ? null
                      : (_) => _change(i, plan.withFit(CropFit.contain)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FilledButton(
                  onPressed: widget.deciding || picture == null
                      ? null
                      : () => widget.onApprove(picture),
                  child: Text(t.photoMarkApprove),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: widget.deciding ? null : widget.onReject,
                  child: Text(t.chatNotNow),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// One candidate as a small tappable picture, at least 48 dp.
  Widget _option(
    AppLocalizations t,
    BotlerColors c,
    List<WebLogoCandidate> all,
    int k,
    bool selected,
  ) {
    final cut = _cut(all, k, _planOf(all, k));
    return Semantics(
      label: t.webMarkOption(k + 1),
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(_optionSize * 0.3),
        onTap: widget.deciding ? null : () => setState(() => _selected = k),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_optionSize * 0.3 + 3),
            border: Border.all(
              color: selected ? c.accent : c.line,
              width: selected ? 3 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: cut != null
                ? MarkBadge(name: widget.name, preview: cut, size: _optionSize)
                : const SizedBox(width: _optionSize, height: _optionSize),
          ),
        ),
      ),
    );
  }

  Widget _none(AppLocalizations t, BotlerColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(t.webMarkNone, style: TextStyle(color: c.danger)),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          OutlinedButton(
            onPressed: widget.deciding
                ? null
                : () => ref.invalidate(webCandidatesProvider(widget.actionId)),
            child: Text(t.photoMarkRetry),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.deciding ? null : widget.onReject,
            child: Text(t.chatNotNow),
          ),
        ],
      ),
    ],
  );
}
