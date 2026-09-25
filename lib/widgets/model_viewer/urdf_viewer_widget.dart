import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/mesh_parsers.dart';
import '../../services/primitive_meshes.dart';
import '../../services/urdf_kinematics.dart';
import '../../services/urdf_parser_service.dart';
import 'scene_view.dart';

/// Geometry of one `<visual>`, prepared once: meshes in the link frame.
class _VisualGeom {
  final String link;
  final Mat4 origin; // visual origin (and mesh scale) in the link frame
  final List<(Float32List, Color?)> meshes;
  final Color? color;
  final bool missing; // mesh file not loaded: placeholder
  const _VisualGeom(this.link, this.origin, this.meshes, this.color, this.missing);
}

/// URDF robot with joint sliders. Mesh visuals use [meshes] (file name →
/// parsed mesh); meshes that were not provided show as small gray boxes.
class UrdfViewerWidget extends StatefulWidget {
  final UrdfRobot robot;
  final Map<String, List<TriMesh>> meshes;
  final VoidCallback? onAddMeshes;

  const UrdfViewerWidget({
    super.key,
    required this.robot,
    this.meshes = const {},
    this.onAddMeshes,
  });

  @override
  State<UrdfViewerWidget> createState() => _UrdfViewerWidgetState();
}

class _UrdfViewerWidgetState extends State<UrdfViewerWidget> {
  static const _palette = [
    Color(0xFF90A4AE), Color(0xFF4FC3F7), Color(0xFF81C784), Color(0xFFFFB74D),
    Color(0xFFE57373), Color(0xFFBA68C8), Color(0xFF4DD0E1), Color(0xFFFFD54F),
  ];
  static const _highlightColor = Color(0xFFFFEB3B);

  final Map<String, double> _joints = {};
  late List<_VisualGeom> _visuals;
  late SceneGeometry _scene;
  String? _highlighted;
  final _viewKey = GlobalKey<SceneViewState>();

  @override
  void initState() {
    super.initState();
    for (final j in widget.robot.joints) {
      if (j.isMovable) _joints[j.name] = 0;
    }
    _prepare();
  }

