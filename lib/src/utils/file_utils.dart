import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;

/// Backup information model
class BackupInfo {
  final String id;
  final DateTime timestamp;
  final String originalPath;
  final String backupPath;
  final String description;
  final String projectPath;

  BackupInfo({
    required this.id,
    required this.timestamp,
    required this.originalPath,
    required this.backupPath,
    required this.description,
    required this.projectPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'originalPath': originalPath,
        'backupPath': backupPath,
        'description': description,
        'projectPath': projectPath,
      };

  factory BackupInfo.fromJson(Map<String, dynamic> json) => BackupInfo(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        originalPath: json['originalPath'] as String,
        backupPath: json['backupPath'] as String,
        description: json['description'] as String,
        projectPath: json['projectPath'] as String,
      );
}

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

  /// Create backup with metadata
  static Future<BackupInfo> createBackup(
    String projectPath,
    String filePath,
    String description,
  ) async {
    final timestamp = DateTime.now();
    final backupDir = await getBackupDirectory(projectPath);
    await ensureDir(backupDir);

    // Create backup metadata
    final backupId = timestamp.millisecondsSinceEpoch.toString();
    final relativePath = p.relative(filePath, from: projectPath);
    final backupFileName = '${p.basename(filePath)}.backup.$backupId';
    final backupFilePath = p.join(backupDir, backupFileName);

    // Copy file to backup location
    await copyFile(filePath, backupFilePath);

    // Create metadata file
    final metadata = BackupInfo(
      id: backupId,
      timestamp: timestamp,
      originalPath: relativePath,
      backupPath: backupFilePath,
      description: description,
      projectPath: projectPath,
    );

    await _saveBackupMetadata(backupDir, metadata);

    return metadata;
  }

  /// Get backup directory for project
  static Future<String> getBackupDirectory(String projectPath) async {
    return p.join(projectPath, '.flutterfix', 'backups');
  }

  /// Save backup metadata
  static Future<void> _saveBackupMetadata(
    String backupDir,
    BackupInfo metadata,
  ) async {
    final metadataPath = p.join(backupDir, 'metadata.json');

    List<Map<String, dynamic>> allMetadata = [];

    if (fileExists(metadataPath)) {
      final content = await readFile(metadataPath);
      final decoded = content.isNotEmpty
          ? (jsonDecode(content) as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      allMetadata = decoded;
    }

    allMetadata.add(metadata.toJson());
    await writeFile(metadataPath, jsonEncode(allMetadata));
  }

  /// List all backups for a project
  static Future<List<BackupInfo>> listBackups(String projectPath) async {
    final backupDir = await getBackupDirectory(projectPath);
    final metadataPath = p.join(backupDir, 'metadata.json');

    if (!fileExists(metadataPath)) {
      return [];
    }

    final content = await readFile(metadataPath);
    if (content.isEmpty) return [];

    final decoded = (jsonDecode(content) as List).cast<Map<String, dynamic>>();
    return decoded.map((json) => BackupInfo.fromJson(json)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Get latest backup
  static Future<BackupInfo?> getLatestBackup(String projectPath) async {
    final backups = await listBackups(projectPath);
    return backups.isEmpty ? null : backups.first;
  }

  /// Restore a backup
  static Future<void> restoreBackup(BackupInfo backup) async {
    final originalPath = p.join(backup.projectPath, backup.originalPath);

    // Ensure parent directory exists
    final parentDir = p.dirname(originalPath);
    await ensureDir(parentDir);

    // Restore the file
    await copyFile(backup.backupPath, originalPath);
  }

  /// Delete a backup
  static Future<void> deleteBackup(
    String projectPath,
    BackupInfo backup,
  ) async {
    // Delete backup file
    if (fileExists(backup.backupPath)) {
      await File(backup.backupPath).delete();
    }

    // Update metadata
    final backupDir = await getBackupDirectory(projectPath);
    final metadataPath = p.join(backupDir, 'metadata.json');

    if (fileExists(metadataPath)) {
      final content = await readFile(metadataPath);
      final decoded =
          (jsonDecode(content) as List).cast<Map<String, dynamic>>();
      final filtered =
          decoded.where((json) => json['id'] != backup.id).toList();
      await writeFile(metadataPath, jsonEncode(filtered));
    }
  }

  /// Clear all backups for a project
  static Future<void> clearAllBackups(String projectPath) async {
    final backupDir = await getBackupDirectory(projectPath);
    if (dirExists(backupDir)) {
      await deleteDir(backupDir);
    }
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
