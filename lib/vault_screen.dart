import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:async';
import 'models.dart';
import 'vault_service.dart';

const List<VaultCategory> vaultCategories = [
  VaultCategory(
    type: VaultCategoryType.photos,
    label: 'Фото',
    icon: 'image',
  ),
  VaultCategory(
    type: VaultCategoryType.videos,
    label: 'Видео',
    icon: 'video',
  ),
  VaultCategory(
    type: VaultCategoryType.documents,
    label: 'Документы',
    icon: 'doc',
  ),
  VaultCategory(
    type: VaultCategoryType.other,
    label: 'Другое',
    icon: 'other',
  ),
];

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
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _buildProgressDialog(),
    ));

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
        content: Text(
          'Импортировано файлов: ${imported.length} из ${files.length}',
        ),
      ),
    );
  }

  Future<bool?> _showLongOperationWarning(int count) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Импорт файлов',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Будет импортировано файлов: $count.\n\n'
          'Процесс включает шифрование каждого файла и может занять '
          'некоторое время в зависимости от их размера. '
          'Не закрывайте приложение во время импорта.',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Начать',
                style: TextStyle(color: Color(0xFF0A84FF))),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Импорт файлов...',
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
                    '${progress.completed} из ${progress.total} '
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
        title: const Text('Хранилище', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.lock_outline, color: Colors.white),
          tooltip: 'Заблокировать',
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
        label:
            const Text('Добавить файл', style: TextStyle(color: Colors.white)),
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
              Text('$count файлов',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class CategoryFilesScreen extends StatelessWidget {
  final VaultCategory category;

  const CategoryFilesScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final files = VaultService.instance.getFilesByCategory(category.type);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title:
            Text(category.label, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: files.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_iconForCategory(category.type),
                      size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  Text('Пока нет файлов',
                      style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final meta = files[index];
                return Card(
                  color: const Color(0xFF1E1E1E),
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: Icon(_iconForCategory(category.type),
                        color: const Color(0xFF0A84FF)),
                    title: Text(meta.originalName,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${(meta.sizeInBytes / 1024).toStringAsFixed(1)} КБ',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
    );
  }
}