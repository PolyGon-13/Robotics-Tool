import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/services/primitive_meshes.dart';
import 'package:robotics_tool/widgets/model_viewer/scene_view.dart';

void main() {
  testWidgets('SceneView paints from many angles without errors', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final geometry = SceneGeometry.build([
      ScenePart(boxMesh(0.2, 0.2, 0.1), const Color(0xFF90A4AE)),
      ScenePart(cylinderMesh(0.015, 0.3), const Color(0xFF222222),
          const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0.25, 0, 0, 0, 1]),
      ScenePart(sphereMesh(0.05), const Color(0xFFD32F2F),
          const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0.4, 0, 0, 0, 1]),
      // Degenerate triangle and a flat open quad
      ScenePart(Float32List.fromList([0, 0, 0, 0, 0, 0, 0, 0, 0]), Colors.black),
      ScenePart(Float32List.fromList([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0]), Colors.green),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SceneView(geometry: geometry, fitKey: 1)),
    ));
    final center = tester.getCenter(find.byType(SceneView));
    for (var i = 0; i < 24; i++) {
      await tester.dragFrom(center, Offset(37.0 * (i % 5 - 2), 23.0 * (i % 3 - 1)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'drag $i');
    }
    // Empty scene
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SceneView(geometry: SceneGeometry.build(const []), fitKey: 2)),
    ));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1)); // let the double-tap timer expire
  });

  test('depthBucket stays in range for float32-rounded depths', () {
    const dMax = 0.30000000000000004;
    final rounded = Float32List.fromList([dMax])[0]; // rounds up past dMax
    expect(rounded, greaterThan(dMax));
    expect(depthBucket(rounded, dMax, 1.0, 4096), 0);
    expect(depthBucket(-10, dMax, 1.0, 4096), 4095);
    expect(depthBucket(0.1, dMax, 0, 4096), 0);
  });
}
