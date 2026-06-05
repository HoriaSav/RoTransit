String normalizeSearchText(String input) {
  final collapsed = input.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  if (collapsed.isEmpty) return '';
  return collapsed
      .replaceAll('ă', 'a')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ș', 's')
      .replaceAll('ş', 's')
      .replaceAll('ț', 't')
      .replaceAll('ţ', 't');
}
