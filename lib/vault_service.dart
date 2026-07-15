import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'models.dart';

enum VaultMode { real, decoy }

enum CodeCheckResult { none, real, duress }

class VaultService {
  VaultService._internal();
  static final VaultService instance = VaultService._internal();

  static const String _vaultFolderName = '.vault_secure';
  static const String _decoyFolderName = '.vault_secure_decoy';
  static const String _secureKeyStorageKey = 'vault_encryption_key_v1';
  static const String _metaBoxName = 'vault_files_meta';
  static const String _decoyMetaBoxName = 'vault_decoy_meta';

  static const String _realCodeHashKey = 'vault_real_code_hash_v1';
  static const String _duressCodeHashKey = 'vault_duress_code_hash_v1';
  static const String _hashSalt = 'CalculatorVaultSalt_v1';
  static const String _defaultRealCode = '0101';

  final _secureStorage = const FlutterSecureStorage();
  final _uuid = const Uuid();

  Directory? _cachedVaultDir;
  Directory? _cachedDecoyDir;
  enc.Key? _cachedKey;
  Box<VaultFileMeta>? _metaBox;
  Box<VaultFileMeta>? _decoyMetaBox;

  bool isVaultOpen = false;

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(VaultFileMetaAdapter());
    }
    _metaBox = await Hive.openBox<VaultFileMeta>(_metaBoxName);
    _decoyMetaBox = await Hive.openBox<VaultFileMeta>(_decoyMetaBoxName);

    await getVaultDirectory(VaultMode.real);
    await getVaultDirectory(VaultMode.decoy);

    final existingRealHash = await _secureStorage.read(key: _realCodeHashKey);
    if (existingRealHash == null) {
      await _secureStorage.write(
        key: _realCodeHashKey,
        value: _hashCode(_defaultRealCode),
      );
    }
  }

  Box<VaultFileMeta> _box(VaultMode mode) {
    final box = mode == VaultMode.real ? _metaBox : _decoyMetaBox;
    if (box == null) {
      throw StateError('VaultService is not initialized. Call init().');
    }
    return box;
  }

  Future<Directory> getVaultDirectory(VaultMode mode) async {
    if (mode == VaultMode.real && _cachedVaultDir != null) return _cachedVaultDir!;
    if (mode == VaultMode.decoy && _cachedDecoyDir != null) return _cachedDecoyDir!;

    final appDocDir = await getApplicationDocumentsDirectory();
    final folderName = mode == VaultMode.real ? _vaultFolderName : _decoyFolderName;
    final dir = Directory(p.join(appDocDir.path, folderName));

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final noMediaFile = File(p.join(dir.path, '.nomedia'));
    if (!await noMediaFile.exists()) {
      await noMediaFile.create();
    }

    if (mode == VaultMode.real) {
      _cachedVaultDir = dir;
    } else {
      _cachedDecoyDir = dir;
    }
    return dir;
  }

  String _hashCode(String rawCode) {
    final bytes = utf8.encode('$_hashSalt::$rawCode');
    return sha256.convert(bytes).toString();
  }

  Future<CodeCheckResult> checkCode(String rawDigits) async {
    if (rawDigits.isEmpty) return CodeCheckResult.none;

    final candidateHash = _hashCode(rawDigits);

    final realHash = await _secureStorage.read(key: _realCodeHashKey);
    if (realHash != null && candidateHash == realHash) {
      return CodeCheckResult.real;
    }

    final duressHash = await _secureStorage.read(key: _duressCodeHashKey);
    if (duressHash != null && candidateHash == duressHash) {
      return CodeCheckResult.duress;
    }

    return CodeCheckResult.none;
  }

  Future<bool> setRealCode(String newCode) async {
    final newHash = _hashCode(newCode);
    final duressHash = await _secureStorage.read(key: _duressCodeHashKey);
    if (duressHash != null && newHash == duressHash) {
      return false;
    }
    await _secureStorage.write(key: _realCodeHashKey, value: newHash);
    return true;
  }

  Future<bool> setDuressCode(String newCode) async {
    final newHash = _hashCode(newCode);
    final realHash = await _secureStorage.read(key: _realCodeHashKey);
    if (realHash != null && newHash == realHash) {
      return false;
    }
    await _secureStorage.write(key: _duressCodeHashKey, value: newHash);
    return true;
  }

  Future<void> clearDuressCode() async {
    await _secureStorage.delete(key: _duressCodeHashKey);
  }

  Future<bool> isDuressCodeSet() async {
    final hash = await _secureStorage.read(key: _duressCodeHashKey);
    return hash != null;
  }

  Future<void> wipeDecoyVault() async {
    final ids = _box(VaultMode.decoy).values.map((f) => f.id).toList();
    await deleteFiles(VaultMode.decoy, ids);
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

  Future<File> _secureWriteFile(VaultMode mode, File sourceFile) async {
    final vaultDir = await getVaultDirectory(mode);
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

  Future<VaultFileMeta> _importSingleFile(
    VaultMode mode,
    PlatformFile platformFile,
  ) async {
    if (platformFile.path == null) {
      throw Exception('File path unavailable: ${platformFile.name}');
    }

    final sourceFile = File(platformFile.path!);
    final storedFile = await _secureWriteFile(mode, sourceFile);

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

    await _box(mode).put(meta.id, meta);
    return meta;
  }

  Future<List<VaultFileMeta>> importFiles(
    VaultMode mode,
    List<PlatformFile> files, {
    required void Function(int completed, int total, String currentFileName)
        onProgress,
  }) async {
    final results = <VaultFileMeta>[];

    for (int i = 0; i < files.length; i++) {
      onProgress(i, files.length, files[i].name);
      try {
        final meta = await _importSingleFile(mode, files[i]);
        results.add(meta);
      } catch (_) {
        continue;
      }
    }

    onProgress(files.length, files.length, '');
    return results;
  }

  List<VaultFileMeta> getAllFiles(VaultMode mode) => _box(mode).values.toList();

  List<VaultFileMeta> getFilesByCategory(
    VaultMode mode,
    VaultCategoryType category,
  ) =>
      _box(mode).values.where((f) => f.category == category).toList();

  Map<VaultCategoryType, int> getCategoryCounts(VaultMode mode) {
    final counts = {for (final c in VaultCategoryType.values) c: 0};
    for (final meta in _box(mode).values) {
      counts[meta.category] = (counts[meta.category] ?? 0) + 1;
    }
    return counts;
  }

  Future<Uint8List> getDecryptedBytes(VaultMode mode, String id) async {
    final vaultDir = await getVaultDirectory(mode);
    final vaultFile = File(p.join(vaultDir.path, id));
    return readDecryptedBytes(vaultFile);
  }

  Future<File> prepareTempPlaybackFile(
    VaultMode mode,
    String id,
    String extension,
  ) async {
    final vaultDir = await getVaultDirectory(mode);
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

  Future<Uint8List?> getVideoThumbnail(
    VaultMode mode,
    String id,
    String extension,
  ) async {
    File? tempFile;
    try {
      tempFile = await prepareTempPlaybackFile(mode, id, extension);
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

  Future<void> deleteFiles(VaultMode mode, List<String> ids) async {
    final vaultDir = await getVaultDirectory(mode);
    for (final id in ids) {
      final file = File(p.join(vaultDir.path, id));
      if (await file.exists()) {
        await file.delete();
      }
      await _box(mode).delete(id);
    }
  }
}