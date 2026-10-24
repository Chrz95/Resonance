import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'local_audio_bridge.dart';
import 'local_engine.dart';
import 'models.dart';
import 'public_services.dart';
import 'song_import.dart';

typedef DesktopCommand =
    Future<Uint8List> Function(String executable, List<String> arguments);
typedef DesktopSavePath = Future<String?> Function(String filename);

class WindowsEngine extends LocalMusicEngine {
  WindowsEngine({WindowsAudioBridge? bridge, PublicMusicServices? services})
    : super(bridge: bridge ?? WindowsAudioBridge(), services: services);
  @override
  String get workspaceOrigin => 'windows-local';
  @override
  Future<Map<String, dynamic>> json(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String>? query,
  }) async {
    if (path == '/health') await (bridge as WindowsAudioBridge).ensureReady();
    return super.json(path, method: method, body: body, query: query);
  }
}

/// Runs bundled programs directly, without a shell, network listener or PATH lookup.
/// The portable TagLib helper writes tags; FFmpeg only decodes PCM and artwork.
class WindowsAudioBridge extends LocalAudioBridge {
  WindowsAudioBridge({
    String? helper,
    String? ffmpeg,
    this.supportDirectory,
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    DesktopCommand? command,
    DesktopSavePath? savePath,
  }) : helper =
           helper ??
           '${File(Platform.resolvedExecutable).parent.path}/tools/resonance_desktop.exe',
       ffmpeg =
           ffmpeg ??
           '${File(Platform.resolvedExecutable).parent.path}/tools/ffmpeg.exe',
       storage = storage,
       command = command,
       savePath = savePath;
  final String helper, ffmpeg;
  final Directory? supportDirectory;
  final FlutterSecureStorage storage;
  final DesktopCommand? command;
  final DesktopSavePath? savePath;
  final tracks = <String, File>{};
  final processes = <Process>{};
  Future<Directory>? _directory;
  Future<void>? _ready;
  Future<void>? _cleanup;
  Future<void> get cleanup => _cleanup ?? Future<void>.value();
  bool closed = false;
  static const settingsKey = 'resonance.windows.online.v1';

  String _id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<Directory> _root() => _directory ??= () async {
    final base = supportDirectory ?? await getTemporaryDirectory();
    final cache = await Directory(
      '${base.path}/resonance-desktop-cache',
    ).create(recursive: true);
    await for (final entry in cache.list()) {
      if (DateTime.now().difference((await entry.stat()).modified).inHours > 24)
        await entry.delete(recursive: true);
    }
    return cache.createTemp('run-');
  }();

  Future<void> ensureReady() => _ready ??= () async {
    if (!await File(helper).exists() || !await File(ffmpeg).exists())
      throw ApiException(
        'The Windows audio tools are missing. Rebuild with tools/bootstrap_client.py and keep the complete app folder together.',
      );
    if (utf8.decode(await _execute(helper, ['version'])).trim() !=
        'resonance-desktop/1')
      throw ApiException(
        'The Windows audio helper does not match this app. Rebuild the complete app folder.',
      );
    await _execute(ffmpeg, ['-version']);
  }();

  Future<Uint8List> _execute(String executable, List<String> arguments) async {
    if (closed) throw ApiException('Local audio processing has closed.');
    if (command != null) return command!(executable, arguments);
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
    );
    processes.add(process);
    Future<Uint8List> collect(Stream<List<int>> stream, int limit) async {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (bytes.length + chunk.length > limit) {
          process.kill();
          throw ApiException('The local audio tool returned too much data.');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }

    try {
      final results =
          await Future.wait<Object>([
            process.exitCode,
            collect(process.stdout, 8 * 1024 * 1024),
            collect(process.stderr, 256 * 1024),
          ]).timeout(
            const Duration(minutes: 3),
            onTimeout: () {
              process.kill();
              throw TimeoutException('Local audio processing timed out.');
            },
          );
      if (results[0] != 0) {
        final message = utf8
            .decode(results[2] as Uint8List, allowMalformed: true)
            .trim();
        throw ApiException(
          message.isEmpty ? 'Local audio processing failed.' : message,
        );
      }
      return results[1] as Uint8List;
    } finally {
      processes.remove(process);
    }
  }

  File _track(Map<String, dynamic> arguments) {
    final file = tracks[arguments['id']];
    if (file == null || !file.existsSync())
      throw ApiException(
        'This audio session expired. Import the file again.',
        statusCode: 404,
      );
    return file;
  }

  Future<Map<String, dynamic>> _read(File file) async {
    final root = await _root();
    final cover = File('${root.path}/${_id()}.img');
    try {
      final result =
          jsonDecode(
                utf8.decode(
                  await _execute(helper, ['read', file.path, cover.path]),
                ),
              )
              as Map;
      return {
        ...Map<String, dynamic>.from(result),
        'cover': await cover.exists() ? await cover.readAsBytes() : null,
      };
    } finally {
      if (await cover.exists()) await cover.delete();
    }
  }

