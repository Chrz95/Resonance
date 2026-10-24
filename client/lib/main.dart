import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'availability_badges.dart';
import 'candidate_availability.dart';
import 'android_engine.dart';
import 'engine.dart';
import 'models.dart';
import 'connection_store.dart';
import 'song_import.dart';
import 'alternate_picker.dart';

const background = Color(0xFF101116);
const panel = Color(0xFF191A22);
const muted = Color(0xFF9B9CAB);
const accent = Color(0xFFB5A1FF);
const mint = Color(0xFF97E2C6);

void main() => runApp(const ResonanceApp());

class ResonanceApp extends StatelessWidget {
  const ResonanceApp({
    super.key,
    this.enableDesktopDrop = true,
    this.autoConnect = true,
  });
  final bool enableDesktopDrop;
  final bool autoConnect;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Resonance',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: mint,
        surface: panel,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF121319),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF30313B)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: muted, fontSize: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerColor: const Color(0xFF2D2E38),
    ),
    home: Studio(
      enableDesktopDrop: enableDesktopDrop,
      autoConnect: autoConnect,
    ),
  );
}

class Studio extends StatefulWidget {
  const Studio({
    super.key,
    this.enableDesktopDrop = true,
    this.autoConnect = true,
  });
  final bool enableDesktopDrop;
  final bool autoConnect;
  @override
  State<Studio> createState() => _StudioState();
}

