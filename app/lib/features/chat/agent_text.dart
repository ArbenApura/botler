// THE ASSISTANT'S WORDS, DRAWN AS MARKDOWN (BOLD, LISTS, CODE, LINKS) IN THE APP'S OWN COLOURS AND TYPE.
// What the model writes is untrusted: pictures are never loaded (a picture address could carry private words out), and a link opens only when tapped.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// -- MODULES -- //
import '../../theme/tokens.dart';

// -- TYPES -- //

class AgentText extends StatelessWidget {
  const AgentText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final body = t.bodyLarge ?? const TextStyle();
    final heading = (t.titleMedium ?? body).copyWith(
      fontWeight: FontWeight.w700,
    );
    return MarkdownBody(
      data: text,
      selectable: true,
      // Never fetch a picture the model asked for
      imageBuilder: (_, _, _) => const SizedBox.shrink(),
      onTapLink: (_, href, _) => _open(href),
      styleSheet: MarkdownStyleSheet(
        p: body,
        strong: body.copyWith(fontWeight: FontWeight.w700),
        em: body.copyWith(fontStyle: FontStyle.italic),
        a: body.copyWith(
          color: c.accentText,
          decoration: TextDecoration.underline,
        ),
        h1: heading,
        h2: heading,
        h3: heading,
        h4: heading,
        code: body.copyWith(
          fontFamily: 'monospace',
          fontSize: 14,
          backgroundColor: c.chip,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(12),
        ),
        listBullet: body,
        listIndent: 20,
        blockSpacing: 8,
        blockquote: body.copyWith(color: c.muted),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.line, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
        tableBorder: TableBorder.all(color: c.line),
        tableHead: body.copyWith(fontWeight: FontWeight.w700),
        tableBody: body,
        tableCellsPadding: const EdgeInsets.all(8),
      ),
    );
  }

  /// Only web addresses open, and only in the browser the person already uses.
  static Future<void> _open(String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