  Future<Uint8List> _normalize(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024)
      throw ApiException('Choose a cover up to 5 MiB.');
    final directory = await (await _root()).createTemp('cover-');
    final input = await File('${directory.path}/input').writeAsBytes(bytes);
    final output = File('${directory.path}/cover.jpg');
    try {
      await _execute(ffmpeg, [
        '-nostdin',
        '-v',
        'error',
        '-y',
        '-max_alloc',
        '67108864',
        '-protocol_whitelist',
        'file,pipe',
        '-i',
        input.path,
        '-frames:v',
        '1',
        '-vf',
        'scale=1200:1200:force_original_aspect_ratio=decrease',
        '-q:v',
        '3',
        output.path,
      ]);
      if (!await output.exists() || await output.length() > 5 * 1024 * 1024)
        throw ApiException('Could not prepare this cover image.');
      return await output.readAsBytes();
    } finally {
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<Object?> call(String method, Map<String, dynamic> arguments) async {
    if (method == 'getSettings') {
      final text = await storage.read(key: settingsKey);
      if (text == null) return <String, String>{};
      try {
        return Map<String, String>.from(jsonDecode(text) as Map);
      } on FormatException {
        return <String, String>{};
      } on TypeError {
        return <String, String>{};
      }
    }
    if (method == 'saveSettings') {
      await storage.write(key: settingsKey, value: jsonEncode(arguments));
      return null;
    }
    await ensureReady();
    if (method == 'import') {
      final input = SongInput(
        arguments['path'] as String,
        arguments['filename'] as String,
      );
      final error = await songInputError(input);
      if (error != null) throw ApiException(error);
      tracks.removeWhere((_, file) => !file.existsSync());
      var used = 0;
      for (final file in tracks.values) {
        used += await file.length();
      }
      if (tracks.length >= 50 ||
          used + await File(input.path).length() > 2 * 1024 * 1024 * 1024)
        throw ApiException(
          'Local session storage is full. Remove a track first.',
        );
      final id = _id();
      final file = File(
        '${(await _root()).path}/$id.${input.name.split('.').last.toLowerCase()}',
      );
      try {
        await File(input.path).copy(file.path);
        final data = await _read(file);
        tracks[id] = file;
        return {
          ...data,
          'id': id,
          'filename': input.name,
          'size': await file.length(),
        };
      } catch (_) {
        if (await file.exists()) await file.delete();
        rethrow;
      }
    }
    if (method == 'normalizeCover')
      return _normalize(arguments['cover'] as Uint8List);
    if (method == 'fingerprint') {
      final file = _track(arguments);
      final pcm = File('${(await _root()).path}/${_id()}.pcm');
      try {
        await _execute(ffmpeg, [
          '-nostdin',
          '-v',
          'error',
          '-y',
          '-protocol_whitelist',
          'file,pipe',
          '-i',
          file.path,
          '-map',
          '0:a:0',
          '-t',
          '120',
          '-ar',
          '44100',
          '-ac',
          '1',
          '-f',
          's16le',
          pcm.path,
        ]);
        return utf8
            .decode(await _execute(helper, ['fingerprint', pcm.path]))
            .trim();
      } finally {
        if (await pcm.exists()) await pcm.delete();
      }
    }
    if (method == 'delete') {
      final file = _track(arguments);
      await file.delete();
      tracks.remove(arguments['id']);
      return null;
    }
    if (method == 'export') {
      final source = _track(arguments);
      final root = await _root();
      final output = File(
        '${root.path}/export-${_id()}.${source.path.split('.').last}',
      );
      final staging = await root.createTemp('tags-');
      try {
        final tags = Map<String, String>.from(arguments['tags'] as Map);
        for (final key in tagNames) {
          final value = tags[key] ?? '';
          if (value.length >
              (key == 'lyrics' || key == 'synced_lyrics' ? 200000 : 2000))
            throw ApiException('The $key field is too long.');
          await File('${staging.path}/$key').writeAsString(value, flush: true);
        }
        final action = arguments['cover_action'] as String? ?? 'keep';
        if (!['keep', 'replace', 'remove'].contains(action))
          throw ApiException('Invalid artwork action.');
        final cover = File('${staging.path}/cover.jpg');
        if (action == 'replace')
          await cover.writeAsBytes(
            await _normalize(arguments['cover'] as Uint8List),
          );
        await source.copy(output.path);
        await _execute(helper, [
          'write',
          output.path,
          staging.path,
          action,
          cover.path,
        ]);
        return output.path;
      } catch (_) {
        if (await output.exists()) await output.delete();
        rethrow;
      } finally {
        await staging.delete(recursive: true);
      }
    }
    if (method == 'saveFile') {
      final file = File(arguments['path'] as String);
      final root = await _root();
      if (!file.absolute.uri.normalizePath().toString().startsWith(
            root.absolute.uri.normalizePath().toString(),
          ) ||
          !await file.exists())
        throw ApiException('Invalid local export file.');
      final name = arguments['filename'] as String;
      final destination = savePath != null
          ? await savePath!(name)
          : await FilePicker.platform.saveFile(
              dialogTitle: 'Save tagged audio',
              fileName: name,
              type: FileType.custom,
              allowedExtensions: [name.split('.').last],
            );
      if (destination == null) return false;
      await file.copy(destination);
      return true;
    }
    throw ApiException('Unknown Windows audio operation.');
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    for (final process in processes) {
      process.kill();
    }
    _cleanup = () async {
      try {
        final root = await _directory;
        if (root != null && await root.exists())
          await root.delete(recursive: true);
      } catch (_) {
        /* Stale working files are removed on a later startup. */
      }
    }();
    unawaited(_cleanup);
  }
}
