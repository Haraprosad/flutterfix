import 'dart:io';
import '../runner/process_runner.dart';
import '../utils/file_utils.dart';
import 'package:path/path.dart' as p;

class IosInfo {
  final String? xcodeVersion;
  final String? swiftVersion;
  final String? cocoaPodsVersion;
  final String? deploymentTarget;
  final bool isXcodeInstalled;
  final bool isCocoaPodsInstalled;

  IosInfo({
    this.xcodeVersion,
    this.swiftVersion,
    this.cocoaPodsVersion,
    this.deploymentTarget,
    this.isXcodeInstalled = false,
    this.isCocoaPodsInstalled = false,
  });

  @override
  String toString() =>
      'Xcode $xcodeVersion, Swift $swiftVersion, CocoaPods $cocoaPodsVersion';
}

class IosProjectInfo {
  final String? bundleId;
  final String? deploymentTarget;
  final List<String> frameworks;

  IosProjectInfo({
    this.bundleId,
    this.deploymentTarget,
    this.frameworks = const [],
  });
}

class IosDetector {
  /// Detect Xcode version
  static Future<String?> detectXcodeVersion() async {
    if (!Platform.isMacOS) return null;

    final result = await ProcessRunner.run('xcodebuild', ['-version']);
    if (!result.success) return null;

    final match =
        RegExp(r'Xcode\s+(\d+\.\d+(?:\.\d+)?)').firstMatch(result.stdout);
    return match?.group(1);
  }

  /// Detect Swift version
  static Future<String?> detectSwiftVersion() async {
    if (!Platform.isMacOS) return null;

    final result = await ProcessRunner.run('swift', ['--version']);
    if (!result.success) return null;

    final match = RegExp(r'Swift\s+version\s+(\d+\.\d+(?:\.\d+)?)')
        .firstMatch(result.stdout);
    return match?.group(1);
  }

  /// Detect CocoaPods version
  static Future<String?> detectCocoaPodsVersion() async {
    final result = await ProcessRunner.run('pod', ['--version']);
    if (!result.success) return null;

    return result.stdout.trim();
  }

  /// Detect all iOS-related info
  static Future<IosInfo> detectAll() async {
    if (!Platform.isMacOS) {
      return IosInfo(
        isXcodeInstalled: false,
        isCocoaPodsInstalled: false,
      );
    }

    final xcodeVersion = await detectXcodeVersion();
    final swiftVersion = await detectSwiftVersion();
    final cocoaPodsVersion = await detectCocoaPodsVersion();

    return IosInfo(
      xcodeVersion: xcodeVersion,
      swiftVersion: swiftVersion,
      cocoaPodsVersion: cocoaPodsVersion,
      isXcodeInstalled: xcodeVersion != null,
      isCocoaPodsInstalled: cocoaPodsVersion != null,
    );
  }

  /// Detect iOS project configuration
  static Future<IosProjectInfo> detectProjectConfig(String projectPath) async {
    final podfilePath = p.join(projectPath, 'ios', 'Podfile');
    final runnerPath =
        p.join(projectPath, 'ios', 'Runner.xcodeproj', 'project.pbxproj');

    String? deploymentTarget;
    String? bundleId;
    final frameworks = <String>[];

    // Read Podfile for deployment target
    if (FileUtils.fileExists(podfilePath)) {
      final podfileContent = await FileUtils.readFile(podfilePath);
      final targetMatch = RegExp("platform\\s+:ios,\\s*['\"](\\d+\\.\\d+)['\"]")
          .firstMatch(podfileContent);
      deploymentTarget = targetMatch?.group(1);
    }

    // Read project.pbxproj for bundle ID
    if (FileUtils.fileExists(runnerPath)) {
      final pbxContent = await FileUtils.readFile(runnerPath);
      final bundleMatch = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);')
          .firstMatch(pbxContent);
      bundleId = bundleMatch?.group(1)?.trim();
    }

    return IosProjectInfo(
      bundleId: bundleId,
      deploymentTarget: deploymentTarget,
      frameworks: frameworks,
    );
  }

  /// Check if Xcode is installed
  static Future<bool> isXcodeInstalled() async {
    if (!Platform.isMacOS) return false;
    return await ProcessRunner.commandExists('xcodebuild');
  }

  /// Check if CocoaPods is installed
  static Future<bool> isCocoaPodsInstalled() async {
    return await ProcessRunner.commandExists('pod');
  }

  /// Check if iOS folder exists in project
  static bool hasIosFolder(String projectPath) {
    return FileUtils.dirExists(p.join(projectPath, 'ios'));
  }

  /// Get recommended deployment target for Flutter version
  static String getRecommendedDeploymentTarget(String flutterVersion) {
    final version = double.tryParse(
          flutterVersion.split('.').take(2).join('.'),
        ) ??
        0;

    if (version >= 3.19) return '12.0';
    if (version >= 3.13) return '11.0';
    if (version >= 3.0) return '11.0';

    return '10.0';
  }

  /// Check if Podfile.lock exists
  static bool hasPodfileLock(String projectPath) {
    return FileUtils.fileExists(p.join(projectPath, 'ios', 'Podfile.lock'));
  }

  /// Check if Pods folder exists
  static bool hasPodsFolder(String projectPath) {
    return FileUtils.dirExists(p.join(projectPath, 'ios', 'Pods'));
  }
}
