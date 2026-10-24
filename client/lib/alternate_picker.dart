import 'dart:math' as math;
import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> pickAlternateSource(
  BuildContext context, {
  required String kind,
  required Map<String, dynamic> candidate,
  required List<Map<String, dynamic>> options,
  required List<String> warnings,
}) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(kind == 'cover' ? 'Other covers' : 'Other lyrics'),
    content: SizedBox(
      width: 600,
      height: math.min(620.0, MediaQuery.sizeOf(context).height * .65),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${candidate['title']} · ${candidate['artist']}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Review the album/version before using a result. Save downloads a separate file; Use updates only this content in the editor.',
            style: TextStyle(fontSize: 12),
          ),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(warning, style: const TextStyle(fontSize: 11)),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: options.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final option = options[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (kind == 'cover') ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  option['preview_url'] as String,
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const SizedBox(
                                    width: 72,
                                    height: 72,
                                    child: Icon(Icons.album_outlined),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${option['title']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${option['artist']}\n${option['album']}\n${option['source']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (kind == 'lyrics') ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 150,
                            child: SingleChildScrollView(
                              child: SelectableText(
                                (option['lyrics'] as String).isNotEmpty
                                    ? option['lyrics'] as String
                                    : option['synced_lyrics'] as String,
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: () => Navigator.pop(dialogContext, {
                                ...option,
                                'action': 'use',
                              }),
                              child: Text(
                                kind == 'cover' ? 'Use cover' : 'Use lyrics',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.pop(dialogContext, {
                                ...option,
                                'action': 'save',
                              }),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 16,
                              ),
                              label: Text(
                                kind == 'cover' ? 'Save image' : 'Save lyrics',
                              ),
                            ),
                          ],
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
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Close'),
      ),
    ],
  ),
);
