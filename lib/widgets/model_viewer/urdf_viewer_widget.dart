import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/urdf_parser_service.dart';

// ─── 3D 수학 ───────────────────────────────────────────────────────────────

class _V3 {
  final double x, y, z;
  const _V3(this.x, this.y, this.z);
  _V3 operator +(_V3 v) => _V3(x + v.x, y + v.y, z + v.z);
  _V3 operator -(_V3 v) => _V3(x - v.x, y - v.y, z - v.z);
  _V3 operator *(double s) => _V3(x * s, y * s, z * s);
  double dot(_V3 v) => x * v.x + y * v.y + z * v.z;
  double get len => math.sqrt(x * x + y * y + z * z);
  _V3 get norm { final l = len; return l > 0 ? _V3(x/l, y/l, z/l) : this; }
}

/// 4×4 행렬 (row-major)
class _M4 {
  final List<double> m;

  _M4._(this.m);

  factory _M4.identity() => _M4._([1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]);

  factory _M4.translation(double x, double y, double z) =>
      _M4._([1,0,0,x, 0,1,0,y, 0,0,1,z, 0,0,0,1]);

  factory _M4.rotX(double a) {
    final c = math.cos(a), s = math.sin(a);
    return _M4._([1,0,0,0, 0,c,-s,0, 0,s,c,0, 0,0,0,1]);
  }
  factory _M4.rotY(double a) {
    final c = math.cos(a), s = math.sin(a);
    return _M4._([c,0,s,0, 0,1,0,0, -s,0,c,0, 0,0,0,1]);
  }
  factory _M4.rotZ(double a) {
    final c = math.cos(a), s = math.sin(a);
    return _M4._([c,-s,0,0, s,c,0,0, 0,0,1,0, 0,0,0,1]);
  }

  /// ROS URDF RPY: Rz * Ry * Rx
  factory _M4.rpy(double roll, double pitch, double yaw) =>
      _M4.rotZ(yaw) * _M4.rotY(pitch) * _M4.rotX(roll);

  factory _M4.fromOrigin(UrdfOrigin o) =>
      _M4.translation(o.x, o.y, o.z) * _M4.rpy(o.roll, o.pitch, o.yaw);

  _M4 operator *(_M4 o) {
    final r = List<double>.filled(16, 0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        for (int k = 0; k < 4; k++) {
          r[i*4+j] += m[i*4+k] * o.m[k*4+j];
        }
      }
    }
    return _M4._(r);
  }

  _V3 transform(_V3 v) => _V3(
    m[0]*v.x + m[1]*v.y + m[2]*v.z + m[3],
    m[4]*v.x + m[5]*v.y + m[6]*v.z + m[7],
    m[8]*v.x + m[9]*v.y + m[10]*v.z + m[11],
  );

  _V3 transformNormal(_V3 v) => _V3(
    m[0]*v.x + m[1]*v.y + m[2]*v.z,
    m[4]*v.x + m[5]*v.y + m[6]*v.z,
    m[8]*v.x + m[9]*v.y + m[10]*v.z,
  ).norm;
}

// ─── 렌더링용 삼각형 ───────────────────────────────────────────────────────

class _Face {
  final _V3 v0, v1, v2, normal;
  final Color color;
  const _Face(this.v0, this.v1, this.v2, this.normal, this.color);
}

// ─── 지오메트리 생성 함수 ──────────────────────────────────────────────────

List<_Face> _makeBox(double sx, double sy, double sz, Color color) {
  final hx = sx/2, hy = sy/2, hz = sz/2;
  final faces = <_Face>[];
  void quad(_V3 a, _V3 b, _V3 c, _V3 d, _V3 n) {
    faces
      ..add(_Face(a, b, c, n, color))
      ..add(_Face(a, c, d, n, color));
  }
  quad(_V3(-hx,-hy, hz), _V3( hx,-hy, hz), _V3( hx, hy, hz), _V3(-hx, hy, hz), const _V3(0,0, 1));
  quad(_V3( hx,-hy,-hz), _V3(-hx,-hy,-hz), _V3(-hx, hy,-hz), _V3( hx, hy,-hz), const _V3(0,0,-1));
  quad(_V3(-hx,-hy,-hz), _V3(-hx,-hy, hz), _V3(-hx, hy, hz), _V3(-hx, hy,-hz), const _V3(-1,0,0));
  quad(_V3( hx,-hy, hz), _V3( hx,-hy,-hz), _V3( hx, hy,-hz), _V3( hx, hy, hz), const _V3(1,0,0));
  quad(_V3(-hx,-hy,-hz), _V3( hx,-hy,-hz), _V3( hx,-hy, hz), _V3(-hx,-hy, hz), const _V3(0,-1,0));
  quad(_V3(-hx, hy, hz), _V3( hx, hy, hz), _V3( hx, hy,-hz), _V3(-hx, hy,-hz), const _V3(0, 1,0));
  return faces;
}

