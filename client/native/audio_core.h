#pragma once
#include <map>
#include <string>
#include <vector>
#include <cstdint>

namespace resonance {
using Tags = std::map<std::string, std::string>;
struct AudioData { Tags tags; double duration; std::vector<uint8_t> cover; };
AudioData read(const std::string &path);
// Mutates a private copy, never the user-selected original.
void write(const std::string &path, const Tags &tags, const std::string &coverAction,
           const std::vector<uint8_t> &jpeg);
}
