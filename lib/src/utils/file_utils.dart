import 'dart:io';
import 'package:path/path.dart' as p;

class FileUtils {
  /// Check if a file exists
  static bool fileExists(String path) => File(path).existsSync();

  /// Check if a directory exists
  static bool dirExists(String path) => Directory(path).existsSync();

  /// Read file content
  static Future<String> readFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', path);
    }
    return await file.readAsString();
  }

  /// Write content to file
  static Future<void> writeFile(String path, String content) async {
    final file = File(path);
    await file.writeAsString(content);
  }

  /// Create directory if it doesn't exist
  static Future<void> ensureDir(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
  }

  /// Delete directory recursively
  static Future<void> deleteDir(String path) async {
    final dir = Directory(path);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// Find files matching pattern
  static List<String> findFiles(String dirPath, String pattern) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    final files = <String>[];
    final regex = RegExp(pattern);

    for (var entity in dir.listSync(recursive: true)) {
      if (entity is File && regex.hasMatch(p.basename(entity.path))) {
        files.add(entity.path);
      }
    }

    return files;
  }

  /// Copy file
  static Future<void> copyFile(String source, String destination) async {
    final sourceFile = File(source);
    if (!sourceFile.existsSync()) {
      throw FileSystemException('Source file not found', source);
    }
    await sourceFile.copy(destination);
  }

  /// Replace text in file using regex
  static Future<void> replaceInFile(
    String path,
    Pattern pattern,
    String replacement,
  ) async {
    final content = await readFile(path);
    final newContent = content.replaceAll(pattern, replacement);
    await writeFile(path, newContent);
  }

  /// Check if path is a Flutter project
  static bool isFlutterProject(String path) {
    return fileExists(p.join(path, 'pubspec.yaml')) &&
        dirExists(p.join(path, 'lib'));
  }

  /// Check if path has Android folder
  static bool hasAndroidFolder(String path) {
    return dirExists(p.join(path, 'android'));
  }

  /// Check if path has iOS folder
  static bool hasIosFolder(String path) {
    return dirExists(p.join(path, 'ios'));
  }

  /// Get project name from pubspec.yaml
  static Future<String?> getProjectName(String projectPath) async {
    final pubspecPath = p.join(projectPath, 'pubspec.yaml');
    if (!fileExists(pubspecPath)) return null;

    final content = await readFile(pubspecPath);
    final match = RegExp(
      r'^name:\s*(.+)$',
      multiLine: true,
    ).firstMatch(content);
    return match?.group(1)?.trim();
  }

  /// Backup file
  static Future<String> backupFile(String path) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '$path.backup.$timestamp';
    await copyFile(path, backupPath);
    return backupPath;
  }

  /// Get file size in bytes
  static int getFileSize(String path) {
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : 0;
  }

  /// Check if file contains text
  static Future<bool> fileContains(String path, Pattern pattern) async {
    if (!fileExists(path)) return false;
    final content = await readFile(path);
    return content.contains(pattern);
  }
}
