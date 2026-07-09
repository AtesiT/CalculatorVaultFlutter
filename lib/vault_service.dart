import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class VaultService {
  VaultService._internal();
  static final VaultService instance = VaultService._internal();

  static const String _vaultFolderName = '.vault_secure';
  static const String _secureKeyStorageKey = 'vault_encryption_key_v1';

  final _secureStorage = const FlutterSecureStorage();
  final _uuid = const Uuid();

  Directory? _cachedVaultDir;
  enc.Key? _cachedKey;

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

  // ---------- ШИФРОВАНИЕ / ДЕШИФРОВАНИЕ ----------

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

  Future<File> secureImportFile(File sourceFile) async {
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

  Future<void> deletePhysicalFile(File vaultFile) async {
    if (await vaultFile.exists()) {
      await vaultFile.delete();
    }
  }
}