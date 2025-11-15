import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/file_utils.dart';
import '../runner/process_runner.dart';

class IosPatcher {
  final String projectPath;

  IosPatcher(this.projectPath);

  /// Update iOS deployment target in Podfile
  Future<bool> updateDeploymentTarget(String target) async {
    if (!Platform.isMacOS) return false;

    final podfilePath = p.join(projectPath, 'ios', 'Podfile');
    if (!FileUtils.fileExists(podfilePath)) return false;

    try {
      var content = await FileUtils.readFile(podfilePath);

      // Update platform line
      if (content.contains('platform :ios')) {
        content = content.replaceAll(
          RegExp("platform\\s+:ios,\\s+['\"][^'\"]*['\"]"),
          "platform :ios, '$target'",
        );
      } else {
        // Add platform line at the top
        content = "platform :ios, '$target'\n\n" + content;
      }

      await FileUtils.writeFile(podfilePath, content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Run pod install
  Future<bool> installPods() async {
    if (!Platform.isMacOS) return false;

    final result = await ProcessRunner.run(
      'pod',
      ['install'],
      workingDirectory: p.join(projectPath, 'ios'),
    );

    return result.success;
  }

  /// Clean iOS build cache
  Future<bool> cleanBuild() async {
    if (!Platform.isMacOS) return false;

    try {
      final buildDir = p.join(projectPath, 'ios', 'build');
      if (FileUtils.dirExists(buildDir)) {
        await FileUtils.deleteDir(buildDir);
      }

      // Clean derived data
      await ProcessRunner.run(
          'rm', ['-rf', '~/Library/Developer/Xcode/DerivedData/*']);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Update minimum deployment target in project.pbxproj
  Future<bool> updatePbxProjectTarget(String target) async {
    final pbxPath =
        p.join(projectPath, 'ios', 'Runner.xcodeproj', 'project.pbxproj');
    if (!FileUtils.fileExists(pbxPath)) return false;

    try {
      await FileUtils.replaceInFile(
        pbxPath,
        RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = \d+\.\d+'),
        'IPHONEOS_DEPLOYMENT_TARGET = $target',
      );
      return true;
    } catch (e) {
      return false;
    }
  }
}
