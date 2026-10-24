import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonance/connection_store.dart';
import 'package:resonance/song_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'Windows defaults to local processing and remembers an explicit backend choice',
    () async {
      const store = ConnectionStore();
      expect(await store.usesBackend(), false);
      await store.selectBackend(true);
      expect(await store.usesBackend(), true);
      await store.selectBackend(false);
      expect(await store.usesBackend(), false);
    },
  );

  test(
    'saved URL and secret are restored together and can be forgotten',
    () async {
      const store = ConnectionStore();
      await store.save(
        const BackendConnection('http://127.0.0.1:8765', 'test-secret'),
      );
      final restored = await store.load();
      expect(restored!.url, 'http://127.0.0.1:8765');
      expect(restored.token, 'test-secret');
      await store.forget();
      expect(await store.load(), isNull);
    },
  );

  test(
    'invalid saved connection never becomes a destination for a token',
    () async {
      for (final url in [
        'file:///secret',
        'http://user:password@localhost:8765',
        'https://example.org/path',
        'https://example.org?q=secret',
      ]) {
        expect(
          BackendConnection.parse({'url': url, 'token': 'test-secret'}),
          isNull,
        );
      }
      expect(
        BackendConnection.parse({'url': 'http://localhost:8765', 'token': ''}),
        isNull,
      );
      FlutterSecureStorage.setMockInitialValues({
        ConnectionStore.key: 'corrupt data',
      });
      expect(await const ConnectionStore().load(), isNull);
    },
  );

  test(
    'desktop drop paths preserve names and validate supported readable audio',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'resonance-drop-test',
      );
      addTearDown(() => folder.delete(recursive: true));
      final file = await File(
        '${folder.path}/My song.MP3',
      ).writeAsBytes([1, 2, 3]);
      expect(SongInput.fromPath(r'C:\Music\My song.MP3').name, 'My song.MP3');
      expect(await songInputError(SongInput.fromPath(file.path)), isNull);
      expect(
        await songInputError(
          SongInput('${folder.path}/missing.mp3', 'missing.mp3'),
        ),
        isNotNull,
      );
      expect(
        await songInputError(SongInput(file.path, 'notes.pdf')),
        isNotNull,
      );
      await file.writeAsBytes([]);
      expect(await songInputError(SongInput.fromPath(file.path)), isNotNull);
      final directory = await Directory('${folder.path}/folder.mp3').create();
      expect(
        await songInputError(SongInput.fromPath(directory.path)),
        isNotNull,
      );
    },
  );
}
