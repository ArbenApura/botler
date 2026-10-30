// THE ASSISTANT'S WORDS, DRAWN AS MARKDOWN (BOLD, LISTS, CODE, LINKS) IN THE APP'S OWN COLOURS AND TYPE.
// What the model writes is untrusted: pictures are never loaded (a picture address could carry private words out), and a link opens only when
// tapped. The style and these rules are shared with the notebook reader: see ui/markdown_kit.dart.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../ui/markdown_kit.dart';

// -- TYPES -- //

class AgentText extends StatelessWidget {
  const AgentText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => BotlerMarkdown(text, selectable: true);
}
