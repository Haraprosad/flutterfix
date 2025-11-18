import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;
import '../runner/process_runner.dart';
import '../utils/file_utils.dart';
import 'package:path/path.dart' as p;

class FlutterInfo {
  final String? version;
  final String? dartVersion;
  final String? channel;
  final String? frameworkRevision;
  final String? engineRevision;
  final bool isInstalled;

  FlutterInfo({
    this.version,
    this.dartVersion,
    this.channel,
    this.frameworkRevision,
    this.engineRevision,
    this.isInstalled = false,
  });

  String get majorMinorVersion {
    if (version == null) return '0.0';
    final parts = version!.split('.');
    return parts.length >= 2 ? '${parts[0]}.${parts[1]}' : version!;
  }

  @override
  String toString() => 'Flutter $version (Dart $dartVersion) on $channel';
}

class ProjectFlutterInfo {
  final String? requiredFlutterVersion;
  final String? sdkConstraint;
  final Map<String, dynamic> dependencies;
  final String? projectName;

  ProjectFlutterInfo({
    this.requiredFlutterVersion,
    this.sdkConstraint,
    this.dependencies = const {},
    this.projectName,
  });
}

class FlutterDetector {
  /// Detect installed Flutter version
  static Future<FlutterInfo> detectInstalled() async {
    final exists = await ProcessRunner.commandExists('flutter');
    if (!exists) {
      return FlutterInfo(isInstalled: false);
    }

    final result = await ProcessRunner.flutter(['--version', '--machine']);

    if (!result.success) {
      return FlutterInfo(isInstalled: false);
    }

    try {
      // Try parsing JSON output (modern Flutter versions)
      final output = result.stdout;
      if (output.startsWith('{')) {
        final json = jsonDecode(output) as Map<String, dynamic>;
        return FlutterInfo(
          version: json['flutterVersion'] as String?,
          dartVersion: json['dartSdkVersion'] as String?,
          channel: json['channel'] as String?,
          frameworkRevision: json['frameworkRevision'] as String?,
          engineRevision: json['engineRevision'] as String?,
          isInstalled: true,
        );
      }

      // Fallback: parse text output
      final versionMatch =
          RegExp(r'Flutter\s+(\d+\.\d+\.\d+)').firstMatch(output);
      final dartMatch = RegExp(r'Dart\s+(\d+\.\d+\.\d+)').firstMatch(output);
      final channelMatch = RegExp(r'channel\s+(\w+)').firstMatch(output);

      return FlutterInfo(
        version: versionMatch?.group(1),
        dartVersion: dartMatch?.group(1),
        channel: channelMatch?.group(1),
        isInstalled: true,
      );
    } catch (e) {
      // Fallback: parse human-readable output
      return _parseHumanReadable(result.stdout);
    }
  }

  static FlutterInfo _parseHumanReadable(String output) {
    final versionMatch =
        RegExp(r'Flutter\s+(\d+\.\d+\.\d+)').firstMatch(output);
    final dartMatch = RegExp(r'Dart\s+(\d+\.\d+\.\d+)').firstMatch(output);
    final channelMatch = RegExp(r'channel\s+(\w+)').firstMatch(output);

    return FlutterInfo(
      version: versionMatch?.group(1),
      dartVersion: dartMatch?.group(1),
      channel: channelMatch?.group(1),
      isInstalled: true,
    );
  }

  /// Detect Flutter configuration from project
  static Future<ProjectFlutterInfo> detectFromProject(
      String projectPath) async {
    final pubspecPath = p.join(projectPath, 'pubspec.yaml');

    if (!FileUtils.fileExists(pubspecPath)) {
      throw Exception('pubspec.yaml not found at $projectPath');
    }

    final content = await FileUtils.readFile(pubspecPath);
    final pubspec = loadYaml(content) as Map;

    final environment = pubspec['environment'] as Map?;
    final dependencies = pubspec['dependencies'] as Map? ?? {};

    return ProjectFlutterInfo(
      projectName: pubspec['name']?.toString(),
      sdkConstraint: environment?['sdk']?.toString(),
      requiredFlutterVersion: environment?['flutter']?.toString(),
      dependencies: Map<String, dynamic>.from(dependencies),
    );
  }

