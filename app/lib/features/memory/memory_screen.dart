// MEMORY: WHAT BOTLER REMEMBERS ABOUT YOU, IN PLAIN SENTENCES YOU CAN EDIT OR DELETE; ITS QUESTIONS WHEN TWO THINGS DISAGREE; HOW YOU WANT IT TO TALK;
// AND EXPORT OR WIPE EVERYTHING. A memory you delete does not come back. What you write yourself is never changed behind your back.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- CONSTANTS -- //

final FutureProvider<List<Json>> _facts =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('memory_list', <String, Object?>{
        'limit': 200,
      }),
    );
final FutureProvider<List<Json>> _pending =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('memory_list', <String, Object?>{
        'pending': true,
      }),
    );
final FutureProvider<Json> _profile = FutureProvider.autoDispose<Json>(
  (ref) => ref.watch(apiProvider).verbJson('profile_get'),
);

// -- TYPES -- //

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  String _query = '';

  void _refresh() => ref
    ..invalidate(_facts)
    ..invalidate(_pending)
    ..invalidate(_profile);

  Future<void> _call(String verb, Json args, {String? done}) async {
    try {
      await ref.read(apiProvider).verb(verb, args);
      _refresh();
      if (done != null && mounted) say(context, done);
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _text(
    String title, {
    String? initial,
    required Future<void> Function(String) save,
  }) async {
    final controller = TextEditingController(text: initial);
    final saved = await showFormSheet<bool>(
      context,
      title: title,
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Field(
            controller: controller,
            label: context.t.memoryInSentence,
            maxLines: 3,
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              await save(controller.text.trim());
              close(true);
            },
            child: Text(context.t.save),
          ),
        ],
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _wipe() async {
    final typed = TextEditingController();
    final wipeWord = context.t.memoryWipeWord;
    final wiped = context.t.memoryWiped;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text(context.t.memoryWipeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.t.memoryWipeBody),
            const SizedBox(height: 12),
            TextField(
              controller: typed,
              decoration: InputDecoration(labelText: context.t.memoryWipeType),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(context.t.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
              foregroundColor: context.colors.paper,
            ),
            onPressed: () => Navigator.of(d).pop(typed.text.trim() == wipeWord),
            child: Text(context.t.memoryWipe),
          ),
        ],
      ),
    );
    if (ok == true)
      await _call('memory_wipe', <String, Object?>{
        'confirm': true,
      }, done: wiped);
  }

  Future<void> _export() async {
    final copied = context.t.memoryCopied;
    try {
      final all = await ref.read(apiProvider).verb('memory_export');
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(all)),
      );
      if (mounted) say(context, copied);
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final facts = ref.watch(_facts);
    final pending = ref.watch(_pending);
    return Scaffold(
      appBar: AppBar(title: Text(context.t.memoryTitle)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          AsyncBody<List<Json>>(
            value: pending,
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              final active = facts.value ?? <Json>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionTitle(context.t.memoryNotSure),
                  for (final p in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PaperCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              context.t.memoryWhichRight,
                              style: TextStyle(color: c.muted),
                            ),
                            const SizedBox(height: 4),
                            ...<Widget>[
                              for (final old in active.where(
                                (f) =>
                                    p['subject'] != null &&
                                    f['subject'] == p['subject'],
                              ))
                                Text(context.t.memoryBefore(str(old['text']))),
                              Text(context.t.memoryNow(str(p['text']))),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: <Widget>[
                                FilledButton(
                                  onPressed: () =>
                                      _call('memory_resolve', <String, Object?>{
                                        'factId': str(p['id']),
                                        'keep': 'new',
                                      }),
                                  child: Text(context.t.memoryUseNew),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _call('memory_resolve', <String, Object?>{
                                        'factId': str(p['id']),
                                        'keep': 'old',
                                      }),
                                  child: Text(context.t.memoryKeepOld),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          SectionTitle(context.t.memoryRemembers),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.t.memorySearchHint,
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          AsyncBody<List<Json>>(
            value: facts,
            onRetry: () => ref.invalidate(_facts),
            data: (all) {
              final list = all
                  .where(
                    (f) =>
                        _query.isEmpty ||
                        str(f['text']).toLowerCase().contains(_query),
                  )
                  .toList();
              if (list.isEmpty) return Note(context.t.memoryEmpty);
              return Column(
                children: <Widget>[
                  for (final f in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(str(f['text'])),
                      subtitle: Text(
                        str(f['source']) == 'user'
                            ? context.t.memoryYouSaid
                            : context.t.memoryLearned,
                        style: TextStyle(color: c.muted),
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: context.t.memoryMore,
                        onSelected: (v) async {
                          final forgotten = context.t.memoryForgotten;
                          if (v == 'edit') {
                            await _text(
                              context.t.memoryChangeTitle,
                              initial: str(f['text']),
                              save: (t) => ref.read(apiProvider).verb(
                                'memory_edit',
                                <String, Object?>{
                                  'factId': str(f['id']),
                                  'text': t,
                                },
                              ),
                            );
                          } else if (await confirm(
                            context,
                            title: context.t.memoryForgetTitle,
                            body: context.t.memoryForgetBody(str(f['text'])),
                            yes: context.t.memoryForgetYes,
                            danger: true,
                          )) {
                            await _call('memory_forget', <String, Object?>{
                              'factId': str(f['id']),
                            }, done: forgotten);
                          }
                        },
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: Text(context.t.memoryChange),
                          ),
                          PopupMenuItem<String>(
                            value: 'forget',
                            child: Text(context.t.memoryForget),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          OutlinedButton.icon(
            onPressed: () => _text(
              context.t.memoryRememberTitle,
              save: (t) => ref.read(apiProvider).verb(
                'memory_remember',
                <String, Object?>{'text': t},
              ),
            ),
            icon: const Icon(Icons.add),
            label: Text(context.t.memoryTellSomething),
          ),
          SectionTitle(context.t.memoryTalks),
          AsyncBody<Json>(
            value: ref.watch(_profile),
            onRetry: () => ref.invalidate(_profile),
            data: (p) => _ProfileForm(profile: p, onSaved: _refresh),
          ),
          SectionTitle(context.t.memoryYourData),
          OutlinedButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.copy_all_outlined),
            label: Text(context.t.memoryCopyAll),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: c.danger),
            onPressed: _wipe,
            icon: const Icon(Icons.delete_outline),
            label: Text(context.t.memoryWipeButton),
          ),
        ],
      ),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile, required this.onSaved});

  final Json profile;
  final VoidCallback onSaved;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final TextEditingController _persona = TextEditingController(
    text: str(widget.profile['persona']),
  );
  late final TextEditingController _about = TextEditingController(
    text: str(widget.profile['about']),
  );
  late final TextEditingController _people = TextEditingController(
    text: asList(widget.profile['people']).whereType<String>().join(', '),
  );

  @override
  void dispose() {
    _persona.dispose();
    _about.dispose();
    _people.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Field(
          controller: _persona,
          label: context.t.memoryPersonaLabel,
          hint: context.t.memoryPersonaHint,
          maxLines: 3,
        ),
        Field(
          controller: _about,
          label: context.t.memoryAboutLabel,
          maxLines: 3,
        ),
        Field(
          controller: _people,
          label: context.t.memoryPeopleLabel,
          hint: context.t.memoryPeopleHint,
        ),
        Text(
          context.t.memoryPeopleNote,
          style: TextStyle(color: context.colors.muted),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            final saved = context.t.memorySaved;
            try {
              await ref.read(apiProvider).verb('profile_set', <String, Object?>{
                'persona': _persona.text.trim(),
                'about': _about.text.trim(),
                'people': <String>[
                  for (final n in _people.text.split(','))
                    if (n.trim().isNotEmpty) n.trim(),
                ],
              });
              widget.onSaved();
              if (context.mounted) say(context, saved);
            } catch (e) {
              if (context.mounted) say(context, errorWords(e, context));
            }
          },
          child: Text(context.t.save),
        ),
      ],
    );
  }
}
