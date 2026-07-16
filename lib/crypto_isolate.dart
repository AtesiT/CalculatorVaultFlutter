import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const int cryptoBlockSize = 16;
const int cryptoChunkSize = 4 * 1024 * 1024;

enum CryptoOperation { encryptFile, decryptFile, decryptToBytes }

class CryptoProgressMessage {
  final int bytesProcessed;
  final int totalBytes;

  const CryptoProgressMessage(this.bytesProcessed, this.totalBytes);
}

class CryptoResultMessage {
  final bool success;
  final String? errorMessage;
  final Uint8List? resultBytes;

  const CryptoResultMessage({
    required this.success,
    this.errorMessage,
    this.resultBytes,
  });
}

class CryptoTaskRequest {
  final CryptoOperation operation;
  final String? inputPath;
  final String? outputPath;
  final Uint8List keyBytes;
  final SendPort sendPort;

  const CryptoTaskRequest({
    required this.operation,
    this.inputPath,
    this.outputPath,
    required this.keyBytes,
    required this.sendPort,
  });
}

Uint8List _generateRandomBytes(int length) {
  final rnd = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = rnd.nextInt(256);
  }
  return bytes;
}

Uint8List _concat(Uint8List a, Uint8List b) {
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  final result = Uint8List(a.length + b.length);
  result.setRange(0, a.length, a);
  result.setRange(a.length, result.length, b);
  return result;
}

Uint8List _pkcs7Pad(Uint8List data) {
  final padLength = cryptoBlockSize - (data.length % cryptoBlockSize);
  final padded = Uint8List(data.length + padLength);
  padded.setRange(0, data.length, data);
  padded.fillRange(data.length, padded.length, padLength);
  return padded;
}

Uint8List _pkcs7Unpad(Uint8List data) {
  if (data.isEmpty) return data;
  final padLength = data[data.length - 1];
  if (padLength < 1 || padLength > cryptoBlockSize || padLength > data.length) {
    throw const FormatException('Invalid padding encountered during decryption');
  }
  return data.sublist(0, data.length - padLength);
}

CBCBlockCipher _buildCipher(Uint8List keyBytes, Uint8List ivBytes, bool forEncryption) {
  final cipher = CBCBlockCipher(AESEngine());
  final params = ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes);
  cipher.init(forEncryption, params);
  return cipher;
}

Uint8List _processBlocks(BlockCipher cipher, Uint8List data) {
  final output = Uint8List(data.length);
  var offset = 0;
  while (offset < data.length) {
    cipher.processBlock(data, offset, output, offset);
    offset += cryptoBlockSize;
  }
  return output;
}

Future<void> _encryptFileStreaming(CryptoTaskRequest request) async {
  final sourceFile = File(request.inputPath!);
  final destFile = File(request.outputPath!);
  RandomAccessFile? raf;
  IOSink? sink;

  try {
    final totalBytes = await sourceFile.length();
    final iv = _generateRandomBytes(cryptoBlockSize);
    final cipher = _buildCipher(request.keyBytes, iv, true);

    raf = await sourceFile.open();
    sink = destFile.openWrite();
    sink.add(iv);

    Uint8List pending = Uint8List(0);
    int bytesProcessed = 0;

    while (true) {
      final chunk = await raf.read(cryptoChunkSize);

      if (chunk.isEmpty) {
        final finalPadded = _pkcs7Pad(pending);
        sink.add(_processBlocks(cipher, finalPadded));
        request.sendPort.send(CryptoProgressMessage(totalBytes, totalBytes));
        break;
      }

      bytesProcessed += chunk.length;
      final combined = _concat(pending, chunk);
      final processableLen = combined.length - (combined.length % cryptoBlockSize);
      final toProcess = combined.sublist(0, processableLen);
      pending = combined.sublist(processableLen);

      if (toProcess.isNotEmpty) {
        sink.add(_processBlocks(cipher, toProcess));
      }

      request.sendPort.send(CryptoProgressMessage(bytesProcessed, totalBytes));
    }

    await sink.flush();
    await sink.close();
    await raf.close();

    request.sendPort.send(const CryptoResultMessage(success: true));
  } catch (e) {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      await raf?.close();
    } catch (_) {}
    if (await destFile.exists()) {
      try {
        await destFile.delete();
      } catch (_) {}
    }
    request.sendPort.send(CryptoResultMessage(success: false, errorMessage: e.toString()));
  }
}