class _StudioState extends State<Studio> {
  final tracks = <TrackDraft>[];
  final search = TextEditingController();
  MusicEngine? api;
  final editorAnchor = GlobalKey();
  TrackDraft? selected;
  bool busy = false;
  String activity = '';
  String serverUrl = 'http://127.0.0.1:8765';
  String accessToken = '';
  Map<String, dynamic>? health;
  int tab = 0;
  bool fetchLyrics = true;
  bool fetchCover = true;
  final connectionStore = const ConnectionStore();
  Future<void>? startupConnection;
  Timer? retryTimer;
  bool reconnecting = false;
  bool settingsOpen = false;
  bool dragging = false;
  String? connectionIssue;
  int connectionGeneration = 0;
  int availabilityGeneration = 0;
  bool handlingDrop = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      final local = AndroidEngine();
      api = local;
      local
          .loadSettings()
          .then((_) async {
            final status = await local.json('/health');
            if (mounted) setState(() => health = status);
          })
          .catchError((Object e) {
            notice('Could not load online settings: $e', error: true);
          });
    } else if (widget.autoConnect) {
      startupConnection = restoreConnection();
    }
  }

  Future<void> restoreConnection() async {
    try {
      final stored =
          await connectionStore.load() ??
          BackendConnection.parse({
            'url': const String.fromEnvironment(
              'RESONANCE_URL',
              defaultValue: 'http://127.0.0.1:8765',
            ),
            'token': const String.fromEnvironment('RESONANCE_TOKEN'),
          });
      if (!mounted || stored == null || api != null || settingsOpen) return;
      serverUrl = stored.url;
      accessToken = stored.token;
      retryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted && api == null && !busy && !settingsOpen)
          unawaited(reconnect());
      });
      await reconnect();
    } catch (_) {
      if (mounted)
        setState(
          () => connectionIssue =
              'Could not read the saved connection. Open Connect to configure it again.',
        );
    }
  }

  Future<void> reconnect() async {
    if (reconnecting ||
        api != null ||
        settingsOpen ||
        accessToken.isEmpty ||
        !mounted)
      return;
    final generation = connectionGeneration;
    setState(() => reconnecting = true);
    final next = ResonanceApi(serverUrl, accessToken);
    try {
      final status = await next
          .json('/health')
          .timeout(const Duration(seconds: 5));
      if (!mounted || generation != connectionGeneration || api != null) {
        next.close();
        return;
      }
      setState(() {
        api = next;
        health = status;
        connectionIssue = null;
      });
    } catch (_) {
      next.close();
      if (mounted && generation == connectionGeneration)
        setState(
          () => connectionIssue =
              'Saved service is unavailable. Retrying automatically; use Connect to change settings.',
        );
    } finally {
      if (mounted) setState(() => reconnecting = false);
    }
  }

  @override
  void dispose() {
    retryTimer?.cancel();
    connectionGeneration++;
    api?.close();
    search.dispose();
    super.dispose();
  }

  void notice(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error
            ? const Color(0xFF8A3548)
            : const Color(0xFF343044),
        duration: const Duration(seconds: 6),
        showCloseIcon: true,
      ),
    );
  }

  Future<void> run(String message, Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      activity = message;
    });
    try {
      await action();
    } on TimeoutException {
      notice(
        'The request timed out. Check the server connection and try again.',
        error: true,
      );
    } catch (e) {
      notice(
        e is PlatformException
            ? (e.message ?? 'Audio operation failed.')
            : e is ApiException
            ? e.message
            : 'Could not complete the operation. Check the connection or file permissions. $e',
        error: true,
      );
    } finally {
      if (mounted)
        setState(() {
          busy = false;
          activity = '';
        });
    }
  }

  Future<void> settings() async {
    connectionGeneration++;
    setState(() => settingsOpen = true);
    try {
      await connectionSettings();
    } finally {
      if (mounted) setState(() => settingsOpen = false);
    }
  }

  Future<void> connectionSettings() async {
    if (api is AndroidEngine) {
      await androidSettings();
      return;
    }
    final url = TextEditingController(text: serverUrl);
    final token = TextEditingController(text: accessToken);
    String? error;
    bool connecting = false;
    final connected = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Connect your music service'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Run the included service on your PC. Use its address and access token here.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: url,
                    enabled: !connecting,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'http://192.168.1.10:8765',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: token,
                    enabled: !connecting,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Access token',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'The server URL and key are saved in protected OS storage. The app reconnects automatically on startup. Audio is processed on your configured service.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  if (tracks.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Changing servers clears the imported queue. Export any edits first.',
                        style: TextStyle(color: accent),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xFFFFA9B8)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: connecting
                  ? null
                  : () async {
                      try {
                        await connectionStore.forget();
                        notice(
                          'Saved connection removed. This session stays connected until the app closes.',
                        );
                      } catch (_) {
                        notice(
                          'Could not remove the saved connection.',
                          error: true,
                        );
                      }
                    },
              child: const Text('Forget saved connection'),
            ),
            TextButton(
              onPressed: connecting
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: connecting
                  ? null
                  : () async {
                      final address = url.text.trim().replaceFirst(
                        RegExp(r'/+$'),
                        '',
                      );
                      final parsed = Uri.tryParse(address);
                      if (parsed == null ||
                          !['http', 'https'].contains(parsed.scheme) ||
                          parsed.host.isEmpty ||
                          parsed.userInfo.isNotEmpty ||
                          parsed.hasQuery ||
                          parsed.hasFragment ||
                          (parsed.path.isNotEmpty && parsed.path != '/')) {
                        update(
                          () => error =
                              'Enter an http or https server address without a path.',
                        );
                        return;
                      }
                      if (token.text.trim().isEmpty) {
                        update(
                          () => error =
                              'Enter the RESONANCE_TOKEN from your server configuration.',
                        );
                        return;
                      }
                      update(() {
                        connecting = true;
                        error = null;
                      });
                      final next = ResonanceApi(address, token.text.trim());
                      try {
                        final status = await next
                            .json('/health')
                            .timeout(const Duration(seconds: 12));
                        try {
                          await connectionStore.save(
                            BackendConnection(address, token.text.trim()),
                          );
                        } catch (_) {
                          throw ApiException(
                            'The service responded, but the key could not be saved in protected OS storage. Check the app installation.',
                          );
                        }
                        if (!mounted || !dialogContext.mounted) {
                          next.close();
                          return;
                        }
                        final changed =
                            api != null &&
                            (address != serverUrl ||
                                token.text.trim() != accessToken);
                        api?.close();
                        setState(() {
                          api = next;
                          health = status;
                          serverUrl = address;
                          accessToken = token.text.trim();
                          connectionIssue = null;
                          if (changed) {
                            tracks.clear();
                            selected = null;
                          }
                        });
                        Navigator.pop(dialogContext, true);
                      } catch (e) {
                        next.close();
                        if (dialogContext.mounted)
                          update(() {
                            error = e is ApiException
                                ? e.message
                                : 'Cannot reach the service. Check its address, token and firewall.';
                            connecting = false;
                          });
                      }
                    },
              child: Text(connecting ? 'Connecting…' : 'Connect'),
            ),
          ],
        ),
      ),
    );
    // Dialog transition may still be reading controllers; release on the next frame.
    Future<void>.delayed(const Duration(seconds: 1), () {
      url.dispose();
      token.dispose();
    });
    if (connected == true && mounted)
      notice('Connected. Import an audio file to get started.');
  }

  Future<void> androidSettings() async {
    final local = api! as AndroidEngine;
    final key = TextEditingController(text: local.services.acoustIdKey);
    final agent = local.services.userAgent;
    final contact = TextEditingController(
      text: RegExp(r'\((.*)\)$').firstMatch(agent)?.group(1) ?? '',
    );
    String? error;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Online services'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  info(
                    'Audio parsing, manual editing, artwork embedding and fingerprint extraction run on this phone. No Windows app or server is needed.',
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: key,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: 'Free AcoustID application key (optional)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: contact,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: 'Contact email or project URL for MusicBrainz',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SelectableText(
                    'Register a free noncommercial application key:\nhttps://acoustid.org/new-application',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Online matching requires Internet access. The complete audio stays on your phone; only fingerprints and lookup text go to music services. These settings are stored locally.',
                    style: TextStyle(fontSize: 12, color: muted, height: 1.5),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xFFFFA9B8)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final text = contact.text.trim();
                      if (text.isNotEmpty &&
                          !(text.contains('@') ||
                              text.startsWith('https://'))) {
                        update(
                          () => error =
                              'Enter a contact email or https project URL.',
                        );
                        return;
                      }
                      update(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await local.saveSettings(key.text.trim(), text);
                        final status = await local.json('/health');
                        if (!mounted || !dialogContext.mounted) return;
                        setState(() => health = status);
                        Navigator.pop(dialogContext);
                      } catch (e) {
                        if (dialogContext.mounted)
                          update(() {
                            error = '$e';
                            saving = false;
                          });
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save settings'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      key.dispose();
      contact.dispose();
    });
  }

  void editManually([int page = 0]) {
    setState(() => tab = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anchor = editorAnchor.currentContext;
      if (anchor != null)
        Scrollable.ensureVisible(
          anchor,
          duration: const Duration(milliseconds: 300),
          alignment: .05,
        );
    });
  }

  Future<void> importLyrics() => run('Opening lyrics…', () async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'lrc'],
    );
    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    if (await file.length() > 1024 * 1024) {
      notice('Choose a lyric file smaller than 1 MiB.', error: true);
      return;
    }
    final text = await file.readAsString();
    if (text.length > 200000) {
      notice('Lyrics must be under 200,000 characters.', error: true);
      return;
    }
    final timed = result.files.single.extension?.toLowerCase() == 'lrc';
    if (mounted)
      setState(() {
        selected!.tags[timed ? 'synced_lyrics' : 'lyrics'] = text.replaceFirst(
          '\uFEFF',
          '',
        );
        selected!.revision++;
        selected!.exported = false;
      });
  });

  void select(TrackDraft track) {
    availabilityGeneration++;
    setState(() {
      selected = track;
      tab = 0;
      search.text = [
        track.tags['artist'],
        track.tags['title'],
      ].where((s) => s != null && s.isNotEmpty).join(' ');
    });
    if (track.candidates.isNotEmpty) startAvailabilityChecks(track);
  }

  Future<void> importFiles() async {
    await startupConnection;
    if (!mounted) return;
    if (api == null) {
      await settings();
      if (api == null) return;
    }
    await run('Choosing audio…', () async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: songExtensions.toList(),
        allowMultiple: true,
      );
      if (result == null) return;
      final inputs = result.files
          .where((f) => f.path != null)
          .map((f) => SongInput(f.path!, f.name))
          .toList();
      await importSongs(inputs, recognize: false);
    });
  }

  Future<void> droppedSongs(List<String> paths) async {
    if (busy || settingsOpen || handlingDrop) return;
    setState(() {
      handlingDrop = true;
      dragging = false;
    });
    try {
      await importDroppedSongs(paths);
    } finally {
      if (mounted) setState(() => handlingDrop = false);
    }
  }

  Future<void> importDroppedSongs(List<String> paths) async {
    setState(() => dragging = false);
    final inputs = paths.map(SongInput.fromPath).toList();
    final valid = <SongInput>[];
    for (final input in inputs) {
      final error = await songInputError(input);
      if (error == null)
        valid.add(input);
      else
        notice('${input.name}: $error', error: true);
    }
    if (valid.isEmpty || !mounted) return;
    await startupConnection;
    if (!mounted) return;
    if (api == null) {
      await reconnect();
    }
    if (api == null) {
      await settings();
      if (api == null) return;
    }
    await run(
      'Importing and identifying dropped songs…',
      () => importSongs(valid, recognize: true),
    );
  }

  Future<void> importSongs(
    List<SongInput> inputs, {
    required bool recognize,
  }) async {
    var imported = 0;
    for (final input in inputs) {
      try {
        final error = await songInputError(input);
        if (error != null) {
          notice('${input.name}: $error', error: true);
          continue;
        }
        if (mounted) setState(() => activity = 'Reading ${input.name}…');
        final track = TrackDraft.fromJson(
          await api!.upload(input.path, input.name),
        );
        if (!mounted) return;
        tracks.add(track);
        select(track);
        imported++;
        if (recognize) {
          setState(() => activity = 'Identifying ${input.name}…');
          try {
            await identifyTrack(track);
          } catch (e) {
            if (mounted)
              setState(
                () => track.notices = [
                  'Identification failed: $e. Manual editing is available.',
                ],
              );
          }
        }
      } catch (e) {
        notice('${input.name}: $e', error: true);
      }
    }
    if (imported > 0)
      notice(
        '$imported ${imported == 1 ? 'file' : 'files'} imported${recognize ? ' and checked for recognition' : ''}.',
      );
  }

  Future<void> identify() => run(
    'Listening to the audio fingerprint…',
    () => identifyTrack(selected!),
  );

  Future<void> identifyTrack(TrackDraft track) async {
    final result = await api!.json(
      '/tracks/${track.id}/identify',
      method: 'POST',
    );
    if (!mounted) return;
    setState(() {
      track.signature = result['signature'] as String;
      track.candidates = (result['candidates'] as List)
          .cast<Map<String, dynamic>>();
      track.notices = (result['warnings'] as List).cast<String>();
    });
    startAvailabilityChecks(track);
  }

  Future<void> searchTracks() => run('Searching MusicBrainz…', () async {
    if (search.text.trim().length < 2) {
      notice('Enter a song title, artist, or both.');
      return;
    }
    final track = selected!;
    final result = await api!.json('/search', query: {'q': search.text.trim()});
    if (!mounted) return;
    setState(() {
      track.candidates = (result['candidates'] as List)
          .cast<Map<String, dynamic>>();
      track.notices = track.candidates.isEmpty
          ? ['No matches. Try a different title or artist.']
          : [];
    });
    startAvailabilityChecks(track);
  });

  void startAvailabilityChecks(TrackDraft track) {
    if (selected != track) return;
    final generation = ++availabilityGeneration;
    final engine = api!;
    final entries = track.candidates;
    unawaited(
      checkCandidateAvailability(
        engine: engine,
        trackId: track.id,
        candidates: entries,
        isActive: () =>
            mounted &&
            generation == availabilityGeneration &&
            selected == track &&
            identical(api, engine) &&
            tracks.contains(track) &&
            identical(track.candidates, entries),
        changed: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> applyMatch(Map<String, dynamic> candidate) => run(
    'Fetching metadata${fetchLyrics ? ', lyrics' : ''}${fetchCover ? ' and artwork' : ''}…',
    () async {
      final track = selected!;
      final result = await api!.json(
        '/tracks/${track.id}/enrich',
        method: 'POST',
        body: {
          'recording_id': candidate['recording_id'],
          if ((candidate['release_id'] as String).isNotEmpty)
            'release_id': candidate['release_id'],
          'lyrics': fetchLyrics,
          'cover': fetchCover,
          'current_tags': track.tags,
        },
      );
      if (!mounted) return;
      setState(() {
        track.selectedCandidate = candidate;
        track.tags = Map<String, String>.from(result['tags'] as Map);
        if (result['cover_base64'] != null) {
          track.cover = base64Decode(result['cover_base64'] as String);
          track.coverAction = 'replace';
        }
        track.notices = (result['warnings'] as List).cast<String>();
        track.sources = (result['sources'] as List).cast<String>();
        track.revision++;
        track.exported = false;
      });
      notice('Match loaded into the editor. Review the tags before exporting.');
    },
  );

  Future<void> otherSources(Map<String, dynamic> candidate, String kind) => run(
    kind == 'cover'
        ? 'Searching alternate artwork…'
        : 'Searching alternate lyrics…',
    () async {
      final track = selected!;
      setState(() => track.selectedCandidate = candidate);
      final result = await api!.json(
        '/tracks/${track.id}/alternatives',
        method: 'POST',
        body: {
          'kind': kind,
          'title': candidate['title'],
          'artist': candidate['artist'],
          'album': candidate['album'] ?? '',
        },
      );
      if (!mounted) return;
      final options = (result['options'] as List).cast<Map<String, dynamic>>();
      final warnings = (result['warnings'] as List).cast<String>();
      if (options.isEmpty) {
        notice(
          'No alternate $kind results found.${warnings.isEmpty ? '' : ' ${warnings.join(' ')}'}',
        );
        return;
      }
      final choice = await pickAlternateSource(
        context,
        kind: kind,
        candidate: candidate,
        options: options,
        warnings: warnings,
      );
      if (choice == null || !mounted) return;
      final stem = '${candidate['artist']} - ${candidate['title']}'.replaceAll(
        RegExp(r'[<>:"/\\|?*\x00-\x1f]'),
        '_',
      );
      final safeName = stem.length > 120 ? stem.substring(0, 120) : stem;
      if (kind == 'cover') {
        final image = await api!.json(
          '/tracks/${track.id}/alternative-cover',
          method: 'POST',
          body: {'collection_id': choice['collection_id']},
        );
        final bytes = base64Decode(image['cover_base64'] as String);
        if (choice['action'] == 'save') {
          final path = await FilePicker.platform.saveFile(
            fileName: '$safeName - cover.jpg',
            bytes: bytes,
            type: FileType.custom,
            allowedExtensions: ['jpg'],
          );
          if (path != null) notice('Cover image saved.');
        } else if (mounted) {
          setState(() {
            track.cover = bytes;
            track.coverAction = 'replace';
            track.exported = false;
            track.sources = {
              ...track.sources,
              image['source_url'] as String,
            }.toList();
            tab = 2;
          });
          notice('Alternate cover loaded into the editor.');
        }
        if (mounted)
          setState(() {
            candidate['alternate_has_cover'] = true;
            candidate['alternate_cover_source'] = 'iTunes';
          });
      } else {
        final plain = choice['lyrics'] as String,
            timed = choice['synced_lyrics'] as String;
        if (choice['action'] == 'save') {
          final extension = plain.isNotEmpty ? 'txt' : 'lrc';
          final path = await FilePicker.platform.saveFile(
            fileName: '$safeName.$extension',
            bytes: utf8.encode(plain.isNotEmpty ? plain : timed),
            type: FileType.custom,
            allowedExtensions: [extension],
          );
          if (path != null) notice('Lyrics saved.');
        } else if (mounted) {
          setState(() {
            track.tags['lyrics'] = plain;
            track.tags['synced_lyrics'] = timed;
            track.revision++;
            track.exported = false;
            track.sources = {
              ...track.sources,
              choice['source_url'] as String,
            }.toList();
            tab = 1;
          });
          notice('Alternate lyrics loaded into the editor.');
        }
        if (mounted)
          setState(() {
            candidate['alternate_has_lyrics'] = true;
            candidate['alternate_lyrics_source'] = choice['source'];
          });
      }
    },
  );

  Future<void> lyrics() => run('Looking for matching lyrics…', () async {
    final track = selected!;
    final result = await api!.json(
      '/tracks/${track.id}/lyrics',
      method: 'POST',
      body: track.tags,
    );
    if (!mounted) return;
    setState(() {
      track.tags['lyrics'] = result['lyrics'] as String;
      track.tags['synced_lyrics'] = result['synced_lyrics'] as String;
      track.sources = {...track.sources, result['source'] as String}.toList();
      track.revision++;
      track.exported = false;
    });
    notice(
      result['instrumental'] == true
          ? 'This track is marked as instrumental.'
          : 'Lyrics found. Review them in the editor.',
    );
  });

  Future<void> chooseCover() => run('Opening artwork…', () async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    if (await file.length() > 5 * 1024 * 1024) {
      notice('Choose an image smaller than 5 MiB.', error: true);
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      selected!.cover = bytes;
      selected!.coverAction = 'replace';
      selected!.exported = false;
    });
  });

  Future<void> export() => run('Writing tags to a new copy…', () async {
    final track = selected!;
    if (api is AndroidEngine) {
      final saved = await (api! as AndroidEngine).saveExport(
        track.id,
        track.exportBody(),
        track.exportName,
      );
      if (!saved) {
        notice('Save canceled. Your edits are still here.');
        return;
      }
      if (mounted) setState(() => track.exported = true);
      notice('Saved ${track.exportName} with your tags, lyrics and artwork.');
      return;
    }
    final bytes = await api!.export(track.id, track.exportBody());
    final output = await FilePicker.platform.saveFile(
      dialogTitle: 'Save tagged audio',
      fileName: track.exportName,
      type: FileType.custom,
      allowedExtensions: [track.filename.split('.').last],
      bytes: bytes,
    );
    if (output == null) {
      notice('Save canceled. Your edits are still here.');
      return;
    }
    if (!mounted) return;
    setState(() => track.exported = true);
    notice('Saved ${track.exportName} with metadata, lyrics and artwork.');
  });

  Future<void> remove(TrackDraft track) =>
      run('Removing temporary audio…', () async {
        try {
          await api!.json('/tracks/${track.id}', method: 'DELETE');
        } on ApiException catch (e) {
          if (!e.message.contains('expired')) rethrow;
        }
        if (!mounted) return;
        setState(() {
          tracks.remove(track);
          selected = tracks.isEmpty ? null : tracks.first;
        });
        if (selected != null) select(selected!);
      });

  Widget badge(String text, {Color color = accent}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final body = buildStudio(context);
    if (!widget.enableDesktopDrop || Platform.isAndroid) return body;
    return DropTarget(
      enable: !busy && !settingsOpen && !handlingDrop,
      onDragEntered: (_) => setState(() => dragging = true),
      onDragExited: (_) => setState(() => dragging = false),
      onDragDone: (details) =>
          unawaited(droppedSongs(details.files.map((f) => f.path).toList())),
      child: Stack(
        children: [
          body,
          if (dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: background.withValues(alpha: .94),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_download_outlined,
                        size: 72,
                        color: accent,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Drop songs to identify',
                        style: TextStyle(fontSize: 28, color: accent),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'MP3 · FLAC · M4A · OGG · OPUS',
                        style: TextStyle(color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildStudio(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100;
          final padding = constraints.maxWidth < 600 ? 18.0 : 30.0;
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(padding, 20, padding, 16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        color: background,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'resonance',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.8,
                            ),
                          ),
                          Text(
                            'A little order for your music.',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                    if (constraints.maxWidth > 650)
                      badge('WINDOWS + ANDROID', color: muted),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: Platform.isAndroid
                          ? 'On-device processing / online settings'
                          : 'Server connection',
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : settings,
                        icon: Icon(
                          api == null
                              ? Icons.link_off_rounded
                              : Icons.link_rounded,
                          size: 18,
                          color: api == null ? muted : mint,
                        ),
                        label: Text(
                          Platform.isAndroid
                              ? 'On device'
                              : api == null
                              ? (reconnecting ? 'Connecting…' : 'Connect')
                              : 'Connected',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: panel,
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(padding, 10, padding, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Give every track its identity.',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -.9,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  busy
                                      ? activity
                                      : 'Identify the sound. Find the details. Keep the music.',
                                  style: const TextStyle(
                                    color: muted,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (constraints.maxWidth > 720)
                            FilledButton.icon(
                              onPressed: busy ? null : importFiles,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Import music'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (connectionIssue != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: info(connectionIssue!),
                        ),
                      if (!Platform.isAndroid &&
                          health != null &&
                          (health!['acoustid_configured'] != true ||
                              health!['musicbrainz_configured'] != true))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: info(
                            '${health!['acoustid_configured'] != true ? 'Fingerprint matching needs the free AcoustID application key. ' : ''}'
                            '${health!['musicbrainz_configured'] != true ? 'Set MUSIC_USER_AGENT on the server for metadata search. ' : ''}'
                            'Manual editing and export are available.',
                          ),
                        ),
                      if (tracks.isEmpty)
                        welcome()
                      else ...[
                        library(),
                        const SizedBox(height: 22),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: recognition()),
                              const SizedBox(width: 22),
                              Expanded(flex: 6, child: editor()),
                            ],
                          )
                        else ...[
                          recognition(),
                          const SizedBox(height: 22),
                          editor(),
                        ],
                      ],
                      const SizedBox(height: 24),
                      const Wrap(
                        spacing: 18,
                        runSpacing: 8,
                        children: [
                          Text(
                            'Powered by open music data',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                          Text(
                            'AcoustID  ·  MusicBrainz  ·  LRCLIB  ·  Cover Art Archive',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
    floatingActionButton:
        MediaQuery.sizeOf(context).width <= 720 && tracks.isNotEmpty
        ? FloatingActionButton(
            onPressed: busy ? null : importFiles,
            tooltip: 'Import music',
            child: const Icon(Icons.add),
          )
        : null,
  );

  Widget info(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .07),
      border: Border.all(color: accent.withValues(alpha: .18)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFFD3C9F8),
        fontSize: 12,
        height: 1.5,
      ),
    ),
  );

  Widget card({Key? key, required Widget child}) => Container(
    key: key,
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: panel,
      border: Border.all(color: const Color(0xFF292A34)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );

  Widget welcome() => card(
    child: Column(
      children: [
        const SizedBox(height: 25),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4B3B77), Color(0xFF252C38)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Icon(
            Icons.library_music_rounded,
            size: 48,
            color: accent,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Your collection, rediscovered.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 490,
          child: Text(
            Platform.isAndroid
                ? 'Choose an audio file to identify or edit on this phone.'
                : 'Drop songs anywhere here to identify them automatically, or choose files to edit.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, height: 1.7),
          ),
        ),
        const SizedBox(height: 25),
        FilledButton.icon(
          onPressed: busy ? null : importFiles,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Choose music files'),
        ),
        const SizedBox(height: 16),
        const Text(
          'MP3 · FLAC · M4A · OGG · OPUS   /   Up to 120 MiB per file',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 11),
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 18),
        const Wrap(
          spacing: 32,
          runSpacing: 18,
          alignment: WrapAlignment.center,
          children: [
            Feature(
              icon: Icons.fingerprint_rounded,
              title: 'Recognize by sound',
              text: 'Chromaprint fingerprints',
            ),
            Feature(
              icon: Icons.lyrics_outlined,
              title: 'Complete the story',
              text: 'Lyrics and cover artwork',
            ),
            Feature(
              icon: Icons.verified_user_outlined,
              title: 'Keep your originals',
              text: 'Review, then save a copy',
            ),
          ],
        ),
        const SizedBox(height: 14),
      ],
    ),
  );

  Widget library() => card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.queue_music_rounded, color: muted, size: 20),
            const SizedBox(width: 10),
            Text(
              'Your session',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: 10),
            badge('${tracks.length} files', color: muted),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final track = tracks[i];
              final active = selected == track;
              return InkWell(
                onTap: busy ? null : () => select(track),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 265,
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                  decoration: BoxDecoration(
                    color: active ? accent.withValues(alpha: .09) : background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? accent.withValues(alpha: .6)
                          : const Color(0xFF2D2E38),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        track.exported
                            ? Icons.check_circle_rounded
                            : Icons.audio_file_outlined,
                        color: track.exported ? mint : accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${track.filename.split('.').last.toUpperCase()} · ${track.time} · ${(track.size / 1048576).toStringAsFixed(1)} MiB',
                              style: const TextStyle(
                                fontSize: 11,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: busy ? null : () => remove(track),
                        icon: const Icon(Icons.close_rounded, size: 15),
                        tooltip: 'Remove file from session',
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget recognition() {
    final track = selected!;
    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              badge('01'),
              const SizedBox(width: 12),
              const Text(
                'Find the right match',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Recognize the sound, search by name, or edit every detail manually.',
            style: TextStyle(color: muted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : editManually,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit manually — no match needed'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : identify,
              icon: const Icon(Icons.fingerprint_rounded),
              label: const Text('Identify audio'),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    hintText: 'Song title or artist',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (_) {
                    if (!busy) searchTracks();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: busy ? null : searchTracks,
                icon: const Icon(Icons.arrow_forward_rounded),
                tooltip: 'Search MusicBrainz',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Fetch lyrics'),
                selected: fetchLyrics,
                onSelected: busy
                    ? null
                    : (v) => setState(() => fetchLyrics = v),
              ),
              FilterChip(
                label: const Text('Fetch cover'),
                selected: fetchCover,
                onSelected: busy ? null : (v) => setState(() => fetchCover = v),
              ),
            ],
          ),
          if (track.signature.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 15, color: mint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Signature ${track.signature.substring(0, 16)}…',
                      style: const TextStyle(color: mint, fontSize: 11),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: track.signature));
                      notice('Signature hash copied.');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    tooltip: 'Copy fingerprint SHA-256',
                  ),
                ],
              ),
            ),
          for (final text in track.notices)
            Padding(padding: const EdgeInsets.only(top: 12), child: info(text)),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'CANDIDATES',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: muted,
                ),
              ),
              const Spacer(),
              Text(
                '${track.candidates.length} found',
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (track.candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'Matches will appear here.\nYou can also edit tags manually.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, height: 1.7),
                ),
              ),
            ),
          for (final candidate in track.candidates) candidateCard(candidate),
          if (track.candidates.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'One recording can have several releases. Check the album, date and edition. Scores describe the lookup match, not certainty about a release.',
                style: TextStyle(color: muted, fontSize: 11, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget candidateCard(Map<String, dynamic> c) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: selected?.selectedCandidate == c
            ? accent
            : const Color(0xFF30313B),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.album_outlined, color: accent, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c['title'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c['artist'] as String,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            badge(
              '${((c['score'] as num) * 100).round()}%',
              color: c['source'] == 'fingerprint' ? mint : accent,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          [
            c['album'],
            c['date'],
            c['country'],
          ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          style: const TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 8),
        AvailabilityBadges(candidate: c),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: busy ? null : () => otherSources(c, 'cover'),
              icon: const Icon(Icons.image_search_outlined, size: 16),
              label: const Text('Other covers'),
            ),
            TextButton.icon(
              onPressed: busy ? null : () => otherSources(c, 'lyrics'),
              icon: const Icon(Icons.lyrics_outlined, size: 16),
              label: const Text('Other lyrics'),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                c['source'] == 'fingerprint'
                    ? 'AcoustID · audio match'
                    : 'MusicBrainz · text match',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ),
            TextButton(
              onPressed: busy ? null : () => applyMatch(c),
              child: const Text('Use match →'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget editor() {
    final track = selected!;
    return card(
      key: editorAnchor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              badge('02'),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Manual editor',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              Tooltip(
                message: 'Reset to imported tags',
                child: IconButton(
                  onPressed: busy ? null : () => setState(track.reset),
                  icon: const Icon(Icons.restart_alt_rounded, size: 21),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            track.filename,
            style: const TextStyle(color: muted, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 18),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Tags')),
              ButtonSegment(value: 1, label: Text('Lyrics')),
              ButtonSegment(value: 2, label: Text('Cover')),
            ],
            selected: {tab},
            onSelectionChanged: (values) => setState(() => tab = values.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 22),
          if (tab == 0) tagsEditor(track),
          if (tab == 1) lyricsEditor(track),
          if (tab == 2) coverEditor(track),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: mint, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${track.changes} changes · Original file preserved',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : export,
              icon: Icon(
                track.exported ? Icons.check_rounded : Icons.save_alt_rounded,
              ),
              label: Text(
                track.exported
                    ? 'Save another tagged copy'
                    : 'Save tagged copy',
              ),
            ),
          ),
          if (track.sources.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'SOURCES',
              style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1),
            ),
            for (final source in track.sources)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: SelectableText(
                  source,
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget field(
    TrackDraft track,
    String key,
    String label, {
    int lines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey('${track.id}:${track.revision}:$key'),
      initialValue: track.tags[key],
      enabled: !busy,
      maxLines: lines,
      minLines: lines > 1 ? lines : null,
      style: TextStyle(
        fontSize: lines > 1 ? 13 : 14,
        height: lines > 1 ? 1.7 : null,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText:
            track.original[key]!.isNotEmpty &&
                track.original[key] != track.tags[key] &&
                lines == 1
            ? 'Was: ${track.original[key]}'
            : null,
        helperMaxLines: 1,
      ),
      onChanged: (value) => setState(() {
        track.tags[key] = value;
        track.exported = false;
      }),
    ),
  );

  Widget tagsEditor(TrackDraft track) => Column(
    children: [
      field(track, 'title', 'Title'),
      field(track, 'artist', 'Artist'),
      field(track, 'album', 'Album'),
      field(track, 'album_artist', 'Album artist'),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: field(track, 'date', 'Release date', hint: 'YYYY-MM-DD'),
          ),
          const SizedBox(width: 12),
          Expanded(child: field(track, 'genre', 'Genre')),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: field(track, 'track_number', 'Track', hint: '3/12')),
          const SizedBox(width: 12),
          Expanded(child: field(track, 'disc_number', 'Disc', hint: '1/1')),
        ],
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text(
          'MusicBrainz identifiers',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        children: [
          field(track, 'recording_id', 'Recording ID'),
          field(track, 'release_id', 'Release ID'),
        ],
      ),
    ],
  );

  Widget lyricsEditor(TrackDraft track) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Type or paste lyrics below, or import a UTF-8 text/LRC file. You can save without an online lookup.',
        style: TextStyle(color: muted, fontSize: 12, height: 1.5),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy ? null : importLyrics,
        icon: const Icon(Icons.note_add_outlined, size: 18),
        label: const Text('Import .txt or .lrc'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy ? null : lyrics,
        icon: const Icon(Icons.cloud_download_outlined, size: 18),
        label: const Text('Find lyrics with LRCLIB'),
      ),
      const SizedBox(height: 16),
      field(
        track,
        'lyrics',
        'Plain lyrics',
        lines: 9,
        hint: 'Lyrics found online or pasted here will be embedded.',
      ),
      field(
        track,
        'synced_lyrics',
        'Timed lyrics (LRC)',
        lines: 5,
        hint: '[00:12.00] A line of lyrics',
      ),
      const Text(
        'Plain lyrics use the container’s native lyrics tag. Timed LRC text uses a custom tag; player support varies.',
        style: TextStyle(color: muted, fontSize: 11, height: 1.5),
      ),
      if (track.tags['synced_lyrics']!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextButton.icon(
            onPressed: busy
                ? null
                : () => run('Saving LRC file…', () async {
                    final stem = track.filename.substring(
                      0,
                      track.filename.lastIndexOf('.'),
                    );
                    await FilePicker.platform.saveFile(
                      fileName: '$stem.lrc',
                      bytes: utf8.encode(track.tags['synced_lyrics']!),
                    );
                  }),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Export .lrc sidecar'),
          ),
        ),
    ],
  );

  Widget coverEditor(TrackDraft track) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 260,
            height: 260,
            child: track.cover == null
                ? Container(
                    color: background,
                    child: const Icon(
                      Icons.album_rounded,
                      size: 90,
                      color: Color(0xFF393746),
                    ),
                  )
                : Image.memory(
                    track.cover!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Text('Cannot preview this image')),
                  ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 8,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : chooseCover,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Choose image'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    track.cover = null;
                    track.coverAction = 'remove';
                    track.exported = false;
                  }),
            child: const Text('Remove'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    track.cover = track.originalCover;
                    track.coverAction = 'keep';
                    track.exported = false;
                  }),
            child: const Text('Keep original'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        'Artwork: ${track.coverAction == 'keep'
            ? 'keep embedded original'
            : track.coverAction == 'remove'
            ? 'remove on export'
            : 'replace on export'}.',
        style: const TextStyle(color: mint, fontSize: 12),
      ),
      const SizedBox(height: 10),
      const Text(
        'Use a match to fetch release artwork automatically. You can also choose a local image up to 5 MiB. New covers are embedded as JPEG, up to 1600 px.',
        style: TextStyle(color: muted, fontSize: 11, height: 1.6),
      ),
    ],
  );
}

class Feature extends StatelessWidget {
  const Feature({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Column(
      children: [
        Icon(icon, color: accent, size: 24),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 5),
        Text(text, style: const TextStyle(color: muted, fontSize: 11)),
      ],
    ),
  );
}
