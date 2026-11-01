// THE FILES A SCRIPT SHOWED TO THE PERSON (BTL-20261031-1334): A PICTURE APPEARS IN THE CHAT, ANY OTHER FILE (A SHEET, A PDF, A CSV) IS A TAPPABLE LINE THAT OFFERS SAVE TO PHONE AND SHARE.
// The files live in the chat's scratch folder on this phone, so the same lines come back when the chat is opened again, until the folder is swept (then the line says the file is gone).

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/file_actions.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/photo_viewer.dart';
import '../../ui/ui.dart';

// -- CONSTANTS -- //

const double _thumb = 160;

// -- FUNCTIONS -- //

/// The files a script result names (its "shown" list), as name and size. Empty when it shows none.
List<({String name, int size})> shownOf(Object? data) {
  final raw = asJson(data)['shown'];
  if (raw is! List<Object?>) return const <({String name, int size})>[];
  return <({String name, int size})>[
    for (final e in raw)
      if (e is Map<String, Object?> && e['name'] is String)
        (
          name: e['name']! as String,
          size: e['size'] is int ? e['size']! as int : 0,
        ),
  ];
}

String sizeWords(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024)
    return '${(bytes / 1024).toStringAsFixed(bytes < 10240 ? 1 : 0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData iconOf(String name) {
  final mime = mimeOf(name);
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mime == 'text/csv' || name.toLowerCase().endsWith('.xlsx')) {
    return Icons.table_chart_outlined;
  }
  if (mime == 'application/zip') return Icons.folder_zip_outlined;
  return Icons.description_outlined;
}

// -- WIDGETS -- //

/// The shown files of one script run, under its quiet line.
class ShownFiles extends ConsumerWidget {
  const ShownFiles({required this.files, required this.chatId, super.key});

  final List<({String name, int size})> files;
  final String? chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (files.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<Directory>(
      future: ref.read(scriptStorageProvider).scratchFor(chatId),
      builder: (context, snap) {
        final dir = snap.data;
        if (dir == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final f in files)
                _ShownFile(
                  name: f.name,
                  size: f.size,
                  path: '${dir.path}${Platform.pathSeparator}${f.name}',
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ShownFile extends ConsumerWidget {
  const _ShownFile({
    required this.name,
    required this.size,
    required this.path,
  });

  final String name;
  final int size;
  final String path;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final t = context.t;
    final ok = await ref.read(fileActionsProvider).save(path, name);
    if (context.mounted && ok) say(context, t.fileSaved);
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(fileActionsProvider).share(path, name);
    } on Object {
      if (context.mounted) say(context, context.t.fileSaveFailed);
    }
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(iconOf(name)),
              title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(sizeWords(size)),
            ),
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.download_outlined),
              title: Text(t.fileSave),
              onTap: () {
                Navigator.of(sheet).pop();
                _save(context, ref);
              },
            ),
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.ios_share),
              title: Text(t.fileShare),
              onTap: () {
                Navigator.of(sheet).pop();
                _share(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The picture large, in the same viewer as the chat photos, with the same Save and Share buttons at its foot.
  Future<void> _viewPicture(BuildContext context, WidgetRef ref) {
    return showPhotoViewer(
      context,
      paths: <String>[path],
      onSave: (_) => _save(context, ref),
      onShare: (_) => _share(context, ref),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final exists = File(path).existsSync();
    if (!exists) {
      return Text('$name · ${t.fileGone}', style: TextStyle(color: c.muted));
    }
    if (isPictureName(name)) {
      return Semantics(
        button: true,
        label: t.filePicture(name),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _viewPicture(context, ref),
          onLongPress: () => _menu(context, ref),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: c.line)),
              child: Image.file(
                File(path),
                width: _thumb,
                height: _thumb,
                fit: BoxFit.cover,
                cacheWidth: (_thumb * 2).round(),
                errorBuilder: (_, _, _) => SizedBox(
                  width: _thumb,
                  height: _thumb,
                  child: Icon(Icons.broken_image_outlined, color: c.muted),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: t.fileOpen(name, sizeWords(size)),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _menu(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, maxWidth: 320),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(iconOf(name), color: c.accentText),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(sizeWords(size), style: TextStyle(color: c.muted)),
                  const SizedBox(width: 4),
                  Icon(Icons.download_outlined, size: 18, color: c.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
