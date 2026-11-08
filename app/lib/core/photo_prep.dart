// A PHOTO MADE READY IN THE BACKGROUND: ITS TEXT READ ON THE PHONE AND ITS PICTURE RESIZED AND COMPRESSED, STARTED RIGHT AFTER IT IS PICKED.
// Each photo gets ONE future that covers both jobs. At most two photos are worked on at once (each in its own isolate), and the text reader
// handles one photo at a time. A photo that cannot be read has no text, a picture that cannot be made is simply missing: the message then goes with
// whatever is left. Nothing here is stored, and nothing waits for the person: sending waits for these futures only at the last moment.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import 'device.dart' show PhotoReader;
import 'photo_upload.dart';

// -- TYPES -- //

/// What came of one photo: the words read from it (empty when none or unreadable) and its picture (null when not asked for or not made).
class PhotoResult {
  const PhotoResult(this.text, this.picture);

  final String text;
  final UploadPicture? picture;

  /// Nothing to send from this photo.
  bool get empty => text.isEmpty && picture == null;
}

/// One photo being made ready: its staged copy on this phone and the future that finishes it. The future never fails.
class PhotoJob {
  const PhotoJob(this.path, this.result);

  final String path;
  final Future<PhotoResult> result;
}

/// Lets only [permits] jobs run at the same time; the rest wait their turn in order.
class _Gate {
  _Gate(this.permits);

  int permits;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() job) async {
    if (permits > 0) {
      permits--;
    } else {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    try {
      return await job();
    } finally {
      if (_waiting.isEmpty) {
        permits++;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}

/// The most photos worked on at the same time.
const int photoJobsAtOnce = 2;

/// Starts the background work for photos. The text reader is made on first use and closed with the app.
class PhotoPrepper {
  PhotoPrepper({
    Future<String> Function(String path)? read,
    Future<UploadPicture?> Function(String path)? prepare,
  }) : _readOverride = read,
       _prepare = prepare ?? prepareUpload;

  final Future<String> Function(String path)? _readOverride;
  final Future<UploadPicture?> Function(String path) _prepare;
  final _Gate _jobs = _Gate(photoJobsAtOnce);
  final _Gate _reading = _Gate(1);
  PhotoReader? _reader;

  Future<String> _read(String path) {
    final custom = _readOverride;
    if (custom != null) return custom(path);
    return (_reader ??= PhotoReader()).read(path);
  }

  /// Starts reading the text on the copy at [path] and, when [picture] is true, making its picture. The result is ready to be awaited later.
  PhotoJob start(String path, {required bool picture}) {
    final result = _jobs.run(() async {
      var text = '';
      try {
        text = await _reading.run(() => _read(path));
      } on Object {
        // A photo that cannot be read has no text
      }
      UploadPicture? made;
      if (picture) {
        try {
          made = await _prepare(path);
        } on Object {
          // A picture that cannot be made leaves the text to go alone
        }
      }
      return PhotoResult(text, made);
    });
    return PhotoJob(path, result);
  }

  Future<void> close() async {
    final reader = _reader;
    _reader = null;
    try {
      await reader?.close();
    } on Object {
      // Closing is best effort
    }
  }
}

// -- PROVIDERS -- //

/// The one background worker for photos. It lives as long as the app, so a message already sent keeps its photos coming when the screen is left.
final Provider<PhotoPrepper> photoPrepperProvider = Provider<PhotoPrepper>((
  ref,
) {
  final prepper = PhotoPrepper();
  ref.onDispose(() => unawaited(prepper.close()));
  return prepper;
});
