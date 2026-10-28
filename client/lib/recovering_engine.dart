import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

import 'api.dart';
import 'local_engine.dart';
import 'engine.dart';

class MissingAudioException extends ApiException {
  MissingAudioException(this.trackId)
    : super(
        'The saved working audio is missing or has changed. Use Locate original to recover this track.',
      );
  final String trackId;
}

class _Reference {
  _Reference(this.path, this.filename, this.runtimeId, this.size, this.digest);
  final String path, filename;
  final int? size;
  final String? digest;
  String? runtimeId;
}

/// Stable local IDs survive restarts; runtime IDs belong only to the current
/// backend/Android process. Re-import uses the immutable private audio copy.
class RecoveringEngine implements MusicEngine {
  RecoveringEngine(this.delegate);
  final MusicEngine delegate;
  final _references = <String, _Reference>{};
  final _imports = <String, Future<String>>{};

  void register(
    String id,
    String path,
    String filename, {
    String? runtimeId,
    int? size,
    String? digest,
  }) {
    _references[id] = _Reference(path, filename, runtimeId, size, digest);
  }

  Future<String> _bind(String id, {String? expiredId}) async {
    final reference = _references[id];
    if (reference == null) throw MissingAudioException(id);
    if (reference.runtimeId != null &&
        (expiredId == null || expiredId != reference.runtimeId))
      return reference.runtimeId!;
    final pending = _imports[id];
    if (pending != null) return pending;
    final job = () async {
      final file = File(reference.path);
      try {
        if (!await file.exists() ||
            (reference.size != null && await file.length() != reference.size))
          throw MissingAudioException(id);
        if (reference.digest != null &&
            (await sha256.bind(file.openRead()).first).toString() !=
                reference.digest)
          throw MissingAudioException(id);
      } on FileSystemException {
        throw MissingAudioException(id);
      }
      final imported = await delegate.upload(
        reference.path,
        reference.filename,
      );
      final runtimeId = imported['id'] as String;
      reference.runtimeId = runtimeId;
      return runtimeId;
    }();
    _imports[id] = job;
    try {
      return await job;
    } finally {
      _imports.remove(id);
    }
  }

  bool _expired(Object error) {
    final text = error is ApiException
        ? error.message
        : error is PlatformException
        ? (error.message ?? '')
        : '';
    return (error is ApiException &&
            error.statusCode == 404 &&
            text.toLowerCase().contains('session expired')) ||
        (error is PlatformException &&
            text.toLowerCase().contains('session expired'));
  }

  Future<T> _withTrack<T>(
    String id,
    Future<T> Function(String runtimeId) action,
  ) async {
    final runtime = await _bind(id);
    try {
      return await action(runtime);
    } catch (e) {
      if (!_expired(e)) rethrow;
      final fresh = await _bind(id, expiredId: runtime);
      return action(
        fresh,
      ); // Exactly one retry; provider 404s never re-upload audio.
    }
  }

  @override
  Future<Map<String, dynamic>> json(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String>? query,
  }) async {
    final parts = path.split('/');
    if (parts.length < 3 || parts[1] != 'tracks')
      return delegate.json(path, method: method, body: body, query: query);
    final id = parts[2];
    if (method == 'DELETE') {
      final runtime = _references[id]?.runtimeId;
      if (runtime != null) {
        try {
          await delegate.json('/tracks/$runtime', method: 'DELETE');
        } catch (e) {
          if (!_expired(e)) rethrow;
        }
      }
      _references.remove(id);
      return {'deleted': true};
    }
    return _withTrack(id, (runtime) {
      final rewritten = List<String>.of(parts)..[2] = runtime;
      return delegate.json(
        rewritten.join('/'),
        method: method,
        body: body,
        query: query,
      );
    });
  }

  @override
  Future<Map<String, dynamic>> upload(String path, String filename) =>
      delegate.upload(path, filename);
  @override
  Future<Uint8List> export(String id, Map<String, dynamic> body) =>
      _withTrack(id, (runtime) => delegate.export(runtime, body));

  Future<bool> saveLocalExport(
    String id,
    Map<String, dynamic> body,
    String filename,
  ) {
    final local = delegate;
    if (local is! LocalMusicEngine)
      throw StateError('Local export requires the on-device engine.');
    return _withTrack(
      id,
      (runtime) => local.saveExport(runtime, body, filename),
    );
  }

  Future<Map<String, dynamic>?> overwriteLocalExport(
    String id,
    Map<String, dynamic> body,
    String filename,
    String expected, {
    String? originalUri,
  }) {
    final local = delegate;
    if (local is! LocalMusicEngine)
      throw StateError('On-device engine required.');
    return _withTrack(
      id,
      (runtime) => local.overwriteExport(
        runtime,
        body,
        filename,
        expected,
        originalUri: originalUri,
      ),
    );
  }

  @override
  void close() => delegate.close();
}
