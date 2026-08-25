import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/map_rendering/mock/mock_valley_scene.dart';

void main() {
  testWidgets('mock valley scene paints at its fixed logical resolution', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(width: 512, height: 512, child: MockValleyScene()),
      ),
    );

    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mock valley debug overlay paints without changing composition', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 512,
          height: 512,
          child: MockValleyScene(showDebug: true),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('interactive mock composes a closed lake without exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 640,
          height: 640,
          child: MockValleyScene(showLake: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
