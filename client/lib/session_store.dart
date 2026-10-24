import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'song_import.dart';

class StagedAudio {
  const StagedAudio(this.id, this.path, this.digest);
  final String id, path, digest;
}

class RestoredSession {
  const RestoredSession(this.tracks, this.selectedId, this.tab, this.messages);
  final List<TrackDraft> tracks;
  final String? selectedId;
  final int tab;
  final List<String> messages;
}

class _Snapshot {
  _Snapshot(TrackDraft draft)
    : data = draft.sessionJson(),
      original = draft.originalCover == null
          ? null
          : Uint8List.fromList(draft.originalCover!),
      edited = draft.coverAction == 'replace' && draft.cover != null
          ? Uint8List.fromList(draft.cover!)
          : null;
  final Map<String, dynamic> data;
  final Uint8List? original, edited;
}

/// Local workspace separated by backend URL (or Android), with immutable artwork
/// assets and atomically replaced, versioned manifests. Audio is never put in JSON.
class SessionStore {
  SessionStore._(this.root, this.origin, this._lock);
  final Directory root;
  final String origin;
  final RandomAccessFile _lock;
  final Expando<String> _imageNames = Expando<String>();
  final Set<String> _pendingAudio = {};
  Future<void> _writes = Future.value();
  Future<void>? _closeFuture;
  String? _lastPayload;
  bool _closing = false;
  bool _primaryValid = true;
  bool _closed = false;
  static final idPattern = RegExp(r'^[a-f0-9]{32}$');
  static final assetPattern = RegExp(r'^[a-f0-9]{64}\.img$');

  static Future<SessionStore> open(
    String origin, {
    Directory? supportDirectory,
  }) async {
    final base = supportDirectory ?? await getApplicationSupportDirectory();
    final key = sha256.convert(utf8.encode(origin)).toString();
    final root = Directory('${base.path}/resonance-sessions/$key');
    await Directory('${root.path}/audio').create(recursive: true);
    await Directory('${root.path}/assets').create(recursive: true);
    final lock = await File(
      '${root.path}/workspace.lock',
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } catch (_) {
      await lock.close();
      throw FileSystemException(
        'This session is already open in another app window.',
        root.path,
      );
    }
    try {
      for (final folder in ['audio', 'assets']) {
        await for (final entry in Directory('${root.path}/$folder').list()) {
          if (entry is File && entry.path.endsWith('.part'))
            await entry.delete();
        }
      }
    } catch (_) {
      await lock.unlock();
      await lock.close();
      rethrow;
    }
    return SessionStore._(root, origin, lock);
  }

  String _extension(String filename) {
    final value = filename.split('.').last.toLowerCase();
    if (!songExtensions.contains(value))
      throw const FormatException('Invalid saved audio extension.');
    return value;
  }

  File audioFile(String id, String filename) {
    if (!idPattern.hasMatch(id))
      throw const FormatException('Invalid saved track identifier.');
    return File('${root.path}/audio/$id.${_extension(filename)}');
  }

