import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stop board sheet has no per-departure line-favorite heart', () {
    final src = File(
      'lib/src/features/map/presentation/stop_board_sheet.dart',
    ).readAsStringSync();
    expect(src.contains('_toggleLineFavorite'), isFalse);
    expect(src.contains('Favorite line'), isFalse);
    expect(src.contains('Icons.favorite_border'), isFalse);
    // Stop favorite (star) remains.
    expect(src.contains('l10n.favoriteStopAdd'), isTrue);
    expect(src.contains('_toggleFavorite'), isTrue);
  });

  test('favorites empty copy points at Timetable, not stop board', () {
    final arb = File('lib/l10n/app_en.arb').readAsStringSync();
    expect(
      arb.contains(
        '"favoritesLinesEmpty": "No favorite lines yet. In Timetable,',
      ),
      isTrue,
    );
    // Saved journeys are gone; no copy may invite users to save one.
    expect(arb.contains('favoritesEmpty'), isFalse);
  });

  test('map gesture thresholds are mid-race (snappy zoom, intentional rotate)',
      () {
    final src = File(
      'lib/src/features/map/presentation/map_tab.dart',
    ).readAsStringSync();
    expect(src.contains('pinchZoomThreshold: 0.65'), isTrue);
    expect(src.contains('rotationThreshold: 18'), isTrue);
  });
}
