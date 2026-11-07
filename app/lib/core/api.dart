// THE SERVER CLIENT: ONE PLACE THAT TALKS TO botler.arbenger.com. EVERY CALL CARRIES THE SESSION TOKEN; EVERY WRITE CARRIES A REQUEST ID.
// A write the phone could not deliver is kept by the outbox with the same request id and sent again, and the server answers a repeat with the first
// result, so a bad connection never makes a double entry. Errors come back as ApiException with the server's own plain-words message.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

// -- MODULES -- //
import 'json.dart';

// -- TYPES -- //

class ApiException implements Exception {
  const ApiException(this.code, this.message, this.status);

  /// INVALID, NOT_FOUND, FORBIDDEN, CONFLICT, LIMIT, UNAVAILABLE, UNAUTHENTICATED, NETWORK
  final String code;
  final String message;

  /// The HTTP status, or 0 when the server could not be reached.
  final int status;

  bool get isNetwork => status == 0;
  bool get isUnauthenticated => status == 401;

  /// Worth sending again later: the server was not reached, or it was busy.
  bool get isRetryable => isNetwork || status == 429 || status >= 500;

  @override
  String toString() => 'ApiException($code, $status)';
}

/// The server does not know an operation the app needs: it is older than the app. The screen says to update the server.
class ServerTooOld implements Exception {
  const ServerTooOld();

  @override
  String toString() => 'ServerTooOld';
}

typedef TokenReader = Future<String?> Function();

// -- CONSTANTS -- //

const Uuid _uuid = Uuid();
const Duration _timeout = Duration(seconds: 30);

/// How long a chat stream may stay silent. The server pings every 10 seconds.
const Duration _idle = Duration(seconds: 45);

/// A message with pictures can be several megabytes, so the wait for the first answer to it is longer.
const Duration _uploadTimeout = Duration(seconds: 120);

// -- FUNCTIONS -- //

/// A fresh request id: 8 to 80 characters, unique.
String newRequestId() => _uuid.v4();

class ApiClient {
  ApiClient({required this.base, required this.token, http.Client? client})
    : _http = client ?? http.Client();

  final String base;
  final TokenReader token;
  final http.Client _http;

  /// Called with the verb name after every successful operation call (the outbox sends through the same path). The app uses it to refresh lists.
  void Function(String verb)? onWrite;

  Future<Map<String, String>> _headers({
    String? key,
    bool json = false,
    String? channel,
  }) async {
    final t = await token();
    final headers = <String, String>{};
    if (t != null) headers['authorization'] = 'Bearer $t';
    if (json) headers['content-type'] = 'application/json';
    if (key != null) headers['idempotency-key'] = key;
    // Says where the call came from (widget or outbox) so the audit trail can show it; the server ignores anything else
    if (channel != null) headers['x-botler-channel'] = channel;
    return headers;
  }

  ApiException _failure(http.Response r) {
    final err = asJson(decodeJson(r.body)['error']);
    return ApiException(
      str(err['code'], r.statusCode == 401 ? 'UNAUTHENTICATED' : 'INTERNAL'),
      str(err['message'], 'Something went wrong. Try again.'),
      r.statusCode,
    );
  }

  // One request that can be stopped from outside: when the wait runs out, completing [abort] closes the socket instead of leaving it open
  Future<http.Response> _send(
    String method,
    Uri uri,
    Future<void> abort, {
    required Map<String, String> headers,
    String? body,
  }) async {
    final req = http.AbortableRequest(method, uri, abortTrigger: abort)
      ..headers.addAll(headers);
    if (body != null) req.body = body;
    return http.Response.fromStream(await _http.send(req));
  }

  Future<T> _guard<T>(Future<T> Function(Future<void> abort) call) async {
    final abort = Completer<void>();
    try {
      return await call(abort.future).timeout(_timeout);
    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException(
        'NETWORK',
        'No connection. It will be tried again.',
        0,
      );
    } on HandshakeException {
      throw const ApiException(
        'NETWORK',
        'A secure connection could not be made. It will be tried again.',
        0,
      );
    } on TlsException {
      throw const ApiException(
        'NETWORK',
        'A secure connection could not be made. It will be tried again.',
        0,
      );
    } on http.ClientException {
      throw const ApiException(
        'NETWORK',
        'No connection. It will be tried again.',
        0,
      );
    } on TimeoutException {
      // The request that ran out of time is stopped (its socket closes); whatever it would have answered later is ignored
      if (!abort.isCompleted) abort.complete();
      throw const ApiException(
        'NETWORK',
        'The server took too long. It will be tried again.',
        0,
      );
    }
  }

