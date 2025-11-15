import 'package:yaml/yaml.dart';
import '../runner/process_runner.dart';
import '../utils/file_utils.dart';
import 'package:path/path.dart' as p;
// Platform import
import 'dart:io' show Platform;

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
      // Parse JSON output
      final output = result.stdout;
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

    // Parse constraint like ">=3.0.0 <4.0.0"
    final match = RegExp(r'>=(\d+\.\d+\.\d+)').firstMatch(constraint);
    return match?.group(1);
  }
}
