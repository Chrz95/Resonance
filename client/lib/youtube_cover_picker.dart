import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'youtube_cover.dart';
import 'youtube_search.dart';

typedef YoutubeCoverChoice = ({YoutubeCover cover, bool save});

Future<YoutubeCoverChoice?> pickYoutubeCover(
  BuildContext context, {
  required String title,
  required String artist,
  double? duration,
}) => showDialog<YoutubeCoverChoice>(
  context: context,
  builder: (_) => YoutubeCoverPicker(
    query: '$artist $title'.trim(),
    title: title,
    artist: artist,
    duration: duration,
  ),
);

class YoutubeCoverPicker extends StatefulWidget {
  const YoutubeCoverPicker({
    super.key,
    required this.query,
    this.title = '',
    this.artist = '',
    this.duration,
    this.autoSearch = true,
    this.searchFactory,
    this.coverFactory,
  });
  final String query;
  final String title;
  final String artist;
  final double? duration;
  final bool autoSearch;
  final YoutubeCoverSearch Function()? searchFactory;
  final YoutubeCovers Function()? coverFactory;
  @override
  State<YoutubeCoverPicker> createState() => _YoutubeCoverPickerState();
}

class _YoutubeCoverPickerState extends State<YoutubeCoverPicker> {
  late final search = TextEditingController(text: widget.query);
  final link = TextEditingController();
  YoutubeCovers? service;
  YoutubeCover? cover;
  String? error;
  bool loading = false;
  bool searching = false;
  bool searched = false;
  String? searchError;
  int searchEpoch = 0;
  YoutubeCoverSearch? searchService;
  final previewAnchor = GlobalKey();
  List<YoutubeSuggestion> suggestions = [];
  final thumbnails = <String, Future<Uint8List?>>{};
  final thumbnailClients = <YoutubeCovers>{};

  YoutubeCovers newCovers() => widget.coverFactory?.call() ?? YoutubeCovers();

