import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/stl_parser_service.dart';

// ─── 3D 수학 유틸리티 ──────────────────────────────────────────────────────

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

// ─── STL 뷰어 위젯 ────────────────────────────────────────────────────────

class StlViewerWidget extends StatefulWidget {
  final Uint8List fileBytes;
  final int fileSize;

  const StlViewerWidget({
    super.key,
    required this.fileBytes,
    required this.fileSize,
  });

  @override
  State<StlViewerWidget> createState() => _StlViewerWidgetState();
}

class _StlViewerWidgetState extends State<StlViewerWidget> {
  StlParseResult? _result;
  String? _error;

  // 카메라 상태
  double _rotX = 0.4;
  double _rotY = 0.6;
  double _scale = 1.0;
  Offset _pan = Offset.zero;

  // 제스처 추적
  Offset? _lastPanPos;
  double? _lastScale;
  Offset? _lastTwoFingerPos;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  void _parse() {
    try {
      final result = StlParserService.parse(widget.fileBytes);
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = 'Parse error: $e');
    }
  }

  void _resetView() => setState(() {
    _rotX = 0.4; _rotY = 0.6;
    _scale = 1.0; _pan = Offset.zero;
  });

  // ─── 제스처 핸들러 ─────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _lastPanPos = d.focalPoint;
    _lastScale = _scale;
    _lastTwoFingerPos = d.pointerCount >= 2 ? d.focalPoint : null;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      if (d.pointerCount >= 2) {
        // 핀치 줌
        _scale = (_lastScale! * d.scale).clamp(0.05, 20.0);
        // 두 손가락 드래그 패닝
        if (_lastTwoFingerPos != null) {
          final delta = d.focalPoint - _lastTwoFingerPos!;
          _pan += delta;
          _lastTwoFingerPos = d.focalPoint;
        }
      } else {
        // 한 손가락 드래그 → 회전
        if (_lastPanPos != null) {
          final delta = d.focalPoint - _lastPanPos!;
          _rotY += delta.dx * 0.007;
          _rotX += delta.dy * 0.007;
          _lastPanPos = d.focalPoint;
        }
      }
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    if (_result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final r = _result!;

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: Container(
              color: const Color(0xFF1E1E1E),
              child: CustomPaint(
                painter: _StlPainter(
                  result: r,
                  rotX: _rotX, rotY: _rotY,
                  scale: _scale, pan: _pan,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),

        // 하단 정보 바
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${r.faces.length} faces',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '${(widget.fileSize / 1024).toStringAsFixed(1)} KB',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IconButton(
                icon: const Icon(Icons.center_focus_strong, size: 20),
                onPressed: _resetView,
                tooltip: 'Reset view',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── CustomPainter (소프트웨어 렌더러) ────────────────────────────────────

class _StlPainter extends CustomPainter {
  final StlParseResult result;
  final double rotX, rotY, scale;
  final Offset pan;

  static const _lightDir = _V3(0.4, 0.7, 0.6);
  static const _baseColor = Color(0xFFA0A0A0);
  static const _fov = 600.0;
  static const _camZ = 4.0;

  _StlPainter({
    required this.result,
    required this.rotX, required this.rotY,
    required this.scale, required this.pan,
  });

  // ─── 회전 변환 ──────────────────────────────────────────────────────────

  _V3 _rotate(_V3 v) {
    // Y축 회전
    final cy = math.cos(rotY), sy = math.sin(rotY);
    final x1 = v.x * cy + v.z * sy;
    final z1 = -v.x * sy + v.z * cy;
    // X축 회전
    final cx = math.cos(rotX), sx = math.sin(rotX);
    final y2 = v.y * cx - z1 * sx;
    final z2 = v.y * sx + z1 * cx;
    return _V3(x1, y2, z2);
  }

  // ─── 원근 투영 ──────────────────────────────────────────────────────────

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
    if (result.faces.isEmpty) return;

    final cx = result.centerX, cy = result.centerY, cz = result.centerZ;
    final modelScale = result.size > 0 ? 2.0 / result.size : 1.0;

    // 모든 면을 변환 후 평균 Z로 정렬 (painter's algorithm)
    final transformed = <({
      _V3 v0, _V3 v1, _V3 v2,
      _V3 normal,
      double avgZ,
    })>[];

    for (final f in result.faces) {
      // 모델 중앙 정렬 + 정규화
      final r0 = _rotate(_V3((f.x0 - cx) * modelScale, (f.y0 - cy) * modelScale, (f.z0 - cz) * modelScale));
      final r1 = _rotate(_V3((f.x1 - cx) * modelScale, (f.y1 - cy) * modelScale, (f.z1 - cz) * modelScale));
      final r2 = _rotate(_V3((f.x2 - cx) * modelScale, (f.y2 - cy) * modelScale, (f.z2 - cz) * modelScale));
      final rn = _rotate(_V3(f.nx, f.ny, f.nz)).norm;

      // 뒷면 컬링: 법선의 Z 성분이 양수면 카메라를 향하지 않음
      if (rn.z > 0.05) continue;

      final avgZ = (r0.z + r1.z + r2.z) / 3;
      transformed.add((v0: r0, v1: r1, v2: r2, normal: rn, avgZ: avgZ));
    }

    // Z 기준 정렬 (멀리 있는 면 먼저)
    transformed.sort((a, b) => a.avgZ.compareTo(b.avgZ));

    final paint = Paint()..style = PaintingStyle.fill;

    for (final t in transformed) {
      final p0 = _project(t.v0, size);
      final p1 = _project(t.v1, size);
      final p2 = _project(t.v2, size);

      // 플랫 셰이딩: 법선과 광원의 내적
      final intensity = (-t.normal.dot(_lightDir)).clamp(0.0, 1.0);
      final ambient = 0.25;
      final brightness = ambient + (1 - ambient) * intensity;

      paint.color = Color.fromARGB(
        255,
        (_baseColor.r * 255.0 * brightness).round().clamp(0, 255),
        (_baseColor.g * 255.0 * brightness).round().clamp(0, 255),
        (_baseColor.b * 255.0 * brightness).round().clamp(0, 255),
      );

      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();

      canvas.drawPath(path, paint);
    }

    // 축 표시 (좌하단)
    _drawAxes(canvas, size);
  }

  void _drawAxes(Canvas canvas, Size size) {
    const origin = _V3(0, 0, 0);
    const len = 0.6;
    final ox = _project(_rotate(origin), size);
    final xx = _project(_rotate(const _V3(len, 0, 0)), size);
    final yx = _project(_rotate(const _V3(0, len, 0)), size);
    final zx = _project(_rotate(const _V3(0, 0, len)), size);

    // 좌하단으로 오프셋
    const off = Offset(60, -60);
    Offset shift(Offset p) => Offset(60 + (p.dx - ox.dx), size.height - 60 + (p.dy - ox.dy));

    final axisPaint = Paint()..strokeWidth = 2..style = PaintingStyle.stroke;

    axisPaint.color = Colors.red;
    canvas.drawLine(shift(ox), shift(xx), axisPaint);
    axisPaint.color = Colors.green;
    canvas.drawLine(shift(ox), shift(yx), axisPaint);
    axisPaint.color = Colors.blue;
    canvas.drawLine(shift(ox), shift(zx), axisPaint);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(String t, Offset pos, Color c) {
      tp.text = TextSpan(text: t, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold));
      tp.layout();
      tp.paint(canvas, shift(pos) + off * 0.15);
    }
    drawLabel('X', xx, Colors.red);
    drawLabel('Y', yx, Colors.green);
    drawLabel('Z', zx, Colors.blue);
  }

  @override
  bool shouldRepaint(_StlPainter old) =>
      rotX != old.rotX || rotY != old.rotY ||
      scale != old.scale || pan != old.pan ||
      result != old.result;
}
