// THE PART OF AN APPROVAL CARD FOR "USE THIS PHOTO AS THE PICTURE OF AN ACCOUNT OR BILL" (BTL-20261031-1011): THE PHONE CUTS ITS OWN COPY OF THE PHOTO BY THE ASSISTANT'S BOX,
// SHOWS THE RESULT, LETS THE PERSON ZOOM AND MOVE IT, AND SENDS THE SMALL PICTURE WITH THE APPROVAL. The chat photo itself never goes to the server.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/photo_crop.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/mark_badge.dart';

// -- CONSTANTS -- //

/// The verb a photo card carries.
const String photoMarkVerb = 'mark_from_photo';

/// The side of the preview.
const double _previewSize = 96;

// -- TYPES -- //

/// One card still waiting, by id, read fresh when its widget appears (a card made a moment ago is not in an older answer). Null when it is
/// not found. A photo card is told apart here: its plan is in the card's arguments, never in the chat events.
final pendingCardProvider = FutureProvider.autoDispose.family<Json?, String>((
  ref,
  id,
) async {
  final cards = await ref.watch(apiProvider).pendingCards();
  for (final c in cards) {
    if (str(c['id']) == id) {
      // A card scrolled out of the list and back is not fetched again, so what the person adjusted is not reset
      ref.keepAlive();
      return c;
    }
  }
  return null;
});

/// What the person adjusted on a photo card (zoom, move, fit), by card id, so it survives the card leaving the screen and coming back.
/// It holds a few numbers, never the photo, and lives until the app restarts.
final photoPlansProvider = Provider<Map<String, CropPlan>>(
  (ref) => <String, CropPlan>{},
);

/// The crop plan and names of a pending photo card, or null when [action] is another kind of card.
({CropPlan plan, int photo, String name})? photoMarkOf(Json? action) {
  if (action == null || str(action['verb']) != photoMarkVerb) return null;
  final args = asJson(action['args']);
  final photo = args['photo'];
  return (
    plan: CropPlan.fromJson(args),
    photo: photo is int ? photo : 1,
    name: str(args['name']),
  );
}

class PhotoMarkEditor extends ConsumerStatefulWidget {
  const PhotoMarkEditor({
    required this.actionId,
    required this.turnId,
    required this.photo,
    required this.name,
    required this.plan,
    required this.deciding,
    required this.onApprove,
    required this.onReject,
    super.key,
  });

  /// The card, to remember the adjusted plan under.
  final String actionId;

  /// The chat turn the photo was sent in (the phone keeps its copies under it), and which of its photos, counted from 1 as the server
  /// counted them (see ChatPhotoStore.numberedPhotosOf).
  final String? turnId;
  final int photo;
  final String name;
  final CropPlan plan;
  final bool deciding;
  final void Function(Uint8List picture) onApprove;
  final VoidCallback onReject;

  @override
  ConsumerState<PhotoMarkEditor> createState() => _PhotoMarkEditorState();
}

class _PhotoMarkEditorState extends ConsumerState<PhotoMarkEditor> {
  // -- STATES -- //

  late CropPlan _plan =
      ref.read(photoPlansProvider)[widget.actionId] ?? widget.plan;
  CropSource? _source;
  Uint8List? _picture;
  bool _gone = false;
  bool _failed = false;
  // A photo that finishes opening after this widget is gone is ignored
  bool _closed = false;

  // -- LIFECYCLES -- //

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  // -- FUNCTIONS -- //

  /// The phone's copy of the photo this card is about, or null. The photo number is the one the server counted, which the store keeps per turn.
  Future<String?> _find() async {
    final turn = widget.turnId;
    if (turn == null) return null;
    try {
      final store = ref.read(chatPhotoStoreProvider);
      await store.ready();
      final files = store.numberedPhotosOf(turn);
      final i = widget.photo - 1;
      return i >= 0 && i < files.length ? files[i] : null;
    } on Object {
      return null;
    }
  }

  /// Finds the photo (once more after a short wait: the files may still be moving into place when the card appears) and reads it once.
  Future<void> _open() async {
    var found = await _find();
    if (_closed) return;
    if (found == null) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (_closed) return;
      found = await _find();
      if (_closed) return;
    }
    if (found == null) {
      setState(() => _gone = true);
      return;
    }
    final source = await openCropSource(found);
    if (_closed) return;
    if (source == null) {
      setState(() => _failed = true);
      return;
    }
    _source = source;
    _cut();
  }

  /// Cuts the working copy by the current plan. It is fast (a small picture from memory), so every nudge cuts again at once.
  void _cut() {
    final source = _source;
    if (source == null) return;
    final made = source.cut(_plan);
    setState(() {
      _picture = made;
      _failed = made == null;
    });
  }

  void _change(CropPlan next) {
    if (next == _plan) return;
    _plan = next;
    ref.read(photoPlansProvider)[widget.actionId] = next;
    _cut();
  }

  // -- WIDGETS -- //

  Widget _nudge(IconData icon, String label, VoidCallback onTap) => IconButton(
    icon: Icon(icon),
    tooltip: label,
    onPressed: widget.deciding || _source == null ? null : onTap,
  );

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    if (_gone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(t.photoMarkGone, style: TextStyle(color: c.danger)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.deciding ? null : widget.onReject,
            child: Text(t.chatNotNow),
          ),
        ],
      );
    }
    final picture = _picture;
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
                      child: Center(
                        child: _failed
                            ? Icon(Icons.broken_image_outlined, color: c.muted)
                            : Semantics(
                                label: t.photoMarkWorking,
                                child: const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              // A live region: a screen reader says when the cut is under way, done or failed
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _failed
                      ? t.markPictureFailed
                      : picture == null
                      ? t.photoMarkWorking
                      : t.photoMarkNote,
                  style: TextStyle(color: c.muted),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          children: <Widget>[
            _nudge(
              Icons.zoom_in,
              t.photoMarkZoomIn,
              () => _change(_plan.zoomed(cropZoomStep)),
            ),
            _nudge(
              Icons.zoom_out,
              t.photoMarkZoomOut,
              () => _change(_plan.zoomed(1 / cropZoomStep)),
            ),
            _nudge(
              Icons.arrow_back,
              t.photoMarkLeft,
              () => _change(_plan.moved(-cropMoveStep, 0)),
            ),
            _nudge(
              Icons.arrow_forward,
              t.photoMarkRight,
              () => _change(_plan.moved(cropMoveStep, 0)),
            ),
            _nudge(
              Icons.arrow_upward,
              t.photoMarkUp,
              () => _change(_plan.moved(0, -cropMoveStep)),
            ),
            _nudge(
              Icons.arrow_downward,
              t.photoMarkDown,
              () => _change(_plan.moved(0, cropMoveStep)),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: Text(t.photoMarkFill),
              selected: _plan.fit == CropFit.cover,
              onSelected: widget.deciding || _source == null
                  ? null
                  : (_) => _change(_plan.withFit(CropFit.cover)),
            ),
            ChoiceChip(
              label: Text(t.photoMarkWhole),
              selected: _plan.fit == CropFit.contain,
              onSelected: widget.deciding || _source == null
                  ? null
                  : (_) => _change(_plan.withFit(CropFit.contain)),
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
  }
}
