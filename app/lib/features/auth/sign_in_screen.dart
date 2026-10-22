// SIGN IN: ONE BUTTON. ONLY THE GOOGLE ACCOUNTS ON THE SERVER'S LIST GET IN; ANYONE ELSE IS TOLD SO IN PLAIN WORDS.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
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
              const SizedBox(height: 8),
              Text(
                'Your money and your time, in one quiet chat.',
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: session.isLoading
                      ? null
                      : () => ref.read(sessionProvider.notifier).signIn(),
                  child: session.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in with Google'),
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
