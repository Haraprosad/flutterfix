import 'dart:io';
import '../runner/process_runner.dart';
import '../utils/file_utils.dart';
import 'package:path/path.dart' as p;

class GradleInfo {
  final String? version;
  final String? agpVersion;
  final String? kotlinVersion;
  final String? javaVersion;
  final bool isInstalled;

  GradleInfo({
    this.version,
    this.agpVersion,
    this.kotlinVersion,
    this.javaVersion,
    this.isInstalled = false,
  });

  @override
  String toString() =>
      'Gradle $version, AGP $agpVersion, Kotlin $kotlinVersion';
}

class AndroidProjectInfo {
  final int? minSdk;
  final int? compileSdk;
  final int? targetSdk;
  final String? namespace;
  final String? applicationId;

  AndroidProjectInfo({
    this.minSdk,
    this.compileSdk,
    this.targetSdk,
    this.namespace,
    this.applicationId,
  });
}

class GradleDetector {
  /// Detect Gradle version from wrapper
  static Future<String?> detectWrapperVersion(String projectPath) async {
    final wrapperProps = p.join(
      projectPath,
      'android',
      'gradle',
      'wrapper',
      'gradle-wrapper.properties',
    );

    if (!FileUtils.fileExists(wrapperProps)) return null;

    final content = await FileUtils.readFile(wrapperProps);
    final match = RegExp(r'gradle-(\d+\.\d+(?:\.\d+)?)-').firstMatch(content);
    return match?.group(1);
  }

  /// Detect installed Gradle version
  static Future<String?> detectInstalledVersion(String projectPath) async {
    final result = await ProcessRunner.gradle(
      ['--version'],
      projectPath: projectPath,
    );

    if (!result.success) return null;

    final match =
        RegExp(r'Gradle\s+(\d+\.\d+(?:\.\d+)?)').firstMatch(result.stdout);
    return match?.group(1);
  }

  /// Detect Android Gradle Plugin version
  static Future<String?> detectAgpVersion(String projectPath) async {
    final buildGradle = p.join(projectPath, 'android', 'build.gradle');
    if (!FileUtils.fileExists(buildGradle)) return null;

    final content = await FileUtils.readFile(buildGradle);

    // Try different patterns
    final patterns = [
      RegExp(r"com\.android\.tools\.build:gradle:(['\" "]?)(\d+\.\d+\.\d+)\1"),
      RegExp(r'id\s*["'
          ']com\.android\.application["'
          ']\s+version\s+["'
          '](\d+\.\d+\.\d+)["'
          ']'),
    ];

    for (var pattern in patterns) {
      final match = pattern.firstMatch(content);
      if (match != null) {
        return match.group(2) ?? match.group(1);
      }
    }

    return null;
  }

  /// Detect Kotlin version
  static Future<String?> detectKotlinVersion(String projectPath) async {
    final buildGradle = p.join(projectPath, 'android', 'build.gradle');
    if (!FileUtils.fileExists(buildGradle)) return null;

    final content = await FileUtils.readFile(buildGradle);

    // Try different patterns
    final patterns = [
      RegExp(r"ext\.kotlin_version\s*=\s*(['\" "])(\d+\.\d+\.\d+)\1"),
      RegExp(
          r'kotlin\(["' ']jvm["' ']\)\s+version\s+["' '](\d+\.\d+\.\d+)["' ']'),
      RegExp(r'org\.jetbrains\.kotlin:kotlin-gradle-plugin:(\d+\.\d+\.\d+)'),
    ];

    for (var pattern in patterns) {
      final match = pattern.firstMatch(content);
      if (match != null) return match.group(1);
    }

    return null;
  }

  /// Detect Java version
  static Future<String?> detectJavaVersion() async {
    final result = await ProcessRunner.java(['-version']);

    final output = result.stderr + result.stdout;
    final match = RegExp(r'version\s+"?(\d+)').firstMatch(output);

    if (match != null) {
      var version = match.group(1)!;
      // Handle old format like "1.8.0"
      if (version == '1') {
        final fullMatch = RegExp(r'version\s+"?1\.(\d+)').firstMatch(output);
        version = fullMatch?.group(1) ?? version;
      }
      return version;
    }

    return null;
  }

  /// Detect all Gradle-related info
  static Future<GradleInfo> detectAll(String projectPath) async {
    final wrapperVersion = await detectWrapperVersion(projectPath);
    final installedVersion = await detectInstalledVersion(projectPath);
    final agpVersion = await detectAgpVersion(projectPath);
    final kotlinVersion = await detectKotlinVersion(projectPath);
    final javaVersion = await detectJavaVersion();

    return GradleInfo(
      version: wrapperVersion ?? installedVersion,
      agpVersion: agpVersion,
      kotlinVersion: kotlinVersion,
      javaVersion: javaVersion,
      isInstalled: wrapperVersion != null || installedVersion != null,
    );
  }

  /// Detect Android project configuration
  static Future<AndroidProjectInfo> detectAndroidConfig(
    String projectPath,
  ) async {
    final appBuildGradle =
        p.join(projectPath, 'android', 'app', 'build.gradle');
    if (!FileUtils.fileExists(appBuildGradle)) {
      return AndroidProjectInfo();
    }

    final content = await FileUtils.readFile(appBuildGradle);

    // Extract SDK versions
    final minSdkMatch = RegExp(r'minSdkVersion\s+(\d+)').firstMatch(content);
    final compileSdkMatch =
        RegExp(r'compileSdk(?:Version)?\s+(\d+)').firstMatch(content);
    final targetSdkMatch =
        RegExp(r'targetSdkVersion\s+(\d+)').firstMatch(content);
    final namespaceMatch =
        RegExp(r'namespace\s+["' ']([^"' ']+)["' ']').firstMatch(content);
    final appIdMatch =
        RegExp(r'applicationId\s+["' ']([^"' ']+)["' ']').firstMatch(content);

    return AndroidProjectInfo(
      minSdk: minSdkMatch != null ? int.tryParse(minSdkMatch.group(1)!) : null,
      compileSdk: compileSdkMatch != null
          ? int.tryParse(compileSdkMatch.group(1)!)
          : null,
      targetSdk: targetSdkMatch != null
          ? int.tryParse(targetSdkMatch.group(1)!)
          : null,
      namespace: namespaceMatch?.group(1),
      applicationId: appIdMatch?.group(1),
    );
  }

  /// Check if Gradle wrapper exists
  static bool hasGradleWrapper(String projectPath) {
    final wrapperScript = Platform.isWindows
        ? p.join(projectPath, 'android', 'gradlew.bat')
        : p.join(projectPath, 'android', 'gradlew');

    return FileUtils.fileExists(wrapperScript);
  }

  /// Check Gradle compatibility with Java
  static bool isCompatibleWithJava(String gradleVersion, String javaVersion) {
    final gradleNum =
        double.tryParse(gradleVersion.split('.').take(2).join('.')) ?? 0;
    final javaNum = int.tryParse(javaVersion) ?? 0;

    if (gradleNum >= 8.0) return javaNum >= 17;
    if (gradleNum >= 7.0) return javaNum >= 11;
    if (gradleNum >= 6.7) return javaNum >= 11;

    return true; // Older versions are usually compatible
  }
}
