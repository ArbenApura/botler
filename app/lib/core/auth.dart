// SIGN IN WITH GOOGLE ON THE PHONE. THE PHONE GETS A GOOGLE ID TOKEN, THE SERVER CHECKS IT AND ANSWERS WITH A SESSION TOKEN, WHICH LIVES ONLY IN THE
// PHONE'S SECURE STORAGE (the Android keystore). Registration is closed on the server: a Google account that is not on its list is refused there.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

// -- MODULES -- //
import 'api.dart';
import 'config.dart';
import 'json.dart';

// -- TYPES -- //

class Session {
  const Session({required this.token, required this.email, required this.name});

  factory Session.fromJson(Json j) => Session(
    token: str(j['token']),
    email: str(j['email']),
    name: str(j['name']),
  );

  final String token;
  final String email;
  final String name;

  Json toJson() => <String, Object?>{
    'token': token,
    'email': email,
    'name': name,
  };
}

/// Where the session is kept. A seam, so tests can use memory.
abstract class SessionStore {
  Future<Session?> read();
  Future<void> write(Session s);
  Future<void> clear();
}

// -- CONSTANTS -- //

const String _key = 'session.v1';

// -- FUNCTIONS -- //

class SecureSessionStore implements SessionStore {
  const SecureSessionStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<Session?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final s = Session.fromJson(decodeJson(raw));
    return s.token.isEmpty ? null : s;
  }

  @override
  Future<void> write(Session s) =>
      _storage.write(key: _key, value: jsonEncode(s.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore([this._session]);

  Session? _session;

  @override
  Future<Session?> read() async => _session;

  @override
  Future<void> write(Session s) async => _session = s;

  @override
  Future<void> clear() async => _session = null;
}

/// Exchanges a Google ID token for a Botler session. Throws ApiException with the server's words when it refuses.
Future<Session> exchangeIdToken(
  String idToken, {
  required String base,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.post(
      Uri.parse('$base/api/auth/sign-in/social'),
      headers: <String, String>{'content-type': 'application/json'},
      body: jsonEncode(<String, Object?>{
        'provider': 'google',
        'idToken': <String, Object?>{'token': idToken},
      }),
    );
    final body = decodeJson(r.body);
    final token = r.headers['set-auth-token'] ?? str(body['token']);
    if (r.statusCode >= 400 || token.isEmpty) {
      throw ApiException(
        str(body['code'], 'UNAUTHENTICATED'),
        str(
          body['message'],
          'Google sign in did not work. Is this account allowed?',
        ),
        r.statusCode == 0 ? 401 : r.statusCode,
      );
    }
    final user = asJson(body['user']);
    return Session(
      token: token,
      email: str(user['email']),
      name: str(user['name']),
    );
  } finally {
    if (client == null) c.close();
  }
}

/// The Google part: asks the phone for the account and an ID token for the server's web client.
Future<String> googleIdToken() async {
  if (googleWebClientId.isEmpty) {
    throw const ApiException(
      'INVALID',
      'This build has no Google client id. Build with --dart-define=GOOGLE_WEB_CLIENT_ID=...',
      400,
    );
  }
  await GoogleSignIn.instance.initialize(serverClientId: googleWebClientId);
  final account = await GoogleSignIn.instance.authenticate();
  final token = account.authentication.idToken;
  if (token == null || token.isEmpty) {
    throw const ApiException(
      'UNAUTHENTICATED',
      'Google did not give an ID token.',
      401,
    );
  }
  return token;
}
