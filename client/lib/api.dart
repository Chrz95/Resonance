import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'engine.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ResonanceApi implements MusicEngine {
  ResonanceApi(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  final _client = http.Client();
  Map<String, String> get headers => {'Authorization': 'Bearer $token'};
  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  void close() => _client.close();

  void check(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = 'Request failed (${response.statusCode}).';
    try {
      final detail = (jsonDecode(response.body) as Map)['detail'];
      if (detail is String) message = detail;
      if (detail is List)
        message =
            'Check your tag values. Track and disc numbers must be digits, or n/total.';
    } catch (_) {
      /* A proxy may return HTML rather than JSON. */
    }
    throw ApiException(message);
  }

  Future<Map<String, dynamic>> json(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, uri(path, query));
    request.headers.addAll(headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await (() async => http.Response.fromStream(
      await _client.send(request),
    ))().timeout(const Duration(seconds: 150));
    check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> upload(String path, String filename) async {
    final request = http.MultipartRequest('POST', uri('/tracks'));
    request.headers.addAll(headers);
    request.files.add(
      await http.MultipartFile.fromPath('file', path, filename: filename),
    );
    final response = await (() async => http.Response.fromStream(
      await _client.send(request),
    ))().timeout(const Duration(minutes: 5));
    check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Uint8List> export(String id, Map<String, dynamic> body) async {
    final response = await _client
        .post(
          uri('/tracks/$id/export'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 3));
    check(response);
    return response.bodyBytes;
  }
}
