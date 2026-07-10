import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'vault_service.dart';

IconData _iconForCategory(VaultCategoryType type) {
  switch (type) {
    case VaultCategoryType.photos:
      return Icons.image_outlined;
    case VaultCategoryType.videos:
      return Icons.videocam_outlined;
    case VaultCategoryType.documents:
      return Icons.description_outlined;
    case VaultCategoryType.other:
      return Icons.folder_outlined;
  }
}

class ImportProgress {
  final int completed;
  final int total;
  final String currentFileName;

  const ImportProgress(this.completed, this.total, this.currentFileName);
}

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  Map<VaultCategoryType, int> _fileCounts = {
    for (final t in VaultCategoryType.values) t: 0,
  };

  final ValueNotifier<ImportProgress> _importProgress =
      ValueNotifier(const ImportProgress(0, 0, ''));

  @override
  void initState() {
    super.initState();
    _refreshCounts();
  }

  void _refreshCounts() {
    setState(() {
      _fileCounts = VaultService.instance.getCategoryCounts();
    });
  }

  Future<void> _onAddFilePressed() async {
    final files = await VaultService.instance.pickFiles();
    if (files.isEmpty) return;

    if (!mounted) return;
    final confirmed = await _showLongOperationWarning(files.length);
    if (confirmed != true) return;

    _importProgress.value = ImportProgress(0, files.length, '');

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _buildProgressDialog(),
    );

    final imported = await VaultService.instance.importFiles(
      files,
      onProgress: (completed, total, name) {
        _importProgress.value = ImportProgress(completed, total, name);
      },
    );

    if (!mounted) return;
    Navigator.of(context).pop();
    _refreshCounts();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Imported ${imported.length} of ${files.length} files'),
      ),
    );
  }

  Future<bool?> _showLongOperationWarning(int count) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Import Files', style: TextStyle(color: Colors.white)),
        content: Text(
          'You are about to import $count file(s).\n\n'
          'Each file will be encrypted before being stored, which may take '
          'some time depending on file size. Please do not close the app '
          'during the import process.',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start', style: TextStyle(color: Color(0xFF0A84FF))),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressDialog() {
    return ValueListenableBuilder<ImportProgress>(
      valueListenable: _importProgress,
      builder: (context, progress, _) {
        final percent =
            progress.total == 0 ? 0.0 : progress.completed / progress.total;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Importing files...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 8,
                      backgroundColor: const Color(0xFF2C2C2E),
                      color: const Color(0xFF0A84FF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${progress.completed} of ${progress.total} '
                    '(${(percent * 100).toInt()}%)',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  if (progress.currentFileName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      progress.currentFileName,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openCategory(VaultCategory category) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CategoryFilesScreen(category: category),
          ),
        )
        .then((_) => _refreshCounts());
  }

  void _lockVault() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text('Vault', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.lock_outline, color: Colors.white),
          tooltip: 'Lock',
          onPressed: _lockVault,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          itemCount: vaultCategories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.1,
          ),
          itemBuilder: (context, index) {
            final category = vaultCategories[index];
            final count = _fileCounts[category.type] ?? 0;
            return _buildCategoryCard(category, count);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0A84FF),
        onPressed: _onAddFilePressed,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add File', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildCategoryCard(VaultCategory category, int count) {
    return Material(
      color: const Color(0xFF1E1E1E),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openCategory(category),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_iconForCategory(category.type),
                  size: 40, color: const Color(0xFF0A84FF)),
              const SizedBox(height: 12),
              Text(
                category.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text('$count files',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class CategoryFilesScreen extends StatefulWidget {
  final VaultCategory category;

  const CategoryFilesScreen({super.key, required this.category});

  @override
  State<CategoryFilesScreen> createState() => _CategoryFilesScreenState();
}

class _CategoryFilesScreenState extends State<CategoryFilesScreen> {
  final Map<String, Future<Uint8List>> _photoCache = {};
  final Map<String, Future<Uint8List?>> _videoThumbCache = {};

  bool get _isMediaGrid =>
      widget.category.type == VaultCategoryType.photos ||
      widget.category.type == VaultCategoryType.videos;

  @override
  Widget build(BuildContext context) {
    final files = VaultService.instance.getFilesByCategory(widget.category.type);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: Text(widget.category.label, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: files.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_iconForCategory(widget.category.type),
                      size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  Text('No files yet',
                      style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ],
              ),
            )
          : (_isMediaGrid ? _buildMediaGrid(files) : _buildDocumentList(files)),
    );
  }

  Widget _buildMediaGrid(List<VaultFileMeta> files) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final meta = files[index];
        return widget.category.type == VaultCategoryType.photos
            ? _buildPhotoTile(meta)
            : _buildVideoTile(meta);
      },
    );
  }

  Widget _buildPhotoTile(VaultFileMeta meta) {
    final future =
        _photoCache.putIfAbsent(meta.id, () => VaultService.instance.getDecryptedBytes(meta.id));

    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PhotoViewerScreen(bytes: snapshot.data!),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              cacheWidth: 300,
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoTile(VaultFileMeta meta) {
    final future = _videoThumbCache.putIfAbsent(
      meta.id,
      () => VaultService.instance.getVideoThumbnail(meta.id, meta.extension),
    );

    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final thumb = snapshot.data;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VideoViewerScreen(id: meta.id, extension: meta.extension),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                thumb != null
                    ? Image.memory(thumb, fit: BoxFit.cover)
                    : Container(color: const Color(0xFF1E1E1E)),
                const Center(
                  child: Icon(Icons.play_circle_fill,
                      color: Colors.white70, size: 36),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocumentList(List<VaultFileMeta> files) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final meta = files[index];
        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            leading: Icon(_iconForCategory(widget.category.type), color: const Color(0xFF0A84FF)),
            title: Text(
              meta.originalName,
              style: const TextStyle(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${(meta.sizeInBytes / 1024).toStringAsFixed(1)} KB',
              style: const TextStyle(color: Colors.grey),
            ),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Preview not available for this file type')),
              );
            },
          ),
        );
      },
    );
  }
}

class PhotoViewerScreen extends StatelessWidget {
  final Uint8List bytes;

  const PhotoViewerScreen({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}

class VideoViewerScreen extends StatefulWidget {
  final String id;
  final String extension;

  const VideoViewerScreen({super.key, required this.id, required this.extension});

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  VideoPlayerController? _controller;
  File? _tempFile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final file = await VaultService.instance.prepareTempPlaybackFile(
      widget.id,
      widget.extension,
    );
    final controller = VideoPlayerController.file(file);
    await controller.initialize();

    if (!mounted) {
      await controller.dispose();
      await VaultService.instance.deleteTempFile(file);
      return;
    }

    setState(() {
      _tempFile = file;
      _controller = controller;
      _loading = false;
    });
    controller.play();
  }

  @override
  void dispose() {
    _controller?.dispose();
    if (_tempFile != null) {
      VaultService.instance.deleteTempFile(_tempFile!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: Color(0xFF0A84FF))
            : AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _controller!.value.isPlaying
                          ? _controller!.pause()
                          : _controller!.play();
                    });
                  },
                  child: VideoPlayer(_controller!),
                ),
              ),
      ),
    );
  }
}