  @override
  void didUpdateWidget(UrdfViewerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meshes != widget.meshes || oldWidget.robot != widget.robot) _prepare();
  }

  Set<String> get _missingFiles => {
        for (final l in widget.robot.links)
          for (final v in l.visuals)
            if (v.geometry.type == 'mesh' && !widget.meshes.containsKey(v.geometry.meshKey))
              v.geometry.meshKey,
      };

  void _prepare() {
    final out = <_VisualGeom>[];
    for (final link in widget.robot.links) {
      for (final v in link.visuals) {
        final g = v.geometry;
        var origin = originMat4(v.origin);
        List<(Float32List, Color?)> meshes;
        var missing = false;
        switch (g.type) {
          case 'box':
            meshes = [(boxMesh(g.sx, g.sy, g.sz), null)];
          case 'cylinder':
            meshes = [(cylinderMesh(g.radius, g.length), null)];
          case 'sphere':
            meshes = [(sphereMesh(g.radius), null)];
          default:
            final loaded = widget.meshes[g.meshKey];
            if (loaded != null) {
              meshes = [for (final m in loaded) (m.tris, m.color)];
              origin = mat4Mul(origin, scaleMat4(g.meshScale[0], g.meshScale[1], g.meshScale[2]));
            } else {
              meshes = [(boxMesh(0.04, 0.04, 0.04), null)];
              missing = true;
            }
        }
        out.add(_VisualGeom(link.name, origin, meshes, v.color, missing));
      }
    }
    _visuals = out;
    _rebuildScene();
  }

  void _rebuildScene() {
    final world = linkTransforms(widget.robot, _joints);
    final linkIndex = {
      for (var i = 0; i < widget.robot.links.length; i++) widget.robot.links[i].name: i,
    };
    final parts = <ScenePart>[];
    for (final v in _visuals) {
      final t = mat4Mul(world[v.link] ?? identityMat4, v.origin);
      for (final (tris, meshColor) in v.meshes) {
        final Color color;
        if (v.link == _highlighted) {
          color = _highlightColor;
        } else if (v.missing) {
          color = const Color(0xFF757575);
        } else {
          color = v.color ?? meshColor ?? _palette[(linkIndex[v.link] ?? 0) % _palette.length];
        }
        parts.add(ScenePart(tris, color, t));
      }
    }
    _scene = SceneGeometry.build(parts);
  }

  void _setJoint(String name, double v) {
    setState(() {
      _joints[name] = v;
      _rebuildScene();
    });
  }

  void _showLinks() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Links (${widget.robot.links.length}): tap to highlight',
                    style: Theme.of(ctx).textTheme.titleSmall),
              ),
              for (final l in widget.robot.links)
                ListTile(
                  dense: true,
                  leading: Icon(
                    l.name == _highlighted ? Icons.highlight : Icons.view_in_ar_outlined,
                    color: l.name == _highlighted ? Colors.amber.shade700 : null,
                  ),
                  title: Text(l.name),
                  subtitle: Text(l.visuals.isEmpty
                      ? 'no visual'
                      : l.visuals
                          .map((v) => v.geometry.type == 'mesh' ? v.geometry.meshKey : v.geometry.type)
                          .join(', ')),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _highlighted = _highlighted == l.name ? null : l.name;
                      _rebuildScene();
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final movable = widget.robot.joints.where((j) => j.isMovable).toList();
    final missing = _missingFiles;

    return Column(
      children: [
        if (widget.robot.looksLikeXacro)
          _Banner(
            icon: Icons.warning_amber_rounded,
            color: Colors.orange.shade800,
            text: 'This file contains xacro expressions (\${…}, \$(…)) that are not '
                'evaluated. Convert it first:\nros2 run xacro xacro robot.urdf.xacro > robot.urdf',
          ),
        if (missing.isNotEmpty)
          _Banner(
            icon: Icons.extension_off_outlined,
            color: cs.primary,
            text: '${missing.length} mesh file${missing.length == 1 ? '' : 's'} not loaded '
                '(${missing.take(3).join(', ')}${missing.length > 3 ? ', …' : ''}), '
                'shown as gray boxes.',
            action: widget.onAddMeshes == null
                ? null
                : TextButton(onPressed: widget.onAddMeshes, child: const Text('Add meshes')),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: SceneView(
                  key: _viewKey,
                  geometry: _scene,
                  fitKey: Object.hash(widget.robot, widget.meshes.length),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: _RoundButton(
                    icon: Icons.account_tree_outlined, tooltip: 'Links', onPressed: _showLinks),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: _RoundButton(
                  icon: Icons.center_focus_strong,
                  tooltip: 'Reset view',
                  onPressed: () => _viewKey.currentState?.resetView(),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 10,
                child: Text(
                  '${widget.robot.links.length} links · ${_scene.triangleCount} triangles',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        if (movable.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            color: cs.surfaceContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                  child: Row(
                    children: [
                      Text('Joints (${movable.length})',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          _joints.updateAll((_, _) => 0);
                          _rebuildScene();
                        }),
                        child: const Text('Zero all'),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    children: [for (final j in movable) _jointRow(j, cs)],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _jointRow(UrdfJoint j, ColorScheme cs) {
    final v = _joints[j.name] ?? 0;
    final prismatic = j.type == 'prismatic';
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(j.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: Slider(
            value: v.clamp(j.limitLower, j.limitUpper),
            min: j.limitLower,
            max: j.limitUpper,
            inactiveColor: cs.outlineVariant,
            onChanged: (x) => _setJoint(j.name, x),
          ),
        ),
        SizedBox(
          width: 58,
          child: Text(
            prismatic ? '${v.toStringAsFixed(3)} m' : '${(v * 180 / math.pi).toStringAsFixed(0)}°',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  const _Banner({required this.icon, required this.color, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: color.withValues(alpha: 0.12),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
            ?action,
          ],
        ),
      );
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _RoundButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        shape: const CircleBorder(),
        elevation: 1,
        child: IconButton(icon: Icon(icon), tooltip: tooltip, onPressed: onPressed),
      );
}
