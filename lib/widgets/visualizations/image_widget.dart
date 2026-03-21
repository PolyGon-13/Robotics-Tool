import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ImageWidget extends StatefulWidget {
  final Map<String, dynamic> msg;
  const ImageWidget({super.key, required this.msg});

  @override
  State<ImageWidget> createState() => _ImageWidgetState();
}

class _ImageWidgetState extends State<ImageWidget> {
  ui.Image? _image;
  String? _error;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    _decode(widget.msg);
  }

  @override
  void didUpdateWidget(ImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.msg != oldWidget.msg) _decode(widget.msg);
  }

  Future<void> _decode(Map<String, dynamic> msg) async {
    if (_decoding) return;
    _decoding = true;

    try {
      final dataStr = msg['data'] as String?;
      final encoding = (msg['encoding'] as String? ?? 'rgb8').toLowerCase();
      final w = msg['width'] as int? ?? 0;
      final h = msg['height'] as int? ?? 0;

      if (dataStr == null || dataStr.isEmpty || w == 0 || h == 0) {
        if (mounted) setState(() { _error = 'No image data'; _decoding = false; });
        return;
      }

      final raw = base64Decode(dataStr);
      Uint8List? rgba;

      switch (encoding) {
        case 'rgb8':
          rgba = Uint8List(w * h * 4);
          for (int i = 0; i < w * h; i++) {
            rgba[i * 4 + 0] = raw[i * 3 + 0];
            rgba[i * 4 + 1] = raw[i * 3 + 1];
            rgba[i * 4 + 2] = raw[i * 3 + 2];
            rgba[i * 4 + 3] = 255;
          }
        case 'bgr8':
          rgba = Uint8List(w * h * 4);
          for (int i = 0; i < w * h; i++) {
            rgba[i * 4 + 0] = raw[i * 3 + 2];
            rgba[i * 4 + 1] = raw[i * 3 + 1];
            rgba[i * 4 + 2] = raw[i * 3 + 0];
            rgba[i * 4 + 3] = 255;
          }
        case 'mono8':
          rgba = Uint8List(w * h * 4);
          for (int i = 0; i < w * h; i++) {
            rgba[i * 4 + 0] = raw[i];
            rgba[i * 4 + 1] = raw[i];
            rgba[i * 4 + 2] = raw[i];
            rgba[i * 4 + 3] = 255;
          }
        case 'rgba8':
          rgba = raw; // base64Decode returns Uint8List
        default:
          if (mounted) setState(() { _error = 'Unsupported encoding: $encoding'; _decoding = false; });
          return;
      }

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba, w, h, ui.PixelFormat.rgba8888,
        (img) => completer.complete(img),
      );
      final img = await completer.future;

      if (mounted) setState(() { _image = img; _error = null; _decoding = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Decode error: $e'; _decoding = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    if (_image == null) return const Center(child: CircularProgressIndicator());

    final encoding = widget.msg['encoding'] as String? ?? 'unknown';
    final w = widget.msg['width'] as int? ?? 0;
    final h = widget.msg['height'] as int? ?? 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'encoding: $encoding  ${w}x$h',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            child: RawImage(
              image: _image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
      ],
    );
  }
}
