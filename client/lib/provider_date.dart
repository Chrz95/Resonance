/// AcoustID release dates are objects; MusicBrainz dates are ISO/partial text.
String normalizeProviderDate(Object? value) {
  if (value is String) return value;
  if (value is! Map) return '';
  int part(String key) {
    final item = value[key];
    if (item is int) return item;
    if (item is String && RegExp(r'^[0-9]+$').hasMatch(item)) {
      return int.tryParse(item) ?? 0;
    }
    return 0;
  }

  final year = part('year'), month = part('month'), day = part('day');
  if (year < 1 || year > 9999) return '';
  var result = year.toString().padLeft(4, '0');
  if (month < 1 || month > 12) return result;
  result += '-${month.toString().padLeft(2, '0')}';
  if (day < 1 || day > 31) return result;
  final date = DateTime.utc(year, month, day);
  // DateTime normalizes impossible days into the next month; do not accept them.
  if (date.year != year || date.month != month || date.day != day)
    return result;
  return '$result-${day.toString().padLeft(2, '0')}';
}
