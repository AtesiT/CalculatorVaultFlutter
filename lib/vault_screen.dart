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

Future<bool> confirmDelete(BuildContext context, int count) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        count > 1 ? 'Delete Files' : 'Delete File',
        style: const TextStyle(color: Colors.white),
      ),
      content: Text(
        count > 1
            ? 'Are you sure you want to permanently delete these $count files? This action cannot be undone.'
            : 'Are you sure you want to permanently delete this file? This action cannot be undone.',
        style: TextStyle(color: Colors.grey[300]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
  return result ?? false;
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

  late List<VaultFileMeta> _files;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  bool get _isMediaGrid =>
      widget.category.type == VaultCategoryType.photos ||
      widget.category.type == VaultCategoryType.videos;

  @override
  void initState() {
    super.initState();
    _files = VaultService.instance.getFilesByCategory(widget.category.type);
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final confirmed = await confirmDelete(context, _selectedIds.length);
    if (!confirmed) return;

    final ids = _selectedIds.toList();
    await VaultService.instance.deleteFiles(ids);

    for (final id in ids) {
      _photoCache.remove(id);
      _videoThumbCache.remove(id);
    }

    setState(() {
      _files.removeWhere((f) => ids.contains(f.id));
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Widget _buildBrokenTile() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined, color: Colors.grey[600]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: _selectionMode ? _buildSelectionAppBar() : _buildDefaultAppBar(),
        body: _files.isEmpty
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
            : (_isMediaGrid ? _buildMediaGrid() : _buildDocumentList()),
      ),
    );
  }

  PreferredSizeWidget _buildDefaultAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF121212),
      elevation: 0,
      title: Text(widget.category.label, style: const TextStyle(color: Colors.white)),
      iconTheme: const IconThemeData(color: Colors.white),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF121212),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: _exitSelectionMode,
      ),
      title: Text('${_selectedIds.length} selected',
          style: const TextStyle(color: Colors.white)),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
        ),
      ],
    );
  }

  Widget _buildMediaGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final meta = _files[index];
        final tile = widget.category.type == VaultCategoryType.photos
            ? _buildPhotoTile(meta)
            : _buildVideoTile(meta);

        if (_selectionMode) return tile;

        return Dismissible(
          key: ValueKey(meta.id),
          direction: DismissDirection.horizontal,
          background: _dismissBackground(Alignment.centerLeft),
          secondaryBackground: _dismissBackground(Alignment.centerRight),
          confirmDismiss: (_) => confirmDelete(context, 1),
          onDismissed: (_) async {
            await VaultService.instance.deleteFiles([meta.id]);
            _photoCache.remove(meta.id);
            _videoThumbCache.remove(meta.id);
            setState(() => _files.removeWhere((f) => f.id == meta.id));
          },
          child: tile,
        );
      },
    );
  }

  Widget _dismissBackground(Alignment alignment) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }

  Widget _buildSelectableOverlay(String id, Widget child) {
    final selected = _selectedIds.contains(id);
    return GestureDetector(
      onLongPress: () => _enterSelectionMode(id),
      onTap: () {
        if (_selectionMode) {
          _toggleSelection(id);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: selected ? 0.5 : 1.0, child: child),
          if (_selectionMode)
            Positioned(
              top: 6,
              right: 6,
              child: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? const Color(0xFF0A84FF) : Colors.white70,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoTile(VaultFileMeta meta) {
    final future = _photoCache.putIfAbsent(
        meta.id, () => VaultService.instance.getDecryptedBytes(meta.id));

    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildBrokenTile();
        }
        if (!snapshot.hasData) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }

        final image = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            cacheWidth: 300,
            errorBuilder: (context, error, stack) => _buildBrokenTile(),
          ),
        );

        return _buildSelectableOverlay(
          meta.id,
          GestureDetector(
            onTap: _selectionMode
                ? null
                : () => Navigator.of(context)
                    .push<bool>(
                      MaterialPageRoute(
                        builder: (_) => PhotoViewerScreen(
                          id: meta.id,
                          bytes: snapshot.data!,
                        ),
                      ),
                    )
                    .then((deleted) {
                      if (deleted == true) {
                        _photoCache.remove(meta.id);
                        setState(() => _files.removeWhere((f) => f.id == meta.id));
                      }
                    }),
            child: image,
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

        final tile = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              thumb != null
                  ? Image.memory(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        color: const Color(0xFF1E1E1E),
                      ),
                    )
                  : Container(color: const Color(0xFF1E1E1E)),
              const Center(
                child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 36),
              ),
            ],
          ),
        );

        return _buildSelectableOverlay(
          meta.id,
          GestureDetector(
            onTap: _selectionMode
                ? null
                : () => Navigator.of(context)
                    .push<bool>(
                      MaterialPageRoute(
                        builder: (_) => VideoViewerScreen(
                          id: meta.id,
                          extension: meta.extension,
                        ),
                      ),
                    )
                    .then((deleted) {
                      if (deleted == true) {
                        _videoThumbCache.remove(meta.id);
                        setState(() => _files.removeWhere((f) => f.id == meta.id));
                      }
                    }),
            child: tile,
          ),
        );
      },
    );
  }

  Widget _buildDocumentList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final meta = _files[index];
        final selected = _selectedIds.contains(meta.id);

        final card = Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            leading: _selectionMode
                ? Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: selected ? const Color(0xFF0A84FF) : Colors.grey,
                  )
                : Icon(_iconForCategory(widget.category.type), color: const Color(0xFF0A84FF)),
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
            onLongPress: () => _enterSelectionMode(meta.id),
            onTap: () {
              if (_selectionMode) {
                _toggleSelection(meta.id);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Preview not available for this file type')),
                );
              }
            },
          ),
        );

        if (_selectionMode) return card;

        return Dismissible(
          key: ValueKey(meta.id),
          direction: DismissDirection.horizontal,
          background: _dismissBackground(Alignment.centerLeft),
          secondaryBackground: _dismissBackground(Alignment.centerRight),
          confirmDismiss: (_) => confirmDelete(context, 1),
          onDismissed: (_) async {
            await VaultService.instance.deleteFiles([meta.id]);
            setState(() => _files.removeWhere((f) => f.id == meta.id));
          },
          child: card,
        );
      },
    );
  }
}

class PhotoViewerScreen extends StatelessWidget {
  final String id;
  final Uint8List bytes;

  const PhotoViewerScreen({super.key, required this.id, required this.bytes});

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await confirmDelete(context, 1);
    if (!confirmed) return;

    await VaultService.instance.deleteFiles([id]);
    if (context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _handleDelete(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.memory(
            bytes,
            errorBuilder: (context, error, stack) => Icon(
              Icons.broken_image_outlined,
              color: Colors.grey[600],
              size: 64,
            ),
          ),
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
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await confirmDelete(context, 1);
    if (!confirmed) return;

    await VaultService.instance.deleteFiles([widget.id]);
    if (mounted) Navigator.of(context).pop(true);
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
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _handleDelete,
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: Color(0xFF0A84FF))
            : _hasError
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.grey[600], size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Unable to play this video',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  )
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