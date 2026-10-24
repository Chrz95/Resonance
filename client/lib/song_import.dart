import 'dart:io';

const songExtensions = {'mp3', 'flac', 'm4a', 'ogg', 'opus'};

class SongInput {
  const SongInput(this.path, this.name);
  final String path;
  final String name;
  static SongInput fromPath(String path) =>
      SongInput(path, path.split(RegExp(r'[/\\]')).last);
}

/// Validate drops/picker input before connecting or uploading any bytes.
Future<String?> songInputError(SongInput input) async {
  final extension = input.name.split('.').last.toLowerCase();
  if (!songExtensions.contains(extension))
    return 'Unsupported file. Use MP3, FLAC, M4A, Ogg or Opus.';
  final FileStat stat;
  try {
    stat = await File(input.path).stat();
  } on FileSystemException {
    return 'Could not read this audio file. Check file permissions.';
  }
  if (stat.type != FileSystemEntityType.file)
    return 'Choose a readable audio file; folders are not imported.';
  if (stat.size <= 0 || stat.size > 120 * 1024 * 1024)
    return 'Audio files must be nonempty and at most 120 MiB.';
  return null;
}