Future<void> _decryptFileStreaming(CryptoTaskRequest request) async {
  final sourceFile = File(request.inputPath!);
  final destFile = File(request.outputPath!);
  RandomAccessFile? raf;
  IOSink? sink;

  try {
    final fullLength = await sourceFile.length();
    final totalBytes = fullLength - cryptoBlockSize;

    raf = await sourceFile.open();
    final ivBytes = await raf.read(cryptoBlockSize);
    final cipher = _buildCipher(request.keyBytes, ivBytes, false);

    sink = destFile.openWrite();

    Uint8List pendingCipher = Uint8List(0);
    Uint8List? heldPlain;
    int bytesProcessed = 0;

    while (true) {
      final chunk = await raf.read(cryptoChunkSize);

      if (chunk.isEmpty) {
        if (heldPlain != null) {
          sink.add(_pkcs7Unpad(heldPlain));
        }
        request.sendPort.send(CryptoProgressMessage(totalBytes, totalBytes));
        break;
      }

      bytesProcessed += chunk.length;
      final combinedCipher = _concat(pendingCipher, chunk);
      final processableLen = combinedCipher.length - (combinedCipher.length % cryptoBlockSize);
      final toProcess = combinedCipher.sublist(0, processableLen);
      pendingCipher = combinedCipher.sublist(processableLen);

      if (toProcess.isNotEmpty) {
        final decrypted = _processBlocks(cipher, toProcess);
        final combinedPlain = _concat(heldPlain ?? Uint8List(0), decrypted);

        if (combinedPlain.length > cryptoBlockSize) {
          final writeLen = combinedPlain.length - cryptoBlockSize;
          sink.add(combinedPlain.sublist(0, writeLen));
          heldPlain = combinedPlain.sublist(writeLen);
        } else {
          heldPlain = combinedPlain;
        }
      }

      request.sendPort.send(CryptoProgressMessage(bytesProcessed, totalBytes));
    }

    await sink.flush();
    await sink.close();
    await raf.close();

    request.sendPort.send(const CryptoResultMessage(success: true));
  } catch (e) {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      await raf?.close();
    } catch (_) {}
    if (await destFile.exists()) {
      try {
        await destFile.delete();
      } catch (_) {}
    }
    request.sendPort.send(CryptoResultMessage(success: false, errorMessage: e.toString()));
  }
}

