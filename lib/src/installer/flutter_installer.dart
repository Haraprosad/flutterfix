import 'dart:io';
import 'package:mason_logger/mason_logger.dart';
import 'package:yaml/yaml.dart';
import '../runner/process_runner.dart';
import '../detect/flutter_detector.dart';
import 'package:path/path.dart' as p;

/// Flutter Installer - Auto-install compatible Flutter version
///
/// This class manages Flutter version installation using FVM (Flutter Version Management)
/// or direct git clone for standalone installations.
class FlutterInstaller {
  final Logger logger;
  late Map<String, dynamic> versionMap;

  FlutterInstaller(this.logger);

  /// Load version compatibility map
  Future<void> loadVersionMap() async {
    // Get the path to the flutterfix package's version_map.yaml
    // Use Platform.script to get the location of the running script
    final scriptUri = Platform.script;
    final scriptPath = scriptUri.toFilePath();

    // Navigate to the package root from the script location
    // Typical structure: package_root/bin/flutterfix.dart or package_root/lib/...
    String packageRoot;

    if (scriptPath.contains('${p.separator}bin${p.separator}')) {
      // Running from bin/flutterfix.dart
      packageRoot = p.dirname(p.dirname(scriptPath));
    } else if (scriptPath.contains('${p.separator}lib${p.separator}')) {
      // Running from lib/ (during development)
      packageRoot = p.dirname(p.dirname(scriptPath));
    } else {
      // Fallback: try to find the package root
      packageRoot = Directory.current.path;
    }

    final versionMapPath = p.join(
      packageRoot,
      'lib',
      'src',
      'config',
      'version_map.yaml',
    );

    if (!File(versionMapPath).existsSync()) {
      // Try alternative path for global installation
      final homeDir =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      final globalPath = p.join(
        homeDir!,
        '.pub-cache',
        'global_packages',
        'flutterfix',
        'lib',
        'src',
        'config',
        'version_map.yaml',
      );

      if (File(globalPath).existsSync()) {
        final yamlString = await File(globalPath).readAsString();
        final yamlDoc = loadYaml(yamlString);
        versionMap =
            Map<String, dynamic>.from(yamlDoc['flutter_compatibility']);
        return;
      }

      throw Exception(
          'Version map not found. Tried:\n  - $versionMapPath\n  - $globalPath');
    }

    final yamlString = await File(versionMapPath).readAsString();
    final yamlDoc = loadYaml(yamlString);
    versionMap = Map<String, dynamic>.from(yamlDoc['flutter_compatibility']);
  }

  /// Check if FVM is installed
  Future<bool> isFvmInstalled() async {
    return await ProcessRunner.commandExists('fvm');
  }

  /// Install FVM
  Future<bool> installFvm() async {
    logger.info('📦 Installing FVM (Flutter Version Management)...');

    final result =
        await ProcessRunner.dart(['pub', 'global', 'activate', 'fvm']);

    if (result.success) {
      logger.success('✅ FVM installed successfully');
      return true;
    } else {
      logger.err('❌ Failed to install FVM: ${result.stderr}');
      return false;
    }
  }