  @override
  void initState() {
    super.initState();
    if (widget.autoSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) findCovers();
      });
    }
  }

  void cancelSearch() {
    searchEpoch++;
    searchService?.close();
    searchService = null;
  }

  void clearThumbnails() {
    for (final client in thumbnailClients) {
      client.close();
    }
    thumbnails.clear();
  }

  void queryChanged(String _) {
    cancelSearch();
    clearThumbnails();
    setState(() {
      searching = false;
      searched = false;
      suggestions = [];
      cover = null;
      error = null;
      searchError = null;
    });
  }

  Future<void> findCovers() async {
    cancelSearch();
    clearThumbnails();
    final epoch = searchEpoch;
    setState(() {
      searching = true;
      searched = true;
      searchError = null;
      cover = null;
      suggestions = [];
      error = null;
    });
    final next = widget.searchFactory?.call() ?? YoutubeCoverSearch();
    searchService = next;
    try {
      final found = await next.search(
        title: widget.title.isEmpty ? search.text : widget.title,
        artist: widget.artist,
        query: search.text,
        duration: widget.duration,
      );
      if (mounted && epoch == searchEpoch) setState(() => suggestions = found);
    } catch (e) {
      if (mounted && epoch == searchEpoch) setState(() => searchError = '$e');
    } finally {
      next.close();
      if (identical(searchService, next)) searchService = null;
      if (mounted && epoch == searchEpoch) setState(() => searching = false);
    }
  }

  Future<Uint8List?> thumbnail(String id) =>
      thumbnails.putIfAbsent(id, () async {
        final next = newCovers();
        thumbnailClients.add(next);
        try {
          return await next.thumbnail(id);
        } catch (_) {
          return null;
        } finally {
          next.close();
          thumbnailClients.remove(next);
        }
      });

  @override
  void dispose() {
    cancelSearch();
    service?.close();
    for (final client in thumbnailClients) {
      client.close();
    }
    search.dispose();
    link.dispose();
    super.dispose();
  }

  Future<void> openSearch() async {
    final uri = youtubeSearchUri(search.text);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Keep a usable fallback if no browser/application can handle the URL.
    }
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (mounted)
      setState(
        () => error =
            'Could not open YouTube. The search link was copied; open it in your browser.',
      );
  }

  Future<void> preview() async {
    cancelSearch();
    setState(() {
      searching = false;
      loading = true;
      error = null;
      cover = null;
    });
    final next = newCovers();
    service = next;
    try {
      final result = await next.load(link.text);
      // Validate the actual image and dimensions before offering Use or Save.
      final buffer = await ui.ImmutableBuffer.fromUint8List(result.bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.width < 1 ||
              descriptor.height < 1 ||
              descriptor.width * descriptor.height > 25000000) {
            throw const FormatException('Thumbnail exceeds 25 megapixels.');
          }
          final codec = await descriptor.instantiateCodec();
          try {
            final frame = await codec.getNextFrame();
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      if (mounted) {
        setState(() => cover = result);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final previewContext = previewAnchor.currentContext;
          if (mounted && previewContext != null) {
            Scrollable.ensureVisible(
              previewContext,
              duration: const Duration(milliseconds: 250),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      next.close();
      if (identical(service, next)) service = null;
      if (mounted) setState(() => loading = false);
    }
  }

  Widget suggestionCard(YoutubeSuggestion suggestion, int index) {
    final video = suggestion.video;
    return Card(
      child: InkWell(
        onTap: loading
            ? null
            : () {
                link.text = video.url.toString();
                preview();
              },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                height: 70,
                child: FutureBuilder<Uint8List?>(
                  future: thumbnail(video.id),
                  builder: (context, snapshot) => snapshot.data == null
                      ? const Icon(Icons.smart_display_outlined)
                      : Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          cacheWidth: 320,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1}. ${video.title}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(video.author, style: const TextStyle(fontSize: 12)),
                    if (video.duration != null &&
                        video.duration!.isFinite &&
                        video.duration! > 0)
                      Text(
                        '${video.duration! ~/ 60}:${(video.duration!.toInt() % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    Text(
                      suggestion.reasons.isEmpty
                          ? 'YouTube result'
                          : suggestion.reasons.join(' · '),
                      style: const TextStyle(fontSize: 11),
                    ),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () {
                              link.text = video.url.toString();
                              preview();
                            },
                      child: const Text('Preview this cover'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('YouTube cover'),
    content: SizedBox(
      width: 560,
      height: math.min(650.0, MediaQuery.sizeOf(context).height * .65),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Suggested thumbnails are ranked by song title, artist, duration and audio/artwork clues. Choose one to preview; nothing is applied automatically.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: search,
              enabled: !loading,
              onChanged: queryChanged,
              onSubmitted: (_) {
                if (!loading) findCovers();
              },
              decoration: const InputDecoration(labelText: 'Song search'),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: loading || searching ? null : findCovers,
                  icon: const Icon(Icons.search),
                  label: const Text('Find covers'),
                ),
                TextButton.icon(
                  onPressed: openSearch,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open YouTube'),
                ),
              ],
            ),
            if (searching) ...[
              const LinearProgressIndicator(),
              const Text('Searching YouTube…'),
            ],
            if (searchError != null) Text(searchError!),
            if (searched &&
                !searching &&
                searchError == null &&
                suggestions.isEmpty)
              const Text(
                'No video suggestions found. Adjust the search or paste a link below.',
              ),
            for (var i = 0; i < suggestions.length; i++)
              suggestionCard(suggestions[i], i),
            const SizedBox(height: 12),
            const Text('Or paste a video link'),
            TextField(
              controller: link,
              enabled: !loading,
              decoration: const InputDecoration(
                labelText: 'YouTube video link',
                hintText: 'https://youtu.be/…',
              ),
              onChanged: (_) => setState(() {
                cover = null;
                error = null;
              }),
              onSubmitted: (_) {
                if (!loading) preview();
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: loading ? null : preview,
              icon: const Icon(Icons.image_search),
              label: const Text('Preview thumbnail'),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (cover != null) ...[
              SizedBox(key: previewAnchor, height: 12),
              Image.memory(
                cover!.bytes,
                height: 180,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 8),
              Text(
                cover!.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text('${cover!.author} · YouTube'),
              SelectableText(
                cover!.videoUrl.toString(),
                style: const TextStyle(fontSize: 11),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Thumbnails may be rectangular, contain text, or differ from album artwork. The full image is kept. Use images you have permission to use.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      OutlinedButton(
        onPressed: cover == null || loading
            ? null
            : () => Navigator.pop(context, (cover: cover!, save: true)),
        child: const Text('Save image'),
      ),
      FilledButton(
        onPressed: cover == null || loading
            ? null
            : () => Navigator.pop(context, (cover: cover!, save: false)),
        child: const Text('Use cover'),
      ),
    ],
  );
}