List<_Face> _makeCylinder(double radius, double length, Color color, {int seg = 18}) {
  final half = length / 2;
  final faces = <_Face>[];
  for (int i = 0; i < seg; i++) {
    final a0 = 2 * math.pi * i / seg;
    final a1 = 2 * math.pi * (i + 1) / seg;
    final x0 = radius * math.cos(a0), y0 = radius * math.sin(a0);
    final x1 = radius * math.cos(a1), y1 = radius * math.sin(a1);
    final n = _V3(math.cos((a0+a1)/2), math.sin((a0+a1)/2), 0).norm;
    faces
      ..add(_Face(_V3(x0,y0,-half), _V3(x1,y1,-half), _V3(x1,y1, half), n, color))
      ..add(_Face(_V3(x0,y0,-half), _V3(x1,y1, half), _V3(x0,y0, half), n, color))
      ..add(_Face(const _V3(0,0, 1)*half, _V3(x0,y0, half), _V3(x1,y1, half), const _V3(0,0, 1), color))
      ..add(_Face(const _V3(0,0,-1)*half, _V3(x1,y1,-half), _V3(x0,y0,-half), const _V3(0,0,-1), color));
  }
  return faces;
}

List<_Face> _makeSphere(double radius, Color color, {int lat = 10, int lon = 16}) {
  final faces = <_Face>[];
  _V3 sv(double th, double ph) => _V3(
    radius * math.sin(th) * math.cos(ph),
    radius * math.sin(th) * math.sin(ph),
    radius * math.cos(th),
  );
  for (int i = 0; i < lat; i++) {
    final t0 = math.pi * i / lat;
    final t1 = math.pi * (i+1) / lat;
    for (int j = 0; j < lon; j++) {
      final p0 = 2*math.pi* j    /lon;
      final p1 = 2*math.pi*(j+1)/lon;
      final a=sv(t0,p0), b=sv(t0,p1), c=sv(t1,p0), d=sv(t1,p1);
      if (i > 0)     faces.add(_Face(a, b, d, (a.norm+b.norm+d.norm).norm, color));
      if (i < lat-1) faces.add(_Face(a, d, c, (a.norm+d.norm+c.norm).norm, color));
    }
  }
  return faces;
}

// ─── URDF 뷰어 위젯 ────────────────────────────────────────────────────────

class UrdfViewerWidget extends StatefulWidget {
  final UrdfRobot robot;

  const UrdfViewerWidget({super.key, required this.robot});

  @override
  State<UrdfViewerWidget> createState() => _UrdfViewerWidgetState();
}

class _UrdfViewerWidgetState extends State<UrdfViewerWidget> {
  // 카메라
  double _rotX = 0.3;
  double _rotY = 0.5;
  double _scale = 1.0;
  Offset _pan = Offset.zero;

  // 제스처
  Offset? _lastPanPos;
  double? _lastScale;
  Offset? _lastTwoFinger;

  // 조인트 값 (이름 → 라디안/미터)
  late Map<String, double> _jointValues;

  // 하이라이트된 링크
  String? _highlighted;

  // 사이드패널 열림 여부
  bool _showPanel = true;

  // 링크 색상 팔레트 (Material 계열)
  static const _palette = [
    Color(0xFF4FC3F7), Color(0xFF81C784), Color(0xFFFFB74D),
    Color(0xFFE57373), Color(0xFFBA68C8), Color(0xFF4DD0E1),
    Color(0xFFA5D6A7), Color(0xFFFFCC02),
  ];

  @override
  void initState() {
    super.initState();
    _jointValues = {
      for (final j in widget.robot.joints)
        if (j.type == 'revolute' || j.type == 'prismatic' || j.type == 'continuous')
          j.name: 0.0,
    };
  }

  Color _linkColor(int index) => _palette[index % _palette.length];

  // ─── 씬 구성 ─────────────────────────────────────────────────────────

