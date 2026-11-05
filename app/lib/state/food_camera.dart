// THE FOOD CAMERA'S TRIP TO THE SERVER: A SCAN IS ITS OWN SHORT-LIVED, UNLISTED CHAT, SO IT NEVER SHOWS AS A CONVERSATION OR TAKES OVER THE ONE THE PERSON IS HAVING.
// THE PHOTOS GO THROUGH THE SAME CHAT PATH AS ANY PHOTO, IN ONE FOOD CHAT, AND THE MEAL COMES BACK AS A CARD THE PERSON CHECKS.
// Photos are never stored here. Nothing is saved until the card is approved.

// -- DEP-MODULES -- //
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../core/api.dart';
import '../core/device.dart';
import '../core/json.dart';
import '../core/photo_upload.dart';
import 'providers.dart';

// -- CONSTANTS -- //

/// The name of the chat older builds kept every scan in. One build archives it, once.
const String _oldFoodChatTitle = 'Food';
const String _oldFoodChatGoneKey = 'health.foodChatArchived.v1';

// -- TYPES -- //

/// What the photos brought back: a card to check, or words saying why not.
class FoodCameraResult {
  const FoodCameraResult({this.actionId, this.args, this.note, this.failure});

  final String? actionId;
  final Json? args;

  /// The assistant's one question about hidden oil or the portion.
  final String? note;

  /// Why there is no card, in words for the person.
  final String? failure;

  bool get hasCard => actionId != null && args != null;
}

// -- FUNCTIONS -- //

/// Older builds kept every scan in one chat called Food, which sat among the person's conversations. It is archived, so nothing in it is lost. A failure only means trying again next
/// scan, and never stops the scan.
Future<void> _archiveOldFoodChat(WidgetRef ref) async {
  final prefs = ref.read(prefsProvider);
  if (prefs.getBool(_oldFoodChatGoneKey) ?? false) return;
  final api = ref.read(apiProvider);
  try {
    final list = await api.verbJson('chat_list', <String, Object?>{});
    for (final c in asJsonList(list['chats'])) {
      if (str(c['title']) != _oldFoodChatTitle) continue;
      await api.verb('chat_archive', <String, Object?>{
        'chatId': str(c['id']),
        'archived': true,
      }, newRequestId());
    }
    await prefs.setBool(_oldFoodChatGoneKey, true);
  } on ApiException {
    return;
  }
}

/// Sends the photos of one meal or one label. [mode] is 'meal' or 'label'. [barcode] is passed along when a scan led to a label.
Future<FoodCameraResult> sendFoodPhotos(
  WidgetRef ref, {
  required String mode,
  required List<String> paths,
  String? barcode,
  String? correction,
}) async {
  final api = ref.read(apiProvider);
  final reader = PhotoReader();
  final texts = <String>[];
  try {
    for (final p in paths) {
      final t = await reader.read(p);
      if (t.isNotEmpty) texts.add(t);
    }
  } on Object {
    // The text only helps: the picture still goes. A text-only setting is answered by the server
  } finally {
    await reader.close();
  }
  final pictures = await prepareUploads(paths);
  final images = <String>[
    for (final p in pictures)
      if (p != null) p.data,
  ];
  await _archiveOldFoodChat(ref);
  final text = <String>[
    'Food camera: $mode',
    if (barcode != null) 'Barcode $barcode',
    ?correction,
  ].join('. ');
  String? actionId;
  final words = StringBuffer();
  String? failed;
  await for (final e in api.chat(
    id: newRequestId(),
    text: text,
    ocrTexts: texts,
    images: images,
    foodCamera: mode,
  )) {
    switch (str(e['type'])) {
      case 'card':
        if (str(e['verb']) == 'meal_log') actionId = str(e['actionId']);
      // Only the words after the last tool are the answer: what came before was the assistant working
      case 'tool_start':
        words.clear();
      case 'delta':
        words.write(str(e['text']));
      case 'error':
        failed = str(e['message']);
    }
  }
  final said = words.toString().trim();
  if (actionId == null) {
    return FoodCameraResult(failure: failed ?? (said.isEmpty ? null : said));
  }
  final cards = await api.pendingCards();
  for (final c in cards) {
    if (str(c['id']) == actionId) {
      return FoodCameraResult(
        actionId: actionId,
        args: asJson(c['args']),
        note: said.isEmpty ? null : said,
      );
    }
  }
  return FoodCameraResult(failure: failed);
}
