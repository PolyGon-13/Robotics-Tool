import 'package:flutter/material.dart';

import '../../services/mesh_parsers.dart';
import 'scene_view.dart';

/// Standalone STL / DAE viewer. Several files are shown together.
class MeshViewerWidget extends StatefulWidget {
  final List<TriMesh> meshes;
  final int fileBytes;

  const MeshViewerWidget({super.key, required this.meshes, required this.fileBytes});

  @override
  State<MeshViewerWidget> createState() => _MeshViewerWidgetState();
}

class _MeshViewerWidgetState extends State<MeshViewerWidget> {
  static const _defaultColor = Color(0xFF90A4AE);
  late SceneGeometry _scene;
  late (double, double, double) _dims;
  final _viewKey = GlobalKey<SceneViewState>();

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(MeshViewerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meshes != widget.meshes) _build();
  }

  void _build() {
    _scene = SceneGeometry.build([
      for (final m in widget.meshes) ScenePart(m.tris, m.color ?? _defaultColor),
    ]);
    double lx = double.infinity, ly = double.infinity, lz = double.infinity;
    double hx = double.negativeInfinity, hy = double.negativeInfinity, hz = double.negativeInfinity;
    final t = _scene.tris;
    for (var i = 0; i + 2 < t.length; i += 3) {
      if (t[i] < lx) lx = t[i];
      if (t[i] > hx) hx = t[i];
      if (t[i + 1] < ly) ly = t[i + 1];
      if (t[i + 1] > hy) hy = t[i + 1];
      if (t[i + 2] < lz) lz = t[i + 2];
      if (t[i + 2] > hz) hz = t[i + 2];
    }
    _dims = lx.isFinite ? (hx - lx, hy - ly, hz - lz) : (0, 0, 0);
  }

  static String _f(double v) => v >= 100 ? v.toStringAsFixed(0) : v >= 1 ? v.toStringAsFixed(2) : v.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (dx, dy, dz) = _dims;
    // STL has no units; CAD exports are often millimeters
    final probablyMm = [dx, dy, dz].any((d) => d > 20);
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: SceneView(key: _viewKey, geometry: _scene, fitKey: widget.meshes),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Material(
                  color: cs.surface.withValues(alpha: 0.85),
                  shape: const CircleBorder(),
                  elevation: 1,
                  child: IconButton(
                    icon: const Icon(Icons.center_focus_strong),
                    tooltip: 'Reset view',
                    onPressed: () => _viewKey.currentState?.resetView(),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          color: cs.surfaceContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Size ${_f(dx)} × ${_f(dy)} × ${_f(dz)}${probablyMm ? ' (likely mm)' : ' m'}',
                  style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              Text(
                '${_scene.triangleCount} triangles · ${(widget.fileBytes / 1024).toStringAsFixed(0)} KB',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