  Future<StagedAudio> stageAudio(String source, String filename) async {
    if (_closed || _closing) throw StateError('Session is closed.');
    final problem = await songInputError(SongInput(source, filename));
    if (problem != null) throw FileSystemException(problem, source);
    var used = 0, count = 0;
    await for (final entry in Directory('${root.path}/audio').list()) {
      if (entry is File && !entry.path.endsWith('.part')) {
        used += await entry.length();
        count++;
      }
    }
    if (count >= 51 ||
        used + await File(source).length() > 2 * 1024 * 1024 * 1024)
      throw const FileSystemException(
        'Saved session storage is full. Remove tracks before importing more audio.',
      );
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final file = audioFile(id, filename),
        temporary = File('${audioFile(id, filename).path}.part');
    _pendingAudio.add(_pathKey(file));
    try {
      await File(source).openRead().pipe(temporary.openWrite());
      final handle = await temporary.open(mode: FileMode.append);
      await handle.flush();
      await handle.close();
      final digest = (await sha256.bind(temporary.openRead()).first).toString();
      await temporary.rename(file.path);
      return StagedAudio(id, file.path, digest);
    } catch (_) {
      _pendingAudio.remove(_pathKey(file));
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> discard(StagedAudio audio) async {
    _pendingAudio.remove(_pathKey(File(audio.path)));
    final file = File(audio.path);
    if (await file.exists()) await file.delete();
  }

  Future<void> relink(TrackDraft track, String source) async {
    if (_closed || _closing) throw StateError('Session is closed.');
    final problem = await songInputError(SongInput(source, track.filename));
    if (problem != null) throw FileSystemException(problem, source);
    final digest = (await sha256.bind(File(source).openRead()).first)
        .toString();
    if (track.sourceDigest != null && track.sourceDigest != digest)
      throw const FileSystemException(
        'That file does not match the saved source. Choose the original audio file.',
      );
    final file = audioFile(track.id, track.filename),
        temporary = File('${audioFile(track.id, track.filename).path}.part');
    await File(source).openRead().pipe(temporary.openWrite());
    final handle = await temporary.open(mode: FileMode.append);
    await handle.flush();
    await handle.close();
    await temporary.rename(file.path);
    track.sourcePath = file.path;
    track.sourceDigest = digest;
    track.sourceMissing = false;
  }

  Future<String?> _asset(Uint8List? bytes) async {
    if (bytes == null) return null;
    if (bytes.length > 5 * 1024 * 1024)
      throw const FormatException('Saved cover exceeds 5 MiB.');
    final name = _imageNames[bytes] ?? '${sha256.convert(bytes)}.img';
    _imageNames[bytes] = name;
    final file = File('${root.path}/assets/$name');
    if (!await file.exists()) {
      final next = File('${file.path}.part');
      await next.writeAsBytes(bytes, flush: true);
      await next.rename(file.path);
    }
    return name;
  }

  Future<Uint8List?> _readAsset(dynamic name) async {
    if (name == null) return null;
    if (name is! String || !assetPattern.hasMatch(name))
      throw const FormatException('Invalid saved artwork reference.');
    final file = File('${root.path}/assets/$name');
    if (!await file.exists() || await file.length() > 5 * 1024 * 1024)
      throw const FileSystemException('Saved cover is missing or too large.');
    final bytes = await file.readAsBytes();
    if ('${sha256.convert(bytes)}.img' != name)
      throw const FileSystemException('Saved cover is damaged.');
    return bytes;
  }

  Future<RestoredSession> load() async {
    var any = false;
    for (final name in [
      'session.json',
      'session.backup.json',
      'session.next.json',
    ]) {
      final file = File('${root.path}/$name');
      if (!await file.exists()) continue;
      any = true;
      try {
        if (await file.length() > 64 * 1024 * 1024)
          throw const FormatException('Session snapshot is too large.');
        final data = jsonDecode(await file.readAsString()) as Map;
        if (data['schema'] != 1 ||
            data['origin'] != origin ||
            data['tracks'] is! List ||
            (data['tracks'] as List).length > 50)
          throw const FormatException('Unsupported session snapshot.');
        final tracks = <TrackDraft>[];
        final ids = <String>{};
        final messages = <String>[];
        for (final raw in data['tracks'] as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          if (!ids.add(row['id'] as String))
            throw const FormatException('Duplicate saved track.');
          Uint8List? originalImage, editedImage;
          try {
            originalImage = await _readAsset(row['original_cover']);
          } on FileSystemException {
            messages.add(
              'Original artwork for ${row['filename']} is unavailable. Text edits were restored.',
            );
          }
          try {
            editedImage = await _readAsset(row['edited_cover']);
          } on FileSystemException {
            messages.add(
              'Replacement artwork for ${row['filename']} is unavailable. Choose its cover again.',
            );
            row['cover_action'] = 'keep';
          }
          final track = TrackDraft.restore(
            row,
            originalImage: originalImage,
            editedImage: editedImage,
          );
          final audio = audioFile(track.id, track.filename);
          track.sourcePath = audio.path;
          track.sourceMissing =
              !await audio.exists() || await audio.length() != track.size;
          if (track.sourceMissing)
            messages.add(
              'Locate the original audio for ${track.filename} to resume processing. Its edits were restored.',
            );
          tracks.add(track);
        }
        _primaryValid = name == 'session.json';
        if (name != 'session.json')
          messages.insert(0, 'Recovered the last valid session snapshot.');
        final tab = data['tab'] is int
            ? (data['tab'] as int).clamp(0, 2).toInt()
            : 0;
        return RestoredSession(
          tracks,
          data['selected_id'] as String?,
          tab,
          messages,
        );
      } catch (e) {
        // Try the previous complete snapshot rather than discarding the workspace.
        if (name == 'session.next.json') break;
      }
    }
    if (any)
      throw const FormatException(
        'No valid session snapshot could be restored. Existing files were preserved.',
      );
    return const RestoredSession([], null, 0, []);
  }

  Future<void> save(
    List<TrackDraft> drafts, {
    String? selectedId,
    int tab = 0,
  }) {
    if (_closed || _closing) throw StateError('Session is closed.');
    if (drafts.length > 50)
      throw const FormatException('Too many tracks in saved session.');
    final snapshots = drafts.map(_Snapshot.new).toList();
    final job = _writes.then((_) async {
      if (_closed) throw StateError('Session is closed.');
      final rows = <Map<String, dynamic>>[];
      for (final snapshot in snapshots) {
        audioFile(
          snapshot.data['id'] as String,
          snapshot.data['filename'] as String,
        );
        rows.add({
          ...snapshot.data,
          'original_cover': await _asset(snapshot.original),
          'edited_cover': await _asset(snapshot.edited),
        });
      }
      final payload = jsonEncode({
        'schema': 1,
        'origin': origin,
        'selected_id': selectedId,
        'tab': tab,
        'tracks': rows,
      });
      if (_lastPayload == payload) return;
      final next = File('${root.path}/session.next.json');
      await next.writeAsString(
        jsonEncode({
          ...jsonDecode(payload) as Map<String, dynamic>,
          'saved_at': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      final current = File('${root.path}/session.json'),
          backup = File('${root.path}/session.backup.json');
      if (_primaryValid && await current.exists()) {
        final backupNext = await current.copy(
          '${root.path}/session.backup.next.json',
        );
        await backupNext.rename(backup.path);
      }
      await next.rename(current.path);
      _primaryValid = true;
      _lastPayload = payload;
      for (final row in rows)
        _pendingAudio.remove(
          _pathKey(audioFile(row['id'] as String, row['filename'] as String)),
        );
      await _collectGarbage();
    });
    _writes = job.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return job;
  }

  Future<void> _collectGarbage() async {
    final keepAudio = <String>{}, keepAssets = <String>{};
    for (final name in ['session.json', 'session.backup.json']) {
      final file = File('${root.path}/$name');
      if (!await file.exists()) continue;
      try {
        final data = jsonDecode(await file.readAsString()) as Map;
        for (final row in data['tracks'] as List) {
          keepAudio.add(
            _pathKey(audioFile(row['id'] as String, row['filename'] as String)),
          );
          for (final key in ['original_cover', 'edited_cover'])
            if (row[key] is String) keepAssets.add(row[key] as String);
        }
      } catch (_) {
        return;
      } // Do not delete recovery files when a manifest is damaged.
    }
    await for (final entry in Directory('${root.path}/audio').list()) {
      if (entry is File &&
          !entry.path.endsWith('.part') &&
          !keepAudio.contains(_pathKey(entry)) &&
          !_pendingAudio.contains(_pathKey(entry)))
        await entry.delete();
    }
    await for (final entry in Directory('${root.path}/assets').list()) {
      if (entry is File &&
          !entry.path.endsWith('.part') &&
          !keepAssets.contains(entry.uri.pathSegments.last))
        await entry.delete();
    }
  }

  static String _pathKey(FileSystemEntity entry) =>
      entry.absolute.uri.normalizePath().toString();

  Future<void> close() => _closeFuture ??= () async {
    _closing = true;
    await _writes;
    _closed = true;
    try {
      await _lock.unlock();
    } finally {
      await _lock.close();
    }
  }();
}
