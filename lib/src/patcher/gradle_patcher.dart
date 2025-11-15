import 'package:path/path.dart' as p;
import '../utils/file_utils.dart';

// Import ProcessRunner
import '../runner/process_runner.dart';

class GradlePatcher {
  final String projectPath;

  GradlePatcher(this.projectPath);

  /// Update Gradle wrapper version
  Future<bool> updateWrapperVersion(String version) async {
    final wrapperProps = p.join(
      projectPath,
      'android',
      'gradle',
      'wrapper',
      'gradle-wrapper.properties',
    );

    if (!FileUtils.fileExists(wrapperProps)) {
      return false;
    }

    try {
      final distributionUrl =
          'https://services.gradle.org/distributions/gradle-$version-bin.zip';

      await FileUtils.replaceInFile(
        wrapperProps,
        RegExp(r'distributionUrl=.*'),
        'distributionUrl=$distributionUrl',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Optimize Gradle properties
  Future<bool> optimizeProperties() async {
    final gradleProps = p.join(projectPath, 'android', 'gradle.properties');

    final optimizations = {
      'org.gradle.jvmargs': '-Xmx2048m -XX:MaxMetaspaceSize=512m -XX:+HeapDumpOnOutOfMemoryError',
      'org.gradle.parallel': 'true',
      'org.gradle.caching': 'true',
      'org.gradle.configureondemand': 'true',
      'android.useAndroidX': 'true',
      'android.enableJetifier': 'true',
    };

    try {
      String content = '';
      if (FileUtils.fileExists(gradleProps)) {
        content = await FileUtils.readFile(gradleProps);
      }

      for (var entry in optimizations.entries) {
        final key = entry.key;
        final value = entry.value;

        if (content.contains(key)) {
          // Update existing
          content = content.replaceAll(
            RegExp('$key=.*'),
            '$key=$value',
          );
        } else {
          // Add new
          content += '\n$key=$value';
        }
      }

      await FileUtils.writeFile(gradleProps, content.trim() + '\n');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Add Google and Maven Central repositories
  Future<bool> ensureRepositories() async {
    final buildGradle = p.join(projectPath, 'android', 'build.gradle');
    if (!FileUtils.fileExists(buildGradle)) return false;

    try {
      var content = await FileUtils.readFile(buildGradle);

      // Check if repositories block exists in buildscript
      if (!content.contains('repositories') || 
          !content.contains('google()') || 
          !content.contains('mavenCentral()')) {
        
        // Add repositories if missing
        if (content.contains('buildscript {')) {
          final buildscriptStart = content.indexOf('buildscript {');
          final buildscriptEnd = content.indexOf('}', buildscriptStart);
          
          if (buildscriptEnd != -1 && !content.substring(buildscriptStart, buildscriptEnd).contains('repositories')) {
            content = content.replaceFirst(
              'buildscript {',
              '''buildscript {
    repositories {
        google()
        mavenCentral()
    }''',
            );
          }
        }
      }

      // Ensure allprojects repositories
      if (!content.contains('allprojects')) {
        content += '''

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
''';
      }

      await FileUtils.writeFile(buildGradle, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Update Gradle distribution to use HTTPS
  Future<bool> enforceHttps() async {
    final wrapperProps = p.join(
      projectPath,
      'android',
      'gradle',
      'wrapper',
      'gradle-wrapper.properties',
    );

    if (!FileUtils.fileExists(wrapperProps)) return false;

    try {
      await FileUtils.replaceInFile(
        wrapperProps,
        RegExp(r'http://'),
        'https://',
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Clean Gradle cache
  Future<bool> cleanCache() async {
    try {
      // Clean .gradle folder
      final gradleCache = p.join(projectPath, 'android', '.gradle');
      if (FileUtils.dirExists(gradleCache)) {
        await FileUtils.deleteDir(gradleCache);
      }

      // Clean build folders
      final androidBuild = p.join(projectPath, 'android', 'build');
      if (FileUtils.dirExists(androidBuild)) {
        await FileUtils.deleteDir(androidBuild);
      }

      final appBuild = p.join(projectPath, 'android', 'app', 'build');
      if (FileUtils.dirExists(appBuild)) {
        await FileUtils.deleteDir(appBuild);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fix Gradle wrapper permissions (Unix/Mac)
  Future<bool> fixWrapperPermissions() async {
    try {
      final gradlewPath = p.join(projectPath, 'android', 'gradlew');
      if (FileUtils.fileExists(gradlewPath)) {
        await ProcessRunner.run('chmod', ['+x', gradlewPath]);
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}

