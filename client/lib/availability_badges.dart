import 'package:flutter/material.dart';

class AvailabilityBadges extends StatelessWidget {
  const AvailabilityBadges({super.key, required this.candidate});
  final Map<String, dynamic> candidate;

  Widget badge(
    String name,
    IconData icon,
    Object? available, {
    bool instrumental = false,
  }) {
    final loading =
        candidate['availability_loading'] == true && available != true;
    final label = loading
        ? '$name …'
        : available == true
        ? '$name ✓'
        : available == false
        ? 'No ${name.toLowerCase()}'
        : '$name ?';
    final color = loading || available == null
        ? const Color(0xFF9B9CAB)
        : available == true
        ? const Color(0xFF97E2C6)
        : const Color(0xFF9B9CAB);
    final detail = loading
        ? 'Checking availability…'
        : instrumental
        ? 'LRCLIB marks this track as instrumental.'
        : available == true
        ? (name == 'Lyrics'
              ? 'Lyrics found via ${candidate['alternate_lyrics_source'] ?? 'LRCLIB'} for this candidate.'
              : candidate['alternate_cover_source'] != null
              ? 'Cover found via ${candidate['alternate_cover_source']} for this candidate.'
              : 'Front cover found for this specific release.')
        : available == false
        ? (name == 'Lyrics'
              ? 'No lyrics found for this candidate.'
              : 'No front cover found for this release, or no release selected.')
        : 'Availability could not be confirmed. You can still select this match.';
    return Tooltip(
      message: detail,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      badge(
        'Lyrics',
        Icons.lyrics_outlined,
        candidate['alternate_has_lyrics'] == true
            ? true
            : candidate['has_lyrics'],
        instrumental:
            candidate['instrumental'] == true &&
            candidate['alternate_has_lyrics'] != true,
      ),
      badge(
        'Cover',
        Icons.image_outlined,
        candidate['alternate_has_cover'] == true
            ? true
            : candidate['has_cover'],
      ),
    ],
  );
}
