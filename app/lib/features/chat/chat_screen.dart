// THE ONE SCREEN THE APP OPENS ON: THE SUMMARY CARD, THE CONVERSATION, AND A BOX TO TALK TO BOTLER BY TYPING, SPEAKING OR PHOTOGRAPHING A RECEIPT.
// One primary action: send. The menu holds everything else (accounts, bills, payday, history, agenda, memory, settings).

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/device.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'chat_items.dart';
import 'chat_state.dart';
import 'summary_card.dart';

// -- TYPES -- //

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final VoiceListener _listener = VoiceListener();
  String? _photoText;
  bool _hearing = false;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    final photo = _photoText;
    if (text.isEmpty && photo == null) return;
    _text.clear();
    setState(() => _photoText = null);
    await ref
        .read(chatProvider.notifier)
        .send(text.isEmpty ? 'Here is a receipt.' : text, ocrText: photo);
    ref
      ..invalidate(syncProvider)
      ..invalidate(balancesProvider);
  }

  Future<void> _photo(PhotoSource source) async {
    try {
      final read = await readPhotoText(source);
      if (read == null || !mounted) return;
      if (read.isEmpty) {
        say(context, 'I could not read any text on that photo.');
        return;
      }
      setState(() => _photoText = read);
    } catch (_) {
      if (mounted) say(context, 'The photo could not be read.');
    }
  }

  Future<void> _speak() async {
    if (_hearing) {
      await _listener.stop();
      setState(() => _hearing = false);
      return;
    }
    final locale = ref.read(settingsProvider).speechLocale;
    final ok = await _listener.start(locale, (words, {required finished}) {
      if (!mounted) return;
      _text.text = words;
      _text.selection = TextSelection.collapsed(offset: words.length);
      if (finished) setState(() => _hearing = false);
    });
    if (!mounted) return;
    if (ok) {
      setState(() => _hearing = true);
    } else {
      say(
        context,
        'This phone cannot listen right now. Check the microphone permission.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chat = ref.watch(chatProvider);
    final pending = ref.watch(outboxCountProvider);
    ref.listen<ChatState>(chatProvider, (_, _) => _toEnd());
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: 'B',
                style: TextStyle(color: c.accent, fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: 'otler'),
            ],
          ),
        ),
        actions: <Widget>[
          if (pending > 0)
            IconButton(
              tooltip: '$pending waiting to be sent',
              onPressed: () => say(
                context,
                '$pending entries are waiting for a connection.',
              ),
              icon: Badge(
                label: Text('$pending'),
                child: const Icon(Icons.cloud_off_outlined),
              ),
            ),
          IconButton(
            tooltip: 'Menu',
            onPressed: () => context.push('/menu'),
            icon: const Icon(Icons.menu),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(syncProvider);
                  await ref.read(syncProvider.future);
                },
                child: ListView.separated(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: chat.items.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) => i == 0
                      ? const SummaryCard()
                      : ChatItemView(
                          chat.items[i - 1],
                          key: ValueKey<int>(chat.items[i - 1].id),
                        ),
                ),
              ),
            ),
            if (_photoText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: InputChip(
                  label: Text('Photo read (${_photoText!.length} characters)'),
                  onDeleted: () => setState(() => _photoText = null),
                ),
              ),
            _Composer(
              controller: _text,
              busy: chat.busy,
              hearing: _hearing,
              onSend: _send,
              onSpeak: _speak,
              onPhoto: () async {
                final source = await showModalBottomSheet<PhotoSource>(
                  context: context,
                  showDragHandle: true,
                  backgroundColor: c.paper,
                  builder: (s) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ListTile(
                          leading: const Icon(Icons.photo_camera_outlined),
                          title: const Text('Take a photo'),
                          onTap: () => Navigator.of(s).pop(PhotoSource.camera),
                        ),
                        ListTile(
                          leading: const Icon(Icons.photo_outlined),
                          title: const Text('Choose a screenshot'),
                          onTap: () => Navigator.of(s).pop(PhotoSource.gallery),
                        ),
                      ],
                    ),
                  ),
                );
                if (source != null) await _photo(source);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.hearing,
    required this.onSend,
    required this.onSpeak,
    required this.onPhoto,
  });

  final TextEditingController controller;
  final bool busy;
  final bool hearing;
  final VoidCallback onSend;
  final VoidCallback onSpeak;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          IconButton(
            tooltip: 'Photo of a receipt',
            onPressed: busy ? null : onPhoto,
            icon: const Icon(Icons.photo_camera_outlined),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Tell Botler… "lunch 180 gcash"',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: hearing ? 'Stop listening' : 'Speak',
            onPressed: busy ? null : onSpeak,
            icon: Icon(
              hearing ? Icons.stop_circle_outlined : Icons.mic_none,
              color: hearing ? c.danger : null,
            ),
          ),
          FilledButton(
            onPressed: busy ? null : onSend,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send'),
          ),
        ],
      ),
    );
  }
}
