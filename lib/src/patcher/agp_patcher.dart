import 'package:path/path.dart' as p;
import '../utils/file_utils.dart';

class AgpPatcher {
  final String projectPath;

  AgpPatcher(this.projectPath);

  /// Update Android Gradle Plugin version
  Future<bool> updateVersion(String version) async {
    final buildGradle = p.join(projectPath, 'android', 'build.gradle');
    if (!FileUtils.fileExists(buildGradle)) return false;

    try {
      // Create backup before modifying
      await FileUtils.createBackup(
        projectPath,
        buildGradle,
        'AGP (Android Gradle Plugin) update to version $version',
      );

      var content = await FileUtils.readFile(buildGradle);

      // Pattern 1: classpath 'com.android.tools.build:gradle:x.x.x'
      content = content.replaceAll(
        RegExp(
            "classpath\\s+['\"]com\\.android\\.tools\\.build:gradle:[^'\"]+['\"]"),
        "classpath 'com.android.tools.build:gradle:$version'",
      );

      // Pattern 2: id 'com.android.application' version 'x.x.x'
      content = content.replaceAll(
        RegExp(
            "id\\s+['\"]com\\.android\\.application['\"]\\s+version\\s+['\"][^'\"]+['\"]"),
        "id 'com.android.application' version '$version'",
      );

      await FileUtils.writeFile(buildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Ensure AGP is declared in dependencies
  Future<bool> ensureAgpDependency(String version) async {
    final buildGradle = p.join(projectPath, 'android', 'build.gradle');
    if (!FileUtils.fileExists(buildGradle)) return false;

    try {
      var content = await FileUtils.readFile(buildGradle);

      // Check if AGP is already declared
      if (!content.contains('com.android.tools.build:gradle')) {
        // Add it to buildscript dependencies
        if (content.contains('dependencies {')) {
          content = content.replaceFirst(
            RegExp(r'dependencies\s*\{'),
            '''dependencies {
        classpath 'com.android.tools.build:gradle:$version\'''',
          );
        }
      }

      await FileUtils.writeFile(buildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fix namespace declaration (required for AGP 8.0+)
  Future<bool> ensureNamespace() async {
    final appBuildGradle =
        p.join(projectPath, 'android', 'app', 'build.gradle');
    if (!FileUtils.fileExists(appBuildGradle)) return false;

    try {
      var content = await FileUtils.readFile(appBuildGradle);

      // Check if namespace is already declared
      if (!content.contains('namespace')) {
        // Try to get package name from AndroidManifest.xml
        final manifest = p.join(projectPath, 'android', 'app', 'src', 'main',
            'AndroidManifest.xml');
        String? packageName;

        if (FileUtils.fileExists(manifest)) {
          final manifestContent = await FileUtils.readFile(manifest);
          final match =
              RegExp(r'package="([^"]+)"').firstMatch(manifestContent);
          packageName = match?.group(1);
        }

        packageName ??= 'com.example.app';

        // Add namespace in android block
        content = content.replaceFirst(
          RegExp(r'android\s*\{'),
          '''android {
    namespace '$packageName\'''',
        );

        await FileUtils.writeFile(appBuildGradle, content);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Update SDK versions
  Future<bool> updateSdkVersions({
    required int minSdk,
    required int compileSdk,
    required int targetSdk,
  }) async {
    final appBuildGradle =
        p.join(projectPath, 'android', 'app', 'build.gradle');
    if (!FileUtils.fileExists(appBuildGradle)) return false;

    try {
      var content = await FileUtils.readFile(appBuildGradle);

      // Update compileSdk
      if (content.contains('compileSdkVersion')) {
        content = content.replaceAll(
          RegExp(r'compileSdkVersion\s+\d+'),
          'compileSdk $compileSdk',
        );
      } else if (content.contains('compileSdk')) {
        content = content.replaceAll(
          RegExp(r'compileSdk\s+\d+'),
          'compileSdk $compileSdk',
        );
      } else {
        // Add compileSdk
        content = content.replaceFirst(
          RegExp(r'android\s*\{'),
          'android {\n    compileSdk $compileSdk',
        );
      }

      // Update minSdkVersion
      content = content.replaceAll(
        RegExp(r'minSdkVersion\s+\d+'),
        'minSdkVersion $minSdk',
      );

      // Also handle flutter.minSdkVersion
      content = content.replaceAll(
        RegExp(r'minSdkVersion\s+flutter\.minSdkVersion'),
        'minSdkVersion $minSdk',
      );

      // Update targetSdkVersion
      content = content.replaceAll(
        RegExp(r'targetSdkVersion\s+\d+'),
        'targetSdkVersion $targetSdk',
      );

      await FileUtils.writeFile(appBuildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fix Java compile options
  Future<bool> fixCompileOptions() async {
    final appBuildGradle =
        p.join(projectPath, 'android', 'app', 'build.gradle');
    if (!FileUtils.fileExists(appBuildGradle)) return false;

    try {
      var content = await FileUtils.readFile(appBuildGradle);

      if (!content.contains('compileOptions')) {
        // Add compileOptions in android block
        content = content.replaceFirst(
          RegExp(r'android\s*\{'),
          '''android {
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
''',
        );
      } else {
        // Update existing compileOptions
        content = content.replaceAll(
          RegExp(r'compileOptions\s*\{[^}]*\}', multiLine: true, dotAll: true),
          '''compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }''',
        );
      }

      await FileUtils.writeFile(appBuildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Remove deprecated features
  Future<bool> removeDeprecatedFeatures() async {
    final appBuildGradle =
        p.join(projectPath, 'android', 'app', 'build.gradle');
    if (!FileUtils.fileExists(appBuildGradle)) return false;

    try {
      var content = await FileUtils.readFile(appBuildGradle);

      // Remove useProguard (deprecated in AGP 7.0+)
      content = content.replaceAll(
        RegExp(r'useProguard\s+\w+'),
        '',
      );

      // Clean up empty lines
      content = content.replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n');

      await FileUtils.writeFile(appBuildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }
}
