import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit_frontend/src/features/search/presentation/search_tab.dart';

void main() {
  testWidgets('search tab renders required fields', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SearchTab(bootstrapFromBackend: false)),
      ),
    );

    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Select date'), findsOneWidget);
    expect(find.text('Select time'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
  });
}
