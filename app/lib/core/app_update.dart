// IN-APP UPDATES: ASK THE SERVER IF A NEWER BUILD EXISTS, DOWNLOAD IT, CHECK IT TWICE AND HAND IT TO ANDROID'S INSTALLER.
// The phone is sideloaded, so this replaces the store. Android always asks the person to tap Install and only installs a build signed with the
// same key and a higher version, so these checks are about never offering a broken file, not about being the last line of defence.
// The decision is a pure function (tested without a phone); everything that touches Android goes through the [UpdateHost] seam.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'api.dart';
import 'json.dart';

// -- TYPES -- //

/// What the phone should do about the newest build. "none" is never stored: no offer means up to date, or nothing known.
enum UpdateKind { optional, required }

class UpdateOffer {
  const UpdateOffer({
    required this.kind,
    required this.versionName,
    required this.versionCode,
    required this.size,
    required this.sha256,
    required this.notes,
    required this.downloadPath,
  });

  final UpdateKind kind;
  final String versionName;
  final int versionCode;
  final int size;
  final String sha256;
  final String notes;
  final String downloadPath;

  bool get isRequired => kind == UpdateKind.required;
}

/// Why an update did not happen. Codes only: they carry no path, no token and no server text.
enum UpdateFailure {
  network,
  server,
  space,
  damaged,
  wrongBuild,
  permission,
  installer,
}

class UpdateException implements Exception {
  const UpdateException(this.failure);
  final UpdateFailure failure;

  @override
  String toString() => 'UpdateException(${failure.name})';
}

/// Everything the update needs from Android. A seam, so tests run without a phone.
abstract class UpdateHost {
  Future<int> installedCode();
  Future<String> installedName();
  Future<String> updateDir();
  Future<int> freeBytes();

  /// "ok", or why the downloaded file is not an update for this app: path, unreadable, package, version, signature.
  Future<String> archiveCheck(String path, int code);
  Future<bool> canInstall();
  Future<void> openInstallSettings();

  /// "ok", "needs_permission" or "error".
  Future<String> install(String path);
}

class MethodChannelUpdateHost implements UpdateHost {
  const MethodChannelUpdateHost();

  static const MethodChannel _channel = MethodChannel(
    'com.arbenger.botler/update',
  );

  @override
  Future<int> installedCode() async =>
      (await _channel.invokeMethod<int>('installedCode')) ?? 0;

  @override
  Future<String> installedName() async =>
      (await _channel.invokeMethod<String>('installedName')) ?? '';

  @override
  Future<String> updateDir() async =>
      (await _channel.invokeMethod<String>('updateDir')) ?? '';

  @override
  Future<int> freeBytes() async =>
      (await _channel.invokeMethod<int>('freeBytes')) ?? 0;

  @override
  Future<String> archiveCheck(String path, int code) async =>
      (await _channel.invokeMethod<String>('archiveCheck', <String, Object?>{
        'path': path,
        'code': code,
      })) ??
      'unreadable';

  @override
  Future<bool> canInstall() async =>
      (await _channel.invokeMethod<bool>('canInstall')) ?? false;

  @override
  Future<void> openInstallSettings() async {
    await _channel.invokeMethod<bool>('openInstallSettings');
  }

  @override
  Future<String> install(String path) async =>
      (await _channel.invokeMethod<String>('install', <String, Object?>{
        'path': path,
      })) ??
      'error';
}

// -- CONSTANTS -- //

/// A check runs on start and then at most this often. The Settings button ignores it.
const Duration checkEvery = Duration(hours: 12);

/// A download that receives nothing for this long is given up on.
const Duration stall = Duration(seconds: 30);

const String _lastCheckKey = 'update.lastCheck';
const String _dismissedKey = 'update.dismissed';

// -- FUNCTIONS -- //

