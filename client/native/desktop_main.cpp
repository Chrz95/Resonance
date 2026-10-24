#include "audio_core.h"
#include <chromaprint.h>
#include <tstring.h>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

namespace fs = std::filesystem;
static constexpr const char* fields[] = {"title", "artist", "album", "album_artist", "date", "genre",
  "track_number", "disc_number", "recording_id", "release_id", "lyrics", "synced_lyrics"};

static std::string json(const std::string& value) {
  std::ostringstream out;
  out << '"';
  for(unsigned char c : value) {
    if(c == '"' || c == '\\') out << '\\' << c;
    else if(c < 32) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<int>(c) << std::dec;
    else out << c;
  }
  out << '"';
  return out.str();
}

static std::vector<uint8_t> bytes(const fs::path& path, size_t limit) {
  if(!fs::is_regular_file(path) || fs::file_size(path) > limit)
    throw std::runtime_error("Missing or oversized local input.");
  std::ifstream input(path, std::ios::binary);
  if(!input) throw std::runtime_error("Cannot read local input.");
  std::vector<uint8_t> result((std::istreambuf_iterator<char>(input)), {});
  if(result.size() > limit) throw std::runtime_error("Local input exceeds size limit.");
  return result;
}

static int run(const std::vector<std::string>& args) {
  if(args.size() == 2 && args[1] == "version") {
    std::cout << "resonance-desktop/1\n"; return 0;
  }
  if(args.size() < 3) throw std::runtime_error("Invalid local audio request.");
  const auto operation = args[1], path = args[2];
  if(operation == "read" && args.size() == 4) {
    const auto data = resonance::read(path);
    if(!data.cover.empty()) {
      std::ofstream cover(fs::u8path(args[3]), std::ios::binary | std::ios::trunc);
      cover.write(reinterpret_cast<const char*>(data.cover.data()), data.cover.size());
      if(!cover) throw std::runtime_error("Cannot stage embedded artwork.");
    }
    std::cout << "{\"duration\":" << std::setprecision(15) << data.duration << ",\"tags\":{";
    bool first = true;
    for(const auto& [key, value] : data.tags) {
      if(!first) std::cout << ',';
      first = false;
      std::cout << json(key) << ':' << json(value);
    }
    std::cout << "}}\n";
  } else if(operation == "write" && args.size() == 6) {
    resonance::Tags tags;
    for(const auto field : fields) {
      const bool lyric = std::string(field) == "lyrics" || std::string(field) == "synced_lyrics";
      auto value = bytes(fs::u8path(args[3]) / field, lyric ? 800000 : 8000);
      tags[field] = std::string(value.begin(), value.end());
    }
    const auto cover = args[4] == "replace" ? bytes(fs::u8path(args[5]), 5 * 1024 * 1024) : std::vector<uint8_t>{};
    resonance::write(path, tags, args[4], cover);
    const auto verified = resonance::read(path);
    if(verified.tags != tags) throw std::runtime_error("The audio container did not retain all requested tags.");
    if(args[4] == "replace" && verified.cover != cover) throw std::runtime_error("Artwork verification failed.");
    if(args[4] == "remove" && !verified.cover.empty()) throw std::runtime_error("Artwork removal failed.");
    std::cout << "ok\n";
  } else if(operation == "fingerprint" && args.size() == 3) {
    // The decoder supplies at most 120 seconds of 44.1 kHz mono signed LE PCM.
    const auto pcm = bytes(fs::u8path(path), 120 * 44100 * 2);
    if(pcm.size() < 44100 * 2 || pcm.size() % 2) throw std::runtime_error("Not enough decodable audio to fingerprint.");
    std::unique_ptr<ChromaprintContext, decltype(&chromaprint_free)> context(
      chromaprint_new(CHROMAPRINT_ALGORITHM_DEFAULT), chromaprint_free);
    if(!context || !chromaprint_start(context.get(), 44100, 1)) throw std::runtime_error("Could not start fingerprinting.");
    std::vector<int16_t> samples(pcm.size() / 2);
    for(size_t i = 0; i < samples.size(); ++i)
      samples[i] = static_cast<int16_t>(pcm[i*2] | (static_cast<unsigned>(pcm[i*2+1]) << 8));
    if(!chromaprint_feed(context.get(), samples.data(), static_cast<int>(samples.size())) || !chromaprint_finish(context.get()))
      throw std::runtime_error("Could not fingerprint this audio.");
    char* result = nullptr;
    if(!chromaprint_get_fingerprint(context.get(), &result)) throw std::runtime_error("Could not read the fingerprint.");
    std::cout << result << '\n';
    chromaprint_dealloc(result);
  } else throw std::runtime_error("Unknown local audio operation.");
  return 0;
}

#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
  _setmode(_fileno(stdout), _O_BINARY);
#else
int main(int argc, char** argv) {
#endif
  try {
    std::vector<std::string> args;
    for(int i = 0; i < argc; ++i) {
#ifdef _WIN32
      args.push_back(TagLib::String(argv[i]).to8Bit(true));
#else
      args.emplace_back(argv[i]);
#endif
    }
    return run(args);
  } catch(const std::exception& error) {
    std::cerr << error.what() << '\n'; return 1;
  }
}
