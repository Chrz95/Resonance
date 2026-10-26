import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'youtube_cover.dart';

typedef YoutubeCoverChoice = ({YoutubeCover cover, bool save});

Future<YoutubeCoverChoice?> pickYoutubeCover(
  BuildContext context, {
  required String title,
  required String artist,
}) => showDialog<YoutubeCoverChoice>(
  context: context,
  builder: (_) => YoutubeCoverPicker(query: '$artist $title'.trim()),
);

class YoutubeCoverPicker extends StatefulWidget {
  const YoutubeCoverPicker({super.key, required this.query});
  final String query;
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

  @override
  void dispose() {
    service?.close();
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
    setState(() {
      loading = true;
      error = null;
      cover = null;
    });
    final next = YoutubeCovers();
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
      if (mounted) setState(() => cover = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      next.close();
      if (identical(service, next)) service = null;
      if (mounted) setState(() => loading = false);
    }
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
              'Search YouTube, copy a video link, then return here to preview its thumbnail. No API key is needed.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: search,
              decoration: const InputDecoration(labelText: 'Song search'),
            ),
            TextButton.icon(
              onPressed: openSearch,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Search on YouTube'),
            ),
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
              const SizedBox(height: 12),
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
