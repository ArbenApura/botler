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

typedef TokenReader = Future<String?> Function();

// -- CONSTANTS -- //

const Uuid _uuid = Uuid();
const Duration _timeout = Duration(seconds: 30);

// -- FUNCTIONS -- //

/// A fresh request id: 8 to 80 characters, unique.
String newRequestId() => _uuid.v4();

class ApiClient {
  ApiClient({required this.base, required this.token, http.Client? client})
    : _http = client ?? http.Client();

  final String base;
  final TokenReader token;
  final http.Client _http;

  Future<Map<String, String>> _headers({String? key, bool json = false}) async {
    final t = await token();
    final headers = <String, String>{};
    if (t != null) headers['authorization'] = 'Bearer $t';
    if (json) headers['content-type'] = 'application/json';
    if (key != null) headers['idempotency-key'] = key;
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

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException(
        'NETWORK',
        'No connection. It will be tried again.',
        0,
      );
    } on http.ClientException {
      throw const ApiException(
        'NETWORK',
        'No connection. It will be tried again.',
        0,
      );
    } on TimeoutException {
      throw const ApiException(
        'NETWORK',
        'The server took too long. It will be tried again.',
        0,
      );
    }
  }

  Future<Json> get(String path, {Map<String, String>? query}) =>
      _guard(() async {
        final uri = Uri.parse('$base$path').replace(queryParameters: query);
        final r = await _http.get(uri, headers: await _headers());
        if (r.statusCode >= 400) throw _failure(r);
        return decodeJson(r.body);
      });

  Future<Json> post(String path, Json body, {String? key}) => _guard(() async {
    final r = await _http.post(
      Uri.parse('$base$path'),
      headers: await _headers(key: key, json: true),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) throw _failure(r);
    return decodeJson(r.body);
  });

  /// Runs one operation of the server's registry (POST /api/v1/do/NAME) and returns its result.
  /// Pass [key] to make the call safe to repeat; the outbox does.
  Future<Object?> verb(
    String name, [
    Json args = const <String, Object?>{},
    String? key,
  ]) async {
    final answer = await post(
      '/api/v1/do/$name',
      args,
      key: key ?? newRequestId(),
    );
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

  /// Answers an approval card.
  Future<Json> decideCard(String id, {required bool approve}) => post(
    '/api/v1/agent/actions/$id',
    <String, Object?>{'decision': approve ? 'approve' : 'reject'},
  );

  /// One chat message as a stream of events (delta, tool, card, fallback, done, error). The same [id] sent again replays the stored answer.
  Stream<Json> chat({
    required String id,
    required String text,
    String? ocrText,
  }) async* {
    final req = http.Request('POST', Uri.parse('$base/api/v1/agent/chat'))
      ..headers.addAll(await _headers(json: true))
      ..body = jsonEncode(<String, Object?>{
        'clientMessageId': id,
        'text': text,
        if (ocrText != null && ocrText.isNotEmpty) 'ocrText': ocrText,
      });
    final http.StreamedResponse res;
    try {
      res = await _http.send(req).timeout(_timeout);
    } on SocketException {
      throw const ApiException('NETWORK', 'No connection.', 0);
    } on http.ClientException {
      throw const ApiException('NETWORK', 'No connection.', 0);
    } on TimeoutException {
      throw const ApiException('NETWORK', 'The server took too long.', 0);
    }
    if (res.statusCode >= 400)
      throw _failure(await http.Response.fromStream(res));
    final lines = res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final event = decodeJson(line.substring(5).trim());
      if (event.isNotEmpty) yield event;
    }
  }

  void close() => _http.close();
}
