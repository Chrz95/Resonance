#pragma once
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <windows.h>

// One top-level window per generated runner. Wait for Dart's durable checkpoint
// before honoring normal WM_CLOSE; forced OS termination still uses autosaves.
namespace resonance_session {
inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
inline bool ready = false;
inline bool closing = false;
inline bool allowed = false;

inline void Initialize(flutter::BinaryMessenger* messenger, HWND window) {
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "org.resonance/session-window", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    if (call.method_name() == "ready") { ready = true; result->Success(); }
    else if (call.method_name() == "allowClose") {
      allowed = true; result->Success(); PostMessage(window, WM_CLOSE, 0, 0);
    } else if (call.method_name() == "cancelClose") { closing = false; result->Success(); }
    else result->NotImplemented();
  });
}

inline bool Handle(UINT message) {
  if (message == WM_CLOSE && ready && !allowed && channel) {
    if (!closing) { closing = true; channel->InvokeMethod("closeRequested", nullptr); }
    return true;
  }
  return false;
}

inline void Dispose() {
  if (channel) channel->SetMethodCallHandler(nullptr);
  channel.reset(); ready = false; closing = false; allowed = false;
}
}
