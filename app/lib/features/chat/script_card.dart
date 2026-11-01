// THE CARD A SCRIPT OR TOOLBOX CALL IS SHOWN IN, IN THE CHAT: WHILE IT RUNS (A SPINNER AND WHAT IT IS DOING), WHEN IT IS DONE (A TICK, THE FIRST LINES OF WHAT IT PRINTED,
// TAP TO OPEN ALL OF IT) AND WHEN IT DID NOT FINISH (THE REASON). THE FILES IT SHOWED SIT UNDER THE OUTPUT INSIDE THE SAME CARD.
// The output is exactly what the server returned (already masked and capped); nothing here reads a file or echoes the code. Every colour is a token.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';

// -- CONSTANTS -- //

/// The lines of output shown before the card is opened.
const int _previewLines = 4;

/// The most height the opened output takes; longer output scrolls inside it.
const double _openHeight = 240;

/// The stage of a script call.
enum ScriptStage { running, done, failed }

// -- TYPES -- //

class ScriptCard extends StatefulWidget {
  const ScriptCard({
    required this.stage,
    this.toolbox = false,
    this.output = '',
    this.message,
    this.files,
    super.key,
  });

  final ScriptStage stage;

  /// The toolbox opened, not a script run (a different icon and words).
  final bool toolbox;

  /// What the script printed, as the server returned it.
  final String output;

  /// Why it did not finish, when it did not.
  final String? message;

  /// The files the script showed, drawn under the output.
  final Widget? files;

  @override
  State<ScriptCard> createState() => _ScriptCardState();
}

class _ScriptCardState extends State<ScriptCard> {
  // -- STATES -- //

  bool _open = false;

  // -- FUNCTIONS -- //

  String _title(BuildContext context) {
    final t = context.t;
    return switch (widget.stage) {
      ScriptStage.running =>
        widget.toolbox ? t.chatUsingToolbox : t.chatRunningScript,
      ScriptStage.done =>
        widget.toolbox ? t.chatUsedToolbox : t.chatRanScriptQuiet,
      ScriptStage.failed => t.chatScriptFailed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final output = widget.output.trim();
    final failed = widget.stage == ScriptStage.failed;
    final running = widget.stage == ScriptStage.running;
    final long =
        output.split('\n').length > _previewLines ||
        output.length > _previewLines * 60;
    final title = _title(context);
    final reason = widget.message?.trim() ?? '';
    return Semantics(
      container: true,
      liveRegion: running,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: failed ? c.warning : c.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.chip,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SizedBox.square(
                      dimension: 32,
                      child: Center(
                        child:
                            running && !MediaQuery.disableAnimationsOf(context)
                            ? SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.accentText,
                                ),
                              )
                            : Icon(
                                widget.toolbox
                                    ? Icons.build_outlined
                                    : Icons.code,
                                size: 18,
                                color: c.accentText,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.stage == ScriptStage.done)
                    Icon(Icons.check_circle, size: 20, color: c.success)
                  else if (failed)
                    Icon(Icons.error_outline, size: 20, color: c.warning),
                ],
              ),
              if (failed && reason.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(reason, style: TextStyle(color: c.muted)),
              ],
              if (!running && !failed && output.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: _open
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: _openHeight,
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(output, style: _mono(c)),
                            ),
                          )
                        : Text(
                            output,
                            maxLines: _previewLines,
                            overflow: TextOverflow.ellipsis,
                            style: _mono(c),
                          ),
                  ),
                ),
                if (long)
                  Semantics(
                    button: true,
                    label: _open
                        ? context.t.chatOutputShowLess
                        : context.t.chatOutputShowAll,
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _open = !_open),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _open
                                ? context.t.chatOutputShowLess
                                : context.t.chatOutputShowAll,
                            style: TextStyle(color: c.accentText),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              if (widget.files != null) widget.files!,
            ],
          ),
        ),
      ),
    );
  }
}

// -- FUNCTIONS -- //

/// The output's look: the phone's fixed-width face, small, in the ink colour.
TextStyle _mono(BotlerColors c) => TextStyle(
  fontFamily: 'monospace',
  fontSize: 12.5,
  height: 1.4,
  color: c.ink,
);
