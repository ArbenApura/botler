// ONE INTENT, ONE REQUEST KEY, ONE CALL AT A TIME. A SHEET OR CHIP HOLDS A Once: THE KEY IS MADE THE FIRST TIME IT IS ASKED FOR AND KEPT UNTIL THE CALL SUCCEEDS,
// SO A SECOND TAP, A RETRY AFTER A TIMEOUT OR AN OFFLINE QUEUE ENTRY ALL CARRY THE SAME KEY AND THE SERVER ANSWERS A REPEAT WITH THE FIRST RESULT.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/widgets.dart';

// -- MODULES -- //
import '../core/api.dart';

// -- CLASSES -- //

/// Holds the in-flight guard and a lazily made request key for each intent (a short name for "this one thing the person asked for").
class Once {
  /// [onChange] is called when a call starts and when it ends (a widget passes its setState) so a button can be disabled.
  Once([this.onChange]);

  final VoidCallback? onChange;

  final Map<String, String> _keys = <String, String>{};
  final Set<String> _running = <String>{};

  /// The key of [intent]: made on the first ask, the same until the call succeeds ([done]).
  String key([String intent = '']) => _keys.putIfAbsent(intent, newRequestId);

  /// True while a call for [intent] (or any call when [intent] is null) is running.
  bool running([String? intent]) =>
      intent == null ? _running.isNotEmpty : _running.contains(intent);

  /// Forgets the key of [intent], so the next time it is a new thing.
  void done([String intent = '']) => _keys.remove(intent);

  /// Runs [body] with the key of [intent] unless one is already running for it (then returns null at once).
  /// The key is dropped when [body] finishes without an error and kept when it throws, so a retry is the same request.
  Future<T?> run<T>(
    Future<T> Function(String key) body, {
    String intent = '',
  }) async {
    if (_running.contains(intent)) return null;
    _running.add(intent);
    onChange?.call();
    try {
      final result = await body(key(intent));
      done(intent);
      return result;
    } on ApiException catch (e) {
      // The server already holds this key for a different request (the sheet was edited after a lost answer): the next try is a new thing
      if (e.status == 409) done(intent);
      rethrow;
    } finally {
      _running.remove(intent);
      onChange?.call();
    }
  }
}

/// Extra: [ok] is [Once.run] for a body with no answer. It is true when the body ran and did not throw, false when a call was already running.
extension OnceOk on Once {
  Future<bool> ok(
    Future<void> Function(String key) body, {
    String intent = '',
  }) async {
    final r = await run<bool>((key) async {
      await body(key);
      return true;
    }, intent: intent);
    return r ?? false;
  }
}

/// What a [SheetScope] hands its builder: the text controllers and the [Once] that live as long as the sheet is in the tree.
class SheetState {
  SheetState._(this.c, this.once);

  /// One controller per entry of [SheetScope.texts], in the same order.
  final List<TextEditingController> c;
  final Once once;
}

/// Owns the text controllers and the [Once] of one sheet or dialog. They are disposed when the sheet leaves the tree (after it has
/// animated closed), never while it is still on its way out, and a rebuild of the route keeps them.
class SheetScope extends StatefulWidget {
  const SheetScope({
    required this.builder,
    this.texts = const <String>[''],
    super.key,
  });

  /// The starting text of each controller; only read once.
  final List<String> texts;
  final Widget Function(BuildContext context, SheetState sheet) builder;

  @override
  State<SheetScope> createState() => _SheetScopeState();
}

class _SheetScopeState extends State<SheetScope> {
  // -- STATES -- //
  late final List<TextEditingController> _controllers = <TextEditingController>[
    for (final t in widget.texts) TextEditingController(text: t),
  ];
  late final Once _once = Once(() {
    if (mounted) setState(() {});
  });
  late final SheetState _sheet = SheetState._(_controllers, _once);

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _sheet);
}