  /// Check if Flutter is properly installed
  static Future<bool> isFlutterHealthy() async {
    final doctorResult = await ProcessRunner.flutter(['doctor', '--machine']);
    return doctorResult.success;
  }

  /// Get Flutter SDK path
  static Future<String?> getFlutterSdkPath() async {
    if (Platform.environment.containsKey('FLUTTER_ROOT')) {
      return Platform.environment['FLUTTER_ROOT'];
    }

    final result = await ProcessRunner.flutter(['--version']);
    if (!result.success) return null;

    // Try to extract from output
    final match = RegExp(r'Flutter SDK at (.+)').firstMatch(result.stdout);
    return match?.group(1);
  }

  /// Check if project uses Flutter
  static Future<bool> isFlutterProject(String projectPath) async {
    final pubspecPath = p.join(projectPath, 'pubspec.yaml');
    if (!FileUtils.fileExists(pubspecPath)) return false;

    return await FileUtils.fileContains(
      pubspecPath,
      RegExp(r'dependencies:\s*\n\s*flutter:', multiLine: true),
    );
  }

  /// Get recommended Flutter version for project
  static Future<String?> getRecommendedVersion(String projectPath) async {
    final projectInfo = await detectFromProject(projectPath);
    final constraint = projectInfo.sdkConstraint;

    if (constraint == null) return null;

    // Remove quotes if present
    final cleanConstraint =
        constraint.replaceAll('"', '').replaceAll("'", '').trim();

    // Parse constraint like ">=3.0.0 <4.0.0" or ">=2.19.0 <3.0.0"
    var match = RegExp(r'>=\s*(\d+\.\d+\.\d+)').firstMatch(cleanConstraint);
    if (match != null) return match.group(1);

    // Parse caret constraint like "^3.5.3"
    match = RegExp(r'\^\s*(\d+\.\d+\.\d+)').firstMatch(cleanConstraint);
    if (match != null) return match.group(1);

    // Parse any version number
    match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(cleanConstraint);
    return match?.group(1);
  }

  /// Detect original Flutter version from .metadata file
  /// WARNING: This shows the version when project was CREATED, not current working version
  static Future<String?> detectOriginalVersion(String projectPath) async {
    final metadataPath = p.join(projectPath, '.metadata');

    if (!FileUtils.fileExists(metadataPath)) {
      return null;
    }

    try {
      final content = await FileUtils.readFile(metadataPath);

      final yaml = loadYaml(content) as Map;

      // Get the revision from .metadata
      final version = yaml['version'] as Map?;
      final revision = version?['revision']?.toString();

      if (revision == null) {
        return null;
      }

      // Try to get version from Flutter's GitHub API
      final versionFromGit = await _getVersionFromRevision(revision);
      if (versionFromGit != null) {
        return versionFromGit;
      }

      // Fallback: Use pubspec.yaml SDK constraint
      return await getRecommendedVersion(projectPath);
    } catch (e) {
      return null;
    }
  }

