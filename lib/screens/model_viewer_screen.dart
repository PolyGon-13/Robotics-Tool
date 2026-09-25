import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/mesh_parsers.dart';
import '../services/urdf_parser_service.dart';
import '../widgets/model_viewer/mesh_viewer_widget.dart';
import '../widgets/model_viewer/urdf_viewer_widget.dart';
import '../widgets/settings_button.dart';

const _meshExtensions = {'stl', 'dae'};

/// Parses one mesh file off the UI thread (STL can be 100k+ triangles).
List<TriMesh> _parseMeshFile((String, Uint8List) file) {
  final (ext, bytes) = file;
  return ext == 'dae'
      ? parseDae(utf8.decode(bytes, allowMalformed: true))
      : [parseStl(bytes)];
}

class ModelViewerScreen extends StatefulWidget {
  const ModelViewerScreen({super.key});

  @override
  State<ModelViewerScreen> createState() => _ModelViewerScreenState();
}

class _ModelViewerScreenState extends State<ModelViewerScreen> {
  String _title = '';
  String? _error;
  bool _loading = false;

  UrdfRobot? _robot;
  Map<String, List<TriMesh>> _urdfMeshes = const {};
  List<TriMesh>? _meshes; // standalone STL/DAE
  int _meshBytes = 0;

  String _ext(PlatformFile f) => (f.extension ?? f.name.split('.').last).toLowerCase();

  Future<List<PlatformFile>?> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );
    return result?.files;
  }

  /// Parses the picked mesh files; returns file name → meshes and skipped names.
  Future<(Map<String, List<TriMesh>>, List<String>)> _loadMeshes(List<PlatformFile> files) async {
    final out = <String, List<TriMesh>>{};
    final failed = <String>[];
    for (final f in files) {
      final ext = _ext(f);
      if (!_meshExtensions.contains(ext) || f.bytes == null) continue;
      try {
        out[meshBaseName(f.name)] = await compute(_parseMeshFile, (ext, f.bytes!));
      } catch (e) {
        failed.add(f.name);
      }
    }
    return (out, failed);
  }

  Future<void> _open() async {
    List<PlatformFile>? files;
    try {
      files = await _pick();
    } catch (e) {
      setState(() => _error = 'File picker error: $e');
      return;
    }
    if (files == null || files.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final urdf = files.where((f) => _ext(f) == 'urdf' || _ext(f) == 'xacro').firstOrNull;
      final (meshes, failed) = await _loadMeshes(files);
      if (!mounted) return;

      if (urdf != null) {
        final robot = UrdfParserService.parse(utf8.decode(urdf.bytes ?? Uint8List(0), allowMalformed: true));
        setState(() {
          _robot = robot;
          _urdfMeshes = meshes;
          _meshes = null;
          _title = urdf.name;
        });
      } else if (meshes.isNotEmpty) {
        setState(() {
          _robot = null;
          _meshes = [for (final m in meshes.values) ...m];
          _meshBytes = files!.fold(0, (s, f) => s + (f.bytes?.length ?? 0));
          _title = meshes.length == 1 ? files.first.name : '${meshes.length} meshes';
        });
      } else {
        final names = files.map((f) => f.name).join(', ');
        setState(() => _error = 'Nothing to show in: $names\n\n'
            'Supported: .urdf (with its .stl / .dae meshes), .stl, .dae');
      }
      if (failed.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read: ${failed.join(', ')}')),
        );
      }
    } on FormatException catch (e) {
      setState(() => _error = 'Could not read the URDF: ${e.message}');
    } catch (e) {
      setState(() => _error = 'Could not open the file: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Add mesh files to the loaded URDF.
  Future<void> _addMeshes() async {
    final files = await _pick();
    if (files == null || files.isEmpty) return;
    setState(() => _loading = true);
    final (meshes, failed) = await _loadMeshes(files);
    if (!mounted) return;
    final wanted = _robot?.meshKeys ?? const <String>{};
    final unused = meshes.keys.where((k) => !wanted.contains(k)).toList();
    setState(() {
      _urdfMeshes = {..._urdfMeshes, ...meshes};
      _loading = false;
    });
    final notes = [
      if (failed.isNotEmpty) 'Could not read: ${failed.join(', ')}',
      if (unused.isNotEmpty) 'Not used by this URDF: ${unused.join(', ')}',
    ];
    if (notes.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notes.join('\n'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasModel = _robot != null || _meshes != null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Model Viewer'),
            if (hasModel)
              Text(_title,
                  style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          if (hasModel)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Open another model',
              onPressed: _loading ? null : _open,
            ),
          const SettingsButton(),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _body()),
          if (_loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final cs = Theme.of(context).colorScheme;
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
                onPressed: _open,
                icon: const Icon(Icons.folder_open),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_robot != null) {
      return UrdfViewerWidget(
        key: ValueKey(_robot),
        robot: _robot!,
        meshes: _urdfMeshes,
        onAddMeshes: _addMeshes,
      );
    }
    if (_meshes != null) {
      return MeshViewerWidget(key: ValueKey(_meshes), meshes: _meshes!, fileBytes: _meshBytes);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_in_ar_rounded, size: 80, color: cs.onSurfaceVariant),
            const SizedBox(height: 20),
            Text('Load STL, DAE or URDF files',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              'For a URDF that uses meshes, select the .urdf file together with '
              'its .stl / .dae files (they are matched by file name).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.folder_open),
              label: const Text('Load File'),
            ),
          ],
        ),
      ),
    );
  }
}
