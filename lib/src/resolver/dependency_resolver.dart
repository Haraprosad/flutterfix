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
  bool isDirectDependency;
  List<String> dependentPackages;

  DependencyConflict({
    required this.package,
    required this.currentVersion,
    required this.conflictingDependency,
    required this.requiredVersion,
    this.isDirectDependency = false,
    this.dependentPackages = const [],
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

  /// Finds the minimum Flutter version that resolves the given conflicts
  Future<String?> findMinimumCompatibleFlutterVersion(
    List<DependencyConflict> conflicts,
  ) async {
    try {
      // Query Flutter releases from GitHub API
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/flutter/flutter/releases'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) {
        logger.warn('Failed to query Flutter releases');
        return null;
      }

      final releases = jsonDecode(response.body) as List<dynamic>;

      // Filter to stable releases only and sort by version
      final stableReleases = <Map<String, dynamic>>[];
      for (final release in releases) {
        final releaseMap = release as Map<String, dynamic>;
        final tagName = releaseMap['tag_name'] as String?;
        final prerelease = releaseMap['prerelease'] as bool?;

        if (tagName != null &&
            prerelease == false &&
            !tagName.contains('beta')) {
          // Extract version number (e.g., "3.24.5" from "v3.24.5" or "3.24.5")
          final versionMatch = RegExp(r'v?(\d+\.\d+\.\d+)').firstMatch(tagName);
          if (versionMatch != null) {
            releaseMap['version'] = versionMatch.group(1);
            stableReleases.add(releaseMap);
          }
        }
      }

      // Sort releases by version (newest first)
      stableReleases.sort((a, b) {
        final versionA = a['version'] as String;
        final versionB = b['version'] as String;
        return _compareVersions(versionB, versionA);
      });

      // For each conflict, check which Flutter version provides compatible packages
      // We need a version that has Dart SDK 3.6+ for collection 1.19.0 support
      for (final release in stableReleases) {
        final flutterVersion = release['version'] as String;
        final parts = flutterVersion.split('.');

        if (parts.isEmpty) continue;

        final major = int.tryParse(parts[0]) ?? 0;
        final minor = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

        // Flutter 3.27+ uses Dart 3.6+ which has collection 1.19.0
        // This resolves most SDK pinning conflicts
        if (major >= 3 && minor >= 27) {
          return flutterVersion;
        }
      }

      // If no suitable version found in recent releases, recommend latest stable
      if (stableReleases.isNotEmpty) {
        return stableReleases.first['version'] as String?;
      }

      return null;
    } catch (e) {
      logger.err('Error finding compatible Flutter version: $e');
      return null;
    }
  }

  /// Gets the current Flutter version
  Future<String?> getCurrentFlutterVersion() async {
    try {
      final command = _usesFvm()
          ? 'fvm flutter --version --machine'
          : 'flutter --version --machine';
      final result = await Process.run(
        'sh',
        ['-c', command],
        workingDirectory: projectPath,
      );

      if (result.exitCode != 0) return null;

      final output = result.stdout.toString();
      if (output.startsWith('{')) {
        final json = jsonDecode(output) as Map<String, dynamic>;
        return json['flutterVersion'] as String?;
      }

      return null;
    } catch (e) {
      logger.detail('Error getting Flutter version: $e');
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

      // Determine the collection version constraint based on Flutter/Dart SDK
      // Flutter 3.24.x uses collection 1.18.0
      // Flutter 3.27+ uses collection 1.19.0
      final collectionMaxVersion = _getCollectionMaxVersion(dartSdkVersion);

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
        bool hasIncompatibleDeps = false;

        if (dependencies != null) {
          // Check for collection dependency (commonly pinned by flutter_test)
          final collectionDep = dependencies['collection'];
          if (collectionDep is String) {
            // Check if collection requirement is higher than what SDK provides
            if (!_collectionSatisfiesConstraint(
                collectionMaxVersion, collectionDep)) {
              logger.detail(
                'Skipping $packageName $version: requires collection $collectionDep (incompatible with SDK collection $collectionMaxVersion)',
              );
              hasIncompatibleDeps = true;
            }
          }
        }

        if (hasIncompatibleDeps) continue;

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

  /// Gets the maximum collection version for a given Dart SDK version
  String _getCollectionMaxVersion(String dartSdkVersion) {
    // Dart 3.5.x (Flutter 3.24.x) uses collection 1.18.0
    // Dart 3.6.x+ (Flutter 3.27+) uses collection 1.19.0
    final parts = dartSdkVersion.split('.');
    if (parts.isEmpty) return '1.18.0';

    final minor = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    // Dart 3.6+ uses collection 1.19.0
    if (minor >= 6) return '1.19.0';

    // Dart 3.5 and earlier uses collection 1.18.0
    return '1.18.0';
  }

  /// Checks if a collection version satisfies the required constraint
  bool _collectionSatisfiesConstraint(
      String availableVersion, String constraint) {
    // Remove caret and get base version
    final cleanConstraint =
        constraint.replaceAll('^', '').replaceAll('>=', '').trim();
    final constraintParts = cleanConstraint.split(' ')[0].split('.');

    if (constraintParts.isEmpty) return true;

    // Get minimum required version
    final minMinor =
        int.tryParse(constraintParts.length > 1 ? constraintParts[1] : '0') ??
            0;
    final availableParts = availableVersion.split('.');
    final availableMinor =
        int.tryParse(availableParts.length > 1 ? availableParts[1] : '0') ?? 0;

    // Check if constraint requires a newer version than available
    if (constraint.startsWith('^') || constraint.startsWith('>=')) {
      // For ^1.19.0 or >=1.19.0, we need at least 1.19.0
      return availableMinor >= minMinor;
    }

    return true;
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

  /// Checks if a package is a direct dependency in pubspec.yaml
  Future<bool> isDirectDependency(String packageName) async {
    try {
      final pubspecPath = p.join(projectPath, 'pubspec.yaml');
      final content = await File(pubspecPath).readAsString();

      // Check in dependencies and dev_dependencies sections
      final dependencyPattern = RegExp(
        r'^\s+' + packageName + r'\s*:',
        multiLine: true,
      );

      return dependencyPattern.hasMatch(content);
    } catch (e) {
      logger.detail('Error checking if $packageName is direct dependency: $e');
      return false;
    }
  }

  /// Finds which packages depend on the given package
  Future<List<String>> findDependentPackages(String packageName) async {
    try {
      final command = _usesFvm()
          ? 'fvm flutter pub deps --json'
          : 'flutter pub deps --json';
      final result = await Process.run(
        'sh',
        ['-c', command],
        workingDirectory: projectPath,
      );

      if (result.exitCode != 0) {
        return [];
      }

      final output = result.stdout.toString();
      final data = jsonDecode(output) as Map<String, dynamic>;
      final packages = data['packages'] as List<dynamic>?;

      if (packages == null) return [];

      final dependents = <String>[];

      for (final pkg in packages) {
        final pkgMap = pkg as Map<String, dynamic>;
        final dependencies = pkgMap['dependencies'] as List<dynamic>?;

        if (dependencies != null) {
          for (final dep in dependencies) {
            if (dep == packageName) {
              final name = pkgMap['name'] as String?;
              if (name != null && name != packageName) {
                dependents.add(name);
              }
            }
          }
        }
      }

      return dependents;
    } catch (e) {
      logger.detail('Error finding dependents of $packageName: $e');
      return [];
    }
  }

  /// Analyzes conflicts to determine if they are direct or transitive
  Future<void> analyzeConflicts(List<DependencyConflict> conflicts) async {
    for (final conflict in conflicts) {
      conflict.isDirectDependency = await isDirectDependency(conflict.package);
      conflict.dependentPackages =
          await findDependentPackages(conflict.package);
    }
  }
}
