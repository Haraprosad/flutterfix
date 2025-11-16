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
    // Try multiple paths to find version_map.yaml
    final pathsToTry = <String>[];

    // 1. Check if we're in the package directory (for local development/testing)
    final currentDir = Directory.current;
    final localPath = p.join(
      currentDir.path,
      'lib',
      'src',
      'config',
      'version_map.yaml',
    );
    if (File(localPath).existsSync()) {
      pathsToTry.add(localPath);
    }

    // 2. Try path relative to Platform.script (for installed package)
    final scriptUri = Platform.script;
    if (scriptUri.scheme == 'file') {
      final scriptPath = scriptUri.toFilePath();
      String packageRoot;

      if (scriptPath.contains('${p.separator}bin${p.separator}')) {
        // Running from bin/flutterfix.dart
        packageRoot = p.dirname(p.dirname(scriptPath));
      } else if (scriptPath.contains('${p.separator}lib${p.separator}')) {
        // Running from lib/
        packageRoot = p.dirname(p.dirname(scriptPath));
      } else {
        packageRoot = p.dirname(scriptPath);
      }

      final scriptBasedPath = p.join(
        packageRoot,
        'lib',
        'src',
        'config',
        'version_map.yaml',
      );
      if (File(scriptBasedPath).existsSync() && scriptBasedPath != localPath) {
        pathsToTry.add(scriptBasedPath);
      }
    }

    // 3. Try pub cache hosted package path (for published package)
    final homeDir =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (homeDir != null) {
      final pubCacheHosted = p.join(homeDir, '.pub-cache', 'hosted');

      // Find flutterfix package directories and sort by version (latest first)
      final pubCacheDir = Directory(pubCacheHosted);
      if (pubCacheDir.existsSync()) {
        final flutterfixPaths = <String>[];
        final subdirs = pubCacheDir.listSync();
        for (final subdir in subdirs) {
          if (subdir is Directory) {
            final flutterfixDirs = subdir
                .listSync()
                .where((e) =>
                    e is Directory &&
                    p.basename(e.path).startsWith('flutterfix-'))
                .toList();

            for (final dir in flutterfixDirs) {
              final versionMapPath = p.join(
                dir.path,
                'lib',
                'src',
                'config',
                'version_map.yaml',
              );
              if (File(versionMapPath).existsSync()) {
                flutterfixPaths.add(versionMapPath);
              }
            }
          }
        }

        // Sort by version number (latest first) by extracting version from path
        flutterfixPaths.sort((a, b) {
          final versionA = _extractVersionFromPath(a);
          final versionB = _extractVersionFromPath(b);
          return _compareVersions(
              versionB, versionA); // Reverse for descending order
        });

        pathsToTry.addAll(flutterfixPaths);
      }

      // 4. Try global packages path (alternative location)
      final globalPath = p.join(
        homeDir,
        '.pub-cache',
        'global_packages',
        'flutterfix',
        'lib',
        'src',
        'config',
        'version_map.yaml',
      );
      if (File(globalPath).existsSync()) {
        pathsToTry.add(globalPath);
      }
    }

    // Try each path until we find one that exists
    for (final versionMapPath in pathsToTry) {
      if (File(versionMapPath).existsSync()) {
        final yamlString = await File(versionMapPath).readAsString();
        final yamlDoc = loadYaml(yamlString);
        versionMap =
            Map<String, dynamic>.from(yamlDoc['flutter_compatibility']);
        return;
      }
    }

    throw Exception(
        'Version map not found. Tried:\n${pathsToTry.map((p) => '  - $p').join('\n')}');
  }

  /// Extract version number from file path
  String _extractVersionFromPath(String path) {
    final match = RegExp(r'flutterfix-(\d+\.\d+\.\d+)').firstMatch(path);
    return match?.group(1) ?? '0.0.0';
  }

  /// Compare two semantic versions
  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList();
    final bParts = b.split('.').map(int.parse).toList();

    for (var i = 0; i < 3; i++) {
      if (aParts[i] != bParts[i]) {
        return aParts[i].compareTo(bParts[i]);
      }
    }
    return 0;
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
        // Parse SDK constraint (e.g., ">=3.0.0 <4.0.0" or "^3.5.3")
        final constraint = projectInfo.sdkConstraint!;

        // Extract minimum version from constraint
        String? minVersion;

        // Handle caret syntax (^3.5.3)
        if (constraint.startsWith('^')) {
          minVersion = constraint.substring(1).split(' ').first;
        }
        // Handle >= syntax (>=3.0.0)
        else {
          final match =
              RegExp(r'>=?(\d+\.\d+(?:\.\d+)?)').firstMatch(constraint);
          if (match != null) {
            minVersion = match.group(1);
          }
        }

        if (minVersion != null) {
          logger.info('📋 Dart SDK constraint: $constraint (min: $minVersion)');

          // Parse the minimum version
          final parts = minVersion.split('.');
          final majorMinor = '${parts[0]}.${parts.length > 1 ? parts[1] : '0'}';

          await loadVersionMap();
          final versions = getAvailableVersions();

          // Try to find the best matching Flutter version
          // Flutter 3.24+ supports Dart SDK 3.5.x
          // Flutter 3.22+ supports Dart SDK 3.4.x
          // Flutter 3.19+ supports Dart SDK 3.3.x

          // First, try exact major.minor match
          for (final version in versions) {
            if (version == majorMinor) {
              logger.info('✅ Found exact match: Flutter $version');
              return version;
            }
          }

          // Try to find closest compatible version (higher or equal)
          final minNum = double.tryParse(majorMinor) ?? 0;
          String? bestMatch;

          for (final version in versions) {
            final versionNum = double.tryParse(version) ?? 0;

            if (versionNum >= minNum) {
              if (bestMatch == null) {
                bestMatch = version;
              } else {
                final bestNum = double.tryParse(bestMatch) ?? 0;
                // Pick the closest version that's still >= minNum
                if (versionNum < bestNum) {
                  bestMatch = version;
                }
              }
            }
          }

          if (bestMatch != null) {
            logger.info('✅ Best compatible version: Flutter $bestMatch');
            return bestMatch;
          }

          // If no compatible version found, suggest the latest
          if (versions.isNotEmpty) {
            logger.warn('⚠️  No exact match found, suggesting latest version');
            return versions.first; // Already sorted descending
          }
        }
      }
    } catch (e) {
      logger.err('❌ Error detecting recommended version: $e');
    }

    return null;
  }

  /// Resolve Flutter version to full stable version
  Future<String> resolveToStableVersion(String version) async {
    // If already a full version (e.g., 3.24.5), return as is
    if (version.split('.').length >= 3) {
      return version;
    }

    // Load version map if not already loaded
    if (versionMap.isEmpty) {
      await loadVersionMap();
    }

    // Check if we have a stable_version mapping in version_map.yaml
    final versionDetails = versionMap[version];
    if (versionDetails != null && versionDetails['stable_version'] != null) {
      return versionDetails['stable_version'] as String;
    }

    // Fallback: Try to get from FVM releases
    try {
      final result = await ProcessRunner.run(
        'fvm',
        ['releases'],
        runInShell: true,
      );

      if (result.success) {
        // Parse FVM releases output to find matching stable version
        final lines = result.stdout.split('\n');
        final matchingVersions = lines
            .where((line) => line.contains(version) && line.contains('stable'))
            .toList();

        if (matchingVersions.isNotEmpty) {
          // Extract version number from first match
          final match =
              RegExp(r'(\d+\.\d+\.\d+)').firstMatch(matchingVersions.first);
          if (match != null) {
            return match.group(1)!;
          }
        }
      }
    } catch (e) {
      logger.warn('⚠️  Could not query FVM releases: $e');
    }

    // Final fallback: add .0 to make it a full version
    logger.warn('⚠️  No stable version found for $version, using ${version}.0');
    return '$version.0';
  }

  /// Install Flutter version using FVM
  Future<bool> installWithFvm(String version) async {
    // Resolve to full stable version
    final fullVersion = await resolveToStableVersion(version);

    if (fullVersion != version) {
      logger.info('📌 Resolved $version → $fullVersion');
    }

    logger.info('🔄 Installing Flutter $fullVersion using FVM...');

    final progress = logger.progress('Downloading Flutter $fullVersion');

    final result = await ProcessRunner.run(
      'fvm',
      ['install', fullVersion],
      runInShell: true,
    );

    progress.complete();

    if (result.success) {
      logger.success('✅ Flutter $fullVersion installed successfully');
      return true;
    } else {
      logger.err('❌ Failed to install Flutter $fullVersion');
      logger.err(result.stderr);

      // Suggest trying with explicit version
      logger.info('💡 FVM requires full version numbers (e.g., 3.24.5)');
      logger.info('   Try: fvm releases | grep $version');

      return false;
    }
  }

  /// Use specific Flutter version in a project with FVM
  Future<bool> useVersionInProject(String projectPath, String version) async {
    // Resolve to full stable version
    final fullVersion = await resolveToStableVersion(version);

    logger.info('🔧 Setting Flutter $fullVersion for project...');

    final result = await ProcessRunner.run(
      'fvm',
      ['use', fullVersion],
      workingDirectory: projectPath,
      runInShell: true,
    );

    if (result.success) {
      logger.success('✅ Project configured to use Flutter $fullVersion');
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

        // Auto-configure PATH
        final configured = await _configurePathForStandalone(flutterDir);

        if (configured) {
          logger.success('✅ PATH configured automatically');
          logger.info('💡 Restart your terminal or run:');
          if (Platform.isMacOS || Platform.isLinux) {
            final shellConfig = _getShellConfigFile();
            logger.info('   source ~/$shellConfig');
          } else {
            logger.info('   Restart your terminal');
          }
        } else {
          logger.info('💡 To use this version, add to PATH manually:');
          logger.info('   export PATH="$flutterDir/bin:\$PATH"');
        }

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

  /// Auto-configure PATH for standalone Flutter installation
  Future<bool> _configurePathForStandalone(String flutterDir) async {
    try {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home == null) return false;

      if (Platform.isMacOS || Platform.isLinux) {
        // Determine shell config file
        final shellConfigFile = _getShellConfigFile();
        final configPath = p.join(home, shellConfigFile);

        // Read existing config
        final configFile = File(configPath);
        String existingContent = '';

        if (configFile.existsSync()) {
          existingContent = await configFile.readAsString();
        }

        // Check if PATH already configured
        final flutterBinPath = '$flutterDir/bin';
        if (existingContent.contains(flutterBinPath)) {
          logger.info('ℹ️  PATH already configured in ~/$shellConfigFile');
          return true;
        }

        // Add FlutterFix managed Flutter paths section
        final pathExport =
            '\n# FlutterFix managed Flutter versions\nexport PATH="$flutterBinPath:\$PATH"\n';

        await configFile.writeAsString(
          existingContent + pathExport,
          mode: FileMode.append,
        );

        logger.info('✅ Updated ~/$shellConfigFile');
        return true;
      } else if (Platform.isWindows) {
        // Windows: Update User PATH environment variable
        final result = await ProcessRunner.run(
          'powershell',
          [
            '-Command',
            '''
            \$oldPath = [Environment]::GetEnvironmentVariable('Path', 'User');
            \$newPath = "$flutterDir\\bin";
            if (\$oldPath -notlike "*\$newPath*") {
              [Environment]::SetEnvironmentVariable('Path', "\$oldPath;\$newPath", 'User');
              Write-Output 'PATH updated';
            } else {
              Write-Output 'PATH already configured';
            }
            '''
          ],
          runInShell: true,
        );

        if (result.success) {
          logger.info('✅ Updated Windows PATH environment variable');
          return true;
        }
      }
    } catch (e) {
      logger.warn('⚠️  Could not auto-configure PATH: $e');
    }

    return false;
  }

  /// Detect shell config file based on current shell
  String _getShellConfigFile() {
    final shell = Platform.environment['SHELL'] ?? '';

    if (shell.contains('zsh')) {
      return '.zshrc';
    } else if (shell.contains('bash')) {
      // Check if .bash_profile or .bashrc exists
      final home = Platform.environment['HOME'];
      if (home != null) {
        if (File(p.join(home, '.bash_profile')).existsSync()) {
          return '.bash_profile';
        }
      }
      return '.bashrc';
    } else if (shell.contains('fish')) {
      return '.config/fish/config.fish';
    }

    // Default to .profile for unknown shells
    return '.profile';
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