Future<void> _decryptToBytesStreaming(CryptoTaskRequest request) async {
  final sourceFile = File(request.inputPath!);
  RandomAccessFile? raf;

  try {
    final fullLength = await sourceFile.length();
    final totalBytes = fullLength - cryptoBlockSize;

    raf = await sourceFile.open();
    final ivBytes = await raf.read(cryptoBlockSize);
    final cipher = _buildCipher(request.keyBytes, ivBytes, false);

    final output = BytesBuilder(copy: false);
    Uint8List pendingCipher = Uint8List(0);
    Uint8List? heldPlain;
    int bytesProcessed = 0;

    while (true) {
      final chunk = await raf.read(cryptoChunkSize);

      if (chunk.isEmpty) {
        if (heldPlain != null) {
          output.add(_pkcs7Unpad(heldPlain));
        }
        request.sendPort.send(CryptoProgressMessage(totalBytes, totalBytes));
        break;
      }

      bytesProcessed += chunk.length;
      final combinedCipher = _concat(pendingCipher, chunk);
      final processableLen = combinedCipher.length - (combinedCipher.length % cryptoBlockSize);
      final toProcess = combinedCipher.sublist(0, processableLen);
      pendingCipher = combinedCipher.sublist(processableLen);

      if (toProcess.isNotEmpty) {
        final decrypted = _processBlocks(cipher, toProcess);
        final combinedPlain = _concat(heldPlain ?? Uint8List(0), decrypted);

        if (combinedPlain.length > cryptoBlockSize) {
          final writeLen = combinedPlain.length - cryptoBlockSize;
          output.add(combinedPlain.sublist(0, writeLen));
          heldPlain = combinedPlain.sublist(writeLen);
        } else {
          heldPlain = combinedPlain;
        }
      }

      request.sendPort.send(CryptoProgressMessage(bytesProcessed, totalBytes));
    }

    await raf.close();

    request.sendPort.send(
      CryptoResultMessage(success: true, resultBytes: output.takeBytes()),
    );
  } catch (e) {
    try {
      await raf?.close();
    } catch (_) {}
    request.sendPort.send(CryptoResultMessage(success: false, errorMessage: e.toString()));
  }
}

Future<void> _runTask(CryptoTaskRequest request) async {
  switch (request.operation) {
    case CryptoOperation.encryptFile:
      await _encryptFileStreaming(request);
      break;
    case CryptoOperation.decryptFile:
      await _decryptFileStreaming(request);
      break;
    case CryptoOperation.decryptToBytes:
      await _decryptToBytesStreaming(request);
      break;
  }
}

void cryptoIsolateEntryPoint(CryptoTaskRequest request) {
  _runTask(request);
}

Future<Uint8List?> _runIsolateTask(
  CryptoOperation operation, {
  String? inputPath,
  String? outputPath,
  required Uint8List keyBytes,
  void Function(int done, int total)? onProgress,
}) async {
  final receivePort = ReceivePort();
  final completer = Completer<Uint8List?>();

  final request = CryptoTaskRequest(
    operation: operation,
    inputPath: inputPath,
    outputPath: outputPath,
    keyBytes: keyBytes,
    sendPort: receivePort.sendPort,
  );

  final subscription = receivePort.listen((message) {
    if (message is CryptoProgressMessage) {
      onProgress?.call(message.bytesProcessed, message.totalBytes);
    } else if (message is CryptoResultMessage) {
      if (message.success) {
        if (!completer.isCompleted) completer.complete(message.resultBytes);
      } else {
        if (!completer.isCompleted) {
          completer.completeError(Exception(message.errorMessage ?? 'Crypto task failed'));
        }
      }
    }
  });

  final isolate = await Isolate.spawn(cryptoIsolateEntryPoint, request);

  try {
    return await completer.future;
  } finally {
    await subscription.cancel();
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

Future<void> encryptFileInIsolate({
  required String inputPath,
  required String outputPath,
  required Uint8List keyBytes,
  void Function(int done, int total)? onProgress,
}) async {
  await _runIsolateTask(
    CryptoOperation.encryptFile,
    inputPath: inputPath,
    outputPath: outputPath,
    keyBytes: keyBytes,
    onProgress: onProgress,
  );
}

Future<void> decryptFileInIsolate({
  required String inputPath,
  required String outputPath,
  required Uint8List keyBytes,
  void Function(int done, int total)? onProgress,
}) async {
  await _runIsolateTask(
    CryptoOperation.decryptFile,
    inputPath: inputPath,
    outputPath: outputPath,
    keyBytes: keyBytes,
    onProgress: onProgress,
  );
}

Future<Uint8List> decryptToBytesInIsolate({
  required String inputPath,
  required Uint8List keyBytes,
  void Function(int done, int total)? onProgress,
}) async {
  final result = await _runIsolateTask(
    CryptoOperation.decryptToBytes,
    inputPath: inputPath,
    keyBytes: keyBytes,
    onProgress: onProgress,
  );
  return result ?? Uint8List(0);
}