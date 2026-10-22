// MEMORY: WHAT BOTLER REMEMBERS ABOUT YOU, IN PLAIN SENTENCES YOU CAN EDIT OR DELETE; ITS QUESTIONS WHEN TWO THINGS DISAGREE; HOW YOU WANT IT TO TALK;
// AND EXPORT OR WIPE EVERYTHING. A memory you delete does not come back. What you write yourself is never changed behind your back.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
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
      if (mounted) say(context, errorWords(e));
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
          Field(controller: controller, label: 'In a sentence', maxLines: 3),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              await save(controller.text.trim());
              close(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _wipe() async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: const Text('Wipe everything Botler remembers?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'This deletes all memories, summaries and your conversations with Botler. Your accounts, bills and money records stay. It cannot be undone.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: typed,
              decoration: const InputDecoration(
                labelText: 'Type WIPE to confirm',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
              foregroundColor: context.colors.paper,
            ),
            onPressed: () => Navigator.of(d).pop(typed.text.trim() == 'WIPE'),
            child: const Text('Wipe'),
          ),
        ],
      ),
    );
    if (ok == true)
      await _call('memory_wipe', <String, Object?>{
        'confirm': true,
      }, done: 'Wiped.');
  }

  Future<void> _export() async {
    try {
      final all = await ref.read(apiProvider).verb('memory_export');
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(all)),
      );
      if (mounted) say(context, 'Copied everything to the clipboard.');
    } catch (e) {
      if (mounted) say(context, errorWords(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final facts = ref.watch(_facts);
    final pending = ref.watch(_pending);
    return Scaffold(
      appBar: AppBar(title: const Text('Memory')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          AsyncBody<List<Json>>(
            value: pending,
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              final active = facts.value ?? <Json>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionTitle('Botler is not sure'),
                  for (final p in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PaperCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Which is right?',
                              style: TextStyle(color: c.muted),
                            ),
                            const SizedBox(height: 4),
                            ...<Widget>[
                              for (final old in active.where(
                                (f) =>
                                    p['subject'] != null &&
                                    f['subject'] == p['subject'],
                              ))
                                Text('Before: ${str(old['text'])}'),
                              Text('Now: ${str(p['text'])}'),
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
                                  child: const Text('Use the new one'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _call('memory_resolve', <String, Object?>{
                                        'factId': str(p['id']),
                                        'keep': 'old',
                                      }),
                                  child: const Text('Keep the old one'),
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
          const SectionTitle('What Botler remembers'),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search the memories',
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
              if (list.isEmpty)
                return const Note(
                  'Nothing yet. Botler learns as you talk, or tell it: “remember that…”.',
                );
              return Column(
                children: <Widget>[
                  for (final f in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(str(f['text'])),
                      subtitle: Text(
                        str(f['source']) == 'user'
                            ? 'You said'
                            : 'Learned from chat',
                        style: TextStyle(color: c.muted),
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'More',
                        onSelected: (v) async {
                          if (v == 'edit') {
                            await _text(
                              'Change this memory',
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
                            title: 'Forget this?',
                            body:
                                '“${str(f['text'])}” will be deleted and will not come back.',
                            yes: 'Forget it',
                            danger: true,
                          )) {
                            await _call('memory_forget', <String, Object?>{
                              'factId': str(f['id']),
                            }, done: 'Forgotten.');
                          }
                        },
                        itemBuilder: (_) => const <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: Text('Change'),
                          ),
                          PopupMenuItem<String>(
                            value: 'forget',
                            child: Text('Forget'),
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
              'Remember something',
              save: (t) => ref.read(apiProvider).verb(
                'memory_remember',
                <String, Object?>{'text': t},
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Tell Botler something to remember'),
          ),
          const SectionTitle('How Botler talks to you'),
          AsyncBody<Json>(
            value: ref.watch(_profile),
            onRetry: () => ref.invalidate(_profile),
            data: (p) => _ProfileForm(profile: p, onSaved: _refresh),
          ),
          const SectionTitle('Your data'),
          OutlinedButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Copy everything (memory and money) as text'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: c.danger),
            onPressed: _wipe,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Wipe what Botler remembers'),
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
          label: 'How should Botler talk?',
          hint: 'Like a friendly older sister, short answers',
          maxLines: 3,
        ),
        Field(controller: _about, label: 'A few lines about you', maxLines: 3),
        Field(
          controller: _people,
          label: 'Names to keep private (separate with commas)',
          hint: 'Mama, Ate Liza',
        ),
        Text(
          'Botler hides these names from the AI that writes its replies.',
          style: TextStyle(color: context.colors.muted),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
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
              if (context.mounted) say(context, 'Saved.');
            } catch (e) {
              if (context.mounted) say(context, errorWords(e));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
