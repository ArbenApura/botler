// THE APP LOCK: WITH IT ON, THE APP ASKS FOR A FINGERPRINT OR FACE WHEN IT OPENS AND WHEN IT COMES BACK AFTER A MINUTE AWAY.
// A wrong finger or a cancel leaves it locked, showing a blank paper with one button. The lock covers the whole app, so no amount can be seen
// behind it (the task switcher also shows the lock, not the chat).

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';

// -- CONSTANTS -- //

/// The app stays unlocked for this long after it was left.
const Duration relockAfter = Duration(minutes: 1);

// -- TYPES -- //

/// Asks the phone to check the person. A seam, so tests can answer without a sensor.
typedef Authenticate = Future<bool> Function();

Future<bool> deviceAuthenticate() async {
  final auth = LocalAuthentication();
  try {
    if (!await auth.isDeviceSupported()) return false;
    return await auth.authenticate(
      // The prompt of the phone's own dialog is in the language the person chose
      localizedReason: wordsFor(
        readSettings(await SharedPreferences.getInstance()).language,
      ).lockReason,
      persistAcrossBackgrounding: true,
    );
  } on LocalAuthException {
    return false;
  }
}

final Provider<Authenticate> authenticateProvider = Provider<Authenticate>(
  (ref) => deviceAuthenticate,
);

class LockGate extends ConsumerStatefulWidget {
  const LockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  bool _locked = true;
  DateTime? _leftAt;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The phone's own fingerprint dialog pauses and resumes the app: those events are not the person leaving, so they are ignored
    if (_asking) return;
    if (state == AppLifecycleState.paused) _leftAt = DateTime.now();
    if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      // Used once: a later resume without a new pause must never lock again from an old time
      _leftAt = null;
      if (left != null && DateTime.now().difference(left) >= relockAfter) {
        setState(() => _locked = true);
        _ask();
      }
    }
  }

  Future<void> _ask() async {
    if (!ref.read(settingsProvider).lockOn) {
      if (_locked) setState(() => _locked = false);
      return;
    }
    if (_asking) return;
    _asking = true;
    final ok = await ref.read(authenticateProvider)();
    _asking = false;
    // The dialog's own pause does not count as time away
    _leftAt = null;
    if (mounted) setState(() => _locked = !ok);
  }

  @override
  Widget build(BuildContext context) {
    final lockOn = ref.watch(settingsProvider.select((s) => s.lockOn));
    if (!lockOn || !_locked) return widget.child;
    final c = context.colors;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.lock_outline, size: 40, color: c.muted),
            const SizedBox(height: 16),
            Text(
              context.t.lockTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _ask, child: Text(context.t.lockUnlock)),
          ],
        ),
      ),
    );
  }
}