  /// Query Flutter GitHub repository to get version from commit revision
  static Future<String?> _getVersionFromRevision(String revision) async {
    try {
      // Get the commit details to find its date
      final commitUrl =
          'https://api.github.com/repos/flutter/flutter/commits/$revision';

      final commitResponse = await http.get(
        Uri.parse(commitUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (commitResponse.statusCode != 200) {
        return null;
      }

      final commitData =
          jsonDecode(commitResponse.body) as Map<String, dynamic>;
      final commit = commitData['commit'] as Map<String, dynamic>?;
      final committer = commit?['committer'] as Map<String, dynamic>?;
      final commitDate = committer?['date'] as String?;

      // Search through multiple pages of tags to find matching commit
      final shortRevision = revision.substring(0, 7);

      for (var page = 1; page <= 10; page++) {
        final tagsUrl =
            'https://api.github.com/repos/flutter/flutter/tags?per_page=100&page=$page';

        final tagsResponse = await http.get(
          Uri.parse(tagsUrl),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        );

        if (tagsResponse.statusCode != 200) {
          break;
        }

        final tags = jsonDecode(tagsResponse.body) as List<dynamic>;

        if (tags.isEmpty) break;

        for (final tag in tags) {
          final tagMap = tag as Map<String, dynamic>;
          final tagName = tagMap['name'] as String?;
          final tagCommit = tagMap['commit'] as Map<String, dynamic>?;
          final sha = tagCommit?['sha'] as String?;

          if (tagName != null && sha != null && sha.startsWith(shortRevision)) {
            final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(tagName);
            if (versionMatch != null &&
                !tagName.contains('beta') &&
                !tagName.contains('dev')) {
              final version = versionMatch.group(1);
              return version;
            }
          }
        }
      }

      // If no exact match, find closest release by date
      if (commitDate != null) {
        final releasesUrl =
            'https://api.github.com/repos/flutter/flutter/releases?per_page=100';
        final releasesResponse = await http.get(
          Uri.parse(releasesUrl),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        );

        if (releasesResponse.statusCode == 200) {
          final releases = jsonDecode(releasesResponse.body) as List<dynamic>;
          final commitDateTime = DateTime.parse(commitDate);

          // Find the first stable release published on or after this commit
          for (final release in releases) {
            final releaseMap = release as Map<String, dynamic>;
            final publishedAt = releaseMap['published_at'] as String?;
            final tagName = releaseMap['tag_name'] as String?;
            final prerelease = releaseMap['prerelease'] as bool? ?? false;
            final draft = releaseMap['draft'] as bool? ?? false;

            if (publishedAt != null &&
                tagName != null &&
                !prerelease &&
                !draft) {
              final releaseDateTime = DateTime.parse(publishedAt);

              // Find release within 30 days of the commit
              if (releaseDateTime.isAfter(commitDateTime) &&
                  releaseDateTime.difference(commitDateTime).inDays <= 30) {
                final versionMatch =
                    RegExp(r'(\d+\.\d+\.\d+)').firstMatch(tagName);
                if (versionMatch != null) {
                  final version = versionMatch.group(1);
                  return version;
                }
              }
            }
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Detects the actual working Flutter version that project dependencies require
  /// This is more accurate than .metadata as it reflects current dependency needs
  static Future<String?> detectRequiredVersion(String projectPath) async {
    final pubspecPath = p.join(projectPath, 'pubspec.yaml');

    if (!FileUtils.fileExists(pubspecPath)) {
      return null;
    }

    try {
      final content = await FileUtils.readFile(pubspecPath);
      final pubspec = loadYaml(content) as Map;

      // Check SDK constraint in environment
      final environment = pubspec['environment'] as Map?;

      if (environment != null) {
        final sdk = environment['sdk'] as String?;

        if (sdk != null) {
          // Remove quotes if present
          final cleanSdk = sdk.replaceAll('"', '').replaceAll("'", '').trim();

          // Parse SDK constraint to find minimum required version
          // Examples: ">=3.4.0 <4.0.0", "^3.5.3", "3.5.0", ">=2.19.0 <3.0.0"

          // Handle range constraints (>=X.Y.Z)
          final rangeMatch =
              RegExp(r'>=\s*(\d+\.\d+\.\d+)').firstMatch(cleanSdk);
          if (rangeMatch != null) {
            return rangeMatch.group(1);
          }

          // Handle caret constraints (^X.Y.Z)
          final caretMatch =
              RegExp(r'\^\s*(\d+\.\d+\.\d+)').firstMatch(cleanSdk);
          if (caretMatch != null) {
            return caretMatch.group(1);
          }

          // Handle exact version (X.Y.Z)
          final exactMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(cleanSdk);
          if (exactMatch != null) {
            return exactMatch.group(1);
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check if dependencies have SDK requirements that conflict with a Flutter version
  /// Returns a map of package name -> {required SDK, compatible version}
  static Future<Map<String, Map<String, String>>> findCompatiblePackageVersions(
      String projectPath, String dartSdkVersion) async {
    final pubspecPath = p.join(projectPath, 'pubspec.yaml');
    final pubspecFile = File(pubspecPath);

    if (!pubspecFile.existsSync()) {
      return {};
    }

    final packageSolutions = <String, Map<String, String>>{};

    try {
      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content) as YamlMap;

      // Get all dependencies (regular + dev dependencies)
      final dependencies = <String, String>{};
      if (yaml['dependencies'] != null) {
        final deps = yaml['dependencies'] as YamlMap;
        for (final entry in deps.entries) {
          if (entry.value is String) {
            dependencies[entry.key.toString()] = entry.value.toString();
          }
        }
      }
      if (yaml['dev_dependencies'] != null) {
        final devDeps = yaml['dev_dependencies'] as YamlMap;
        for (final entry in devDeps.entries) {
          if (entry.value is String) {
            dependencies[entry.key.toString()] = entry.value.toString();
          }
        }
      }

      // Check each package
      for (final entry in dependencies.entries) {
        final packageName = entry.key;
        final currentConstraint = entry.value;

        if (packageName == 'flutter' ||
            packageName == 'flutter_test' ||
            packageName == 'flutter_driver') {
          continue; // Skip Flutter SDK packages
        }

        try {
          // Find compatible version for this package
          final solution = await _findCompatibleVersion(
            packageName,
            currentConstraint,
            dartSdkVersion,
          );

          if (solution != null) {
            packageSolutions[packageName] = solution;
          }
        } catch (e) {
          // Skip packages that fail to query
          continue;
        }
      }

      return packageSolutions;
    } catch (e) {
      return {};
    }
  }

  /// Find a compatible version of a package that works with the given Dart SDK
  static Future<Map<String, String>?> _findCompatibleVersion(
    String packageName,
    String currentConstraint,
    String dartSdkVersion,
  ) async {
    try {
      // Query pub.dev API for package versions
      final response = await http.get(
        Uri.parse('https://pub.dev/api/packages/$packageName'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final versions = data['versions'] as List<dynamic>?;

      if (versions == null || versions.isEmpty) return null;

      // Sort versions by date (newest first)
      versions.sort((a, b) {
        final dateA = DateTime.parse((a as Map)['published'] as String);
        final dateB = DateTime.parse((b as Map)['published'] as String);
        return dateB.compareTo(dateA);
      });

      // Try to find the latest version that is compatible with our Dart SDK
      for (final versionData in versions) {
        final versionMap = versionData as Map<String, dynamic>;
        final version = versionMap['version'] as String;
        final pubspec = versionMap['pubspec'] as Map<String, dynamic>?;

        if (pubspec == null) continue;

        final environment = pubspec['environment'] as Map?;
        if (environment == null) {
          // No SDK constraint = compatible with any SDK
          // But prefer versions with constraints for safety
          continue;
        }

        final sdkConstraint = environment['sdk'] as String?;
        if (sdkConstraint == null) continue;

        // Check if this version is compatible with our Dart SDK
        if (_isDartSdkCompatible(dartSdkVersion, sdkConstraint)) {
          // Found a compatible version!
          // Extract min SDK requirement
          final minSdkMatch =
              RegExp(r'>=?\s*(\d+\.\d+\.\d+)').firstMatch(sdkConstraint);
          final minSdk = minSdkMatch?.group(1) ?? 'unknown';

          return {
            'version': version,
            'sdkConstraint': sdkConstraint,
            'minSdk': minSdk,
            'currentConstraint': currentConstraint,
          };
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check if a Dart SDK version is compatible with a package SDK constraint
  static bool _isDartSdkCompatible(String dartSdk, String constraint) {
    try {
      // Clean the constraint
      final cleanConstraint =
          constraint.replaceAll('"', '').replaceAll("'", '').trim();

      // Extract min and max versions from constraint
      final minMatch =
          RegExp(r'>=?\s*(\d+\.\d+\.\d+)').firstMatch(cleanConstraint);
      final maxMatch =
          RegExp(r'<\s*(\d+\.\d+\.\d+)').firstMatch(cleanConstraint);

      if (minMatch == null) return false;

      final minVersion = minMatch.group(1)!;
      final maxVersion = maxMatch?.group(1);

      // Check if dartSdk >= minVersion
      if (_compareVersions(dartSdk, minVersion) < 0) {
        return false;
      }

      // Check if dartSdk < maxVersion
      if (maxVersion != null && _compareVersions(dartSdk, maxVersion) >= 0) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if dependencies have SDK requirements that conflict with a Flutter version
  /// Returns a map of package name -> required SDK version (DEPRECATED - use findCompatiblePackageVersions)
  static Future<Map<String, String>> checkDependencySdkRequirements(
      String projectPath) async {
    final pubspecPath = p.join(projectPath, 'pubspec.yaml');
    final pubspecFile = File(pubspecPath);

    if (!pubspecFile.existsSync()) {
      return {};
    }

    final conflicts = <String, String>{};

    try {
      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content) as YamlMap;

      // Get all dependencies (regular + dev dependencies)
      final dependencies = <String>[];
      if (yaml['dependencies'] != null) {
        final deps = yaml['dependencies'] as YamlMap;
        dependencies.addAll(deps.keys.cast<String>());
      }
      if (yaml['dev_dependencies'] != null) {
        final devDeps = yaml['dev_dependencies'] as YamlMap;
        dependencies.addAll(devDeps.keys.cast<String>());
      }

      // Query pub.dev API for each package to get SDK requirements
      for (final packageName in dependencies) {
        if (packageName == 'flutter' ||
            packageName == 'flutter_test' ||
            packageName == 'flutter_driver') {
          continue; // Skip Flutter SDK packages
        }

        try {
          // Query pub.dev API for package info
          final response = await http.get(
            Uri.parse('https://pub.dev/api/packages/$packageName'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final latest = data['latest'] as Map<String, dynamic>?;

            if (latest != null) {
              final pubspec = latest['pubspec'] as Map<String, dynamic>?;
              if (pubspec != null) {
                final environment = pubspec['environment'] as Map?;
                if (environment != null) {
                  final sdkConstraint = environment['sdk'] as String?;
                  if (sdkConstraint != null) {
                    // Extract minimum SDK version
                    final minVersionMatch = RegExp(r'>=?\s*(\d+\.\d+\.\d+)')
                        .firstMatch(sdkConstraint);
                    if (minVersionMatch != null) {
                      final minSdk = minVersionMatch.group(1)!;
                      // Only flag if requires SDK >= 2.12 (null safety era onwards)
                      final parts = minSdk.split('.');
                      if (parts.isNotEmpty) {
                        final major = int.tryParse(parts[0]) ?? 0;
                        final minor = parts.length > 1
                            ? (int.tryParse(parts[1]) ?? 0)
                            : 0;
                        if (major > 2 || (major == 2 && minor >= 12)) {
                          conflicts[packageName] = minSdk;
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        } catch (e) {
          // Skip packages that fail to query
          continue;
        }
      }

      return conflicts;
    } catch (e) {
      return {};
    }
  }

  /// Find minimum Flutter version that satisfies Dart SDK requirement
  /// Returns null if no mapping available
  static String? getFlutterVersionForDartSdk(String dartSdkVersion) {
    // Flutter -> Dart SDK version mapping (approximate)
    // Source: https://docs.flutter.dev/release/archive
    final flutterDartMap = {
      '2.12.0': '2.2.0', // Null safety
      '2.15.0': '2.8.0',
      '2.17.0': '3.0.0',
      '2.18.0': '3.3.0',
      '2.19.0': '3.7.0',
      '3.0.0': '3.10.0',
      '3.1.0': '3.13.0',
      '3.2.0': '3.16.0',
      '3.3.0': '3.19.0',
      '3.4.0': '3.22.0',
      '3.5.0': '3.24.0',
    };

    // Find the minimum Flutter version for the required Dart SDK
    for (final entry in flutterDartMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      if (_compareVersions(entry.key, dartSdkVersion) >= 0) {
        return entry.value;
      }
    }

    // If Dart SDK is very new, suggest latest Flutter
    final parts = dartSdkVersion.split('.');
    if (parts.isNotEmpty) {
      final major = int.tryParse(parts[0]) ?? 0;
      if (major >= 3) {
        return '3.24.0'; // Latest stable as of writing
      }
    }

    return null;
  }

  static int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = v2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;

      if (p1 > p2) return 1;
      if (p2 > p1) return -1;
    }

    return 0;
  }

  /// Gets the best version to use: compares .metadata vs pubspec.yaml requirements
  /// Returns the NEWER version to ensure compatibility
  static Future<String?> detectBestVersion(String projectPath) async {
    final metadataVersion = await detectOriginalVersion(projectPath);
    final requiredVersion = await detectRequiredVersion(projectPath);

    // If we only have one, use it
    if (metadataVersion == null) return requiredVersion;
    if (requiredVersion == null) return metadataVersion;

    // Compare versions and return the newer one
    final parts1 =
        metadataVersion.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 =
        requiredVersion.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;

      if (p1 > p2) return metadataVersion;
      if (p2 > p1) return requiredVersion;
    }

    // Same version
    return metadataVersion;
  }
}
