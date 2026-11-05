// THE FOOD CAMERA: ONE SCREEN WITH THREE MODES, MEAL, BARCODE AND LABEL. ONLY ONE CAMERA IS EVER OPEN: SWITCHING MODE OR LEAVING THE APP CLOSES IT AND OPENS IT AGAIN.
// A capture is sized down to the chat's photo limits before it goes anywhere, and the files are deleted when the screen closes.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';

// -- CONSTANTS -- //

const int maxMealAngles = 3;

// -- TYPES -- //

class FoodCameraScreen extends StatefulWidget {
  const FoodCameraScreen({this.mode = 'meal', this.barcode, super.key});

  /// 'meal', 'barcode' or 'label'.
  final String mode;

  /// The barcode a label belongs to, when a scan found nothing.
  final String? barcode;

  @override
  State<FoodCameraScreen> createState() => _FoodCameraScreenState();
}

class _FoodCameraScreenState extends State<FoodCameraScreen>
    with WidgetsBindingObserver {
  // -- STATES -- //

  late String _mode = widget.mode;
  CameraController? _camera;
  MobileScannerController? _scanner;
  bool _denied = false;
  bool _flash = false;
  bool _busy = false;
  bool _scanned = false;
  final List<String> _shots = <String>[];

  // -- LIFECYCLES -- //

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_close());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_open());
    }
  }

  // -- FUNCTIONS -- //

  Future<void> _close() async {
    final camera = _camera;
    final scanner = _scanner;
    _camera = null;
    _scanner = null;
    await camera?.dispose();
    await scanner?.dispose();
  }

  Future<void> _open() async {
    await _close();
    if (!mounted) return;
    if (_mode == 'barcode') {
      setState(() {
        _scanner = MobileScannerController(
          formats: const <BarcodeFormat>[
            BarcodeFormat.ean13,
            BarcodeFormat.ean8,
            BarcodeFormat.upcA,
            BarcodeFormat.upcE,
          ],
          detectionSpeed: DetectionSpeed.noDuplicates,
        );
      });
      return;
    }
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted || _mode == 'barcode') {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _denied = false;
      });
    } on CameraException {
      if (mounted) setState(() => _denied = true);
    } on StateError {
      // This phone reports no camera at all
      if (mounted) setState(() => _denied = true);
    }
  }

  Future<void> _switch(String mode) async {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _shots.clear();
      _scanned = false;
    });
    await _open();
  }

  Future<void> _toggleFlash() async {
    final next = !_flash;
    setState(() => _flash = next);
    await _camera?.setFlashMode(next ? FlashMode.torch : FlashMode.off);
    if (_scanner != null) await _scanner?.toggleTorch();
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await camera.takePicture();
      if (!mounted) return;
      _shots.add(shot.path);
      if (_mode == 'label' || _shots.length >= maxMealAngles) {
        _finish();
      } else {
        setState(() {});
      }
    } on CameraException {
      if (mounted) setState(() => _denied = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gallery() async {
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 2000,
      imageQuality: 85,
      limit: _mode == 'label' ? 1 : maxMealAngles,
    );
    if (files.isEmpty || !mounted) return;
    _shots
      ..clear()
      ..addAll(files.map((f) => f.path));
    _finish();
  }

  void _finish() {
    if (_shots.isEmpty) return;
    unawaited(_close());
    context.pushReplacement(
      '/health/reading',
      extra: <String, Object?>{
        'mode': _mode,
        'paths': List<String>.of(_shots),
        'barcode': widget.barcode,
      },
    );
  }

  void _onBarcode(BarcodeCapture capture) {
    if (_scanned) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || !RegExp(r'^\d{8,14}$').hasMatch(code)) return;
    _scanned = true;
    unawaited(_close());
    context.pushReplacement(
      '/health/barcode',
      extra: <String, Object?>{'code': code},
    );
  }

  // -- WIDGETS -- //

  Widget _preview() {
    final c = context.colors;
    final t = context.t;
    if (_denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            t.healthCameraDenied,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.onScrim),
          ),
        ),
      );
    }
    final scanner = _scanner;
    if (scanner != null) {
      return MobileScanner(controller: scanner, onDetect: _onBarcode);
    }
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const SizedBox.expand();
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: camera.value.previewSize?.height ?? 1080,
          height: camera.value.previewSize?.width ?? 1920,
          child: CameraPreview(camera),
        ),
      ),
    );
  }

  String get _hint {
    final t = context.t;
    return switch (_mode) {
      'barcode' => t.healthCameraHintBarcode,
      'label' => t.healthCameraHintLabel,
      _ =>
        _shots.isEmpty
            ? t.healthCameraHintMeal
            : t.healthCameraHintAngle('${_shots.length}', '$maxMealAngles'),
    };
  }

  Widget _modeTabs() {
    final c = context.colors;
    final t = context.t;
    Widget tab(String mode, String text) {
      final on = mode == _mode;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: text,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _switch(mode),
            child: Container(
              alignment: Alignment.center,
              constraints: const BoxConstraints(minHeight: minTap),
              decoration: BoxDecoration(
                color: on ? c.onScrim : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: on ? c.scrim : c.onScrim,
                  fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        tab('meal', t.healthCameraMeal),
        tab('barcode', t.healthCameraBarcode),
        tab('label', t.healthCameraLabel),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.t;
    return Scaffold(
      backgroundColor: c.scrim,
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _preview(),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          IconButton.filledTonal(
                            tooltip: t.healthClose,
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.close),
                          ),
                          IconButton.filledTonal(
                            tooltip: t.healthFlash,
                            onPressed: _toggleFlash,
                            icon: Icon(
                              _flash ? Icons.flash_on : Icons.flash_off,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.onScrim),
                  ),
                  const SizedBox(height: 12),
                  _modeTabs(),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 64),
                        child: _shots.isEmpty || _mode != 'meal'
                            ? null
                            : TextButton(
                                onPressed: _finish,
                                child: Text(
                                  t.healthDone,
                                  style: TextStyle(color: c.onScrim),
                                ),
                              ),
                      ),
                      Semantics(
                        button: true,
                        label: t.healthCameraTake,
                        child: GestureDetector(
                          onTap: _mode == 'barcode' ? null : _shoot,
                          child: Opacity(
                            opacity: _mode == 'barcode' || _busy ? 0.4 : 1,
                            child: Container(
                              width: 76,
                              height: 76,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: c.onScrim, width: 3),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c.onScrim,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: _mode == 'barcode'
                            ? null
                            : IconButton(
                                tooltip: t.healthCameraGallery,
                                onPressed: _gallery,
                                icon: Icon(
                                  Icons.photo_library_outlined,
                                  color: c.onScrim,
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Removes the temporary files of the photos once they have been sent.
Future<void> deleteShots(List<String> paths) async {
  for (final p in paths) {
    try {
      await File(p).delete();
    } on FileSystemException {
      // Already gone, or it belongs to the gallery's cache: the phone clears those itself
    }
  }
}