  List<_Face> _buildScene() {
    final allFaces = <_Face>[];
    final linkIndex = <String, int>{};
    for (int i = 0; i < widget.robot.links.length; i++) {
      linkIndex[widget.robot.links[i].name] = i;
    }

    // 루트 링크 찾기 (parent가 아닌 링크)
    final childLinks = widget.robot.joints.map((j) => j.child).toSet();
    final rootLinks = widget.robot.links
        .where((l) => !childLinks.contains(l.name))
        .map((l) => l.name)
        .toList();

    // DFS 순회 with 누적 변환 행렬
    void traverse(String linkName, _M4 world) {
      final link = widget.robot.links.firstWhere(
        (l) => l.name == linkName,
        orElse: () => const UrdfLink(name: '', visuals: []),
      );

      final idx = linkIndex[linkName] ?? 0;
      final isHighlighted = _highlighted == linkName;
      final base = isHighlighted ? Colors.yellow : _linkColor(idx);

      for (final vis in link.visuals) {
        final localT = _M4.fromOrigin(vis.origin);
        final combined = world * localT;
        final faces = _geomToFaces(vis.geometry, base);
        for (final f in faces) {
          allFaces.add(_Face(
            combined.transform(f.v0),
            combined.transform(f.v1),
            combined.transform(f.v2),
            combined.transformNormal(f.normal),
            f.color,
          ));
        }
      }

      // 자식 조인트 찾기
      for (final joint in widget.robot.joints) {
        if (joint.parent != linkName) continue;
        final jointT = _M4.fromOrigin(joint.origin);

        // 조인트 각도 적용
        final val = _jointValues[joint.name] ?? 0.0;
        _M4 jointRot = _M4.identity();
        if ((joint.type == 'revolute' || joint.type == 'continuous') && val != 0) {
          final axis = _V3(joint.axisX, joint.axisY, joint.axisZ).norm;
          jointRot = _axisAngle(axis, val);
        } else if (joint.type == 'prismatic' && val != 0) {
          final axis = _V3(joint.axisX, joint.axisY, joint.axisZ).norm;
          jointRot = _M4.translation(axis.x * val, axis.y * val, axis.z * val);
        }

        traverse(joint.child, world * jointT * jointRot);
      }
    }

    for (final root in rootLinks) {
      traverse(root, _M4.identity());
    }
    return allFaces;
  }

  List<_Face> _geomToFaces(UrdfGeometry g, Color color) {
    switch (g.type) {
      case 'box':
        return _makeBox(
          g.sx > 0 ? g.sx : 0.1,
          g.sy > 0 ? g.sy : 0.1,
          g.sz > 0 ? g.sz : 0.1,
          color,
        );
      case 'cylinder':
        return _makeCylinder(
          g.radius > 0 ? g.radius : 0.05,
          g.length > 0 ? g.length : 0.1,
          color,
        );
      case 'sphere':
        return _makeSphere(g.radius > 0 ? g.radius : 0.05, color);
      case 'mesh':
        // 메시 파일 없음 → fallback 박스
        return _makeBox(0.1, 0.1, 0.1, color.withValues(alpha: 0.6));
      default:
        return _makeBox(0.1, 0.1, 0.1, color);
    }
  }

  /// 축-각도 회전 행렬 (Rodrigues)
  _M4 _axisAngle(_V3 axis, double angle) {
    final c = math.cos(angle), s = math.sin(angle), t = 1 - c;
    final x = axis.x, y = axis.y, z = axis.z;
    return _M4._([
      t*x*x+c,   t*x*y-s*z, t*x*z+s*y, 0,
      t*x*y+s*z, t*y*y+c,   t*y*z-s*x, 0,
      t*x*z-s*y, t*y*z+s*x, t*z*z+c,   0,
      0,         0,         0,         1,
    ]);
  }

