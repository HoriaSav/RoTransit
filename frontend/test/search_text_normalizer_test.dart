import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/core/format/search_text_normalizer.dart';

void main() {
  test('normalizes Romanian diacritics to base letters', () {
    expect(
      normalizeSearchText('Făget Științei'),
      'faget stiintei',
    );
  });

  test('collapses whitespace and lowercases text', () {
    expect(
      normalizeSearchText('  GARA   Brașov  '),
      'gara brasov',
    );
  });
}
