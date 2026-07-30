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
  final targets = await resolveHistoryFileManagerTargets(item);
  return targets.isEmpty ? null : targets.first;
}

/// Resolves every top-level history entry while preserving whether it was a
/// file or directory. The persisted kind remains authoritative after deletion.
Future<List<FileManagerTarget>> resolveHistoryFileManagerTargets(
  TransferHistoryItem item,
) async {
  final targets = <FileManagerTarget>[];
  for (final file in item.filesPayload.files) {
    if (file.path.isEmpty) continue;

    final path = await resolveHistoryPersistedPath(file.path);
    if (path == null) continue;
    targets.add(
      file.isDirectory
          ? FileManagerTarget.directory(path)
          : FileManagerTarget.file(path),
    );
  }
  if (targets.isNotEmpty) return targets;

  final payloadPath = item.payloadPath;
  if (payloadPath == null || payloadPath.isEmpty) return targets;

  final path = await resolveHistoryPersistedPath(payloadPath);
  if (path == null) return targets;
  final type = await FileSystemEntity.type(path);
  targets.add(
    type == FileSystemEntityType.directory
        ? FileManagerTarget.directory(path)
        : FileManagerTarget.file(path),
  );
  return targets;
}

Future<String?> resolveHistoryPersistedPath(String path) async {
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
