import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/widgets/visualizations/image_widget.dart';

void main() {
  test('rgb8 and bgr8 map channels correctly', () {
    final raw = Uint8List.fromList([10, 20, 30]);
    final rgb = decodeRosImage(raw: raw, encoding: 'rgb8', width: 1, height: 1);
    expect(rgb.rgba, [10, 20, 30, 255]);
    final bgr = decodeRosImage(raw: raw, encoding: 'bgr8', width: 1, height: 1);
    expect(bgr.rgba, [30, 20, 10, 255]);
  });

  test('row padding (step) is skipped', () {
    // 1x2 mono8 with 4-byte rows
    final raw = Uint8List.fromList([7, 0, 0, 0, 9, 0, 0, 0]);
    final img = decodeRosImage(raw: raw, encoding: 'mono8', width: 1, height: 2, step: 4);
    expect(img.rgba, [7, 7, 7, 255, 9, 9, 9, 255]);
  });

  test('16UC1 depth is normalized and zero means no reading', () {
    final bd = ByteData(6)
      ..setUint16(0, 500, Endian.little)
      ..setUint16(2, 1500, Endian.little)
      ..setUint16(4, 0, Endian.little);
    final img = decodeRosImage(
        raw: bd.buffer.asUint8List(), encoding: '16UC1', width: 3, height: 1);
    expect(img.min, 500);
    expect(img.max, 1500);
    expect(img.rgba.sublist(8, 12), [0, 0, 0, 255]);
    // near pixel is reddish, far pixel is bluish
    expect(img.rgba[0], greaterThan(img.rgba[2]));
    expect(img.rgba[6], greaterThan(img.rgba[4]));
  });

  test('32FC1 handles NaN pixels', () {
    final bd = ByteData(8)
      ..setFloat32(0, 1.25, Endian.little)
      ..setFloat32(4, double.nan, Endian.little);
    final img = decodeRosImage(
        raw: bd.buffer.asUint8List(), encoding: '32FC1', width: 2, height: 1);
    expect(img.min, 1.25);
    expect(img.rgba.sublist(4), [0, 0, 0, 255]);
  });

  test('unsupported encodings and short data throw FormatException', () {
    expect(
        () => decodeRosImage(raw: Uint8List(3), encoding: 'yuv422', width: 1, height: 1),
        throwsFormatException);
    expect(
        () => decodeRosImage(raw: Uint8List(2), encoding: 'rgb8', width: 1, height: 1),
        throwsFormatException);
  });
}
