import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/urdf_parser_service.dart';
import '../widgets/model_viewer/stl_viewer_widget.dart';
import '../widgets/model_viewer/urdf_viewer_widget.dart';

enum _FileType { stl, urdf }

class ModelViewerScreen extends StatefulWidget {
  const ModelViewerScreen({super.key});

  @override
  State<ModelViewerScreen> createState() => _ModelViewerScreenState();
}

class _ModelViewerScreenState extends State<ModelViewerScreen> {
  Uint8List? _fileBytes;
  String _fileName = '';
  _FileType? _fileType;
  String? _error;

  // URDF 전용
  UrdfRobot? _urdfRobot;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final ext = (file.extension ?? '').toLowerCase();
      final bytes = file.bytes;

      if (bytes == null) {
        setState(() => _error = 'Could not read file data');
        return;
      }

      if (ext == 'stl') {
        setState(() {
          _fileBytes = bytes;
          _fileName = file.name;
          _fileType = _FileType.stl;
          _urdfRobot = null;
          _error = null;
        });
      } else if (ext == 'urdf') {
        try {
          final text = String.fromCharCodes(bytes);
          final robot = UrdfParserService.parse(text);
          setState(() {
            _fileBytes = bytes;
            _fileName = file.name;
            _fileType = _FileType.urdf;
            _urdfRobot = robot;
            _error = null;
          });
        } catch (e) {
          setState(() => _error = 'URDF parse error: $e');
        }
      } else {
        setState(() => _error = 'Unsupported file type: .$ext\n(STL / URDF only)');
      }
    } catch (e) {
      setState(() => _error = 'File picker error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Viewer'),
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    // 에러 표시
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    // 파일 없음 → 안내 화면
    if (_fileBytes == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_in_ar_rounded, size: 80, color: cs.onSurfaceVariant),
            const SizedBox(height: 20),
            Text(
              'Load STL or URDF file',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the folder icon to select a file',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Load File'),
            ),
          ],
        ),
      );
    }

    // 뷰어 화면
    return Column(
      children: [
        // 상단 파일 정보 바
        Container(
          color: cs.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _fileName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  _fileType == _FileType.stl ? 'STL' : 'URDF',
                  style: const TextStyle(fontSize: 11),
                ),
                padding: EdgeInsets.zero,
                backgroundColor: _fileType == _FileType.stl
                    ? cs.primaryContainer
                    : cs.tertiaryContainer,
              ),
            ],
          ),
        ),

        // 3D 뷰어
        Expanded(
          child: _fileType == _FileType.stl
              ? StlViewerWidget(
                  key: ValueKey(_fileName),
                  fileBytes: _fileBytes!,
                  fileSize: _fileBytes!.length,
                )
              : UrdfViewerWidget(
                  key: ValueKey(_fileName),
                  robot: _urdfRobot!,
                ),
        ),
      ],
    );
  }
}
