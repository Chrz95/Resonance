import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'api.dart';
import 'engine.dart';
import 'public_services.dart';
import 'local_audio_bridge.dart';

class LocalMusicEngine implements MusicEngine {
  LocalMusicEngine({required this.bridge, PublicMusicServices? services})
    : services = services ?? PublicMusicServices();
  final LocalAudioBridge bridge;
  String get workspaceOrigin => 'android-local';
  final PublicMusicServices services;
  final _tracks = <String, Map<String, dynamic>>{};

  Future<Map<String, String>> loadSettings() async {
    final value = Map<String, String>.from(
      await bridge.invokeMapMethod<String, String>('getSettings') ?? {},
    );
    final key = value['acoustid_key'] ?? '';
    final agent = value['user_agent'] ?? '';
    services.acoustIdKey = key.isEmpty
        ? const String.fromEnvironment('ACOUSTID_API_KEY')
        : key;
    services.userAgent = agent.isEmpty
        ? const String.fromEnvironment('MUSIC_USER_AGENT')
        : agent;
    return {
      'acoustid_key': services.acoustIdKey,
      'user_agent': services.userAgent,
    };
  }

  Future<void> saveSettings(String key, String contact) async {
    final agent = contact.isEmpty ? '' : 'Resonance/1.1 ($contact)';
    await bridge.invokeMethod<void>('saveSettings', {
      'acoustid_key': key,
      'user_agent': agent,
    });
    services.acoustIdKey = key;
    services.userAgent = agent;
  }

  @override
  Future<Map<String, dynamic>> upload(String path, String filename) async {
    final data = Map<String, dynamic>.from(
      await bridge.invokeMapMethod<String, dynamic>('import', {
            'path': path,
            'filename': filename,
          }) ??
          {},
    );
    final tags = Map<String, String>.from(data['tags'] as Map);
    data['tags'] = tags;
    final cover = data.remove('cover') as Uint8List?;
    data['cover_base64'] = cover == null || cover.isEmpty
        ? null
        : base64Encode(cover);
    _tracks[data['id'] as String] = data;
    return data;
  }

  Map<String, dynamic> _track(String id) {
    final value = _tracks[id];
    if (value == null)
      throw ApiException(
        'This audio session expired. Import the file again.',
        statusCode: 404,
      );
    return value;
  }

  @override
  Future<Map<String, dynamic>> json(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String>? query,
  }) async {
    if (path == '/health')
      return {
        'status': 'ok',
        'version': '1.6.0',
        'alternative_sources': true,
        'candidate_availability': true,
        'on_device': true,
        'fingerprint_tool': true,
        'acoustid_configured': services.acoustIdKey.isNotEmpty,
        'musicbrainz_configured': services.userAgent.isNotEmpty,
      };
    if (path == '/search') return services.search(query!['q']!);
    final parts = path.split('/');
    if (parts.length < 3 || parts[1] != 'tracks')
      throw ApiException('Unknown local operation.');
    final id = parts[2];
    final track = _track(id);
    if (method == 'DELETE') {
      await bridge.invokeMethod<void>('delete', {'id': id});
      _tracks.remove(id);
      return {'deleted': true};
    }
    final duration = (track['duration'] as num).toDouble();
    switch (parts.last) {
      case 'alternatives':
        return services.alternateSources.find(body as Map);
      case 'alternative-cover':
        final result = await services.alternateSources.cover(
          (body as Map)['collection_id'] as int,
        );
        final jpeg = await bridge.invokeMethod<Uint8List>('normalizeCover', {
          'cover': base64Decode(result['cover_base64'] as String),
        });
        if (jpeg == null)
          throw ApiException('Could not prepare this cover image.');
        result['cover_base64'] = base64Encode(jpeg);
        return result;
      case 'availability':
        return services.availability(body as Map, duration);
      case 'identify':
        final fingerprint = await bridge.invokeMethod<String>('fingerprint', {
          'id': id,
        });
        if (fingerprint == null || fingerprint.length < 8)
          throw ApiException('Not enough decodable audio to fingerprint.');
        return services.identify(
          fingerprint,
          duration,
          sha256.convert(utf8.encode(fingerprint)).toString(),
        );
      case 'enrich':
        final request = body as Map;
        return services.enrich(
          request,
          Map<String, String>.from(
            (request['current_tags'] ?? track['tags']) as Map,
          ),
          duration,
        );
      case 'lyrics':
        final result = await services.lyrics(
          Map<String, String>.from(body as Map),
          duration,
        );
        if (result == null)
          throw ApiException('No matching lyrics. Existing lyrics were kept.');
        return result;
      default:
        throw ApiException('Unknown local operation.');
    }
  }

  @override
  Future<Uint8List> export(String id, Map<String, dynamic> body) async {
    final output = await _exportPath(id, body);
    final file = File(output);
    try {
      return await file.readAsBytes();
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<String> _exportPath(String id, Map<String, dynamic> body) async {
    _track(id);
    final output = await bridge.invokeMethod<String>('export', {
      'id': id,
      'tags': body['tags'],
      'cover_action': body['cover_action'],
      if (body['cover_base64'] != null)
        'cover': base64Decode(body['cover_base64'] as String),
    });
    if (output == null)
      throw ApiException('Could not write tags on this device.');
    return output;
  }

  /// Stream/copy the completed file through the platform save dialog. Large
  /// audio files never travel through Flutter's method-channel byte buffers.
  Future<bool> saveExport(
    String id,
    Map<String, dynamic> body,
    String filename,
  ) async {
    final output = await _exportPath(id, body);
    try {
      return await bridge.invokeMethod<bool>('saveFile', {
            'path': output,
            'filename': filename,
          }) ??
          false;
    } finally {
      final file = File(output);
      if (await file.exists()) await file.delete();
    }
  }

  Future<String?> overwriteExport(
    String id,
    Map<String, dynamic> body,
    String filename,
    String expected,
  ) async {
    final output = await _exportPath(id, body);
    try {
      return await bridge.invokeMethod<String>('overwriteFile', {
        'path': output,
        'filename': filename,
        'expected_digest': expected,
      });
    } finally {
      final file = File(output);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  void close() {
    services.close();
    bridge.close();
  }
}
