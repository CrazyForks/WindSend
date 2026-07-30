import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wind_send/ui/transfer_history/history.dart';
import 'package:wind_send/ui/transfer_history/history_file_manager.dart';
import 'package:wind_send/utils/file_manager.dart';

void main() {
  group('resolveFileManagerDirectory', () {
    test('opens a deleted file containing directory', () async {
      final root = p.rootPrefix(p.absolute('history'));
      final directory = p.join(root, 'storage', 'WindSend', 'backup');
      final file = p.join(directory, 'deleted.act');

      final result = await resolveFileManagerDirectory(
        FileManagerTarget.file(file),
        directoryExists: (path) async => path == directory,
      );

      expect(result, directory);
    });

    test('walks up to the nearest surviving directory', () async {
      final root = p.rootPrefix(p.absolute('history'));
      final surviving = p.join(root, 'storage', 'WindSend');
      final deletedDirectory = p.join(surviving, 'deleted', 'nested');

      final result = await resolveFileManagerDirectory(
        FileManagerTarget.directory(deletedDirectory),
        directoryExists: (path) async => path == surviving,
      );

      expect(result, surviving);
    });

    test('returns null when no ancestor can be opened', () async {
      final target = p.absolute('missing', 'file.txt');

      final result = await resolveFileManagerDirectory(
        FileManagerTarget.file(target),
        directoryExists: (_) async => false,
      );

      expect(result, isNull);
    });
  });

  group('resolveHistoryFileManagerTarget', () {
    test('preserves file kind without probing a deleted path', () async {
      final filePath = p.absolute('storage', 'WindSend', 'deleted.act');
      final item = _historyItem(
        FileInfo(
          name: 'deleted.act',
          size: 12,
          path: filePath,
          isDirectory: false,
        ),
      );

      final target = await resolveHistoryFileManagerTarget(item);

      expect(target, isA<FileManagerFileTarget>());
      expect(target?.path, filePath);
    });

    test('preserves directory kind without probing a deleted path', () async {
      final directoryPath = p.absolute('storage', 'WindSend', 'deleted');
      final item = _historyItem(
        FileInfo(
          name: 'deleted',
          size: 0,
          path: directoryPath,
          isDirectory: true,
        ),
      );

      final target = await resolveHistoryFileManagerTarget(item);

      expect(target, isA<FileManagerDirectoryTarget>());
      expect(target?.path, directoryPath);
    });
  });

  test(
    'direct file opening reports a missing file without opening a folder',
    () async {
      final target = FileManagerFileTarget(
        p.absolute('storage', 'WindSend', 'missing.txt'),
      );
      var openAttempted = false;

      final result = await openFileTarget(
        target,
        fileExists: (_) async => false,
        fileOpener: (_) async {
          openAttempted = true;
          throw StateError('A missing file must not reach the platform opener');
        },
      );

      expect(result, isA<FileOpenFailed>());
      expect((result as FileOpenFailed).reason, FileOpenFailureReason.missing);
      expect(openAttempted, isFalse);
    },
  );
}

TransferHistoryItem _historyItem(FileInfo file) {
  return TransferHistoryItem(
    createdAt: DateTime(2026),
    fromDeviceId: 'local',
    toDeviceId: 'remote',
    isOutgoing: true,
    type: TransferType.file,
    dataSize: file.size,
    filesJson: FilesPayload(files: [file], totalSize: file.size).toJsonString(),
  );
}
