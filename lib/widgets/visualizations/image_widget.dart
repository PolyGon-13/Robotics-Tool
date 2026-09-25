import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import '../../utils/time_series.dart';

/// Result of converting a sensor_msgs/Image to RGBA pixels.
class DecodedImage {
  final Uint8List rgba;
  final int width, height;

  /// Value range of depth / 16-bit images (raw units), null for color.
  final double? min, max;
  const DecodedImage(this.rgba, this.width, this.height, {this.min, this.max});
}

/// Converts raw image bytes to RGBA. Throws [FormatException] for
/// unsupported encodings or truncated data.
DecodedImage decodeRosImage({
  required Uint8List raw,
  required String encoding,
  required int width,
  required int height,
  int? step,
  bool bigEndian = false,
}) {
  final enc = encoding.toLowerCase();
  final bpp = switch (enc) {
    'rgb8' || 'bgr8' || '8uc3' => 3,
    'rgba8' || 'bgra8' || '8uc4' => 4,
    'mono8' || '8uc1' => 1,
    'mono16' || '16uc1' => 2,
    '32fc1' => 4,
    _ => throw FormatException('Unsupported encoding: $encoding'),
  };
  final stride = (step != null && step >= width * bpp) ? step : width * bpp;
  if (raw.length < stride * (height - 1) + width * bpp) {
    throw FormatException('Image data too short: ${raw.length} bytes for ${width}x$height $encoding');
  }
  final out = Uint8List(width * height * 4);
  final bd = ByteData.sublistView(raw);
  final endian = bigEndian ? Endian.big : Endian.little;

  // Color and 8-bit mono
  if (bpp != 2 && enc != '32fc1') {
    final bgr = enc.startsWith('bgr') || enc == '8uc3' || enc == '8uc4';
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * stride + x * bpp, o = (y * width + x) * 4;
        if (bpp == 1) {
          out[o] = out[o + 1] = out[o + 2] = raw[i];
        } else {
          out[o] = raw[i + (bgr ? 2 : 0)];
          out[o + 1] = raw[i + 1];
          out[o + 2] = raw[i + (bgr ? 0 : 2)];
        }
        out[o + 3] = 255;
      }
    }
    return DecodedImage(out, width, height);
  }

  // Depth / 16-bit: normalize over the valid range and apply a colormap
  final vals = Float64List(width * height);
  double lo = double.infinity, hi = double.negativeInfinity;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * stride + x * bpp;
      final v = bpp == 2 ? bd.getUint16(i, endian).toDouble() : bd.getFloat32(i, endian);
      vals[y * width + x] = v;
      if (v.isFinite && v > 0) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
  }
  final span = (hi - lo) > 0 ? hi - lo : 1.0;
  for (var k = 0; k < vals.length; k++) {
    final v = vals[k];
    final o = k * 4;
    if (!v.isFinite || v <= 0 || !lo.isFinite) {
      out[o + 3] = 255; // no reading → black
      continue;
    }
    final c = _turbo((v - lo) / span);
    out[o] = c.$1;
    out[o + 1] = c.$2;
    out[o + 2] = c.$3;
    out[o + 3] = 255;
  }
  return DecodedImage(out, width, height,
      min: lo.isFinite ? lo : null, max: hi.isFinite ? hi : null);
}

/// Near = red, far = blue (approximation of the Turbo colormap, reversed).
(int, int, int) _turbo(double t) {
  // Skip Turbo's near-black ends so far pixels stay distinct from "no reading"
  final x = 0.95 - 0.85 * t.clamp(0.0, 1.0);
  // Polynomial fit of Turbo (Mikhailov, 2019); x = 0 dark blue … 1 dark red
  final r = 0.13572138 + x * (4.61539260 + x * (-42.66032258 + x * (132.13108234 + x * (-152.94239396 + x * 59.28637943))));
  final g = 0.09140261 + x * (2.19418839 + x * (4.84296658 + x * (-14.18503333 + x * (4.27729857 + x * 2.82956604))));
  final b = 0.10667330 + x * (12.64194608 + x * (-60.58204836 + x * (110.36276771 + x * (-89.90310912 + x * 27.34824973))));
  int c(double v) => (v.clamp(0.0, 1.0) * 255).round();
  return (c(r), c(g), c(b));
}

class ImageWidget extends StatefulWidget {
  final Map<String, dynamic> msg;
  const ImageWidget({super.key, required this.msg});

  @override
  State<ImageWidget> createState() => _ImageWidgetState();
}

class _ImageWidgetState extends State<ImageWidget> {
  ui.Image? _image;
  DecodedImage? _info;
  String? _error;
  bool _decoding = false;
  Map<String, dynamic>? _pending;

  @override
  void initState() {
    super.initState();
    _decode(widget.msg);
  }

  @override
  void didUpdateWidget(ImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.msg, oldWidget.msg)) _decode(widget.msg);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode(Map<String, dynamic> msg) async {
    // Keep only the newest frame while a decode is running
    if (_decoding) {
      _pending = msg;
      return;
    }
    _decoding = true;
    try {
      final data = msg['data'];
      final w = asInt(msg['width']) ?? 0;
      final h = asInt(msg['height']) ?? 0;
      if (data is! String || data.isEmpty || w == 0 || h == 0) {
        throw const FormatException('Message has no image data');
      }
      final decoded = decodeRosImage(
        raw: base64Decode(data),
        encoding: msg['encoding']?.toString() ?? 'rgb8',
        width: w,
        height: h,
        step: asInt(msg['step']),
        bigEndian: asInt(msg['is_bigendian']) == 1,
      );
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(decoded.rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
      final img = await completer.future;
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = img;
        _info = decoded;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : '$e');
    } finally {
      _decoding = false;
      final next = _pending;
      _pending = null;
      if (next != null && mounted) _decode(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _image == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_image == null) return const Center(child: CircularProgressIndicator());

    final enc = widget.msg['encoding']?.toString() ?? '?';
    final info = _info!;
    final depth = info.min != null
        ? '  ·  range ${fmtNum(info.min!)}–${fmtNum(info.max!)}'
            '${enc.toLowerCase() == '32fc1' ? ' m' : enc.toLowerCase() == '16uc1' ? ' mm' : ''}'
        : '';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('$enc  ·  ${info.width}×${info.height}$depth',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
        Expanded(
          child: InteractiveViewer(
            maxScale: 8,
            child: SizedBox.expand(
              child: RawImage(
                image: _image,
                fit: BoxFit.contain,
                // Small robot camera frames look better unsmoothed
                filterQuality: info.width < 320 ? FilterQuality.none : FilterQuality.low,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