  Future<Json> get(String path, {Map<String, String>? query}) =>
      _guard((abort) async {
        final uri = Uri.parse('$base$path').replace(queryParameters: query);
        final r = await _send('GET', uri, abort, headers: await _headers());
        if (r.statusCode >= 400) throw _failure(r);
        return decodeJson(r.body);
      });

  Future<Json> post(String path, Json body, {String? key, String? channel}) =>
      _guard((abort) async {
        final r = await _send(
          'POST',
          Uri.parse('$base$path'),
          abort,
          headers: await _headers(key: key, json: true, channel: channel),
          body: jsonEncode(body),
        );
        if (r.statusCode >= 400) throw _failure(r);
        return decodeJson(r.body);
      });

  Future<Json> delete(String path, {Map<String, String>? query}) =>
      _guard((abort) async {
        final uri = Uri.parse('$base$path').replace(queryParameters: query);
        final r = await _send('DELETE', uri, abort, headers: await _headers());
        if (r.statusCode >= 400) throw _failure(r);
        return decodeJson(r.body);
      });

  /// A download as a stream, for the app update. The session token goes only to the Botler server over https (or the local server a debug
  /// build talks to), and a redirect is never followed, so the token can never be sent anywhere else. Throws ApiException on 4xx and 5xx.
  Future<http.StreamedResponse> getStream(String path) async {
    if (!base.startsWith('https://') && !base.startsWith('http://')) {
      throw const ApiException(
        'INVALID',
        'The server address is not valid.',
        0,
      );
    }
    final stop = Completer<void>();
    final req =
        http.AbortableRequest(
            'GET',
            Uri.parse('$base$path'),
            abortTrigger: stop.future,
          )
          ..followRedirects = false
          ..headers.addAll(await _headers())
          // The file is already compressed, and the byte count must stay exact
          ..headers['accept-encoding'] = 'identity';
    final http.StreamedResponse res;
    try {
      res = await _http.send(req).timeout(_timeout);
    } on SocketException {
      throw const ApiException('NETWORK', 'No connection.', 0);
    } on HandshakeException {
      throw const ApiException('NETWORK', 'No secure connection.', 0);
    } on TlsException {
      throw const ApiException('NETWORK', 'No secure connection.', 0);
    } on http.ClientException {
      throw const ApiException('NETWORK', 'No connection.', 0);
    } on TimeoutException {
      // The late answer is not wanted: the request is stopped so its socket closes
      if (!stop.isCompleted) stop.complete();
      throw const ApiException('NETWORK', 'The server took too long.', 0);
    }
    if (res.statusCode >= 300) {
      // A redirect counts as a failure here: the update never leaves the Botler server
      throw _failure(await http.Response.fromStream(res));
    }
    return res;
  }

  /// Runs one operation of the server's registry (POST /api/v1/do/NAME) and returns its result.
  /// Pass [key] to make the call safe to repeat; the outbox does.
  Future<Object?> verb(
    String name, [
    Json args = const <String, Object?>{},
    String? key,
    String? channel,
  ]) async {
    final answer = await post(
      '/api/v1/do/$name',
      args,
      key: key ?? newRequestId(),
      channel: channel,
    );
    // Told only after the server accepted it, so a refused or unreached write never refreshes anything
    final told = onWrite;
    if (told != null) {
      try {
        told(name);
      } on Object {
        // A listener that fails must never turn a saved write into an error
      }
    }
    return answer['result'];
  }

  Future<Json> verbJson(
    String name, [
    Json args = const <String, Object?>{},
    String? key,
  ]) async => asJson(await verb(name, args, key));

  Future<List<Json>> verbList(
    String name, [
    Json args = const <String, Object?>{},
  ]) async => asJsonList(await verb(name, args));

  /// The reminders, the summary card and the calendar state. [cursor] is the last one seen.
  Future<Json> sync({String? cursor}) {
    final query = <String, String>{};
    if (cursor != null) query['cursor'] = cursor;
    return get('/api/v1/sync', query: query);
  }

  /// Answers an approval card. [imageData] is the small picture the phone cut for a photo card (base64): it goes with the approval and nowhere else.
  Future<Json> decideCard(
    String id, {
    required bool approve,
    String? imageData,
    Json? editedArgs,
  }) => post('/api/v1/agent/actions/$id', <String, Object?>{
    'decision': approve ? 'approve' : 'reject',
    'imageData': ?imageData,
    'editedArgs': ?editedArgs,
  });

