import 'package:flutter/services.dart';
import 'local_audio_bridge.dart';
import 'local_engine.dart';
import 'public_services.dart';

/// Android uses the Kotlin/JNI bridge; online workflows are shared with Windows.
class AndroidEngine extends LocalMusicEngine {
  AndroidEngine({MethodChannel? channel, PublicMusicServices? services})
    : super(
        bridge: MethodAudioBridge(
          channel ?? const MethodChannel('org.resonance/audio'),
        ),
        services: services,
      );
}
