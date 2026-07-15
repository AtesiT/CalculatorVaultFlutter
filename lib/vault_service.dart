import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'models.dart';

class VaultService {
  VaultService._internal();
  static final VaultService instance = VaultService._internal();

  static const String _vaultFolderName = '.vault_secure';
  static const String _secureKeyStorageKey = 'vault_encryption_key_v1';
  static const String _metaBoxName = 'vault_files_meta';

  final _secureStorage = const FlutterSecureStorage();
  final _uuid = const Uuid();

  Directory? _cachedVaultDir;
  enc.Key? _cachedKey;
  Box<VaultFileMeta>? _metaBox;

  bool isVaultOpen = false;

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(VaultFileMetaAdapter());
    }
    _metaBox = await Hive.openBox<VaultFileMeta>(_metaBoxName);
    await getVaultDirectory();
  }

  Box<VaultFileMeta> get _box {
    if (_metaBox == null) {
      throw StateError('VaultService is not initialized. Call init().');
    }
    return _metaBox!;
  }

  Future<Directory> getVaultDirectory() async {
    if (_cachedVaultDir != null) return _cachedVaultDir!;

    final appDocDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(appDocDir.path, _vaultFolderName));

    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }

    final noMediaFile = File(p.join(vaultDir.path, '.nomedia'));
    if (!await noMediaFile.exists()) {
      await noMediaFile.create();
    }

    _cachedVaultDir = vaultDir;
    return vaultDir;
  }

  Future<enc.Key> _getEncryptionKey() async {
    if (_cachedKey != null) return _cachedKey!;

    String? storedKey = await _secureStorage.read(key: _secureKeyStorageKey);

    if (storedKey == null) {
      final newKey = enc.Key.fromSecureRandom(32);
      storedKey = base64Encode(newKey.bytes);
      await _secureStorage.write(key: _secureKeyStorageKey, value: storedKey);
    }

    _cachedKey = enc.Key(base64Decode(storedKey));
    return _cachedKey!;
  }

  Future<Uint8List> _encryptBytes(Uint8List plainBytes) async {
    final key = await _getEncryptionKey();
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);

    final result = BytesBuilder();
    result.add(iv.bytes);
    result.add(encrypted.bytes);
    return result.toBytes();
  }

  Future<Uint8List> _decryptBytes(Uint8List fileBytes) async {
    final key = await _getEncryptionKey();
    final iv = enc.IV(fileBytes.sublist(0, 16));
    final cipherBytes = fileBytes.sublist(16);

    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final decrypted =
        encrypter.decryptBytes(enc.Encrypted(cipherBytes), iv: iv);
    return Uint8List.fromList(decrypted);
  }

  Future<File> _secureWriteFile(File sourceFile) async {
    final vaultDir = await getVaultDirectory();
    final plainBytes = await sourceFile.readAsBytes();
    final encryptedBytes = await _encryptBytes(plainBytes);

    final newFileName = _uuid.v4();
    final newFile = File(p.join(vaultDir.path, newFileName));

    await newFile.writeAsBytes(encryptedBytes, flush: true);
    return newFile;
  }

  Future<Uint8List> readDecryptedBytes(File vaultFile) async {
    final encryptedBytes = await vaultFile.readAsBytes();
    return _decryptBytes(encryptedBytes);
  }

  Future<List<PlatformFile>> pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      return result?.files ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<VaultFileMeta> _importSingleFile(PlatformFile platformFile) async {
    if (platformFile.path == null) {
      throw Exception('File path unavailable: ${platformFile.name}');
    }

    final sourceFile = File(platformFile.path!);
    final storedFile = await _secureWriteFile(sourceFile);

    final ext = p.extension(platformFile.name).replaceAll('.', '');
    final category = detectCategoryForExtension(ext);
    final id = p.basename(storedFile.path);

    final meta = VaultFileMeta(
      id: id,
      originalName: platformFile.name,
      storedFileName: id,
      extension: ext,
      sizeInBytes: platformFile.size,
      categoryIndex: category.index,
      dateAddedMillis: DateTime.now().millisecondsSinceEpoch,
    );

    await _box.put(meta.id, meta);
    return meta;
  }

  Future<List<VaultFileMeta>> importFiles(
    List<PlatformFile> files, {
    required void Function(int completed, int total, String currentFileName)
        onProgress,
  }) async {
    final results = <VaultFileMeta>[];

    for (int i = 0; i < files.length; i++) {
      onProgress(i, files.length, files[i].name);
      try {
        final meta = await _importSingleFile(files[i]);
        results.add(meta);
      } catch (_) {
        continue;
      }
    }

    onProgress(files.length, files.length, '');
    return results;
  }

  List<VaultFileMeta> getAllFiles() => _box.values.toList();

  List<VaultFileMeta> getFilesByCategory(VaultCategoryType category) =>
      _box.values.where((f) => f.category == category).toList();

  Map<VaultCategoryType, int> getCategoryCounts() {
    final counts = {for (final c in VaultCategoryType.values) c: 0};
    for (final meta in _box.values) {
      counts[meta.category] = (counts[meta.category] ?? 0) + 1;
    }
    return counts;
  }

  Future<Uint8List> getDecryptedBytes(String id) async {
    final vaultDir = await getVaultDirectory();
    final vaultFile = File(p.join(vaultDir.path, id));
    return readDecryptedBytes(vaultFile);
  }

  Future<File> prepareTempPlaybackFile(String id, String extension) async {
    final vaultDir = await getVaultDirectory();
    final vaultFile = File(p.join(vaultDir.path, id));
    final decrypted = await readDecryptedBytes(vaultFile);

    final tempDir = await getTemporaryDirectory();
    final suffix = extension.isNotEmpty ? '.$extension' : '';
    final tempFile = File(p.join(tempDir.path, '$id$suffix'));

    await tempFile.writeAsBytes(decrypted, flush: true);
    return tempFile;
  }

  Future<void> deleteTempFile(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Uint8List?> getVideoThumbnail(String id, String extension) async {
    File? tempFile;
    try {
      tempFile = await prepareTempPlaybackFile(id, extension);
      final bytes = await VideoThumbnail.thumbnailData(
        video: tempFile.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 250,
        quality: 60,
      );
      return bytes;
    } catch (_) {
      return null;
    } finally {
      if (tempFile != null) {
        await deleteTempFile(tempFile);
      }
    }
  }

  Future<void> deleteFiles(List<String> ids) async {
    final vaultDir = await getVaultDirectory();
    for (final id in ids) {
      final file = File(p.join(vaultDir.path, id));
      if (await file.exists()) {
        await file.delete();
      }
      await _box.delete(id);
    }
  }
}