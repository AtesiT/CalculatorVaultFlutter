import 'package:flutter/material.dart';

enum VaultCategoryType { photos, videos, documents, other }

class VaultCategory {
  final VaultCategoryType type;
  final String label;
  final IconData icon;

  const VaultCategory({
    required this.type,
    required this.label,
    required this.icon,
  });
}

const List<VaultCategory> vaultCategories = [
  VaultCategory(
    type: VaultCategoryType.photos,
    label: 'Фото',
    icon: Icons.image_outlined,
  ),
  VaultCategory(
    type: VaultCategoryType.videos,
    label: 'Видео',
    icon: Icons.videocam_outlined,
  ),
  VaultCategory(
    type: VaultCategoryType.documents,
    label: 'Документы',
    icon: Icons.description_outlined,
  ),
  VaultCategory(
    type: VaultCategoryType.other,
    label: 'Другое',
    icon: Icons.folder_outlined,
  ),
];

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final Map<VaultCategoryType, int> _fileCounts = {
    VaultCategoryType.photos: 0,
    VaultCategoryType.videos: 0,
    VaultCategoryType.documents: 0,
    VaultCategoryType.other: 0,
  };

  void _onAddFilePressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Импорт файлов будет добавлен в Stage 7')),
    );
  }

  void _openCategory(VaultCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryFilesScreen(category: category),
      ),
    );
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
        label: const Text(
          'Добавить файл',
          style: TextStyle(color: Colors.white),
        ),
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
              Icon(category.icon, size: 40, color: const Color(0xFF0A84FF)),
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
              Text(
                '$count файлов',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
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
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: Text(
          category.label,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(category.icon, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              'Пока нет файлов',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '(реальные файлы появятся в Stage 8)',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}