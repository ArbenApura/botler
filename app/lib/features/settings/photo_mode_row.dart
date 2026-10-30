// THE PHOTOS SECTION OF SETTINGS: WHETHER THE ASSISTANT GETS THE PICTURE ITSELF OR ONLY THE TEXT THE PHONE READ FROM IT.
// The choice is kept on the server first, like the other shared settings, because the server is what decides what reaches the AI. The words under
// it say plainly what leaves the phone, and say so when the AI server cannot look at pictures at all.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'provider_row.dart';

// -- CONSTANTS -- //

/// Remembers on this phone that the person has been told, once, that a picture is sent as it is.
const String pictureNoticeKey = 'photos.noticeSeen';

// -- FUNCTIONS -- //

/// The name of the AI server a picture goes to, for the words that name it: the one that looks at pictures, which is the person's own server
/// when it can and another one when it cannot.
String answeringServer(Settings s) =>
    providerLabel(s.photoHost ?? s.modelProvider ?? 'deepseek');

/// True when the pictures go to a different server from the one that answers the rest of the chat.
bool picturesGoElsewhere(Settings s) =>
    s.photoHost != null &&
    s.modelProvider != null &&
    s.photoHost != s.modelProvider;

/// Tells the person once that a picture is sent as it is, and asks. True when pictures may go; false when they chose text only (which is saved).
/// Nothing is asked again after the first answer.
Future<bool> pictureNoticeAccepted(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(prefsProvider);
  if (prefs.getBool(pictureNoticeKey) ?? false) return true;
  final server = answeringServer(ref.read(settingsProvider));
  final yes = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (d) => AlertDialog(
      title: Text(d.t.photoNoticeTitle),
      content: Text(d.t.photoNoticeBody(server)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(d).pop(false),
          child: Text(d.t.photoNoticeNo),
        ),
        FilledButton(
          onPressed: () => Navigator.of(d).pop(true),
          child: Text(d.t.photoNoticeYes),
        ),
      ],
    ),
  );
  if (yes ?? false) {
    await prefs.setBool(pictureNoticeKey, true);
    return true;
  }
  try {
    await ref.read(settingsProvider.notifier).saveToServer(photoMode: 'text');
  } on Object {
    // The choice is kept on this phone even when the server cannot be reached; the server still decides what it receives
    await ref
        .read(settingsProvider.notifier)
        .update(ref.read(settingsProvider).copyWith(photoMode: 'text'));
  }
  return false;
}

// -- WIDGETS -- //

class PhotoModeRow extends StatelessWidget {
  const PhotoModeRow({
    required this.settings,
    required this.onChanged,
    super.key,
  });

  final Settings settings;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final server = answeringServer(settings);
    final image = settings.photoMode == 'image';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(t.settingsPhotosTitle),
          Semantics(
            label: t.settingsPhotosTitle,
            child: SegmentedButton<String>(
              segments: <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'image',
                  icon: const Icon(Icons.image_outlined),
                  label: Text(t.settingsPhotoImage),
                ),
                ButtonSegment<String>(
                  value: 'text',
                  icon: const Icon(Icons.text_fields),
                  label: Text(t.settingsPhotoText),
                ),
              ],
              selected: <String>{settings.photoMode},
              onSelectionChanged: (v) => onChanged(v.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            image
                ? (settings.photoVision
                      ? (picturesGoElsewhere(settings)
                            ? t.settingsPhotoHelpOther(
                                server,
                                providerLabel(settings.modelProvider ?? ''),
                              )
                            : t.settingsPhotoHelpImage(server))
                      : t.settingsPhotoNoVision(
                          providerLabel(settings.modelProvider ?? 'deepseek'),
                        ))
                : t.settingsPhotoHelpText,
            style: TextStyle(color: c.muted),
          ),
        ],
      ),
    );
  }
}
