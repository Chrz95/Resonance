import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:resonance/api.dart';
import 'package:resonance/models.dart';
import 'package:resonance/public_services.dart';
import 'package:resonance/windows_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File input;
  late WindowsEngine engine;
  late WindowsAudioBridge bridge;
  late List<List<String>> commands;
  String? destination;
  Map<String, String>? writtenTags;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('resonance-windows-');
    input = await File('${temporary.path}/音楽 song.mp3').writeAsBytes([1, 2, 3]);
    final helper = await File(
      '${temporary.path}/resonance_desktop.exe',
    ).writeAsBytes([]);
    final ffmpeg = await File('${temporary.path}/ffmpeg.exe').writeAsBytes([]);
    destination = '${temporary.path}/saved.mp3';
    commands = [];
    writtenTags = null;
    bridge = WindowsAudioBridge(
      helper: helper.path,
      ffmpeg: ffmpeg.path,
      supportDirectory: temporary,
      savePath: (_) async => destination,
      command: (executable, arguments) async {
        commands.add([executable, ...arguments]);
        if (executable == helper.path) {
          switch (arguments.first) {
            case 'version':
              return Uint8List.fromList(utf8.encode('resonance-desktop/1\n'));
            case 'read':
              return Uint8List.fromList(
                utf8.encode(
                  jsonEncode({
                    'duration': 180.0,
                    'tags': {for (final key in tagNames) key: ''},
                  }),
                ),
              );
            case 'write':
              writtenTags = {
                for (final key in tagNames)
                  key: await File('${arguments[2]}/$key').readAsString(),
              };
              await File(arguments[1]).writeAsBytes([9, 8, 7]);
              return Uint8List.fromList(utf8.encode('ok\n'));
            case 'fingerprint':
              return Uint8List.fromList(
                utf8.encode('AQAA-windows-fingerprint\n'),
              );
          }
        } else if (arguments.first == '-version') {
          return Uint8List.fromList(utf8.encode('ffmpeg fixture'));
        } else {
          await File(arguments.last).writeAsBytes([4, 5, 6]);
          return Uint8List(0);
        }
        throw StateError('Unexpected local command: $arguments');
      },
    );
    engine = WindowsEngine(
      bridge: bridge,
      services: PublicMusicServices(
        client: MockClient((_) async {
          throw StateError('Manual processing must never request the network');
        }),
      ),
    );
  });
  tearDown(() async {
    engine.close();
    await bridge.cleanup;
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'standalone startup and import use local tools without a backend',
    () async {
      await engine.loadSettings();
      expect((await engine.json('/health'))['on_device'], true);
      expect(engine.workspaceOrigin, 'windows-local');
      final track = await engine.upload(input.path, '音楽 song.mp3');
      expect(track['filename'], '音楽 song.mp3');
      expect(track['size'], 3);
      expect(bridge.tracks[track['id']]!.path, isNot(input.path));
      expect(await input.readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'save copies the completed export and preserves original working audio',
    () async {
      final track = await engine.upload(input.path, 'song.mp3');
      final tags = {for (final key in tagNames) key: ''};
      tags['title'] = '音楽 "quoted"';
      tags['lyrics'] = 'First line\nSecond line';
      expect(
        await engine.saveExport(track['id'] as String, {
          'tags': tags,
          'cover_action': 'keep',
        }, 'song - tagged.mp3'),
        true,
      );
      expect(writtenTags, tags);
      expect(await File(destination!).readAsBytes(), [9, 8, 7]);
      expect(await input.readAsBytes(), [1, 2, 3]);
      expect(await bridge.tracks[track['id']]!.readAsBytes(), [1, 2, 3]);
      expect(
        commands.expand((c) => c),
        isNot(contains('First line\nSecond line')),
      );
      final export = commands.firstWhere(
        (c) => c.length > 1 && c[1] == 'write',
      )[2];
      expect(await File(export).exists(), false);
    },
  );

  test(
    'canceling save retains the draft and removes the temporary export',
    () async {
      destination = null;
      final track = await engine.upload(input.path, 'song.mp3');
      expect(
        await engine.saveExport(track['id'] as String, {
          'tags': {for (final key in tagNames) key: ''},
          'cover_action': 'keep',
        }, 'song.mp3'),
        false,
      );
      expect(await input.exists(), true);
      final export = commands.firstWhere(
        (c) => c.length > 1 && c[1] == 'write',
      )[2];
      expect(await File(export).exists(), false);
    },
  );

  test(
    'fingerprint decoding is capped and uses the bundled programs',
    () async {
      final track = await engine.upload(input.path, 'song.mp3');
      expect(
        await bridge.call('fingerprint', {'id': track['id']}),
        'AQAA-windows-fingerprint',
      );
      final decode = commands.firstWhere((c) => c.contains('s16le'));
      expect(decode[decode.indexOf('-t') + 1], '120');
      expect(decode[decode.indexOf('-protocol_whitelist') + 1], 'file,pipe');
      expect(decode[decode.indexOf('-ar') + 1], '44100');
      expect(await File(decode.last).exists(), false);
    },
  );

  test(
    'Windows online settings persist separately from backend credentials',
    () async {
      await engine.saveSettings('application-key', 'me@example.org');
      engine.services.acoustIdKey = '';
      expect((await engine.loadSettings())['acoustid_key'], 'application-key');
      final stored = await const FlutterSecureStorage().read(
        key: WindowsAudioBridge.settingsKey,
      );
      expect(jsonDecode(stored!)['acoustid_key'], 'application-key');
    },
  );

  test('missing bundled tools produce a clear startup failure', () async {
    final missing = WindowsAudioBridge(
      helper: '${temporary.path}/missing.exe',
      ffmpeg: '${temporary.path}/missing-ffmpeg.exe',
    );
    await expectLater(
      missing.ensureReady(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('tools are missing'),
        ),
      ),
    );
    missing.close();
  });

  test(
    'expired temporary audio is distinguishable from provider failures',
    () async {
      final track = await engine.upload(input.path, 'song.mp3');
      await bridge.tracks[track['id']]!.delete();
      await expectLater(
        bridge.call('fingerprint', {'id': track['id']}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    },
  );
}
