import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonance/api.dart';
import 'package:resonance/engine.dart';
import 'package:resonance/recovering_engine.dart';

class FakeEngine implements MusicEngine {
  int uploads = 0;
  final paths = <String>[];
  String? exportedId;
  Future<void>? uploadGate;
  Object? nextError;
  final errors = <Object>[];
  @override
  Future<Map<String, dynamic>> upload(String path, String filename) async {
    uploads++;
    await uploadGate;
    return {'id': 'runtime-$uploads'};
  }

  @override
  Future<Map<String, dynamic>> json(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String>? query,
  }) async {
    paths.add(path);
    if (errors.isNotEmpty) throw errors.removeAt(0);
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    return {'ok': true};
  }

  @override
  Future<Uint8List> export(String id, Map<String, dynamic> body) async {
    exportedId = id;
    return Uint8List.fromList([1]);
  }

  @override
  void close() {}
}

void main() {
  late Directory temporary;
  late File source;
  late FakeEngine delegate;
  late RecoveringEngine engine;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('resonance-recovery-');
    source = await File('${temporary.path}/song.mp3').writeAsBytes([1, 2, 3]);
    delegate = FakeEngine();
    engine = RecoveringEngine(delegate);
    engine.register(
      'local',
      source.path,
      'song.mp3',
      size: 3,
      digest: sha256.convert([1, 2, 3]).toString(),
    );
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('concurrent restored-track requests share one import', () async {
    final gate = Completer<void>();
    delegate.uploadGate = gate.future;
    final requests = [
      engine.json('/tracks/local/identify'),
      engine.json('/tracks/local/availability'),
    ];
    gate.complete();
    await Future.wait(requests);
    expect(delegate.uploads, 1);
    expect(delegate.paths, [
      '/tracks/runtime-1/identify',
      '/tracks/runtime-1/availability',
    ]);
    await engine.export('local', {});
    expect(delegate.exportedId, 'runtime-1');
  });

  test('explicit backend expiration reimports and retries once', () async {
    engine.register('local', source.path, 'song.mp3', runtimeId: 'expired');
    delegate.nextError = ApiException('Track session expired', statusCode: 404);
    await engine.json('/tracks/local/identify');
    expect(delegate.paths, [
      '/tracks/expired/identify',
      '/tracks/runtime-1/identify',
    ]);
    expect(delegate.uploads, 1);
  });

  test('provider lyric 404 does not reimport audio', () async {
    engine.register('local', source.path, 'song.mp3', runtimeId: 'live');
    delegate.nextError = ApiException('Lyrics not found', statusCode: 404);
    await expectLater(
      engine.json('/tracks/local/lyrics'),
      throwsA(isA<ApiException>()),
    );
    expect(delegate.uploads, 0);
  });

  test(
    'an expired native Android cache reimports the durable source',
    () async {
      engine.register(
        'local',
        source.path,
        'song.mp3',
        runtimeId: 'old-android',
      );
      delegate.nextError = PlatformException(
        code: 'AUDIO_ERROR',
        message: 'This audio session expired. Import the file again.',
      );
      await engine.json('/tracks/local/identify');
      expect(delegate.uploads, 1);
      expect(delegate.paths.last, '/tracks/runtime-1/identify');
    },
  );

  test(
    'a second expiration is surfaced rather than retried indefinitely',
    () async {
      engine.register('local', source.path, 'song.mp3', runtimeId: 'old');
      delegate.errors.addAll([
        ApiException('Session expired', statusCode: 404),
        ApiException('Session expired', statusCode: 404),
      ]);
      await expectLater(
        engine.json('/tracks/local/identify'),
        throwsA(isA<ApiException>()),
      );
      expect(delegate.uploads, 1);
      expect(delegate.paths, hasLength(2));
    },
  );

  test('missing or same-size changed source never uploads', () async {
    await source.writeAsBytes([3, 2, 1]);
    await expectLater(
      engine.json('/tracks/local/identify'),
      throwsA(isA<MissingAudioException>()),
    );
    await source.delete();
    await expectLater(
      engine.export('local', {}),
      throwsA(isA<MissingAudioException>()),
    );
    expect(delegate.uploads, 0);
  });

  test('deleting an unbound restored track never uploads it', () async {
    await engine.json('/tracks/local', method: 'DELETE');
    expect(delegate.uploads, 0);
    expect(delegate.paths, isEmpty);
  });

  test('non-track routes delegate without audio import', () async {
    await engine.json('/search', query: {'q': 'hello'});
    expect(delegate.paths, ['/search']);
    expect(delegate.uploads, 0);
  });
}
