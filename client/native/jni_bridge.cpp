#include "audio_core.h"
#include <jni.h>
#include <chromaprint.h>
#include <memory>
#include <stdexcept>

static std::string str(JNIEnv *env, jstring value) {
  // GetStringUTFChars uses modified UTF-8 (breaks supplementary Unicode).
  // Java String.getBytes("UTF-8") produces real UTF-8 for TagLib paths/tags.
  auto cls = env->FindClass("java/lang/String");
  auto method = env->GetMethodID(cls, "getBytes", "(Ljava/lang/String;)[B");
  auto encoding = env->NewStringUTF("UTF-8");
  auto array = static_cast<jbyteArray>(env->CallObjectMethod(value, method, encoding));
  auto len = env->GetArrayLength(array);
  std::string result(static_cast<size_t>(len), '\0');
  env->GetByteArrayRegion(array, 0, len, reinterpret_cast<jbyte *>(result.data()));
  env->DeleteLocalRef(array); env->DeleteLocalRef(encoding); env->DeleteLocalRef(cls);
  return result;
}
static jstring jstr(JNIEnv *env, const std::string &text) {
  auto bytes = env->NewByteArray(static_cast<jsize>(text.size()));
  env->SetByteArrayRegion(bytes, 0, static_cast<jsize>(text.size()), reinterpret_cast<const jbyte *>(text.data()));
  auto cls = env->FindClass("java/lang/String");
  auto ctor = env->GetMethodID(cls, "<init>", "([BLjava/lang/String;)V");
  auto encoding = env->NewStringUTF("UTF-8");
  auto result = static_cast<jstring>(env->NewObject(cls, ctor, bytes, encoding));
  env->DeleteLocalRef(bytes); env->DeleteLocalRef(cls); env->DeleteLocalRef(encoding);
  return result;
}
static void fail(JNIEnv *env, const std::exception &e) { env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), e.what()); }
extern "C" JNIEXPORT jobject JNICALL
Java_org_resonance_resonance_NativeAudio_read(JNIEnv *env, jobject, jstring path) {
  try {
    auto data = resonance::read(str(env, path));
    auto cls = env->FindClass("java/util/HashMap");
    auto init = env->GetMethodID(cls, "<init>", "()V");
    auto put = env->GetMethodID(cls, "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    auto result = env->NewObject(cls, init);
    auto tags = env->NewObject(cls, init);
    for(const auto &[key, value] : data.tags) {
      auto k = jstr(env, key); auto v = jstr(env, value);
      env->CallObjectMethod(tags, put, k, v); env->DeleteLocalRef(k); env->DeleteLocalRef(v);
    }
    auto key = jstr(env, "tags"); env->CallObjectMethod(result, put, key, tags); env->DeleteLocalRef(key);
    auto doubleClass = env->FindClass("java/lang/Double");
    auto number = env->NewObject(doubleClass, env->GetMethodID(doubleClass, "<init>", "(D)V"), data.duration);
    key = jstr(env, "duration"); env->CallObjectMethod(result, put, key, number); env->DeleteLocalRef(key);
    auto cover = env->NewByteArray(static_cast<jsize>(data.cover.size()));
    if(!data.cover.empty()) env->SetByteArrayRegion(cover, 0, static_cast<jsize>(data.cover.size()), reinterpret_cast<const jbyte *>(data.cover.data()));
    key = jstr(env, "cover"); env->CallObjectMethod(result, put, key, cover);
    return result;
  } catch(const std::exception &e) { fail(env, e); return nullptr; }
}
extern "C" JNIEXPORT void JNICALL
Java_org_resonance_resonance_NativeAudio_write(JNIEnv *env, jobject, jstring path, jobjectArray keys, jobjectArray values, jstring action, jbyteArray artwork) {
  try {
    resonance::Tags tags;
    for(jsize i = 0; i < env->GetArrayLength(keys); ++i) {
      auto key = static_cast<jstring>(env->GetObjectArrayElement(keys, i));
      auto value = static_cast<jstring>(env->GetObjectArrayElement(values, i));
      tags[str(env, key)] = str(env, value); env->DeleteLocalRef(key); env->DeleteLocalRef(value);
    }
    std::vector<uint8_t> cover(artwork ? env->GetArrayLength(artwork) : 0);
    if(!cover.empty()) env->GetByteArrayRegion(artwork, 0, static_cast<jsize>(cover.size()), reinterpret_cast<jbyte *>(cover.data()));
    resonance::write(str(env, path), tags, str(env, action), cover);
  } catch(const std::exception &e) { fail(env, e); }
}
extern "C" JNIEXPORT jlong JNICALL
Java_org_resonance_resonance_NativeAudio_createFingerprint(JNIEnv *env, jobject, jint rate, jint channels) {
  auto ctx = chromaprint_new(CHROMAPRINT_ALGORITHM_DEFAULT);
  if(!ctx || !chromaprint_start(ctx, rate, channels)) {
    if(ctx) chromaprint_free(ctx);
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Cannot initialize Chromaprint."); return 0;
  }
  return reinterpret_cast<jlong>(ctx);
}
extern "C" JNIEXPORT void JNICALL
Java_org_resonance_resonance_NativeAudio_feedFingerprint(JNIEnv *env, jobject, jlong handle, jshortArray samples) {
  auto pcm = env->GetShortArrayElements(samples, nullptr);
  const int ok = chromaprint_feed(reinterpret_cast<ChromaprintContext *>(handle), pcm, env->GetArrayLength(samples));
  env->ReleaseShortArrayElements(samples, pcm, JNI_ABORT);
  if(!ok) env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Chromaprint could not process audio.");
}
extern "C" JNIEXPORT jstring JNICALL
Java_org_resonance_resonance_NativeAudio_finishFingerprint(JNIEnv *env, jobject, jlong handle) {
  auto ctx = reinterpret_cast<ChromaprintContext *>(handle); char *encoded = nullptr;
  if(!chromaprint_finish(ctx) || !chromaprint_get_fingerprint(ctx, &encoded)) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Could not finish fingerprint."); return nullptr;
  }
  auto result = env->NewStringUTF(encoded); chromaprint_dealloc(encoded); return result;
}
extern "C" JNIEXPORT void JNICALL
Java_org_resonance_resonance_NativeAudio_freeFingerprint(JNIEnv *, jobject, jlong handle) {
  if(handle) chromaprint_free(reinterpret_cast<ChromaprintContext *>(handle));
}
