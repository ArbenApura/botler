// WHILE THE PHOTOS ARE READ: A CALM "WORKING ON IT", THEN THE REVIEW. EVERY WAY IT CAN FAIL SAYS WHAT HAPPENED, KEEPS NOTHING AND OFFERS THE NEXT STEP.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../l10n/l10n.dart';
import '../../state/food_camera.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'camera_screen.dart';
import 'food_sheets.dart';
import 'health_parts.dart';

// -- TYPES -- //

class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({
    required this.mode,
    required this.paths,
    this.barcode,
    super.key,
  });

  final String mode;
  final List<String> paths;
  final String? barcode;

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  // -- STATES -- //

  String? _failure;
  bool _offline = false;
  bool _settingBlock = false;
  String? _heldForReview;

  // -- LIFECYCLES -- //

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  // -- FUNCTIONS -- //

  Future<void> _run() async {
    final t = context.t;
    try {
      final r = await sendFoodPhotos(
        ref,
        mode: widget.mode,
        paths: widget.paths,
        barcode: widget.barcode,
      );
      if (!mounted) return;
      if (r.hasCard) {
        _heldForReview = widget.paths.isEmpty ? null : widget.paths.first;
        context.pushReplacement(
          '/health/review',
          extra: <String, Object?>{
            'photo': _heldForReview,
            'actionId': r.actionId,
            'args': r.args,
            'note': r.note,
          },
        );
        return;
      }
      setState(() => _failure = r.failure ?? t.healthPhotoFailedLine);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _offline = e.isNetwork;
        _settingBlock = e.code == 'INVALID' && widget.mode == 'meal';
        _failure = e.isNetwork ? t.healthCameraOffline : e.message;
      });
    } on Object {
      if (mounted) setState(() => _failure = t.healthPhotoFailedLine);
    } finally {
      // The review shows the first photo and deletes it when it closes
      unawaited(
        deleteShots(widget.paths.where((p) => p != _heldForReview).toList()),
      );
    }
  }

  // -- WIDGETS -- //

  Widget _photo() {
    final first = widget.paths.isEmpty ? null : widget.paths.first;
    if (first == null) return const SizedBox(height: 200);
    return SizedBox(
      height: 260,
      width: double.infinity,
      child: Image.file(
        File(first),
        fit: BoxFit.cover,
        semanticLabel: context.t.healthPhotoLabel,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final failure = _failure;
    if (failure != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconTile(
                  _settingBlock
                      ? Icons.image_outlined
                      : _offline
                      ? Icons.wifi_off
                      : Icons.report_gmailerrorred_outlined,
                  size: 72,
                  color: _settingBlock ? c.accentText : c.warning,
                  fill: _settingBlock ? c.accentSoft : c.chip,
                ),
                const SizedBox(height: 16),
                Text(
                  _settingBlock
                      ? t.healthPhotoSettingTitle
                      : _offline
                      ? t.healthCameraOfflineTitle
                      : t.healthPhotoFailedTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  failure,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: BottomDock(
          primary: FilledButton(
            onPressed: () => context.pushReplacement(
              _settingBlock
                  ? '/health/camera?mode=barcode'
                  : '/health/camera?mode=${widget.mode}',
            ),
            child: Text(
              _settingBlock ? t.healthScanBarcode : t.healthTakeAnother,
            ),
          ),
          below: TextButton(
            onPressed: () {
              context.pop();
              unawaited(showAddFoodSheet(context, ref));
            },
            child: Text(t.healthAddByHand),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(t.healthReadingTitle)),
      body: ListView(
        children: <Widget>[
          _photo(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      t.healthWorkingOnIt,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(t.healthReadingLine, style: TextStyle(color: c.muted)),
                const SizedBox(height: 16),
                const SkeletonRows(count: 3, kind: SkeletonKind.tile),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reads a food's source as a short word on the review.
String sourceWord(BuildContext context, String kind) {
  final t = context.t;
  return switch (kind) {
    'usda' || 'usda_branded' => 'USDA',
    'filipino' => t.healthSourceFilipino,
    'saved' => t.healthSourceSaved,
    'off' => 'Open Food Facts',
    'label' => t.healthSourceLabel,
    'estimate' => t.healthSourceEstimate,
    _ => t.healthSourceYours,
  };
}