/// Turns the server's answer into an offer, or null. The server's own "status" word is not trusted: the decision is made again here
/// from the build it names, so a wrong or hostile answer can never block the app. "required" needs a build above the phone's, a minimum
/// above the phone's, and a minimum that the offered build itself meets.
UpdateOffer? decideOffer(Json answer, int installedCode) {
  final latest = asJson(answer['latest']);
  final code = intOf(latest['versionCode']);
  final size = intOf(latest['size']);
  final hash = str(latest['sha256']);
  final path = str(answer['downloadPath']);
  final name = str(latest['versionName']);
  if (code <= installedCode || size <= 0) return null;
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return null;
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(name)) return null;
  // The download must be this server's own update path for this build, nothing else
  if (path != '/api/v1/app/update/apk/$code') return null;
  final minimum = intOf(latest['minSupportedCode'], 1);
  final isRequired = installedCode < minimum && minimum <= code;
  return UpdateOffer(
    kind: isRequired ? UpdateKind.required : UpdateKind.optional,
    versionName: name,
    versionCode: code,
    size: size,
    sha256: hash,
    notes: str(latest['notes']),
    downloadPath: path,
  );
}

/// Is a new check due? Never checked, or the last good check is old enough. A clock that moved back counts as due.
bool checkDue(DateTime? last, DateTime now) =>
    last == null || now.isBefore(last) || now.difference(last) >= checkEvery;

/// The failure for a server or network error during the check or the download.
UpdateFailure failureOf(ApiException e) =>
    e.isNetwork ? UpdateFailure.network : UpdateFailure.server;

