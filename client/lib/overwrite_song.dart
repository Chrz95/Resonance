import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'api.dart';

Future<String> songDigest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Stage beside the destination, back up before replacement, and roll back
/// ordinary I/O failures. Never use a workspace/cache path as the target.
Future<String> overwriteSong(
  File target,
  Uint8List bytes,
  String expected, {
  Future<void> Function(File staged, File target)? commit,
}) async {
  if (await FileSystemEntity.type(target.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw ApiException(
      'Choose an existing regular audio file, not a link or folder.',
    );
  }
  if (await songDigest(target) != expected) {
    throw ApiException(
      'This file differs from the imported song or the last overwrite. Import it again before replacing it.',
    );
  }
  if (bytes.isEmpty) throw ApiException('The tagged output is empty.');
  final staging = await target.parent.createTemp('.resonance-overwrite-');
  final backup = File('${staging.path}/original-backup');
  var replacing = false;
  var keepBackup = false;
  try {
    final output = File('${staging.path}/tagged');
    await output.writeAsBytes(bytes, flush: true);
    final digest = sha256.convert(bytes).toString();
    if (await songDigest(output) != digest)
      throw ApiException('Could not verify the staged output.');
    await target.copy(backup.path);
    if (await songDigest(backup) != expected ||
        await songDigest(target) != expected) {
      throw ApiException(
        'The original changed while saving. No overwrite was performed.',
      );
    }
    replacing = true;
    if (commit == null) {
      await output.rename(target.path);
    } else {
      await commit(output, target);
    }
    if (await songDigest(target) != digest)
      throw ApiException('The replacement could not be verified.');
    return digest;
  } catch (error) {
    if (replacing) {
      try {
        await backup.copy(target.path);
        if (await songDigest(target) != expected)
          throw StateError('Restore verification failed.');
      } catch (_) {
        keepBackup = true;
        throw ApiException(
          'Overwrite failed. Recover the original from ${backup.path}. $error',
        );
      }
    }
    rethrow;
  } finally {
    if (!keepBackup) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {
        /* Recovery data can be removed later. */
      }
    }
  }
}
