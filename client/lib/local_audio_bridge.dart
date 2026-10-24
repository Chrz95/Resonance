import 'package:flutter/services.dart';

/// Local file operations shared by Kotlin/JNI and the portable Windows helper.
abstract class LocalAudioBridge {
  Future<Object?> call(String method, Map<String, dynamic> arguments);
  Future<T?> invokeMethod<T>(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]) async => await call(method, arguments) as T?;
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    final value = await call(method, arguments);
    return value == null ? null : Map<K, V>.from(value as Map);
  }

  void close() {}
}

class MethodAudioBridge extends LocalAudioBridge {
  MethodAudioBridge(this.channel);
  final MethodChannel channel;
  @override
  Future<Object?> call(String method, Map<String, dynamic> arguments) =>
      channel.invokeMethod<Object?>(method, arguments);
}