  /// The phone's answer to a call the assistant made to it (a script run, the toolbox), under the call id the chat stream announced.
  Future<Json> postDeviceResult(String callId, bool ok, Json result) => post(
    '/api/v1/agent/device-result',
    <String, Object?>{'callId': callId, 'ok': ok, 'result': result},
  );

  /// The cards still waiting for an answer, newest first, with the plan each carries.
  Future<List<Json>> pendingCards() async => asJsonList(
    (await get(
      '/api/v1/agent/actions',
      query: <String, String>{'status': 'pending'},
    ))['actions'],
  );

  /// One chat message as a stream of events (start, phase, reasoning, tool_start, delta, tool, card, fallback, done, error).
  /// The same [id] sent again replays the stored answer. Completing [abort] stops this one request (the stream just ends);
  /// the shared client stays open for everything else.
  Stream<Json> chat({
    required String id,
    required String text,
    List<String> ocrTexts = const <String>[],
    List<String> images = const <String>[],
    String? chatId,
    Future<void>? abort,
    Duration idle = _idle,
    bool scripts = false,
    String? foodCamera,
    String? clock,
  }) async* {
    // Stopped by the person (abort) or when the first answer takes too long: either way the socket is closed
    final stop = Completer<void>();
    if (abort != null) {
      unawaited(abort.then((_) => stop.isCompleted ? null : stop.complete()));
    }
    final req =
        http.AbortableRequest(
            'POST',
            Uri.parse('$base/api/v1/agent/chat'),
            abortTrigger: stop.future,
          )
          ..headers.addAll(await _headers(json: true))
          // Nothing may compress the stream: compressed pieces are held back and the answer would arrive all at once
          ..headers['accept-encoding'] = 'identity'
          ..body = jsonEncode(<String, Object?>{
            'clientMessageId': id,
            'text': text,
            'chatId': ?chatId,
            // This app can run the assistant's script and toolbox calls and answer them (the server offers those tools only to such an app)
            if (scripts) 'scripts': true,
            // The food camera sent this: the server refuses a meal photo at once when the model could not see it
            'foodCamera': ?foodCamera,
            // The clock this phone reads (12 or 24), so the assistant writes times the way the person reads them
            'clock': ?clock,
            if (ocrTexts.isNotEmpty) 'ocrTexts': ocrTexts,
            // The pictures themselves, as JPEG base64. Sent only when the server has said it will use them (an older server refuses the key)
            if (images.isNotEmpty)
              'images': <Map<String, String>>[
                for (final data in images)
                  <String, String>{'mediaType': 'image/jpeg', 'data': data},
              ],
          });
    final http.StreamedResponse res;
    try {
      res = await _http
          .send(req)
          .timeout(images.isEmpty ? _timeout : _uploadTimeout);
    } on http.RequestAbortedException {
      // Stopped by the person before the server answered
      return;
    } on SocketException {
      throw const ApiException('NETWORK', 'No connection.', 0);
    } on HandshakeException {
      throw const ApiException('NETWORK', 'No secure connection.', 0);
    } on TlsException {
      throw const ApiException('NETWORK', 'No secure connection.', 0);
    } on http.ClientException {
      throw const ApiException('NETWORK', 'No connection.', 0);
    } on TimeoutException {
      if (!stop.isCompleted) stop.complete();
      throw const ApiException('NETWORK', 'The server took too long.', 0);
    }
    if (res.statusCode >= 400)
      throw _failure(await http.Response.fromStream(res));
    // The server pings every 10 seconds, so a stream silent for longer than _idle is dead; any line, a ping included, restarts the wait
    final lines = res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(
          idle,
          onTimeout: (sink) => sink.addError(TimeoutException('idle')),
        );
    try {
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final event = decodeJson(line.substring(5).trim());
        if (event.isNotEmpty) yield event;
      }
    } on http.RequestAbortedException {
      // Stopped by the person: the stream just ends
      return;
    } on SocketException {
      throw const ApiException('NETWORK', 'The connection was lost.', 0);
    } on HandshakeException {
      throw const ApiException('NETWORK', 'The connection was lost.', 0);
    } on TlsException {
      throw const ApiException('NETWORK', 'The connection was lost.', 0);
    } on http.ClientException {
      throw const ApiException('NETWORK', 'The connection was lost.', 0);
    } on TimeoutException {
      if (!stop.isCompleted) stop.complete();
      throw const ApiException('NETWORK', 'The connection went quiet.', 0);
    }
  }

  void close() => _http.close();
}