/// Collects the one digest a chunked hash produces.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class AppUpdater {
  AppUpdater({
    required this.api,
    required this.host,
    required this.prefs,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final ApiClient api;
  final UpdateHost host;
  final SharedPreferences prefs;
  final DateTime Function() _now;

  // -- STATES -- //

  bool _downloading = false;

  /// The last check could not reach the server or understand it (Settings says so; the app stays quiet).
  bool lastCheckFailed = false;

  // -- FUNCTIONS -- //

  DateTime? get lastCheck {
    final ms = prefs.getInt(_lastCheckKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// The versionCode of the offer the person dismissed (the banner for it stays hidden), or 0.
  int get dismissedCode => prefs.getInt(_dismissedKey) ?? 0;

  Future<void> dismiss(int code) => prefs.setInt(_dismissedKey, code);

  /// Is a check due? The Settings button and the start always ask.
  bool isDue({required bool force}) => force || checkDue(lastCheck, _now());

  /// Asks the server. Returns the offer, or null for "up to date". Offline, a server fault or a strange answer is a quiet null and the
  /// time of the last check is not moved, so the next start asks again. Only a good answer is remembered.
  Future<UpdateOffer?> check({bool force = false}) async {
    if (!isDue(force: force)) return null;
    lastCheckFailed = false;
    try {
      final installed = await host.installedCode();
      final answer = await api.get(
        '/api/v1/app/update',
        query: <String, String>{'versionCode': '$installed'},
      );
      // A reply that is not the server's answer (a captive portal, a proxy page) is a failed check, not "up to date"
      if (answer['status'] is! String) {
        lastCheckFailed = true;
        return null;
      }
      await prefs.setInt(_lastCheckKey, _now().millisecondsSinceEpoch);
      return decideOffer(answer, installed);
    } on ApiException {
      lastCheckFailed = true;
      return null;
    } on PlatformException {
      lastCheckFailed = true;
      return null;
    }
  }

  /// Removes every downloaded file and unfinished download. Runs on start, so nothing old waits in the cache.
  Future<void> sweep() async {
    try {
      final dir = Directory(await host.updateDir());
      if (!dir.existsSync()) return;
      for (final f in dir.listSync()) {
        if (f is File) f.deleteSync();
      }
    } on FileSystemException {
      // A file that cannot be removed now is tried again on the next start
    } on PlatformException {
      // No update folder available: nothing to sweep
    }
  }

  /// Downloads and checks the build. Returns the path of the checked file. One download at a time: a second call while one runs is
  /// refused. Always restarts from zero. [progress] gets 0..1. Throws [UpdateException].
  Future<String> download(
    UpdateOffer offer,
    void Function(double) progress, {
    void Function()? verifying,
  }) async {
    if (_downloading) throw const UpdateException(UpdateFailure.server);
    _downloading = true;
    File? part;
    try {
      final dir = Directory(await host.updateDir());
      dir.createSync(recursive: true);
      // Nothing from an earlier try may be left behind
      for (final f in dir.listSync()) {
        if (f is File) f.deleteSync();
      }
      // The installer needs the file and its own working space
      if (await host.freeBytes() < offer.size * 2) {
        throw const UpdateException(UpdateFailure.space);
      }
      final name = 'botler-${offer.versionCode}.apk';
      part = File('${dir.path}/$name.part');
      final res = await _open(offer);
      final declared = res.contentLength;
      if (declared != null && declared != offer.size) {
        throw const UpdateException(UpdateFailure.damaged);
      }
      final sink = part.openWrite();
      final digestSink = _DigestSink();
      final hash = sha256.startChunkedConversion(digestSink);
      var received = 0;
      try {
        await for (final chunk in res.stream.timeout(stall)) {
          received += chunk.length;
          // A body longer than promised is stopped at once
          if (received > offer.size) {
            throw const UpdateException(UpdateFailure.damaged);
          }
          hash.add(chunk);
          sink.add(chunk);
          progress(received / offer.size);
        }
      } finally {
        await sink.close();
      }
      hash.close();
      verifying?.call();
      if (received != offer.size ||
          digestSink.value?.toString() != offer.sha256) {
        throw const UpdateException(UpdateFailure.damaged);
      }
      final done = await part.rename('${dir.path}/$name');
      part = null;
      final verdict = await host.archiveCheck(done.path, offer.versionCode);
      if (verdict != 'ok') {
        done.deleteSync();
        throw const UpdateException(UpdateFailure.wrongBuild);
      }
      return done.path;
    } on UpdateException {
      _discard(part);
      rethrow;
    } on ApiException catch (e) {
      _discard(part);
      throw UpdateException(failureOf(e));
    } on TimeoutException {
      _discard(part);
      throw const UpdateException(UpdateFailure.network);
    } on SocketException {
      _discard(part);
      throw const UpdateException(UpdateFailure.network);
    } on http.ClientException {
      // The connection broke while the body was arriving
      _discard(part);
      throw const UpdateException(UpdateFailure.network);
    } on TlsException {
      _discard(part);
      throw const UpdateException(UpdateFailure.network);
    } on PlatformException {
      _discard(part);
      throw const UpdateException(UpdateFailure.installer);
    } on FileSystemException {
      _discard(part);
      throw const UpdateException(UpdateFailure.space);
    } finally {
      _downloading = false;
    }
  }

  /// Opens the download. A 404 or 416 means the build changed under the phone: one more try, then one clear error.
  Future<http.StreamedResponse> _open(UpdateOffer offer) async {
    try {
      return await api.getStream(offer.downloadPath);
    } on ApiException catch (e) {
      if (e.status != 404 && e.status != 416) rethrow;
      return api.getStream(offer.downloadPath);
    }
  }

  void _discard(File? f) {
    try {
      if (f != null && f.existsSync()) f.deleteSync();
    } on FileSystemException {
      // Swept on the next start
    }
  }

  /// Opens the system installer for a checked file. [UpdateFailure.permission] when Android has not allowed installs from Botler yet.
  Future<void> install(String path) async {
    final verdict = await host.install(path);
    if (verdict == 'needs_permission') {
      throw const UpdateException(UpdateFailure.permission);
    }
    if (verdict != 'ok') throw const UpdateException(UpdateFailure.installer);
  }
}
