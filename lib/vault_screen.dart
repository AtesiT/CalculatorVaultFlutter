import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final VaultMode mode;

  const VaultScreen({super.key, required this.mode});

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
      _fileCounts = VaultService.instance.getCategoryCounts(widget.mode);
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
      widget.mode,
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
            builder: (_) => CategoryFilesScreen(category: category, mode: widget.mode),
          ),
        )
        .then((_) => _refreshCounts());
  }

  void _lockVault() {
    Navigator.of(context).pop();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VaultSettingsScreen()),
    );
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
        actions: widget.mode == VaultMode.real
            ? [
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: Colors.white),
                  tooltip: 'Security Settings',
                  onPressed: _openSettings,
                ),
              ]
            : null,
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
  final VaultMode mode;

  const CategoryFilesScreen({super.key, required this.category, required this.mode});

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
    _files = VaultService.instance.getFilesByCategory(widget.mode, widget.category.type);
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
    await VaultService.instance.deleteFiles(widget.mode, ids);

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
            await VaultService.instance.deleteFiles(widget.mode, [meta.id]);
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
        meta.id, () => VaultService.instance.getDecryptedBytes(widget.mode, meta.id));

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
                          mode: widget.mode,
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
      () => VaultService.instance.getVideoThumbnail(widget.mode, meta.id, meta.extension),
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
                          mode: widget.mode,
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
            await VaultService.instance.deleteFiles(widget.mode, [meta.id]);
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
  final VaultMode mode;

  const PhotoViewerScreen({
    super.key,
    required this.id,
    required this.bytes,
    required this.mode,
  });

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await confirmDelete(context, 1);
    if (!confirmed) return;

    await VaultService.instance.deleteFiles(mode, [id]);
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
  final VaultMode mode;

  const VideoViewerScreen({
    super.key,
    required this.id,
    required this.extension,
    required this.mode,
  });

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
        widget.mode,
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

    await VaultService.instance.deleteFiles(widget.mode, [widget.id]);
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

class VaultSettingsScreen extends StatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  State<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends State<VaultSettingsScreen> {
  final _newCodeController = TextEditingController();
  final _confirmCodeController = TextEditingController();
  final _newDuressController = TextEditingController();
  final _confirmDuressController = TextEditingController();

  bool _duressEnabled = false;
  bool _loadingDuressState = true;

  @override
  void initState() {
    super.initState();
    _loadDuressState();
  }

  Future<void> _loadDuressState() async {
    final isSet = await VaultService.instance.isDuressCodeSet();
    if (!mounted) return;
    setState(() {
      _duressEnabled = isSet;
      _loadingDuressState = false;
    });
  }

  @override
  void dispose() {
    _newCodeController.dispose();
    _confirmCodeController.dispose();
    _newDuressController.dispose();
    _confirmDuressController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveRealCode() async {
    final newCode = _newCodeController.text;
    final confirmCode = _confirmCodeController.text;

    if (newCode.length < 4) {
      _showMessage('Code must be at least 4 digits long');
      return;
    }
    if (newCode != confirmCode) {
      _showMessage('Codes do not match');
      return;
    }

    final success = await VaultService.instance.setRealCode(newCode);
    if (!success) {
      _showMessage('This code is already used as the duress code');
      return;
    }

    _newCodeController.clear();
    _confirmCodeController.clear();
    _showMessage('Access code updated');
  }

  Future<void> _saveDuressCode() async {
    final newCode = _newDuressController.text;
    final confirmCode = _confirmDuressController.text;

    if (newCode.length < 4) {
      _showMessage('Code must be at least 4 digits long');
      return;
    }
    if (newCode != confirmCode) {
      _showMessage('Codes do not match');
      return;
    }

    final success = await VaultService.instance.setDuressCode(newCode);
    if (!success) {
      _showMessage('This code is already used as your access code');
      return;
    }

    _newDuressController.clear();
    _confirmDuressController.clear();
    setState(() => _duressEnabled = true);
    _showMessage('Duress code enabled');
  }

  Future<void> _disableDuress() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Disable Duress Code', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will remove the duress code protection.',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disable', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await VaultService.instance.clearDuressCode();
    setState(() => _duressEnabled = false);
    _showMessage('Duress code disabled');
  }

  Future<void> _wipeDecoyVault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Erase Decoy Vault', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently delete all files stored in the decoy vault. Continue?',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await VaultService.instance.wipeDecoyVault();
    if (mounted) _showMessage('Decoy vault content erased');
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3A3A3C)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0A84FF)),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text('Vault Security', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSectionTitle('Access Code'),
          const SizedBox(height: 8),
          Text(
            'This code opens your real vault from the calculator.',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _newCodeController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('New code'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCodeController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('Confirm new code'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A84FF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saveRealCode,
              child: const Text('Save Access Code', style: TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 36),
          const Divider(color: Color(0xFF2C2C2E)),
          const SizedBox(height: 20),
          _buildSectionTitle('Duress Code'),
          const SizedBox(height: 8),
          Text(
            'If entered instead of your access code, this opens a separate, '
            'empty decoy vault. Your real files stay hidden and untouched.',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_loadingDuressState)
            const Center(child: CircularProgressIndicator(color: Color(0xFF0A84FF)))
          else ...[
            if (_duressEnabled)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Duress code is active', style: TextStyle(color: Colors.white)),
                    ),
                    TextButton(
                      onPressed: _disableDuress,
                      child: const Text('Disable', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _newDuressController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration(_duressEnabled ? 'New duress code' : 'Set duress code'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmDuressController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration('Confirm duress code'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF0A84FF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _saveDuressCode,
                child: Text(
                  _duressEnabled ? 'Update Duress Code' : 'Enable Duress Code',
                  style: const TextStyle(color: Color(0xFF0A84FF)),
                ),
              ),
            ),
            if (_duressEnabled) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _wipeDecoyVault,
                  child: const Text('Erase Decoy Vault Content', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}