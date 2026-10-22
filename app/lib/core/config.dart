// BUILD-TIME SETTINGS. THE SERVER ADDRESS AND THE GOOGLE WEB CLIENT ID ARE NOT SECRETS (THE ID IS IN EVERY SIGN-IN LINK); NOTHING SECRET IS EVER IN THE APP.
// Override with:  flutter run --dart-define=BOTLER_API=http://10.0.2.2:5280   (the emulator's address for the PC's localhost)

// -- CONSTANTS -- //

const String apiBase = String.fromEnvironment(
  'BOTLER_API',
  defaultValue: 'https://botler.arbenger.com',
);

/// The Google OAuth *web* client id. The server checks ID tokens against it. Set at build time (P6.10).
const String googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

/// A session made for the local dev database, for a debug build on the emulator (Google sign in needs a real account there). It is only
/// read in a debug build talking to a local http server, so a release build can never use it. Pass it from a file, never on a command line.
const String devSessionToken = String.fromEnvironment('DEV_SESSION_TOKEN');
const String devSessionEmail = String.fromEnvironment('DEV_SESSION_EMAIL');
const String devSessionName = String.fromEnvironment('DEV_SESSION_NAME');

/// A build against a local server may use plain http (an emulator talking to the PC); a build for the VPS never does.
bool get apiIsLocal => apiBase.startsWith('http://');
