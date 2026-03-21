import 'dart:math' as math;
import 'dart:typed_data';

class StlFace {
  final double nx, ny, nz;
  final double x0, y0, z0;
  final double x1, y1, z1;
  final double x2, y2, z2;

  const StlFace({
    required this.nx, required this.ny, required this.nz,
    required this.x0, required this.y0, required this.z0,
    required this.x1, required this.y1, required this.z1,
    required this.x2, required this.y2, required this.z2,
  });
}

class StlParseResult {
  final List<StlFace> faces;
  final double minX, maxX, minY, maxY, minZ, maxZ;

  const StlParseResult({
    required this.faces,
    required this.minX, required this.maxX,
    required this.minY, required this.maxY,
    required this.minZ, required this.maxZ,
  });

  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
  double get centerZ => (minZ + maxZ) / 2;
  double get size =>
      math.sqrt(math.pow(maxX - minX, 2) + math.pow(maxY - minY, 2) + math.pow(maxZ - minZ, 2));
}

class StlParserService {
  static StlParseResult parse(Uint8List bytes) {
    // 헤더 80바이트 + 삼각형 수 4바이트 = 최소 84바이트
    // 각 삼각형: 12(normal) + 36(3 vertices) + 2(attr) = 50바이트
    final isBinary = _isBinaryStl(bytes);
    return isBinary ? _parseBinary(bytes) : _parseAscii(bytes);
  }

  static bool _isBinaryStl(Uint8List bytes) {
    if (bytes.length < 84) return false;
    // ASCII STL은 "solid"로 시작
    final header = String.fromCharCodes(bytes.sublist(0, 5));
    if (!header.startsWith('solid')) return true;
    // "solid"로 시작해도 바이너리일 수 있음: 삼각형 수로 크기 검증
    final view = ByteData.sublistView(bytes);
    final triCount = view.getUint32(80, Endian.little);
    final expectedSize = 84 + triCount * 50;
    return bytes.length == expectedSize;
  }

  static StlParseResult _parseBinary(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    final triCount = view.getUint32(80, Endian.little);
    final faces = <StlFace>[];

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;

    for (int i = 0; i < triCount; i++) {
      final offset = 84 + i * 50;
      if (offset + 50 > bytes.length) break;

      final nx = view.getFloat32(offset +  0, Endian.little);
      final ny = view.getFloat32(offset +  4, Endian.little);
      final nz = view.getFloat32(offset +  8, Endian.little);
      final x0 = view.getFloat32(offset + 12, Endian.little);
      final y0 = view.getFloat32(offset + 16, Endian.little);
      final z0 = view.getFloat32(offset + 20, Endian.little);
      final x1 = view.getFloat32(offset + 24, Endian.little);
      final y1 = view.getFloat32(offset + 28, Endian.little);
      final z1 = view.getFloat32(offset + 32, Endian.little);
      final x2 = view.getFloat32(offset + 36, Endian.little);
      final y2 = view.getFloat32(offset + 40, Endian.little);
      final z2 = view.getFloat32(offset + 44, Endian.little);

      faces.add(StlFace(
        nx: nx, ny: ny, nz: nz,
        x0: x0, y0: y0, z0: z0,
        x1: x1, y1: y1, z1: z1,
        x2: x2, y2: y2, z2: z2,
      ));

      minX = math.min(minX, math.min(x0, math.min(x1, x2)));
      maxX = math.max(maxX, math.max(x0, math.max(x1, x2)));
      minY = math.min(minY, math.min(y0, math.min(y1, y2)));
      maxY = math.max(maxY, math.max(y0, math.max(y1, y2)));
      minZ = math.min(minZ, math.min(z0, math.min(z1, z2)));
      maxZ = math.max(maxZ, math.max(z0, math.max(z1, z2)));
    }

    return StlParseResult(
      faces: faces,
      minX: minX == double.infinity ? 0 : minX, maxX: maxX == -double.infinity ? 0 : maxX,
      minY: minY == double.infinity ? 0 : minY, maxY: maxY == -double.infinity ? 0 : maxY,
      minZ: minZ == double.infinity ? 0 : minZ, maxZ: maxZ == -double.infinity ? 0 : maxZ,
    );
  }

  static StlParseResult _parseAscii(Uint8List bytes) {
    final text = String.fromCharCodes(bytes);
    final lines = text.split('\n').map((l) => l.trim()).toList();
    final faces = <StlFace>[];

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;

    double nx = 0, ny = 0, nz = 0;
    final verts = <(double, double, double)>[];

    for (final line in lines) {
      if (line.startsWith('facet normal')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          nx = double.tryParse(parts[2]) ?? 0;
          ny = double.tryParse(parts[3]) ?? 0;
          nz = double.tryParse(parts[4]) ?? 0;
        }
        verts.clear();
      } else if (line.startsWith('vertex')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final x = double.tryParse(parts[1]) ?? 0;
          final y = double.tryParse(parts[2]) ?? 0;
          final z = double.tryParse(parts[3]) ?? 0;
          verts.add((x, y, z));

          minX = math.min(minX, x); maxX = math.max(maxX, x);
          minY = math.min(minY, y); maxY = math.max(maxY, y);
          minZ = math.min(minZ, z); maxZ = math.max(maxZ, z);
        }
      } else if (line.startsWith('endfacet') && verts.length == 3) {
        faces.add(StlFace(
          nx: nx, ny: ny, nz: nz,
          x0: verts[0].$1, y0: verts[0].$2, z0: verts[0].$3,
          x1: verts[1].$1, y1: verts[1].$2, z1: verts[1].$3,
          x2: verts[2].$1, y2: verts[2].$2, z2: verts[2].$3,
        ));
      }
    }

    return StlParseResult(
      faces: faces,
      minX: minX == double.infinity ? 0 : minX, maxX: maxX == -double.infinity ? 0 : maxX,
      minY: minY == double.infinity ? 0 : minY, maxY: maxY == -double.infinity ? 0 : maxY,
      minZ: minZ == double.infinity ? 0 : minZ, maxZ: maxZ == -double.infinity ? 0 : maxZ,
    );
  }
}
