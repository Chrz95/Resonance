import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BackendConnection {
  const BackendConnection(this.url, this.token);
  final String url;
  final String token;

  static BackendConnection? parse(Object? value) {
    if (value is! Map || value['url'] is! String || value['token'] is! String)
      return null;
    final url = (value['url'] as String).trim().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    final token = (value['token'] as String).trim();
    final uri = Uri.tryParse(url);
    if (token.isEmpty ||
        uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty)
      return null;
    return BackendConnection(url, token);
  }
}

/// Store the URL and secret in one protected OS-storage entry, never a plain file.
class ConnectionStore {
  const ConnectionStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;
  final FlutterSecureStorage _storage;
  static const key = 'resonance.backend.connection.v1';
  Future<BackendConnection?> load() async {
    final text = await _storage.read(key: key);
    if (text == null) return null;
    try {
      return BackendConnection.parse(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(BackendConnection connection) => _storage.write(
    key: key,
    value: jsonEncode({'url': connection.url, 'token': connection.token}),
  );
  Future<void> forget() => _storage.delete(key: key);
}
