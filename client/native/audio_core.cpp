#include "audio_core.h"
#include <fileref.h>
#include <tpropertymap.h>
#include <tvariant.h>
#include <stdexcept>
#include <regex>

namespace resonance {
using namespace TagLib;
static const std::map<std::string, const char *> keys = {
  {"title", "TITLE"}, {"artist", "ARTIST"}, {"album", "ALBUM"},
  {"album_artist", "ALBUMARTIST"}, {"date", "DATE"}, {"genre", "GENRE"},
  {"track_number", "TRACKNUMBER"}, {"disc_number", "DISCNUMBER"},
  {"recording_id", "MUSICBRAINZ_TRACKID"}, {"release_id", "MUSICBRAINZ_ALBUMID"},
  {"lyrics", "LYRICS"}, {"synced_lyrics", "SYNCEDLYRICS"}
};

AudioData read(const std::string &path) {
  FileRef file(path.c_str(), true, AudioProperties::Accurate);
  if(file.isNull() || !file.file()->isValid() || !file.audioProperties())
    throw std::runtime_error("Invalid or unsupported audio file.");
  AudioData result;
  result.duration = file.audioProperties()->lengthInMilliseconds() / 1000.0;
  const auto props = file.properties();
  for(const auto &[field, key] : keys) {
    auto list = props.value(key);
    result.tags[field] = list.isEmpty() ? "" : list.front().to8Bit(true);
  }
  // Legacy desktop custom key, supported for files exported by Resonance 1.0.
  if(result.tags["synced_lyrics"].empty()) {
    auto list = props.value("LYRICS_SYNCED");
    if(!list.isEmpty()) result.tags["synced_lyrics"] = list.front().to8Bit(true);
  }
  auto pictures = file.complexProperties("PICTURE");
  for(const auto &picture : pictures) {
    auto bytes = picture.value("data").toByteVector();
    if(!bytes.isEmpty() && (result.cover.empty() || picture.value("pictureType").toString() == "Front Cover")) {
      if(bytes.size() <= 5U * 1024U * 1024U)
        result.cover.assign(bytes.begin(), bytes.end());
      if(picture.value("pictureType").toString() == "Front Cover") break;
    }
  }
  return result;
}

void write(const std::string &path, const Tags &tags, const std::string &coverAction,
           const std::vector<uint8_t> &jpeg) {
  FileRef file(path.c_str());
  if(file.isNull() || !file.file()->isValid()) throw std::runtime_error("Invalid audio container.");
  auto props = file.properties();
  for(const auto &[field, key] : keys) {
    auto it = tags.find(field);
    const auto text = it == tags.end() ? std::string() : it->second;
    if((field == "track_number" || field == "disc_number") && !text.empty() &&
       !std::regex_match(text, std::regex("[0-9]{1,5}(/[0-9]{1,5})?")))
      throw std::runtime_error("Track and disc numbers must be digits or n/total.");
    props.erase(key);
    if(!text.empty()) props[key] = StringList(String(text, String::UTF8));
  }
  // Clear the old synonym so timed lyrics can also be removed deliberately.
  props.erase("LYRICS_SYNCED");
  auto rejected = file.setProperties(props);
  for(const auto &[field, key] : keys) {
    if(rejected.contains(key)) throw std::runtime_error(std::string("This container rejected ") + field);
  }
  if(coverAction != "keep") {
    List<VariantMap> pictures;
    if(coverAction == "replace") {
      if(jpeg.empty() || jpeg.size() > 5U * 1024U * 1024U)
        throw std::runtime_error("Choose a valid cover up to 5 MiB.");
      VariantMap picture;
      picture["data"] = ByteVector(reinterpret_cast<const char *>(jpeg.data()), static_cast<unsigned int>(jpeg.size()));
      picture["pictureType"] = String("Front Cover");
      picture["mimeType"] = String("image/jpeg");
      pictures.append(picture);
    } else if(coverAction != "remove") throw std::runtime_error("Invalid artwork action.");
    if(!file.setComplexProperties("PICTURE", pictures)) throw std::runtime_error("Could not update embedded artwork.");
  }
  if(!file.save()) throw std::runtime_error("Could not save this audio file.");
}
}