  /// Get list of available Flutter versions from version map
  List<String> getAvailableVersions() {
    if (versionMap.isEmpty) {
      return [];
    }
    return versionMap.keys.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Get recommended Flutter version for a project
  Future<String?> getRecommendedVersion(String projectPath) async {
    try {
      final pubspecPath = p.join(projectPath, 'pubspec.yaml');

      if (!File(pubspecPath).existsSync()) {
        logger.warn('⚠️  pubspec.yaml not found');
        return null;
      }

      final projectInfo = await FlutterDetector.detectFromProject(projectPath);

      if (projectInfo.sdkConstraint != null) {
        // Parse SDK constraint (e.g., ">=3.0.0 <4.0.0")
        final constraint = projectInfo.sdkConstraint!;
        final match = RegExp(r'>=?(\d+\.\d+)').firstMatch(constraint);

        if (match != null) {
          final minVersion = match.group(1)!;

          // Find the closest compatible version from version map
          await loadVersionMap();
          final versions = getAvailableVersions();

          for (final version in versions) {
            if (version.startsWith(minVersion)) {
              return version;
            }
          }

          // If exact match not found, get the latest compatible version
          for (final version in versions) {
            final versionNum = double.tryParse(version) ?? 0;
            final minNum = double.tryParse(minVersion) ?? 0;

            if (versionNum >= minNum) {
              return version;
            }
          }
        }
      }
    } catch (e) {
      logger.err('❌ Error detecting recommended version: $e');
    }

    return null;
  }

  /// Install Flutter version using FVM
  Future<bool> installWithFvm(String version) async {
    logger.info('🔄 Installing Flutter $version using FVM...');

    final progress = logger.progress('Downloading Flutter $version');

    final result = await ProcessRunner.run(
      'fvm',
      ['install', version],
      runInShell: true,
    );

    progress.complete();

    if (result.success) {
      logger.success('✅ Flutter $version installed successfully');
      return true;
    } else {
      logger.err('❌ Failed to install Flutter $version');
      logger.err(result.stderr);
      return false;
    }
  }

  /// Use specific Flutter version in a project with FVM
  Future<bool> useVersionInProject(String projectPath, String version) async {
    logger.info('🔧 Setting Flutter $version for project...');

    final result = await ProcessRunner.run(
      'fvm',
      ['use', version],
      workingDirectory: projectPath,
      runInShell: true,
    );

    if (result.success) {
      logger.success('✅ Project configured to use Flutter $version');
      logger.info('💡 Run: fvm flutter run');
      return true;
    } else {
      logger.err('❌ Failed to set Flutter version: ${result.stderr}');
      return false;
    }
  }

  /// Install Flutter version globally (without FVM)
  Future<bool> installStandalone(String version) async {
    logger.info('🔄 Installing Flutter $version (standalone)...');

    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) {
      logger.err('❌ Could not determine home directory');
      return false;
    }

    final flutterDir = p.join(home, 'flutter-versions', version);

    if (Directory(flutterDir).existsSync()) {
      logger.warn('⚠️  Flutter $version already exists at $flutterDir');
      return true;
    }

    logger.info('📁 Installing to: $flutterDir');
    Directory(p.dirname(flutterDir)).createSync(recursive: true);

    final progress = logger.progress('Cloning Flutter SDK');

    final result = await ProcessRunner.run(
      'git',
      [
        'clone',
        '--depth',
        '1',
        '--branch',
        version,
        'https://github.com/flutter/flutter.git',
        flutterDir,
      ],
      runInShell: true,
    );

    progress.complete();

    if (result.success) {
      logger.success('✅ Flutter $version cloned successfully');

      // Run flutter doctor to download dependencies
      logger.info('🔧 Setting up Flutter SDK...');
      final setupProgress = logger.progress('Running flutter doctor');

      final doctorResult = await ProcessRunner.run(
        p.join(flutterDir, 'bin', 'flutter'),
        ['doctor'],
        runInShell: true,
      );

      setupProgress.complete();

      if (doctorResult.success || doctorResult.exitCode == 0) {
        logger.success('✅ Flutter SDK setup complete');
        logger.info('');
        logger.info('💡 To use this version, add to PATH:');
        logger.info('   export PATH="$flutterDir/bin:\$PATH"');
        return true;
      } else {
        logger
            .warn('⚠️  Flutter doctor had issues, but installation completed');
        return true;
      }
    } else {
      logger.err('❌ Failed to clone Flutter: ${result.stderr}');
      return false;
    }
  }

  /// List installed Flutter versions (FVM)
  Future<List<String>> listInstalledVersions() async {
    final hasFvm = await isFvmInstalled();

    if (!hasFvm) {
      return [];
    }

    final result = await ProcessRunner.run(
      'fvm',
      ['list'],
      runInShell: true,
    );

    if (result.success) {
      final versions = <String>[];
      final lines = result.stdout.split('\n');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && RegExp(r'^\d+\.\d+').hasMatch(trimmed)) {
          versions.add(trimmed);
        }
      }

      return versions;
    }

    return [];
  }

  /// Auto-install compatible Flutter version based on project requirements
  Future<bool> autoInstall(String projectPath) async {
    logger.info('🔍 Analyzing project requirements...\n');

    // Load version map
    await loadVersionMap();

    // Get recommended version
    final recommended = await getRecommendedVersion(projectPath);

    if (recommended == null) {
      logger.warn('⚠️  Could not determine recommended Flutter version');
      logger.info('💡 Available versions:');
      for (final version in getAvailableVersions()) {
        logger.info('   • $version');
      }
      return false;
    }

    logger.info('📦 Recommended Flutter version: $recommended\n');

    // Check if FVM is available
    final hasFvm = await isFvmInstalled();

    if (!hasFvm) {
      logger.info('📦 FVM not found. Installing FVM first...\n');
      final fvmInstalled = await installFvm();

      if (!fvmInstalled) {
        logger.warn(
            '⚠️  FVM installation failed. Using standalone installation...\n');
        return await installStandalone(recommended);
      }
    }

    // Install with FVM
    final installed = await installWithFvm(recommended);

    if (!installed) {
      return false;
    }

    // Configure project to use this version
    return await useVersionInProject(projectPath, recommended);
  }

  /// Get version details from version map
  Map<String, dynamic>? getVersionDetails(String version) {
    if (versionMap.isEmpty || !versionMap.containsKey(version)) {
      return null;
    }

    return Map<String, dynamic>.from(versionMap[version]);
  }

  /// Print version compatibility info
  void printVersionInfo(String version) {
    final details = getVersionDetails(version);

    if (details == null) {
      logger.warn('⚠️  Version $version not found in compatibility matrix');
      return;
    }

    logger.info('');
    logger.info('📊 Flutter $version Compatibility:');
    logger.info('   Gradle:      ${details['gradle']}');
    logger.info('   AGP:         ${details['agp']}');
    logger.info('   Kotlin:      ${details['kotlin']}');
    logger.info('   Java:        ${details['java']}+');
    logger.info('   Min SDK:     ${details['min_sdk']}');
    logger.info('   Target SDK:  ${details['target_sdk']}');
    logger.info('   Compile SDK: ${details['compile_sdk']}');
  }
}
