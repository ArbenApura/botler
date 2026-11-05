// THE FOOD CAMERA'S TRIP TO THE SERVER: THE PHOTOS GO THROUGH THE SAME CHAT PATH AS ANY PHOTO, IN ONE FOOD CHAT, AND THE MEAL COMES BACK AS A CARD THE PERSON CHECKS.
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

/// The name of the chat that holds food camera messages, so ordinary chats stay clean.
const String foodChatTitle = 'Food';

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

String? _foodChatNewKey;
String? _foodChatRenameKey;

/// The Food chat's id, made the first time.
Future<String> foodChatId(ApiClient api) async {
  final list = await api.verbJson('chat_list', <String, Object?>{});
  final chats = asJsonList(list['chats']);
  for (final c in chats) {
    if (str(c['title']) == foodChatTitle) return str(c['id']);
  }
  // The same keys until both calls worked, so a retry after a dropped connection makes no second chat
  final newKey = _foodChatNewKey ??= newRequestId();
  final renameKey = _foodChatRenameKey ??= newRequestId();
  final made = await api.verbJson(
    'chat_new',
    const <String, Object?>{},
    newKey,
  );
  final id = str(made['id'], str(made['chatId']));
  await api.verb('chat_rename', <String, Object?>{
    'chatId': id,
    'title': foodChatTitle,
  }, renameKey);
  _foodChatNewKey = null;
  _foodChatRenameKey = null;
  return id;
}

/// Sends the photos of one meal or one label. [mode] is 'meal' or 'label'. [barcode] is passed along when a scan led to a label.
Future<FoodCameraResult> sendFoodPhotos(
  WidgetRef ref, {
  required String mode,
  required List<String> paths,
  String? barcode,
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
  final chatId = await foodChatId(api);
  final text = barcode == null
      ? 'Food camera: $mode'
      : 'Food camera: $mode. Barcode $barcode';
  String? actionId;
  final words = StringBuffer();
  String? failed;
  await for (final e in api.chat(
    id: newRequestId(),
    text: text,
    ocrTexts: texts,
    images: images,
    chatId: chatId,
    foodCamera: mode,
  )) {
    switch (str(e['type'])) {
      case 'card':
        if (str(e['verb']) == 'meal_log') actionId = str(e['actionId']);
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
