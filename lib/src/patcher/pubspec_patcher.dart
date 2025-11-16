import 'dart:io';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Patches pubspec.yaml to fix dependency version conflicts while preserving
/// formatting, comments, and structure.
class PubspecPatcher {
  final Logger logger;
  final String projectPath;

  PubspecPatcher(this.logger, this.projectPath);

  String get pubspecPath => p.join(projectPath, 'pubspec.yaml');

  /// Creates a backup of pubspec.yaml
  Future<File> createBackup() async {
    final pubspecFile = File(pubspecPath);
    if (!pubspecFile.existsSync()) {
      throw Exception('pubspec.yaml not found at $pubspecPath');
    }

    final backupPath = '$pubspecPath.backup';
    final backupFile = await pubspecFile.copy(backupPath);
    logger.detail('Created backup: $backupPath');

    return backupFile;
  }

  /// Restores pubspec.yaml from backup
  Future<void> restoreFromBackup() async {
    final backupPath = '$pubspecPath.backup';
    final backupFile = File(backupPath);

    if (!backupFile.existsSync()) {
      throw Exception('Backup file not found at $backupPath');
    }

    await backupFile.copy(pubspecPath);
    await backupFile.delete();
    logger.info('Restored pubspec.yaml from backup');
  }

  /// Deletes backup file
  Future<void> deleteBackup() async {
    final backupPath = '$pubspecPath.backup';
    final backupFile = File(backupPath);

    if (backupFile.existsSync()) {
      await backupFile.delete();
      logger.detail('Deleted backup file');
    }
  }

  /// Updates a package version in pubspec.yaml while preserving formatting
  Future<bool> updatePackageVersion(
    String packageName,
    String newVersion,
  ) async {
    try {
      final pubspecFile = File(pubspecPath);
      if (!pubspecFile.existsSync()) {
        logger.err('pubspec.yaml not found at $pubspecPath');
        return false;
      }

      final content = await pubspecFile.readAsString();
      final lines = content.split('\n');

      bool inDependencies = false;
      bool inDevDependencies = false;
      bool updated = false;

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];

        // Track sections
        if (line.startsWith('dependencies:')) {
          inDependencies = true;
          inDevDependencies = false;
          continue;
        } else if (line.startsWith('dev_dependencies:')) {
          inDevDependencies = true;
          inDependencies = false;
          continue;
        } else if (line.isNotEmpty &&
            !line.startsWith(' ') &&
            !line.startsWith('\t')) {
          // New top-level section
          inDependencies = false;
          inDevDependencies = false;
        }

        // Update package version if in dependencies sections
        if ((inDependencies || inDevDependencies) &&
            line.contains('$packageName:')) {
          // Pattern: "  package_name: ^1.2.3" or "  package_name: 1.2.3"
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('$packageName:')) {
            final indent = line.substring(0, line.length - trimmed.length);

            // Check if version is on the same line
            if (trimmed.contains(':') && trimmed.split(':').length == 2) {
              lines[i] = '$indent$packageName: ^$newVersion';
              updated = true;
              logger.detail('Updated $packageName: ^$newVersion');
              break;
            }
          }
        }
      }

      if (!updated) {
        logger.warn('Package $packageName not found in pubspec.yaml');
        return false;
      }

      // Write updated content
      await pubspecFile.writeAsString(lines.join('\n'));
      logger.info('✓ Updated $packageName to ^$newVersion in pubspec.yaml');

      return true;
    } catch (e) {
      logger.err('Error updating pubspec.yaml: $e');
      return false;
    }
  }

  /// Gets current package versions from pubspec.yaml
  Future<Map<String, String>> getPackageVersions() async {
    try {
      final pubspecFile = File(pubspecPath);
      if (!pubspecFile.existsSync()) {
        return {};
      }

      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content) as Map<dynamic, dynamic>;

      final packages = <String, String>{};

      // Get regular dependencies
      final dependencies = yaml['dependencies'] as Map<dynamic, dynamic>?;
      if (dependencies != null) {
        for (final entry in dependencies.entries) {
          final name = entry.key.toString();
          final value = entry.value;

          if (value is String) {
            packages[name] = value;
          } else if (value is Map) {
            // Skip complex dependencies (git, path, etc.)
            continue;
          }
        }
      }

      // Get dev dependencies
      final devDependencies =
          yaml['dev_dependencies'] as Map<dynamic, dynamic>?;
      if (devDependencies != null) {
        for (final entry in devDependencies.entries) {
          final name = entry.key.toString();
          final value = entry.value;

          if (value is String) {
            packages[name] = value;
          }
        }
      }

      return packages;
    } catch (e) {
      logger.err('Error reading pubspec.yaml: $e');
      return {};
    }
  }

  /// Checks if a package exists in pubspec.yaml
  Future<bool> hasPackage(String packageName) async {
    final packages = await getPackageVersions();
    return packages.containsKey(packageName);
  }
}
