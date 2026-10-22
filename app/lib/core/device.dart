// THE PHONE'S OWN SENSES: LISTENING (ENGLISH OR FILIPINO) AND READING A PHOTO OF A RECEIPT. BOTH STAY ON THE PHONE.
// Only the words that come out are ever sent: the recording and the picture are not. The server treats text read from a photo as untrusted and the
// amount in it is always shown for a yes before it is saved.

// -- DEP-MODULES -- //
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

// -- TYPES -- //

enum PhotoSource { camera, gallery }

/// The words heard so far; [finished] is true for the last piece.
typedef HeardCallback = void Function(String text, {required bool finished});

// -- FUNCTIONS -- //

/// Takes or picks a photo and reads the text on it with the on-device reader. Null when the person cancelled.
Future<String?> readPhotoText(PhotoSource source) async {
  final file = await ImagePicker().pickImage(
    source: source == PhotoSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: 2000,
    imageQuality: 85,
  );
  if (file == null) return null;
  final recognizer = TextRecognizer();
  try {
    final result = await recognizer.processImage(
      InputImage.fromFilePath(file.path),
    );
    final text = result.text.trim();
    // A receipt is short; a very long read is not one, and the server caps it too
    return text.length > 6000 ? text.substring(0, 6000) : text;
  } finally {
    await recognizer.close();
  }
}

/// Speech to text with a locale the person chose (en_PH for English, fil_PH for Filipino and Taglish).
class VoiceListener {
  final SpeechToText _speech = SpeechToText();
  bool _ready = false;

  bool get listening => _speech.isListening;

  /// Starts listening. [onText] gets the words so far; [finished] is true for the last one. Returns false when the phone cannot listen.
  Future<bool> start(String locale, HeardCallback onText) async {
    _ready = _ready || await _speech.initialize();
    if (!_ready) return false;
    await _speech.listen(
      onResult: (r) => onText(r.recognizedWords, finished: r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: locale,
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
    return true;
  }

  Future<void> stop() => _speech.stop();
}
