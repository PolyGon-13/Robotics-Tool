import 'dart:convert';

import 'package:flutter/material.dart';

class CompressedImageWidget extends StatelessWidget {
  final Map<String, dynamic> msg;
  const CompressedImageWidget({super.key, required this.msg});

  @override
  Widget build(BuildContext context) {
    final dataStr = msg['data'] as String?;
    final format = (msg['format'] as String? ?? 'jpeg').toLowerCase();

    if (dataStr == null || dataStr.isEmpty) {
      return const Center(child: Text('No image data'));
    }

    try {
      final bytes = base64Decode(dataStr);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.image, size: 16),
                const SizedBox(width: 6),
                Text(
                  'format: $format  ${(bytes.length / 1024).toStringAsFixed(1)} KB',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 8.0,
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    const Center(child: Text('Cannot decode image')),
              ),
            ),
          ),
        ],
      );
    } catch (e) {
      return Center(child: Text('Decode error: $e'));
    }
  }
}
