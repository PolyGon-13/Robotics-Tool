import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/services/mesh_parsers.dart';
import 'package:robotics_tool/services/primitive_meshes.dart';
import 'package:robotics_tool/services/urdf_kinematics.dart';
import 'package:robotics_tool/services/urdf_parser_service.dart';
import 'package:robotics_tool/widgets/model_viewer/scene_view.dart';

Uint8List binaryStl(List<List<double>> tris, {String header = 'solid but binary'}) {
  final b = ByteData(84 + tris.length * 50);
  final h = header.codeUnits;
  for (var i = 0; i < h.length && i < 80; i++) {
    b.setUint8(i, h[i]);
  }
  b.setUint32(80, tris.length, Endian.little);
  for (var t = 0; t < tris.length; t++) {
    for (var k = 0; k < 9; k++) {
      b.setFloat32(84 + t * 50 + 12 + k * 4, tris[t][k], Endian.little);
    }
  }
  return b.buffer.asUint8List();
}

void main() {
  group('STL', () {
    test('binary, even when the header starts with "solid"', () {
      final m = parseStl(binaryStl([
        [0, 0, 0, 1, 0, 0, 0, 1, 0],
        [0, 0, 1, 1, 0, 1, 0, 1, 1],
      ]));
      expect(m.triangleCount, 2);
      expect(m.tris.sublist(9, 12), [0, 0, 1]);
    });

    test('ASCII', () {
      const text = '''solid t
facet normal 0 0 0
 outer loop
  vertex 0 0 0
  vertex 1 0 0
  vertex 0 1e0 0
 endloop
endfacet
endsolid t''';
      final m = parseStl(Uint8List.fromList(text.codeUnits));
      expect(m.triangleCount, 1);
      expect(m.tris[7], 1.0);
    });

    test('truncated binary keeps the complete triangles', () {
      final full = binaryStl([
        [0, 0, 0, 1, 0, 0, 0, 1, 0],
        [0, 0, 1, 1, 0, 1, 0, 1, 1],
      ]);
      expect(parseStl(full.sublist(0, full.length - 10)).triangleCount, 1);
    });
  });

  group('COLLADA', () {
    String dae({String up = 'Z_UP', String unit = '1', String node = '', String prim = ''}) => '''
<?xml version="1.0"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
  <asset><unit meter="$unit"/><up_axis>$up</up_axis></asset>
  <library_effects><effect id="red-fx"><profile_COMMON><technique sid="t"><lambert>
    <diffuse><color>1 0 0 1</color></diffuse></lambert></technique></profile_COMMON></effect></library_effects>
  <library_materials><material id="red-mat"><instance_effect url="#red-fx"/></material></library_materials>
  <library_geometries><geometry id="g"><mesh>
    <source id="pos"><float_array id="pa" count="12">0 0 0 1 0 0 0 1 0 1 1 0</float_array>
      <technique_common><accessor source="#pa" count="4" stride="3"/></technique_common></source>
    <vertices id="v"><input semantic="POSITION" source="#pos"/></vertices>
    ${prim.isEmpty ? '<triangles material="m" count="1"><input semantic="VERTEX" source="#v" offset="0"/><input semantic="NORMAL" source="#v" offset="1"/><p>0 0 1 0 2 0</p></triangles>' : prim}
  </mesh></geometry></library_geometries>
  <library_visual_scenes><visual_scene id="s"><node>$node
    <instance_geometry url="#g"><bind_material><technique_common>
      <instance_material symbol="m" target="#red-mat"/></technique_common></bind_material></instance_geometry>
  </node></visual_scene></library_visual_scenes>
</COLLADA>''';

    test('triangles with interleaved inputs and a bound material color', () {
      final meshes = parseDae(dae());
      expect(meshes.single.triangleCount, 1);
      expect(meshes.single.tris, [0, 0, 0, 1, 0, 0, 0, 1, 0]);
      expect(meshes.single.color, const Color(0xFFFF0000));
    });

    test('Y_UP files are rotated to Z_UP and units applied', () {
      final m = parseDae(dae(up: 'Y_UP', unit: '0.01')).single;
      // vertex (0, 1, 0) in Y-up cm → (0, 0, 0.01) m in Z-up
      expect(m.tris[6], closeTo(0, 1e-9));
      expect(m.tris[7], closeTo(0, 1e-9));
      expect(m.tris[8], closeTo(0.01, 1e-9));
    });

    test('node translate and polylist quads', () {
      final m = parseDae(dae(
        node: '<translate>0 0 5</translate>',
        prim: '<polylist material="m" count="1"><input semantic="VERTEX" source="#v" offset="0"/>'
            '<vcount>4</vcount><p>0 1 3 2</p></polylist>',
      )).single;
      expect(m.triangleCount, 2);
      expect([m.tris[2], m.tris[5], m.tris[8]], [5, 5, 5]);
    });
  });

  group('URDF', () {
    const urdf = '''
<robot name="r" xmlns:xacro="http://www.ros.org/wiki/xacro">
  <material name="blue"><color rgba="0 0 1 1"/></material>
  <link name="base">
    <visual><geometry><mesh filename="package://pkg/meshes/Base.STL" scale="0.001 0.001 0.001"/></geometry>
      <material name="blue"/></visual>
  </link>
  <link name="arm"><visual><geometry><box size="1 1 1"/></geometry>
    <material name="x"><color rgba="1 0 0 1"/></material></visual></link>
  <joint name="j" type="revolute"><parent link="base"/><child link="arm"/>
    <origin xyz="1 0 0" rpy="0 0 1.5707963"/><limit lower="-1" upper="1"/></joint>
  <joint name="w" type="continuous"><parent link="base"/><child link="wheel"/></joint>
  <link name="wheel"/>
</robot>''';

    test('named and inline materials, mesh scale and key', () {
      final r = UrdfParserService.parse(urdf);
      final base = r.links.first.visuals.single;
      expect(base.color, const Color(0xFF0000FF));
      expect(base.geometry.meshKey, 'base.stl');
      expect(base.geometry.meshScale, [0.001, 0.001, 0.001]);
      expect(r.links[1].visuals.single.color, const Color(0xFFFF0000));
      expect(r.meshKeys, {'base.stl'});
      expect(r.looksLikeXacro, isFalse, reason: 'a namespace alone is not xacro usage');
    });

    test('joint defaults: axis (1,0,0), continuous gets a full turn', () {
      final r = UrdfParserService.parse(urdf);
      final j = r.joints.first;
      expect([j.axisX, j.axisY, j.axisZ], [1, 0, 0]);
      expect([j.limitLower, j.limitUpper], [-1, 1]);
      final w = r.joints[1];
      expect(w.limitUpper, closeTo(math.pi, 1e-3));
    });

    test('xacro expressions are detected', () {
      final r = UrdfParserService.parse(
          '<robot name="x"><link name="\${prefix}base"/></robot>');
      expect(r.looksLikeXacro, isTrue);
      expect(() => UrdfParserService.parse('<notrobot/>'), throwsFormatException);
    });

    test('kinematics: origin rpy and revolute axis', () {
      final r = UrdfParserService.parse(urdf);
      // arm frame: at (1,0,0), rotated 90° about Z; joint axis x rotates about that frame's x
      final t = linkTransforms(r, {'j': 0.0});
      final arm = t['arm']!;
      expect(arm[3], closeTo(1, 1e-9));
      // local x axis now points along world +y
      expect(arm[4], closeTo(1, 1e-6));
      // A joint rotation keeps the transform a proper rotation
      final t2 = linkTransforms(r, {'j': math.pi / 2});
      final m = t2['arm']!;
      final det = m[0] * (m[5] * m[10] - m[6] * m[9]) -
          m[1] * (m[4] * m[10] - m[6] * m[8]) +
          m[2] * (m[4] * m[9] - m[5] * m[8]);
      expect(det, closeTo(1, 1e-9));
      expect(t2['wheel'], identityMat4, reason: 'joint without origin');
    });
  });

  test('SceneGeometry: world transform, normals and bounds', () {
    final g = SceneGeometry.build([
      ScenePart(Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]), const Color(0xFF00FF00),
          const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 2, 0, 0, 0, 1]),
    ]);
    expect(g.triangleCount, 1);
    expect(g.tris[2], 2);
    expect(g.normals.sublist(0, 3), [0, 0, 1]);
    expect(g.minZ, 2);
    expect(SceneGeometry.build(const []).triangleCount, 0);
  });

  test('SceneGeometry detects winding of closed meshes', () {
    final box = boxMesh(1, 2, 3);
    final flipped = Float32List(box.length);
    for (var i = 0; i < box.length; i += 9) {
      flipped.setRange(i, i + 3, box.sublist(i, i + 3));
      flipped.setRange(i + 3, i + 6, box.sublist(i + 6, i + 9));
      flipped.setRange(i + 6, i + 9, box.sublist(i + 3, i + 6));
    }
    const c = Color(0xFF000000);
    expect(SceneGeometry.build([ScenePart(box, c)]).orientation.first, 1);
    expect(SceneGeometry.build([ScenePart(flipped, c)]).orientation.first, -1);
    expect(SceneGeometry.build([ScenePart(cylinderMesh(1, 1), c)]).orientation.first, isNot(0));
    // open mesh (a single quad) has no reliable orientation
    expect(SceneGeometry.build([ScenePart(box.sublist(0, 18), c)]).orientation.first, 0);
  });
}
