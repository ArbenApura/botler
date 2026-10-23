// WHAT THE PERSON CAN DO WITH ONE MESSAGE: BRANCH FROM IT INTO A NEW CHAT, EDIT IT AND SEND IT AGAIN FROM JUST BEFORE IT, OR COPY IT.
// A long press opens a small sheet. Branching and editing need the server to know the message, so they wait while a reply is still being written.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'chat_state.dart';

// -- TYPES -- //

/// A message being edited: the composer holds its words until the new version is accepted.
class EditTarget {
  const EditTarget(this.turnId, this.text);

  final String turnId;
  final String text;
}

class EditNotifier extends Notifier<EditTarget?> {
  @override
  EditTarget? build() => null;

  void start(EditTarget target) => state = target;

  void stop() => state = null;
}

final NotifierProvider<EditNotifier, EditTarget?> editProvider =
    NotifierProvider<EditNotifier, EditTarget?>(EditNotifier.new);

// -- FUNCTIONS -- //

/// Opens the sheet for one message. [mine] is true for what the person wrote (it can be edited), false for an answer.
Future<void> showMessageSheet(
  BuildContext context,
  WidgetRef ref, {
  required String text,
  required String? turnId,
  required bool mine,
}) async {
  final t = context.t;
  final busy = ref.read(chatProvider).busy;
  final canBranch = turnId != null && !busy;
  final pick = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.colors.paper,
    builder: (s) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (canBranch)
            ListTile(
              leading: const Icon(Icons.call_split),
              title: Text(t.chatMsgBranch),
              onTap: () => Navigator.of(s).pop('branch'),
            ),
          if (canBranch && mine)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(t.chatMsgEdit),
              onTap: () => Navigator.of(s).pop('edit'),
            ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(t.chatMsgCopy),
            onTap: () => Navigator.of(s).pop('copy'),
          ),
        ],
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  switch (pick) {
    case 'copy':
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) say(context, t.chatMsgCopied);
    case 'edit':
      if (turnId != null) {
        ref.read(editProvider.notifier).start(EditTarget(turnId, text));
      }
    case 'branch':
      if (turnId == null) return;
      try {
        await ref.read(chatProvider.notifier).branch(turnId);
      } catch (e) {
        if (context.mounted) say(context, errorWords(e, context));
      }
  }
}
