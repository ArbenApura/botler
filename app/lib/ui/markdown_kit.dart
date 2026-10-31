// THE MARKDOWN THE APP DRAWS (THE ASSISTANT'S REPLIES IN THE CHAT, AND THE PAGES OF A NOTEBOOK IN THE READER) IN THE APP'S OWN COLOURS AND TYPE.
// One style sheet for both, so a table or a list looks the same in a reply and on a page. What the model writes is untrusted: pictures are never
// loaded (a picture address could carry private words out), and a link opens only when tapped, and only if it is a web address.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
// The markdown package is what flutter_markdown_plus is built on; its syntax type is needed to add an own inline form and is not re-exported
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

// -- MODULES -- //
import '../theme/tokens.dart';

// -- FUNCTIONS -- //

/// Only web addresses open, and only in the browser the person already uses.
Future<void> openWebLink(String? href) async {
  final uri = href == null ? null : Uri.tryParse(href);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The style sheet. [levels] gives a heading its size by level (the reader needs to tell a chapter from a section); the chat keeps one heading
/// style, so a reply never shouts.
MarkdownStyleSheet botlerMarkdownStyle(
  BuildContext context, {
  bool levels = false,
}) {
  final c = context.colors;
  final t = Theme.of(context).textTheme;
  final body = t.bodyLarge ?? const TextStyle();
  final heading = (t.titleMedium ?? body).copyWith(fontWeight: FontWeight.w700);
  final h1 = levels
      ? (t.titleLarge ?? heading).copyWith(fontWeight: FontWeight.w700)
      : heading;
  final h3 = levels ? body.copyWith(fontWeight: FontWeight.w700) : heading;
  return MarkdownStyleSheet(
    p: body,
    strong: body.copyWith(fontWeight: FontWeight.w700),
    em: body.copyWith(fontStyle: FontStyle.italic),
    a: body.copyWith(color: c.accentText, decoration: TextDecoration.underline),
    h1: h1,
    h2: heading,
    h3: h3,
    h4: h3,
    h5: h3,
    h6: h3,
    code: body.copyWith(
      fontFamily: 'monospace',
      // Code a step smaller than the body text: the theme's medium body size
      fontSize: t.bodyMedium?.fontSize,
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
  );
}

/// Markdown in the app's look. Pictures are blocked; a tap on a link opens only a web address, unless [onTapLink] takes it over (the reader
/// takes over its [[Page]] links).
class BotlerMarkdown extends StatelessWidget {
  const BotlerMarkdown(
    this.data, {
    this.selectable = false,
    this.levels = false,
    this.onTapLink,
    this.builders = const <String, MarkdownElementBuilder>{},
    this.inlineSyntaxes = const <md.InlineSyntax>[],
    super.key,
  });

  final String data;

  /// Words can be selected and copied. Off inside the reader, which is wrapped in one selection area of its own.
  final bool selectable;
  final bool levels;
  final void Function(String text, String? href)? onTapLink;

  /// Own drawing for some elements, by tag (the reader draws a link to a missing page this way).
  final Map<String, MarkdownElementBuilder> builders;

  /// Own inline forms the text may hold, read before the usual ones.
  final List<md.InlineSyntax> inlineSyntaxes;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: selectable,
      builders: builders,
      inlineSyntaxes: inlineSyntaxes,
      // Never fetch a picture the model asked for
      imageBuilder: (_, _, _) => const SizedBox.shrink(),
      onTapLink: (text, href, _) {
        final take = onTapLink;
        if (take != null) {
          take(text, href);
        } else {
          openWebLink(href);
        }
      },
      styleSheet: botlerMarkdownStyle(context, levels: levels),
    );
  }
}
