import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'dart:async';
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
    String? yamlContent;

    // Strategy 1: Try to load as package resource URI (works for published packages)
    try {
      final resourceUri =
          Uri.parse('package:flutterfix/src/config/version_map.yaml');
      // ignore: deprecated_member_use
      final resolvedUri = await Isolate.resolvePackageUri(resourceUri);
      if (resolvedUri != null && resolvedUri.scheme == 'file') {
        final file = File(resolvedUri.toFilePath());
        if (file.existsSync()) {
          yamlContent = await file.readAsString();
          logger.detail('Loaded version_map.yaml from package URI');
        }
      }
    } catch (e) {
      logger.detail('Package URI resolution failed: $e');
      // Ignore and try other methods
    }

    // Strategy 2: Try multiple file system paths
    if (yamlContent == null) {
      final pathsToTry = <String>[];

      // 2a. Check current directory (for local development/testing)
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

      // 2b. For path-activated packages, resolve from snapshot location
      final scriptUri = Platform.script;
      if (scriptUri.scheme == 'file') {
        final scriptPath = scriptUri.toFilePath();

        // Check if snapshot is in .dart_tool/pub/bin/ (path-activated package)
        if (scriptPath.contains(
            '.dart_tool${p.separator}pub${p.separator}bin${p.separator}')) {
          final dartToolIndex = scriptPath.indexOf('.dart_tool');
          if (dartToolIndex != -1) {
            final packageRoot = scriptPath.substring(0, dartToolIndex);
            final pathActivatedVersionMap = p.join(
              packageRoot,
              'lib',
              'src',
              'config',
              'version_map.yaml',
            );
            if (File(pathActivatedVersionMap).existsSync()) {
              pathsToTry.add(pathActivatedVersionMap);
            }
          }
        }
      }

      // 2c. Try path relative to Platform.script
      if (scriptUri.scheme == 'file') {
        final scriptPath = scriptUri.toFilePath();
        String packageRoot;

        if (scriptPath.contains('${p.separator}bin${p.separator}')) {
          packageRoot = p.dirname(p.dirname(scriptPath));
        } else if (scriptPath.contains('${p.separator}lib${p.separator}')) {
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
        if (File(scriptBasedPath).existsSync() &&
            scriptBasedPath != localPath) {
          pathsToTry.add(scriptBasedPath);
        }
      }

      // 2d. Try pub cache hosted package path (for published packages)
      final homeDir =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (homeDir != null) {
        final pubCacheHosted = p.join(homeDir, '.pub-cache', 'hosted');

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

          // Sort by version number (latest first)
          flutterfixPaths.sort((a, b) {
            final versionA = _extractVersionFromPath(a);
            final versionB = _extractVersionFromPath(b);
            return _compareVersions(versionB, versionA);
          });

          pathsToTry.addAll(flutterfixPaths);
        }

        // 2e. Try global packages path
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
          yamlContent = await File(versionMapPath).readAsString();
          break;
        }
      }

      if (yamlContent == null) {
        throw Exception(
            'Version map not found. Tried:\n${pathsToTry.map((p) => '  - $p').join('\n')}');
      }
    }

    // Parse YAML content
    final yamlDoc = loadYaml(yamlContent);
    versionMap = Map<String, dynamic>.from(yamlDoc['flutter_compatibility']);
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

    final progress = logger.progress('Installing FVM via dart pub global');

    final result =
        await ProcessRunner.dart(['pub', 'global', 'activate', 'fvm']);

    progress.complete();

    if (result.success) {
      logger.success('✅ FVM installed successfully');
      return true;
    } else {
      logger.err('❌ Failed to install FVM: ${result.stderr}');
      return false;
    }
  }

  /// Install Flutter showing real FVM output
  Future<ProcessResult> _installWithProgress(String version) async {
    try {
      logger.info('📡 Starting FVM download process...');
      logger.info('💡 Showing real-time FVM output:');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      final process = await Process.start(
        'fvm',
        ['install', version, '--verbose'],
        runInShell: true,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      var lastOutputTime = DateTime.now();
      var hasOutput = false;

      // Show a simple "waiting for output" indicator initially
      Progress? waitingProgress = logger.progress('Waiting for FVM output...');

      // Listen to stdout and show real FVM output
      process.stdout.transform(utf8.decoder).listen((data) {
        stdoutBuffer.write(data);
        hasOutput = true;
        lastOutputTime = DateTime.now();

        // Cancel waiting progress and show real output
        waitingProgress?.cancel();
        waitingProgress = null;

        // Print real FVM output directly to console
        stdout.write(data);
      });

      // Listen to stderr and show real FVM output
      process.stderr.transform(utf8.decoder).listen((data) {
        stderrBuffer.write(data);
        hasOutput = true;
        lastOutputTime = DateTime.now();

        // Cancel waiting progress and show real output
        waitingProgress?.cancel();
        waitingProgress = null;

        // Print real FVM stderr output (often contains progress info)
        stderr.write(data);
      });

      // Monitor for lack of output (possible hang)
      final monitorTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        final now = DateTime.now();
        if (hasOutput && now.difference(lastOutputTime).inSeconds > 60) {
          print(
              '\n⚠️  No output from FVM for 60 seconds, process may be stuck...');
          print('💡 You can press Ctrl+C to cancel if needed');
        }
      });

      // Wait for process to complete with timeout
      final exitCode = await process.exitCode.timeout(
        const Duration(minutes: 30),
        onTimeout: () {
          monitorTimer.cancel();
          waitingProgress?.cancel();
          process.kill();
          return -1;
        },
      );

      monitorTimer.cancel();
      waitingProgress?.cancel();

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      logger.info('📡 FVM process completed');

      return ProcessResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
      );
    } catch (e) {
      return ProcessResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Error starting FVM process: $e',
      );
    }
  }

  /// Check if specific Flutter version is installed with FVM
  Future<bool> isVersionInstalled(String version) async {
    final result = await ProcessRunner.run(
      'fvm',
      ['list'],
      runInShell: true,
    );

    if (result.success) {
      return result.stdout.contains(version);
    }
    return false;
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

  /// Resolve Flutter version to FVM-compatible format
  Future<String> resolveToStableVersion(String version) async {
    // Query FVM releases to find exact matching version
    logger.detail('🔍 Querying FVM for version: $version');

    try {
      final result = await ProcessRunner.run(
        'fvm',
        ['releases'],
        runInShell: true,
        timeout: const Duration(seconds: 30),
      );

      if (result.success) {
        final lines = result.stdout.split('\n');
        final allVersions = <String>[];

        // Collect all available versions from FVM output
        for (final line in lines) {
          final cleanLine = line.trim();
          if (cleanLine.isEmpty) continue;

          // Extract version from the line (handles v1.0.0, 1.17.0, 1.5.4-hotfix.2, etc.)
          final versionMatch = RegExp(r'(?:v)?(\d+\.\d+\.\d+(?:[+\-][\w.]+)?)')
              .firstMatch(cleanLine);
          if (versionMatch != null) {
            final extractedVersion = versionMatch.group(1)!;
            // Also add with 'v' prefix if it was present in original
            if (cleanLine.contains('v$extractedVersion')) {
              allVersions.add('v$extractedVersion');
            }
            allVersions.add(extractedVersion);
          }
        }

        // Remove duplicates
        final uniqueVersions = allVersions.toSet().toList();

        // Strategy 1: Exact match (without v prefix)
        if (uniqueVersions.contains(version)) {
          logger.detail('✓ Found exact FVM version: $version');
          return version;
        }

        // Strategy 2: Exact match with v prefix
        if (uniqueVersions.contains('v$version')) {
          logger.detail('✓ Found FVM version: v$version');
          return 'v$version';
        }

        // Strategy 3: Try with -stable suffix (rare, but possible)
        final stableVersion = '$version-stable';
        if (uniqueVersions.contains(stableVersion)) {
          logger.detail('✓ Found FVM version: $stableVersion');
          return stableVersion;
        }

        // Strategy 4: Find best match (handles hotfix, beta, dev suffixes)
        for (final fvmVersion in uniqueVersions) {
          if (fvmVersion.startsWith(version) ||
              fvmVersion.startsWith('v$version')) {
            logger.detail('✓ Found similar FVM version: $fvmVersion');
            logger.info('💡 Using $fvmVersion instead of $version');
            return fvmVersion;
          }
        }

        // Strategy 5: Partial match (e.g., "3.24" matches "3.24.5")
        final versionParts = version.split('.');
        if (versionParts.length == 2) {
          // User provided major.minor, find latest patch
          final majorMinor = '${versionParts[0]}.${versionParts[1]}';
          final matchingVersions = uniqueVersions
              .where((v) => v.replaceFirst('v', '').startsWith('$majorMinor.'))
              .toList()
            ..sort((a, b) => b.compareTo(a)); // Latest first

          if (matchingVersions.isNotEmpty) {
            final bestMatch = matchingVersions.first;
            logger.detail('✓ Found best match: $bestMatch for $version');
            logger.info('💡 Using latest patch version: $bestMatch');
            return bestMatch;
          }
        }

        // Strategy 6: Find nearest available version
        logger.warn('⚠️  Exact version $version not found in FVM releases');

        final nearestVersion = _findNearestVersion(version, uniqueVersions);
        if (nearestVersion != null) {
          logger.info('💡 Found nearest available version: $nearestVersion');
          final shouldUse = logger.confirm(
            'Would you like to use $nearestVersion instead of $version?',
            defaultValue: true,
          );

          if (shouldUse) {
            return nearestVersion;
          }
        }

        logger.info('💡 Available versions close to $version:');

        // Show similar versions to help user
        final similarVersions = uniqueVersions
            .where((v) =>
                v.replaceFirst('v', '').contains(version.split('.').first))
            .take(10)
            .toList();

        if (similarVersions.isNotEmpty) {
          for (final v in similarVersions) {
            logger.info('   - $v');
          }
        } else {
          logger.info('💡 Run "fvm releases" to see all available versions');
        }

        throw Exception(
          'Flutter version $version is not available in FVM.\n'
          'Please choose from the versions listed above.',
        );
      }
    } catch (e) {
      logger.detail('⚠️  Failed to query FVM releases: $e');
    }

    // Load version map if not already loaded
    if (versionMap.isEmpty) {
      await loadVersionMap();
    }

    // Check if we have a stable_version mapping in version_map.yaml
    final versionDetails = versionMap[version];
    if (versionDetails != null && versionDetails['stable_version'] != null) {
      final mappedVersion = versionDetails['stable_version'] as String;
      logger.detail('✓ Found version map: $version → $mappedVersion');
      return mappedVersion;
    }

    // If we reach here, version not found anywhere
    throw Exception(
      'Flutter version $version could not be resolved.\n'
      'Run "fvm releases" to see available versions.',
    );
  }

  /// Find the nearest available version in FVM releases
  String? _findNearestVersion(
      String targetVersion, List<String> availableVersions) {
    try {
      // Parse target version (remove v prefix if present)
      final cleanTarget = targetVersion.replaceFirst('v', '');
      final targetParts = cleanTarget.split('.');
      if (targetParts.length < 2) return null;

      final targetMajor = int.tryParse(targetParts[0]);
      final targetMinor = int.tryParse(targetParts[1]);
      if (targetMajor == null || targetMinor == null) return null;

      // Find versions with same major version
      final sameMajor = availableVersions.where((v) {
        final cleanV = v.replaceFirst('v', '');
        final parts = cleanV.split('.');
        if (parts.isEmpty) return false;
        final major = int.tryParse(parts[0]);
        return major == targetMajor;
      }).toList();

      if (sameMajor.isEmpty) return null;

      // Find closest version
      String? closest;
      int minDiff = 999999;

      for (final v in sameMajor) {
        final cleanV = v.replaceFirst('v', '');
        final parts = cleanV.split('.');
        if (parts.length < 2) continue;

        final major = int.tryParse(parts[0]);
        final minor = int.tryParse(parts[1].split(RegExp(r'[+\-]')).first);
        if (major == null || minor == null) continue;

        final diff = (minor - targetMinor).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closest = v;
        }
      }

      return closest;
    } catch (e) {
      logger.detail('Error finding nearest version: $e');
      return null;
    }
  }

  /// Install Flutter version using FVM
  Future<bool> installWithFvm(String version) async {
    // Resolve to full stable version
    final fullVersion = await resolveToStableVersion(version);

    if (fullVersion != version) {
      logger.info('📌 Resolved $version → $fullVersion');
    }

    // Check if already installed first
    final checkProgress =
        logger.progress('Checking if Flutter $fullVersion is installed');
    final alreadyInstalled = await isVersionInstalled(fullVersion);
    checkProgress.complete();

    if (alreadyInstalled) {
      logger.info('✓ Flutter $fullVersion already installed');
      return true;
    }

    logger.warn('⚠️  Flutter $fullVersion is not installed');
    logger.info('📥 Starting download and installation...');
    logger.info('🔄 Installing Flutter $fullVersion using FVM...');

    final result = await _installWithProgress(fullVersion);

    // Check if installation actually completed even if process didn't exit cleanly
    if (!result.success) {
      logger
          .warn('⚠️  FVM process exited with error, verifying installation...');

      // Wait a moment for FVM to finalize
      await Future.delayed(const Duration(seconds: 2));

      // Verify if version is actually installed
      final verifyProgress =
          logger.progress('Verifying Flutter $fullVersion installation');
      final isNowInstalled = await isVersionInstalled(fullVersion);
      verifyProgress.complete();

      if (isNowInstalled) {
        logger
            .success('✅ Flutter $fullVersion download completed successfully');
        logger.info('💡 Installation verified despite process warning');
        return true;
      }

      logger.err('❌ Failed to install Flutter $fullVersion');
      logger.err(result.stderr);

      // Suggest trying with explicit version
      logger.info('💡 FVM requires full version numbers (e.g., 3.24.5)');
      logger.info('   Try: fvm releases | grep $version');

      return false;
    }

    logger.success('✅ Flutter $fullVersion download completed successfully');
    return true;
  }

  /// Use specific Flutter version in a project with FVM
  Future<bool> useVersionInProject(String projectPath, String version) async {
    // Resolve to full stable version
    final fullVersion = await resolveToStableVersion(version);

    logger.info('🔧 Setting Flutter $fullVersion for project...');

    // Check if version is already installed
    final checkProgress =
        logger.progress('Checking if Flutter $fullVersion is installed');
    final isInstalled = await isVersionInstalled(fullVersion);
    checkProgress.complete();

    if (!isInstalled) {
      logger.info('📥 Flutter $fullVersion not found, installing first...');
      final installed = await installWithFvm(fullVersion);
      if (!installed) {
        logger.err('❌ Failed to install Flutter $fullVersion');
        return false;
      }
    } else {
      logger.info('✓ Flutter $fullVersion already installed');
    }

    // Pre-configure .gitignore to avoid interactive prompt
    final gitignorePath = p.join(projectPath, '.gitignore');
    try {
      if (File(gitignorePath).existsSync()) {
        final content = await File(gitignorePath).readAsString();
        if (!content.contains('.fvm/')) {
          await File(gitignorePath)
              .writeAsString('$content\n# FVM Version Cache\n.fvm/\n');
          logger.info('✓ Added .fvm/ to .gitignore');
        }
      }
    } catch (e) {
      // Non-critical, continue anyway
    }

    final progress =
        logger.progress('Configuring project to use Flutter $fullVersion');

    final result = await ProcessRunner.run(
      'fvm',
      ['use', fullVersion, '--skip-setup', '--skip-pub-get', '--force'],
      workingDirectory: projectPath,
      runInShell: true,
    );

    progress.complete();

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
