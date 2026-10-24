#include "audio_core.h"
#include <chromaprint.h>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

int main(int argc, char **argv) {
  try {
    if(argc < 3) throw std::runtime_error("usage: native_test read|write|clear|keep|fingerprint path [jpeg]");
    std::string operation = argv[1], path = argv[2];
    if(operation == "fingerprint") {
      std::ifstream input(path, std::ios::binary);
      auto ctx = chromaprint_new(CHROMAPRINT_ALGORITHM_DEFAULT);
      if(!ctx || !chromaprint_start(ctx, 44100, 1)) throw std::runtime_error("fingerprint init");
      std::vector<int16_t> pcm(4096);
      while(input.read(reinterpret_cast<char *>(pcm.data()), pcm.size() * 2) || input.gcount()) {
        if(!chromaprint_feed(ctx, pcm.data(), static_cast<int>(input.gcount() / 2))) throw std::runtime_error("fingerprint feed");
      }
      char *fingerprint = nullptr;
      if(!chromaprint_finish(ctx) || !chromaprint_get_fingerprint(ctx, &fingerprint)) throw std::runtime_error("fingerprint finish");
      std::cout << fingerprint << '\n';
      chromaprint_dealloc(fingerprint); chromaprint_free(ctx);
    } else if(operation == "read") {
      auto data = resonance::read(path);
      for(const auto &[key, value] : data.tags) std::cout << key << '=' << value << '\n';
      std::cout << "cover_bytes=" << data.cover.size() << '\n';
    } else if(operation == "clear") {
      resonance::write(path, {}, "remove", {});
      auto data = resonance::read(path);
      for(const auto &[key, value] : data.tags) if(!value.empty()) throw std::runtime_error("Not cleared: " + key);
      if(!data.cover.empty()) throw std::runtime_error("Cover not removed");
    } else if(operation == "keep") {
      auto data = resonance::read(path);
      auto before = data.cover;
      data.tags["title"] = "Manually edited title";
      resonance::write(path, data.tags, "keep", {});
      if(resonance::read(path).cover != before) throw std::runtime_error("Keep changed artwork");
    } else if(operation == "write") {
      if(argc != 4) throw std::runtime_error("Cover argument required");
      std::ifstream image(argv[3], std::ios::binary);
      std::vector<uint8_t> cover((std::istreambuf_iterator<char>(image)), {});
      resonance::Tags tags = {{"title", "Δοκιμή — 音楽 🎵"}, {"artist", "Manual artist"},
        {"album", "Manual album"}, {"album_artist", "Album artist"}, {"date", "2024-03-02"},
        {"genre", "Rock"}, {"track_number", "2/10"}, {"disc_number", "1/2"},
        {"lyrics", "Manually typed lyrics"}, {"synced_lyrics", "[00:01.00] Timed lyrics"},
        {"recording_id", "ab4d36ac-ed70-4e6b-8528-8012ab81dd42"},
        {"release_id", "1211553d-7e94-46af-a13c-146f67f534d5"}};
      resonance::write(path, tags, "replace", cover);
      auto data = resonance::read(path);
      if(data.tags != tags) {
        for(const auto &[key, value] : tags) if(data.tags[key] != value) std::cerr << key << ": expected " << value << ", got " << data.tags[key] << '\n';
        throw std::runtime_error("Tag round-trip failed");
      }
      if(data.cover != cover) throw std::runtime_error("Cover round-trip failed");
    } else throw std::runtime_error("Unknown operation");
    return 0;
  } catch(const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
