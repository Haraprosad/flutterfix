import 'package:path/path.dart' as p;
import '../utils/file_utils.dart';

class KotlinPatcher {
  final String projectPath;

  KotlinPatcher(this.projectPath);

  /// Update Kotlin version in build.gradle
  Future<bool> updateVersion(String version) async {
    final buildGradle = p.join(projectPath, 'android', 'build.gradle');
    if (!FileUtils.fileExists(buildGradle)) return false;

    try {
      var content = await FileUtils.readFile(buildGradle);

      // Update ext.kotlin_version
      if (content.contains('ext.kotlin_version')) {
        content = content.replaceAll(
          RegExp("ext\\.kotlin_version\\s*=\\s*['\"][^'\"]*['\"]"),
          "ext.kotlin_version = '$version'",
        );
      } else {
        // Add ext.kotlin_version in buildscript
        if (content.contains('buildscript {')) {
          content = content.replaceFirst(
            'buildscript {',
            "buildscript {\n    ext.kotlin_version = '$version'",
          );
        } else {
          // Add buildscript block
          content =
              "buildscript {\n    ext.kotlin_version = '$version'\n}\n\n" +
                  content;
        }
      }

      await FileUtils.writeFile(buildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Ensure Kotlin plugin is declared
  Future<bool> ensureKotlinPlugin(String version) async {
    final buildGradle = p.join(projectPath, 'android', 'build.gradle');
    if (!FileUtils.fileExists(buildGradle)) return false;

    try {
      var content = await FileUtils.readFile(buildGradle);

      // Check if Kotlin plugin is declared
      if (!content.contains('org.jetbrains.kotlin:kotlin-gradle-plugin')) {
        // Add to buildscript dependencies
        if (content.contains('dependencies {')) {
          content = content.replaceAllMapped(
            RegExp(r'buildscript\s*\{[^}]*dependencies\s*\{', dotAll: true),
            (match) =>
                '${match.group(0)}\n        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:\$kotlin_version"',
          );
        }
      } else {
        // Update existing plugin to use variable
        content = content.replaceAll(
          RegExp(
              "classpath\\s+['\"]org\\.jetbrains\\.kotlin:kotlin-gradle-plugin:[^'\"]*['\"]"),
          'classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:\$kotlin_version"',
        );
      }

      await FileUtils.writeFile(buildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Apply kotlin-android plugin to app module
  Future<bool> applyKotlinAndroidPlugin() async {
    final appBuildGradle =
        p.join(projectPath, 'android', 'app', 'build.gradle');
    if (!FileUtils.fileExists(appBuildGradle)) return false;

    try {
      var content = await FileUtils.readFile(appBuildGradle);

      // Check if kotlin-android is already applied
      if (!content.contains("apply plugin: 'kotlin-android'") &&
          !content.contains('id "org.jetbrains.kotlin.android"') &&
          !content.contains("id 'org.jetbrains.kotlin.android'")) {
        // Add after the first apply plugin line
        content = content.replaceAllMapped(
          RegExp(r"apply plugin: '[^']*'"),
          (match) => "${match.group(0)}\napply plugin: 'kotlin-android'",
        );
      }

      await FileUtils.writeFile(appBuildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Add kotlinOptions for JVM target
  Future<bool> addKotlinOptions() async {
    final appBuildGradle =
        p.join(projectPath, 'android', 'app', 'build.gradle');
    if (!FileUtils.fileExists(appBuildGradle)) return false;

    try {
      var content = await FileUtils.readFile(appBuildGradle);

      // Only add if kotlin-android is applied
      if (content.contains('kotlin-android') &&
          !content.contains('kotlinOptions')) {
        // Add kotlinOptions in android block
        content = content.replaceFirst(
          RegExp(r'android\s*\{'),
          '''android {
    kotlinOptions {
        jvmTarget = '1.8'
    }
''',
        );
      }

      await FileUtils.writeFile(appBuildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Convert MainActivity from Java to Kotlin (if needed)
  Future<bool> ensureKotlinMainActivity() async {
    // This is a complex operation - skip for now
    // Would need to parse package structure and convert Java to Kotlin
    return true;
  }

  /// Fix Kotlin stdlib dependency
  Future<bool> fixKotlinStdlib() async {
    final appBuildGradle =
        p.join(projectPath, 'android', 'app', 'build.gradle');
    if (!FileUtils.fileExists(appBuildGradle)) return false;

    try {
      var content = await FileUtils.readFile(appBuildGradle);

      // Remove explicit kotlin-stdlib dependencies (handled by Kotlin plugin)
      content = content.replaceAll(
        RegExp(
            "implementation\\s+['\"]org\\.jetbrains\\.kotlin:kotlin-stdlib[^'\"]*['\"]"),
        '// kotlin-stdlib is now included automatically',
      );

      await FileUtils.writeFile(appBuildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Update Kotlin language version
  Future<bool> setLanguageVersion(String version) async {
    final appBuildGradle =
        p.join(projectPath, 'android', 'app', 'build.gradle');
    if (!FileUtils.fileExists(appBuildGradle)) return false;

    try {
      var content = await FileUtils.readFile(appBuildGradle);

      if (content.contains('kotlinOptions')) {
        // Update existing kotlinOptions
        if (!content.contains('languageVersion')) {
          content = content.replaceFirst(
            RegExp(r'kotlinOptions\s*\{'),
            "kotlinOptions {\n        languageVersion = '$version'",
          );
        }
      }

      await FileUtils.writeFile(appBuildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }
}
