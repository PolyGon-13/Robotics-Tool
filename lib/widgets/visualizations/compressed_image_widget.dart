import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// sensor_msgs/CompressedImage (jpeg / png, and compressedDepth PNGs).
class CompressedImageWidget extends StatefulWidget {
  final Map<String, dynamic> msg;
  const CompressedImageWidget({super.key, required this.msg});

  @override
  State<CompressedImageWidget> createState() => _CompressedImageWidgetState();
}

class _CompressedImageWidgetState extends State<CompressedImageWidget> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(CompressedImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Decode once per message, not on every rebuild (status refresh etc.)
    if (!identical(oldWidget.msg, widget.msg)) _decode();
  }

  void _decode() {
    final data = widget.msg['data'];
    if (data is! String || data.isEmpty) {
      _error = 'No image data';
      return;
    }
    try {
      var bytes = base64Decode(data);
      // compressed_depth_image_transport prepends a 12-byte config header
      final format = widget.msg['format']?.toString() ?? '';
      if (format.contains('compressedDepth') && bytes.length > 12) {
        bytes = bytes.sublist(12);
      }
      _bytes = bytes;
      _error = null;
    } on FormatException catch (e) {
      _error = 'Decode error: ${e.message}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return Center(child: Text(_error ?? 'No image data'));
    final format = (widget.msg['format']?.toString() ?? 'jpeg').toLowerCase();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.image, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'format: $format  ${(bytes.length / 1024).toStringAsFixed(1)} KB',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 8.0,
            child: SizedBox.expand(
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true, // no flicker between frames
                errorBuilder: (_, _, _) => const Center(child: Text('Cannot decode image')),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
