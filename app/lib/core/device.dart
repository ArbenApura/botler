// THE PHONE'S OWN SENSES: LISTENING (ENGLISH OR FILIPINO) AND READING THE PHOTOS OF RECEIPTS. BOTH STAY ON THE PHONE.
// Only the words that come out are ever sent: the recording and the picture are not. The server treats text read from a photo as untrusted and the
// amount in it is always shown for a yes before it is saved.

// -- DEP-MODULES -- //
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

// -- MODULES -- //
import 'photo_budget.dart';

// -- TYPES -- //

enum PhotoSource { camera, gallery }

/// The words heard so far; [finished] is true for the last piece.
typedef HeardCallback = void Function(String text, {required bool finished});

// -- FUNCTIONS -- //

/// Takes one photo with the camera, or picks up to [room] from the gallery. Only the paths come back; empty when the person cancelled.
Future<List<String>> pickPhotos(PhotoSource source, {required int room}) async {
  final picker = ImagePicker();
  if (source == PhotoSource.camera || room < 2) {
    final file = await picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    return file == null ? const <String>[] : <String>[file.path];
  }
  final files = await picker.pickMultiImage(
    maxWidth: 2000,
    imageQuality: 85,
    limit: room,
  );
  // Some phones ignore the limit, so it is kept here as well
  return <String>[for (final f in files.take(room)) f.path];
}

/// Reads the text on photos with the on-device reader, one after another. Close it when the photos are done.
class PhotoReader {
  final TextRecognizer _recognizer = TextRecognizer();

  /// The text on the photo at [path], trimmed and cut at the most one photo may send. Empty when it holds no text.
  Future<String> read(String path) async {
    final result = await _recognizer.processImage(
      InputImage.fromFilePath(path),
    );
    final text = result.text.trim();
    return text.length > maxPhotoChars
        ? text.substring(0, maxPhotoChars)
        : text;
  }

  Future<void> close() => _recognizer.close();
}

/// Speech to text with a locale the person chose (en_PH for English, fil_PH for Filipino and Taglish).
class VoiceListener {
  final SpeechToText _speech = SpeechToText();
  bool _ready = false;
  // Told when the phone stops listening by itself (a pause, the time limit, an error), so the screen never keeps showing a live mic
  void Function()? _onEnded;

  bool get listening => _speech.isListening;

  /// Starts listening. [onText] gets the words so far; [finished] is true for the last one. Returns false when the phone cannot listen.
  Future<bool> start(
    String locale,
    HeardCallback onText, {
    required void Function() onEnded,
  }) async {
    _onEnded = onEnded;
    _ready =
        _ready ||
        await _speech.initialize(
          // The phone often ends a dictation with a status and no final result, so the status is what closes the mic
          onStatus: (status) {
            if (status == SpeechToText.doneStatus ||
                status == SpeechToText.notListeningStatus) {
              _onEnded?.call();
            }
          },
          onError: (_) => _onEnded?.call(),
        );
    if (!_ready) return false;
    await _speech.listen(
      onResult: (r) => onText(r.recognizedWords, finished: r.finalResult),
      listenOptions: SpeechListenOptions(
        // A dictation never runs on for ever: it ends after three seconds of quiet or a minute in all
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        localeId: locale,
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
    return true;
  }

  /// Stops and cancels, so the microphone is released and no late result comes in after the person pressed stop.
  Future<void> stop() async {
    _onEnded = null;
    await _speech.stop();
    await _speech.cancel();
  }
}
