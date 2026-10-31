// THE ASSISTANT'S WORDS, DRAWN AS MARKDOWN (BOLD, LISTS, CODE, LINKS) IN THE APP'S OWN COLOURS AND TYPE.
// What the model writes is untrusted: pictures are never loaded (a picture address could carry private words out), and a link opens only when
// tapped. The style and these rules are shared with the notebook reader: see ui/markdown_kit.dart.
// While an answer streams in, the markdown is read at most once every 250 ms (a token arrives every ~40 ms and a parse of a long answer on each one
// would drop frames); the moment it is complete the whole text is read once more, so the final look is exact.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../ui/markdown_kit.dart';

// -- CONSTANTS -- //

/// The least time between two reads of a streaming answer.
const Duration agentTextThrottle = Duration(milliseconds: 250);

// -- TYPES -- //

class AgentText extends StatefulWidget {
  const AgentText(this.text, {this.streaming = false, super.key});

  final String text;

  /// True while the answer is still arriving.
  final bool streaming;

  /// How many times the markdown was handed new text, for the throttle test.
  @visibleForTesting
  static int renders = 0;

  @override
  State<AgentText> createState() => _AgentTextState();
}

class _AgentTextState extends State<AgentText> {
  // -- STATES -- //
  late String _shown = widget.text;
  late Widget _body = _make();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _later;

  Widget _make() {
    AgentText.renders++;
    return BotlerMarkdown(_shown, selectable: true);
  }

  void _show(String text) {
    _later?.cancel();
    _later = null;
    if (text == _shown) return;
    setState(() {
      _shown = text;
      _body = _make();
      _last = DateTime.now();
    });
  }

  // -- LIFECYCLES -- //

  @override
  void didUpdateWidget(AgentText old) {
    super.didUpdateWidget(old);
    if (widget.text == _shown) return;
    if (!widget.streaming) {
      // Finished: the whole text, now
      _show(widget.text);
      return;
    }
    final wait = agentTextThrottle - DateTime.now().difference(_last);
    if (wait <= Duration.zero) {
      _show(widget.text);
    } else {
      // The newest text is read when the pause is over
      _later ??= Timer(wait, () {
        if (mounted) _show(widget.text);
      });
    }
  }

  @override
  void dispose() {
    _later?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _body;
}
