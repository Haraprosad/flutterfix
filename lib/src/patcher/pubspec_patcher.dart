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

  /// Updates multiple packages at once
  /// Returns the number of packages successfully updated
  Future<int> updateMultiplePackages(
    Map<String, String> packageVersions,
  ) async {
    var updated = 0;

    for (final entry in packageVersions.entries) {
      final success = await updatePackageVersion(entry.key, entry.value);
      if (success) {
        updated++;
      }
    }

    return updated;
  }

  /// Checks if a package exists in pubspec.yaml
  Future<bool> hasPackage(String packageName) async {
    final packages = await getPackageVersions();
    return packages.containsKey(packageName);
  }

  /// Updates the SDK constraint in pubspec.yaml to be compatible with the target Flutter version
  /// Set skipConfirmation to true to update without user prompts (for --original mode)
  /// Returns true if updated, false if no update needed
  Future<bool> updateSdkConstraint(String flutterVersion,
      {bool skipConfirmation = false}) async {
    try {
      final pubspecFile = File(pubspecPath);
      if (!pubspecFile.existsSync()) {
        logger.err('pubspec.yaml not found');
        return false;
      }

      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content) as Map<dynamic, dynamic>;

      // Get current SDK constraint
      final environment = yaml['environment'] as Map<dynamic, dynamic>?;
      if (environment == null) {
        logger.warn('No environment section in pubspec.yaml');
        return false;
      }

      final currentSdk = environment['sdk'] as String?;
      if (currentSdk == null) {
        logger.warn('No SDK constraint in pubspec.yaml');
        return false;
      }

      // Determine required SDK constraint based on Flutter version
      final requiredSdk = _getRequiredSdkConstraint(flutterVersion);

      // Check if current SDK constraint needs updating
      if (_sdkConstraintNeedsUpdate(currentSdk, requiredSdk)) {
        logger.info(
            '📝 Updating SDK constraint from $currentSdk to $requiredSdk');

        // Check if this requires null safety migration
        final needsNullSafety = _requiresNullSafety(currentSdk, requiredSdk);
        if (needsNullSafety && !skipConfirmation) {
          logger.warn('⚠️  This update crosses null safety boundary!');
          logger.info('');
          logger.info('💡 Your project may need null safety migration:');
          logger.info('   1. Run: dart migrate');
          logger.info('   2. Review and apply suggested changes');
          logger.info('   3. Update dependencies to null-safe versions');
          logger.info('');
          logger.info('📚 Guide: https://dart.dev/null-safety/migration-guide');
          logger.info('');

          final shouldContinue = logger.confirm(
            'Do you want to update the SDK constraint now?',
            defaultValue: true,
          );

          if (!shouldContinue) {
            logger.info('⏭️  Skipping SDK constraint update');
            return false;
          }
        } else if (needsNullSafety && skipConfirmation) {
          // In --original mode, just inform but don't block
          logger.detail(
              'Note: SDK constraint crosses null safety boundary (Dart <2.12 → ≥2.12)');
          logger.detail(
              'Packages will resolve to compatible versions automatically');
        }

        // Update using line-by-line replacement to preserve formatting
        final lines = content.split('\n');
        final updatedLines = <String>[];
        var inEnvironment = false;
        var sdkUpdated = false;

        for (var line in lines) {
          if (line.trim().startsWith('environment:')) {
            inEnvironment = true;
            updatedLines.add(line);
          } else if (inEnvironment && line.trim().startsWith('sdk:')) {
            // Replace SDK line while preserving indentation
            final indent = line.substring(0, line.indexOf('sdk:'));
            updatedLines.add('${indent}sdk: \'$requiredSdk\'');
            sdkUpdated = true;
            inEnvironment = false; // Usually SDK is first in environment
          } else {
            updatedLines.add(line);
          }
        }

        if (sdkUpdated) {
          await pubspecFile.writeAsString(updatedLines.join('\n'));
          logger.success('✅ SDK constraint updated to $requiredSdk');

          if (needsNullSafety) {
            logger.info('');
            logger.warn('⚠️  Next steps:');
            logger.warn('   1. Run: dart migrate');
            logger.warn('   2. Update dependencies to null-safe versions');
            logger.warn('   3. Fix any null safety issues in your code');
          }

          return true;
        }
      } else {
        logger.detail('SDK constraint $currentSdk is already compatible');
      }

      return false;
    } catch (e) {
      logger.err('Error updating SDK constraint: $e');
      return false;
    }
  }

  /// Checks if the update requires null safety migration
  bool _requiresNullSafety(String currentSdk, String requiredSdk) {
    // Extract minimum versions
    final currentMinMatch =
        RegExp(r'>=?\s*(\d+\.\d+\.\d+)').firstMatch(currentSdk);
    final requiredMinMatch =
        RegExp(r'>=?\s*(\d+\.\d+\.\d+)').firstMatch(requiredSdk);

    if (currentMinMatch == null || requiredMinMatch == null) {
      return false;
    }

    final currentMin = currentMinMatch.group(1)!;
    final requiredMin = requiredMinMatch.group(1)!;

    // Null safety was introduced in Dart 2.12.0
    // If current < 2.12 and required >= 2.12, migration is needed
    final currentParts =
        currentMin.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final requiredParts =
        requiredMin.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    final currentMajor = currentParts[0];
    final currentMinor = currentParts.length > 1 ? currentParts[1] : 0;
    final requiredMajor = requiredParts[0];
    final requiredMinor = requiredParts.length > 1 ? requiredParts[1] : 0;

    // Current is before null safety, required is after
    if (currentMajor < 2 || (currentMajor == 2 && currentMinor < 12)) {
      if (requiredMajor > 2 || (requiredMajor == 2 && requiredMinor >= 12)) {
        return true;
      }
    }

    return false;
  }

  /// Determines the required SDK constraint based on Flutter version
  String _getRequiredSdkConstraint(String flutterVersion) {
    final parts = flutterVersion.split('.');
    if (parts.isEmpty) return '>=2.12.0 <4.0.0';

    final major = int.tryParse(parts[0]) ?? 0;
    final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    // Flutter 3.x requires Dart 3.x (null safety mandatory)
    if (major >= 3) {
      // Flutter 3.24+ uses Dart 3.5+
      if (major == 3 && minor >= 24) {
        return '>=3.5.0 <4.0.0';
      }
      // Flutter 3.10+ uses Dart 3.0+
      if (major == 3 && minor >= 10) {
        return '>=3.0.0 <4.0.0';
      }
      // Flutter 3.0+ uses Dart 2.17+
      return '>=2.17.0 <4.0.0';
    }

    // Flutter 2.x
    if (major == 2) {
      // Flutter 2.8+ uses Dart 2.15+ (null safety stable)
      if (minor >= 8) {
        return '>=2.15.0 <3.0.0';
      }
      // Flutter 2.0+ uses Dart 2.12+ (null safety)
      return '>=2.12.0 <3.0.0';
    }

    // Flutter 1.x (legacy, no null safety)
    return '>=2.7.0 <3.0.0';
  }

  /// Checks if SDK constraint needs updating
  bool _sdkConstraintNeedsUpdate(String currentSdk, String requiredSdk) {
    // Extract minimum version from constraints
    final currentMinMatch =
        RegExp(r'>=?\s*(\d+\.\d+\.\d+)').firstMatch(currentSdk);
    final requiredMinMatch =
        RegExp(r'>=?\s*(\d+\.\d+\.\d+)').firstMatch(requiredSdk);

    if (currentMinMatch == null || requiredMinMatch == null) {
      return true; // Can't parse, update to be safe
    }

    final currentMin = currentMinMatch.group(1)!;
    final requiredMin = requiredMinMatch.group(1)!;

    // Check if current minimum is less than required minimum
    final currentParts =
        currentMin.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final requiredParts =
        requiredMin.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final curr = i < currentParts.length ? currentParts[i] : 0;
      final req = i < requiredParts.length ? requiredParts[i] : 0;

      if (curr < req) return true;
      if (curr > req) return false;
    }

    // Extract maximum version from constraints
    final currentMaxMatch = RegExp(r'<\s*(\d+)').firstMatch(currentSdk);
    final requiredMaxMatch = RegExp(r'<\s*(\d+)').firstMatch(requiredSdk);

    // If upper bounds differ, update
    if (currentMaxMatch?.group(1) != requiredMaxMatch?.group(1)) {
      return true;
    }

    return false;
  }

  /// Restore SDK constraint for pre-null safety projects
  /// This reverts modified SDK constraints back to pre-null safety era
  Future<bool> restorePreNullSafetySdk(String flutterVersion) async {
    try {
      final pubspecFile = File(pubspecPath);
      if (!await pubspecFile.exists()) {
        logger.err('pubspec.yaml not found at $pubspecPath');
        return false;
      }

      final content = await pubspecFile.readAsString();
      final doc = loadYaml(content) as Map;
      final environment = doc['environment'] as Map?;

      if (environment == null) {
        logger.warn('No environment section in pubspec.yaml');
        return false;
      }

      final currentSdk = environment['sdk'] as String?;
      if (currentSdk == null) {
        logger.warn('No SDK constraint in pubspec.yaml');
        return false;
      }

      // Determine appropriate pre-null safety SDK constraint
      final restoredSdk = _getPreNullSafetySdkConstraint(flutterVersion);

      logger
          .info('📝 Restoring SDK constraint from $currentSdk to $restoredSdk');

      // Update using line-by-line replacement to preserve formatting
      final lines = content.split('\n');
      final updatedLines = <String>[];
      var inEnvironment = false;
      var sdkUpdated = false;

      for (var line in lines) {
        if (line.trim().startsWith('environment:')) {
          inEnvironment = true;
          updatedLines.add(line);
        } else if (inEnvironment && line.trim().startsWith('sdk:')) {
          // Replace SDK line while preserving indentation
          final indent = line.substring(0, line.indexOf('sdk:'));
          updatedLines.add('${indent}sdk: \'$restoredSdk\'');
          sdkUpdated = true;
          inEnvironment = false;
        } else {
          updatedLines.add(line);
        }
      }

      if (sdkUpdated) {
        await pubspecFile.writeAsString(updatedLines.join('\n'));
        logger.success('✅ SDK constraint restored to $restoredSdk');
        logger.detail(
            'Project will use packages compatible with pre-null safety');
        return true;
      }

      return false;
    } catch (e) {
      logger.err('Error restoring SDK constraint: $e');
      return false;
    }
  }

  /// Get appropriate pre-null safety SDK constraint for Flutter version
  String _getPreNullSafetySdkConstraint(String flutterVersion) {
    final parts = flutterVersion.split('.');
    if (parts.isEmpty) return '>=2.7.0 <3.0.0';

    final major = int.tryParse(parts[0]) ?? 0;
    final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    // Flutter 1.22+ uses Dart 2.10
    if (major == 1 && minor >= 22) {
      return '>=2.10.0 <3.0.0';
    }

    // Flutter 1.20-1.21 uses Dart 2.9
    if (major == 1 && minor >= 20) {
      return '>=2.9.0 <3.0.0';
    }

    // Flutter 1.17-1.19 uses Dart 2.8
    if (major == 1 && minor >= 17) {
      return '>=2.8.0 <3.0.0';
    }

    // Flutter 1.12-1.16 uses Dart 2.7
    if (major == 1 && minor >= 12) {
      return '>=2.7.0 <3.0.0';
    }

    // Earlier versions
    return '>=2.1.0 <3.0.0';
  }
}
