import 'dart:convert';
import 'dart:io';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

/// Result of running pub get
class PubGetResult {
  final bool success;
  final String output;
  final List<DependencyConflict> conflicts;

  PubGetResult({
    required this.success,
    required this.output,
    required this.conflicts,
  });

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Represents a dependency conflict
class DependencyConflict {
  final String package;
  final String currentVersion;
  final String conflictingDependency;
  final String requiredVersion;

  DependencyConflict({
    required this.package,
    required this.currentVersion,
    required this.conflictingDependency,
    required this.requiredVersion,
  });

  @override
  String toString() {
    return '$package $currentVersion conflicts with $conflictingDependency $requiredVersion';
  }
}

/// Resolves Dart package dependency conflicts by finding compatible versions
/// for the current Flutter/Dart SDK version.
class DependencyResolver {
  final Logger logger;
  final String projectPath;

  DependencyResolver(this.logger, this.projectPath);

  /// Detects if project uses FVM
  bool _usesFvm() {
    final fvmDir = Directory(p.join(projectPath, '.fvm'));
    return fvmDir.existsSync();
  }

  /// Gets the appropriate pub get command based on FVM usage
  String _getPubGetCommand() {
    return _usesFvm() ? 'fvm flutter pub get' : 'flutter pub get';
  }

  /// Runs pub get and captures output to detect conflicts
  Future<PubGetResult> runPubGet() async {
    final command = _getPubGetCommand();
    logger.detail('Running: $command');

    final result = await Process.run(
      'sh',
      ['-c', command],
      workingDirectory: projectPath,
      runInShell: true,
    );

    final output = result.stdout.toString() + result.stderr.toString();
    final conflicts = _parseConflicts(output);

    return PubGetResult(
      success: result.exitCode == 0,
      output: output,
      conflicts: conflicts,
    );
  }

  /// Parses pub get output to extract dependency conflicts
  List<DependencyConflict> _parseConflicts(String output) {
    final conflicts = <DependencyConflict>[];

    // Pattern: "package_name x.y.z depends on dependency ^a.b.c"
    // Example: "http_parser 4.1.2 depends on collection ^1.19.0"
    final conflictPattern = RegExp(
      r'(\w+)\s+([\d.]+)\s+depends on\s+(\w+)\s+([^\s,]+)',
      multiLine: true,
    );

    // Pattern: "package from sdk is incompatible with package version"
    // Example: "flutter_test from sdk is incompatible with http_parser ^4.1.2"
    final incompatiblePattern = RegExp(
      r'(\w+)\s+from\s+sdk\s+is\s+incompatible\s+with\s+(\w+)\s+([^\s,]+)',
      multiLine: true,
    );

    for (final match in conflictPattern.allMatches(output)) {
      conflicts.add(DependencyConflict(
        package: match.group(1)!,
        currentVersion: match.group(2)!,
        conflictingDependency: match.group(3)!,
        requiredVersion: match.group(4)!,
      ));
    }

    for (final match in incompatiblePattern.allMatches(output)) {
      conflicts.add(DependencyConflict(
        package: match.group(2)!,
        currentVersion: match.group(3)!.replaceAll('^', ''),
        conflictingDependency: match.group(1)!,
        requiredVersion: 'sdk',
      ));
    }

    return conflicts;
  }

  /// Gets the Dart SDK version from the current Flutter installation
  Future<String?> getDartSdkVersion() async {
    try {
      final command = _usesFvm() ? 'fvm dart --version' : 'dart --version';
      final result = await Process.run(
        'sh',
        ['-c', command],
        workingDirectory: projectPath,
      );

      final output = result.stdout.toString() + result.stderr.toString();
      final versionMatch =
          RegExp(r'Dart SDK version:\s+([\d.]+)').firstMatch(output);

      if (versionMatch != null) {
        return versionMatch.group(1);
      }

      return null;
    } catch (e) {
      logger.err('Error getting Dart SDK version: $e');
      return null;
    }
  }

