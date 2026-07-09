import 'package:hive/hive.dart';

enum VaultCategoryType { photos, videos, documents, other }

class VaultCategory {
  final VaultCategoryType type;
  final String label;
  final String icon;

  const VaultCategory({
    required this.type,
    required this.label,
    required this.icon,
  });
}

VaultCategoryType detectCategoryForExtension(String extension) {
  final ext = extension.toLowerCase().replaceAll('.', '');

  const photoExts = {'jpg', 'jpeg', 'png', 'heic', 'gif', 'bmp', 'webp'};
  const videoExts = {'mp4', 'mov', 'avi', 'mkv', '3gp', 'webm'};
  const docExts = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv'
  };

  if (photoExts.contains(ext)) return VaultCategoryType.photos;
  if (videoExts.contains(ext)) return VaultCategoryType.videos;
  if (docExts.contains(ext)) return VaultCategoryType.documents;
  return VaultCategoryType.other;
}

class VaultFileMeta extends HiveObject {
  final String id;
  final String originalName;
  final String storedFileName;
  final String extension;
  final int sizeInBytes;
  final int categoryIndex;
  final int dateAddedMillis;

  VaultFileMeta({
    required this.id,
    required this.originalName,
    required this.storedFileName,
    required this.extension,
    required this.sizeInBytes,
    required this.categoryIndex,
    required this.dateAddedMillis,
  });

  VaultCategoryType get category => VaultCategoryType.values[categoryIndex];

  DateTime get dateAdded =>
      DateTime.fromMillisecondsSinceEpoch(dateAddedMillis);
}

/// Ручной TypeAdapter — без кодогенерации build_runner.
class VaultFileMetaAdapter extends TypeAdapter<VaultFileMeta> {
  @override
  final int typeId = 0;

  @override
  VaultFileMeta read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VaultFileMeta(
      id: fields[0] as String,
      originalName: fields[1] as String,
      storedFileName: fields[2] as String,
      extension: fields[3] as String,
      sizeInBytes: fields[4] as int,
      categoryIndex: fields[5] as int,
      dateAddedMillis: fields[6] as int,
    );
  }

  @override
  void write(BinaryWriter writer, VaultFileMeta obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.originalName)
      ..writeByte(2)
      ..write(obj.storedFileName)
      ..writeByte(3)
      ..write(obj.extension)
      ..writeByte(4)
      ..write(obj.sizeInBytes)
      ..writeByte(5)
      ..write(obj.categoryIndex)
      ..writeByte(6)
      ..write(obj.dateAddedMillis);
  }
}