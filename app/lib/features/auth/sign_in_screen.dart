// SIGN IN: ONE BUTTON. ONLY THE GOOGLE ACCOUNTS ON THE SERVER'S LIST GET IN; ANYONE ELSE IS TOLD SO IN PLAIN WORDS.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- TYPES -- //

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final session = ref.watch(sessionProvider);
    // The first read of the saved sign-in (the app opening): show only the name, so a signed-in person is not shown a button and a
    // spinner for a blink before the chat opens. A real sign-in in progress (also a retry after a failure) keeps its busy button.
    final starting =
        session.isLoading && !session.hasValue && !session.hasError;
    final busy = session.isLoading && !starting;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: 'B',
                      style: TextStyle(color: c.accent),
                    ),
                    const TextSpan(text: 'otler'),
                  ],
                ),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              // The tagline and button keep their space while hidden, so the name does not move
              Visibility(
                visible: !starting,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(height: 8),
                    Text(
                      context.t.signInTagline,
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: session.isLoading
                            ? null
                            : () => ref.read(sessionProvider.notifier).signIn(),
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(context.t.signInButton),
                      ),
                    ),
                  ],
                ),
              ),
              if (session.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    errorWords(session.error ?? ''),
                    style: TextStyle(color: c.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