  /// Finds a compatible version for a package that works with the current SDK
  Future<String?> findCompatibleVersion(
    String packageName,
    String dartSdkVersion,
  ) async {
    try {
      logger.detail('Querying pub.dev for $packageName compatible versions');

      final response = await http.get(
        Uri.parse('https://pub.dev/api/packages/$packageName'),
      );

      if (response.statusCode != 200) {
        logger.warn('Failed to query pub.dev for $packageName');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final versions = data['versions'] as List<dynamic>;

      // Sort versions in descending order (newest first)
      versions.sort((a, b) {
        final versionA = a['version'] as String;
        final versionB = b['version'] as String;
        return _compareVersions(versionB, versionA);
      });

      // Find the highest version that is compatible with current Dart SDK
      // and doesn't have conflicting dependencies
      for (final versionData in versions) {
        final version = versionData['version'] as String;
        final pubspec = versionData['pubspec'] as Map<String, dynamic>;
        final environment = pubspec['environment'] as Map<String, dynamic>?;

        if (environment == null) continue;

        final sdkConstraint = environment['sdk'] as String?;
        if (sdkConstraint == null) continue;

        // Check if current Dart SDK satisfies this version's constraint
        if (!_sdkSatisfiesConstraint(dartSdkVersion, sdkConstraint)) {
          continue;
        }

        // Check if this version's dependencies conflict with Flutter SDK pinned packages
        final dependencies = pubspec['dependencies'] as Map<String, dynamic>?;
        if (dependencies != null) {
          // Check for collection dependency (commonly pinned by flutter_test)
          final collectionDep = dependencies['collection'];
          if (collectionDep is String) {
            // Parse the collection constraint
            // Flutter 3.24.5 has collection 1.18.0
            // If package requires ^1.19.0, it's incompatible
            if (collectionDep.startsWith('^1.19') ||
                collectionDep.startsWith('>=1.19') ||
                collectionDep.contains('^1.19.') ||
                collectionDep.contains('>=1.19.')) {
              logger.detail(
                'Skipping $packageName $version: requires collection $collectionDep (incompatible with Flutter SDK collection 1.18.0)',
              );
              continue;
            }
            // ^1.15.0, ^1.16.0, ^1.17.0, ^1.18.0 are all compatible with 1.18.0
            // So we only skip versions requiring 1.19+
          }
        }

        logger.detail(
          'Found compatible version: $packageName $version (SDK: $sdkConstraint)',
        );
        return version;
      }

      logger.warn('No compatible version found for $packageName');
      return null;
    } catch (e) {
      logger.err('Error finding compatible version for $packageName: $e');
      return null;
    }
  }

  /// Checks if a Dart SDK version satisfies a version constraint
  bool _sdkSatisfiesConstraint(String sdkVersion, String constraint) {
    // Remove any pre-release info
    sdkVersion = sdkVersion.split('-').first;

    // Handle caret constraints (^3.4.0 means >=3.4.0 <4.0.0)
    if (constraint.startsWith('^')) {
      final minVersion = constraint.substring(1);
      final parts = minVersion.split('.');
      if (parts.isEmpty) return false;

      final majorVersion = int.tryParse(parts[0]);
      if (majorVersion == null) return false;

      final maxVersion = '${majorVersion + 1}.0.0';

      return _compareVersions(sdkVersion, minVersion) >= 0 &&
          _compareVersions(sdkVersion, maxVersion) < 0;
    }

    // Handle range constraints (>=3.4.0 <4.0.0)
    if (constraint.contains(' ')) {
      final parts = constraint.split(' ');
      bool satisfies = true;

      for (final part in parts) {
        if (part.startsWith('>=')) {
          final minVersion = part.substring(2);
          if (_compareVersions(sdkVersion, minVersion) < 0) {
            satisfies = false;
            break;
          }
        } else if (part.startsWith('>')) {
          final minVersion = part.substring(1);
          if (_compareVersions(sdkVersion, minVersion) <= 0) {
            satisfies = false;
            break;
          }
        } else if (part.startsWith('<=')) {
          final maxVersion = part.substring(2);
          if (_compareVersions(sdkVersion, maxVersion) > 0) {
            satisfies = false;
            break;
          }
        } else if (part.startsWith('<')) {
          final maxVersion = part.substring(1);
          if (_compareVersions(sdkVersion, maxVersion) >= 0) {
            satisfies = false;
            break;
          }
        }
      }

      return satisfies;
    }

    // Exact version match
    return sdkVersion == constraint;
  }

  /// Compares two semantic versions
  /// Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
  int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = v2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;

      if (p1 != p2) {
        return p1.compareTo(p2);
      }
    }

    return 0;
  }
}
