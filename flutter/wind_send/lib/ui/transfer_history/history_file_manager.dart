import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/file_manager.dart';
import '../../utils/logger.dart';
import '../../utils/utils.dart';
import 'history.dart';

/// Converts persisted history metadata into an explicit filesystem target.
///
/// File metadata is authoritative because it retains the file/directory kind
/// after deletion. The legacy payload path is only a fallback for records that
/// predate the structured file list.
Future<FileManagerTarget?> resolveHistoryFileManagerTarget(
  TransferHistoryItem item,
) async {
  final firstFile = item.filesPayload.firstFile;
  if (firstFile != null && firstFile.path.isNotEmpty) {
    final path = await _resolvePersistedPath(firstFile.path);
    if (path == null) return null;
    return firstFile.isDirectory
        ? FileManagerTarget.directory(path)
        : FileManagerTarget.file(path);
  }

  final payloadPath = item.payloadPath;
  if (payloadPath == null || payloadPath.isEmpty) return null;

  final path = await _resolvePersistedPath(payloadPath);
  if (path == null) return null;
  final type = await FileSystemEntity.type(path);
  return type == FileSystemEntityType.directory
      ? FileManagerTarget.directory(path)
      : FileManagerTarget.file(path);
}

Future<String?> _resolvePersistedPath(String path) async {
  if (p.isAbsolute(path)) return path;

  try {
    return await toAbsolutePayloadPath(path);
  } catch (error, stackTrace) {
    SharedLogger().logger.w(
      'Unable to resolve persisted history path: $path',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}
