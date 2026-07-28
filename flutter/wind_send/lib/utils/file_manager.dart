import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'logger.dart';

/// A file-manager destination whose original filesystem kind remains known even
/// after the entry has been moved or deleted.
sealed class FileManagerTarget {
  const FileManagerTarget(this.path);

  const factory FileManagerTarget.file(String path) = FileManagerFileTarget;
  const factory FileManagerTarget.directory(String path) =
      FileManagerDirectoryTarget;

  final String path;
}

final class FileManagerFileTarget extends FileManagerTarget {
  const FileManagerFileTarget(super.path);
}

final class FileManagerDirectoryTarget extends FileManagerTarget {
  const FileManagerDirectoryTarget(super.path);
}

typedef DirectoryExists = Future<bool> Function(String path);

/// Resolves the closest directory that can still be opened for [target].
///
/// History outlives transferred files. Falling back through existing ancestors
/// preserves the action's "open location" meaning without pretending the old
/// file itself is still available.
Future<String?> resolveFileManagerDirectory(
  FileManagerTarget target, {
  DirectoryExists? directoryExists,
}) async {
  if (target.path.trim().isEmpty) return null;

  final exists = directoryExists ?? (path) => Directory(path).exists();
  var candidate = p.normalize(switch (target) {
    FileManagerFileTarget() => p.dirname(target.path),
    FileManagerDirectoryTarget() => target.path,
  });

  while (true) {
    if (await exists(candidate)) return candidate;

    final parent = p.dirname(candidate);
    if (parent == candidate) return null;
    candidate = parent;
  }
}

/// Reveals an existing file when the platform supports it, otherwise opens its
/// containing directory (or the nearest surviving ancestor).
Future<bool> openInFileManager(FileManagerTarget target) async {
  try {
    final directory = await resolveFileManagerDirectory(target);
    if (directory == null) {
      SharedLogger().logger.w(
        'No accessible directory for file manager target: ${target.path}',
      );
      return false;
    }

    if (Platform.isWindows) {
      return _openInWindowsExplorer(target, directory);
    }
    if (Platform.isMacOS) {
      return _openInMacOSFinder(target, directory);
    }
    if (Platform.isLinux) {
      return _openInLinuxFileManager(directory);
    }
    if (Platform.isAndroid) {
      return _openInAndroidFileManager(directory);
    }
    if (Platform.isIOS) {
      return _openInIOSFileManager(directory);
    }

    return false;
  } catch (error, stackTrace) {
    SharedLogger().logger.e(
      'openInFileManager error: $error',
      stackTrace: stackTrace,
    );
    return false;
  }
}

Future<bool> _openInWindowsExplorer(
  FileManagerTarget target,
  String directory,
) async {
  final canRevealFile =
      target is FileManagerFileTarget && await File(target.path).exists();
  final arguments = canRevealFile
      ? ['/select,', _handleWindowsLongPath(target.path)]
      : [_handleWindowsLongPath(directory)];

  // Explorer's exit code is not a reliable launch signal, so successful process
  // creation is the strongest result available here.
  await Process.run('explorer', arguments, runInShell: true);
  return true;
}

Future<bool> _openInMacOSFinder(
  FileManagerTarget target,
  String directory,
) async {
  final canRevealFile =
      target is FileManagerFileTarget && await File(target.path).exists();
  final result = await Process.run(
    'open',
    canRevealFile ? ['-R', target.path] : [directory],
  );
  return result.exitCode == 0;
}

Future<bool> _openInLinuxFileManager(String directory) async {
  final fileManagers = ['xdg-open', 'nautilus', 'dolphin', 'nemo', 'thunar'];

  for (final fileManager in fileManagers) {
    try {
      final result = await Process.run(fileManager, [
        directory,
      ], runInShell: true);
      if (result.exitCode == 0) return true;
    } on ProcessException {
      // Desktop environments expose different launchers; absence of one is a
      // capability signal to continue down the ordered fallback list.
    }
  }

  return false;
}

const _androidFileManagerChannel = MethodChannel(
  'com.doraemon.wind_send/file_manager',
);

Future<bool> _openInAndroidFileManager(String directory) async {
  try {
    return await _androidFileManagerChannel.invokeMethod<bool>(
          'openDirectory',
          {'path': directory},
        ) ??
        false;
  } on PlatformException catch (error, stackTrace) {
    SharedLogger().logger.e(
      'Android file manager error: ${error.message}',
      stackTrace: stackTrace,
    );
    return false;
  }
}

Future<bool> _openInIOSFileManager(String directory) async {
  final uri = Uri.file(directory, windows: false);
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

const _windowsMaxPathLength = 260;
const _windowsLongPathPrefix = r'\\?\';

String _handleWindowsLongPath(String path) {
  var windowsPath = path.replaceAll('/', r'\');
  if (windowsPath.startsWith(_windowsLongPathPrefix) ||
      windowsPath.length <= _windowsMaxPathLength) {
    return windowsPath;
  }
  if (windowsPath.startsWith(r'\\')) {
    return r'\\?\UNC\' + windowsPath.substring(2);
  }
  return _windowsLongPathPrefix + windowsPath;
}
