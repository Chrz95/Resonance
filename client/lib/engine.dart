import 'dart:typed_data';

/// The editor uses the same contract for a desktop service or on-device Android.
abstract class MusicEngine {
  Future<Map<String, dynamic>> json(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String>? query,
  });
  Future<Map<String, dynamic>> upload(String path, String filename);
  Future<Uint8List> export(String id, Map<String, dynamic> body);
  void close();
}