  // ─── 제스처 ─────────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _lastPanPos = d.focalPoint;
    _lastScale = _scale;
    _lastTwoFinger = d.pointerCount >= 2 ? d.focalPoint : null;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      if (d.pointerCount >= 2) {
        _scale = (_lastScale! * d.scale).clamp(0.05, 20.0);
        if (_lastTwoFinger != null) {
          _pan += d.focalPoint - _lastTwoFinger!;
          _lastTwoFinger = d.focalPoint;
        }
      } else if (_lastPanPos != null) {
        final delta = d.focalPoint - _lastPanPos!;
        _rotY += delta.dx * 0.007;
        _rotX += delta.dy * 0.007;
        _lastPanPos = d.focalPoint;
      }
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final movableJoints = widget.robot.joints
        .where((j) =>
            j.type == 'revolute' ||
            j.type == 'prismatic' ||
            j.type == 'continuous')
        .toList();

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              // 사이드 패널: 링크 트리
              if (_showPanel)
                SizedBox(
                  width: 180,
                  child: Column(
                    children: [
                      Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.account_tree, size: 14),
                            const SizedBox(width: 4),
                            const Expanded(child: Text('Links', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            InkWell(
                              onTap: () => setState(() => _showPanel = false),
                              child: const Icon(Icons.close, size: 14),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            for (int i = 0; i < widget.robot.links.length; i++)
                              ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 6,
                                  backgroundColor: _linkColor(i),
                                ),
                                title: Text(
                                  widget.robot.links[i].name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _highlighted == widget.robot.links[i].name
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                selected: _highlighted == widget.robot.links[i].name,
                                onTap: () => setState(() {
                                  _highlighted = _highlighted == widget.robot.links[i].name
                                      ? null
                                      : widget.robot.links[i].name;
                                }),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // 3D 뷰
              Expanded(
                child: GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: Stack(
                    children: [
                      Container(
                        color: const Color(0xFF1E1E1E),
                        child: CustomPaint(
                          painter: _UrdfPainter(
                            faces: _buildScene(),
                            rotX: _rotX, rotY: _rotY,
                            scale: _scale, pan: _pan,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      if (!_showPanel)
                        Positioned(
                          top: 8, left: 8,
                          child: IconButton(
                            icon: const Icon(Icons.account_tree, color: Colors.white70),
                            onPressed: () => setState(() => _showPanel = true),
                            tooltip: 'Show links',
                          ),
                        ),
                      Positioned(
                        top: 8, right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.center_focus_strong, color: Colors.white70),
                          onPressed: () => setState(() {
                            _rotX = 0.3; _rotY = 0.5;
                            _scale = 1.0; _pan = Offset.zero;
                          }),
                          tooltip: 'Reset view',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 조인트 슬라이더 패널
        if (movableJoints.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text('Joint Control',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final j in movableJoints)
                        Row(
                          children: [
                            SizedBox(
                              width: 100,
                              child: Text(
                                j.name,
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                value: (_jointValues[j.name] ?? 0)
                                    .clamp(j.limitLower, j.limitUpper),
                                min: j.limitLower,
                                max: j.limitUpper,
                                onChanged: (v) =>
                                    setState(() => _jointValues[j.name] = v),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                (_jointValues[j.name] ?? 0).toStringAsFixed(2),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── URDF CustomPainter ───────────────────────────────────────────────────

class _UrdfPainter extends CustomPainter {
  final List<_Face> faces;
  final double rotX, rotY, scale;
  final Offset pan;

  static const _lightDir = _V3(0.4, 0.7, 0.6);
  static const _fov = 600.0;
  static const _camZ = 5.0;

  const _UrdfPainter({
    required this.faces,
    required this.rotX, required this.rotY,
    required this.scale, required this.pan,
  });

  _V3 _rotate(_V3 v) {
    final cy = math.cos(rotY), sy = math.sin(rotY);
    final x1 = v.x * cy + v.z * sy;
    final z1 = -v.x * sy + v.z * cy;
    final cx = math.cos(rotX), sx = math.sin(rotX);
    return _V3(x1, v.y * cx - z1 * sx, v.y * sx + z1 * cx);
  }

  Offset _project(_V3 v, Size size) {
    final dz = v.z + _camZ;
    if (dz <= 0.01) return Offset(size.width / 2, size.height / 2);
    final s = _fov / dz;
    return Offset(
      size.width  / 2 + v.x * s * scale + pan.dx,
      size.height / 2 - v.y * s * scale + pan.dy,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'No visual geometry in URDF',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(
        (size.width - tp.width) / 2,
        (size.height - tp.height) / 2,
      ));
      return;
    }

    // 변환 + 정렬
    final items = <({_V3 v0, _V3 v1, _V3 v2, _V3 n, double z, Color c})>[];
    for (final f in faces) {
      final r0 = _rotate(f.v0);
      final r1 = _rotate(f.v1);
      final r2 = _rotate(f.v2);
      final rn = _rotate(f.normal).norm;
      if (rn.z > 0.1) continue; // 뒷면 컬링
      items.add((
        v0: r0, v1: r1, v2: r2, n: rn,
        z: (r0.z + r1.z + r2.z) / 3,
        c: f.color,
      ));
    }
    items.sort((a, b) => a.z.compareTo(b.z));

    final paint = Paint()..style = PaintingStyle.fill;
    for (final t in items) {
      final p0 = _project(t.v0, size);
      final p1 = _project(t.v1, size);
      final p2 = _project(t.v2, size);
      final intensity = (-t.n.dot(_lightDir)).clamp(0.0, 1.0);
      final b = 0.25 + 0.75 * intensity;
      final c = t.c;
      paint.color = Color.fromARGB(
        (c.a * 255.0).round().clamp(0, 255),
        (c.r * 255.0 * b).round().clamp(0, 255),
        (c.g * 255.0 * b).round().clamp(0, 255),
        (c.b * 255.0 * b).round().clamp(0, 255),
      );
      canvas.drawPath(
        Path()
          ..moveTo(p0.dx, p0.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_UrdfPainter old) =>
      rotX != old.rotX || rotY != old.rotY ||
      scale != old.scale || pan != old.pan ||
      faces != old.faces;
}
