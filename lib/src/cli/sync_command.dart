import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mason_logger/mason_logger.dart';
import '../detect/flutter_detector.dart';
import '../patcher/gradle_patcher.dart';
import '../patcher/agp_patcher.dart';
import '../patcher/kotlin_patcher.dart';
import '../patcher/pubspec_patcher.dart';
import '../utils/file_utils.dart';
import '../runner/process_runner.dart';
import '../installer/flutter_installer.dart';
import '../resolver/dependency_resolver.dart';

/// Result of analyzing project version from multiple sources
class VersionAnalysis {
  final String? recommendedVersion;
  final bool hasConflict;
  final String conflictReason;
  final String resolutionStrategy;
  final String? trueOriginalVersion;

  VersionAnalysis({
    required this.recommendedVersion,
    this.hasConflict = false,
    this.conflictReason = '',
    this.resolutionStrategy = '',
    this.trueOriginalVersion,
  });
}

class SyncCommand {
  final Logger logger;
  final String projectPath;
  final bool useOriginal;
  final bool autoInstallFlutter;
  final bool fixDependencies;
  final bool autoApplyFixes;
  late Map<String, dynamic> versionMap;

  SyncCommand(
    this.logger,
    this.projectPath, {
    this.useOriginal = false,
    this.autoInstallFlutter = false,
    this.fixDependencies = false,
    this.autoApplyFixes = false,
  });

  Future<void> execute() async {
    _printHeader();

    // Load version compatibility map
    await _loadVersionMap();

    // Handle --original flag
    if (useOriginal) {
      await _executeWithOriginalVersion();
      return;
    }

    // Detect versions
    var flutterInfo = await FlutterDetector.detectInstalled();

    // If Flutter not installed, try auto-install
    if (!flutterInfo.isInstalled || flutterInfo.version == null) {
      logger.warn('⚠️  Flutter not detected in system PATH');
      logger.info('🔍 Checking for FVM or project-specific Flutter...\n');

      // Check if project has FVM config
      final fvmConfigPath = p.join(projectPath, '.fvm', 'fvm_config.json');
      if (FileUtils.fileExists(fvmConfigPath)) {
        final fvmConfig = await FileUtils.readFile(fvmConfigPath);
        final config = jsonDecode(fvmConfig) as Map<String, dynamic>;
        final fvmVersion = config['flutterSdkVersion'] as String?;

        if (fvmVersion != null) {
          logger.info('📦 Found FVM config: Flutter $fvmVersion');
          logger.info('💡 Using project-specific Flutter version\n');

          final flutterVersion = fvmVersion;
          final fixed = <String>[];
          final warnings = <String>[];
          final errors = <String>[];

          if (FileUtils.hasAndroidFolder(projectPath)) {
            await _fixAndroid(flutterVersion, fixed, warnings, errors);
          }

          if (fixDependencies) {
            await _fixDartDependencies(flutterVersion);
          }

          await _cleanAndRefresh(fixed, warnings, flutterVersion);
          _printSummary(fixed, warnings, errors);
          return;
        }
      }

      // Try to auto-install based on project requirements
      logger.info(
          '🤖 Attempting to auto-install compatible Flutter version...\n');

      final installer = FlutterInstaller(logger);
      await installer.loadVersionMap();

      final recommended = await installer.getRecommendedVersion(projectPath);
      if (recommended != null) {
        logger.info('📦 Recommended Flutter version: $recommended\n');

        final hasFvm = await installer.isFvmInstalled();
        if (!hasFvm) {
          logger.info('📦 Installing FVM first...\n');
          await installer.installFvm();
        }

        logger.info('📥 Installing Flutter $recommended...\n');
        final installed = await installer.installWithFvm(recommended);

        if (installed) {
          await installer.useVersionInProject(projectPath, recommended);
          logger.success('✅ Flutter $recommended installed successfully\n');

          // Continue with the installed version
          final fixed = <String>[];
          final warnings = <String>[];
          final errors = <String>[];

          if (FileUtils.hasAndroidFolder(projectPath)) {
            await _fixAndroid(recommended, fixed, warnings, errors);
          }

          if (fixDependencies) {
            await _fixDartDependencies(recommended);
          }

          await _cleanAndRefresh(fixed, warnings, recommended);
          _printSummary(fixed, warnings, errors);
          return;
        }
      }

      // Final fallback - cannot proceed
      logger.err('❌ Could not detect or install Flutter');
      logger.info('💡 Manual installation required:');
      logger.info(
          '   1. Install Flutter: https://flutter.dev/docs/get-started/install');
      logger.info('   2. Or install FVM: dart pub global activate fvm');
      return;
    }

    final flutterVersion = flutterInfo.version!;
    logger.info('📦 Flutter $flutterVersion detected\n');

    final fixed = <String>[];
    final warnings = <String>[];
    final errors = <String>[];

    // Fix Android
    if (FileUtils.hasAndroidFolder(projectPath)) {
      await _fixAndroid(flutterVersion, fixed, warnings, errors);
    }

    // Fix Dart dependencies if requested
    if (fixDependencies) {
      await _fixDartDependencies(flutterVersion);
    }

    // Clean and refresh
    await _cleanAndRefresh(fixed, warnings, flutterVersion);

    // Print summary
    _printSummary(fixed, warnings, errors);
  }

  Future<void> _executeWithOriginalVersion() async {
    logger.info('🔍 Analyzing project Flutter version requirements...\n');

    // Check if a different Flutter version is already configured via FVM
    final fvmConfigPath = p.join(projectPath, '.fvm', 'fvm_config.json');
    String? currentFvmVersion;
    if (FileUtils.fileExists(fvmConfigPath)) {
      final fvmConfig = await FileUtils.readFile(fvmConfigPath);
      final config = jsonDecode(fvmConfig) as Map<String, dynamic>;
      currentFvmVersion = config['flutterSdkVersion'] as String?;
    }

    // Collect versions from ALL available sources
    final metadataVersion =
        await FlutterDetector.detectOriginalVersion(projectPath);
    final requiredVersion =
        await FlutterDetector.detectRequiredVersion(projectPath);

    // Determine the TRUE original version using smart prioritization
    final versionAnalysis = await _analyzeProjectVersion(
      metadataVersion,
      requiredVersion,
      currentFvmVersion,
    );

    if (versionAnalysis.recommendedVersion == null) {
      logger.err('❌ Could not detect Flutter version requirements');
      logger.info('');
      logger.info('💡 Possible solutions:');
      logger.info('');
      logger.info(
          '   1. Run without --original flag (uses currently installed Flutter):');
      logger.info('      flutterfix sync --install-flutter <project-path>');
      logger.info(
          '      This will use your system Flutter version instead of .metadata');
      logger.info('');
      logger.info(
          '   2. Check if .metadata and pubspec.yaml exist in the project');
      logger.info('      The project might not be a valid Flutter project');
      logger.info('');
      logger.info('   3. Manually specify a Flutter version:');
      logger.info('      flutterfix install --version 3.27 <project-path>');
      logger.info('');
      return;
    }

    // Show comprehensive version analysis
    logger.info('📊 Version Analysis:');
    if (metadataVersion != null) {
      logger.info('   • Project created with: $metadataVersion (.metadata)');
    }
    if (requiredVersion != null) {
      logger
          .info('   • Dependencies require: >=$requiredVersion (pubspec.yaml)');
    }
    if (currentFvmVersion != null) {
      logger.info('   • Currently configured: $currentFvmVersion (FVM)');
    }
    logger.info('');

    // Display analysis result and reasoning
    if (versionAnalysis.hasConflict) {
      logger.warn('⚠️  ${versionAnalysis.conflictReason}');
      logger.info('');
      logger.info('💡 ${versionAnalysis.resolutionStrategy}');
      logger.info('');
    } else {
      logger.success(
          '✅ Recommended Flutter version: ${versionAnalysis.recommendedVersion}\n');
    }

    final originalVersion = versionAnalysis.recommendedVersion!;

    // Check if current FVM version is different
    if (currentFvmVersion != null && currentFvmVersion != originalVersion) {
      logger.info('📌 Recommended version: $originalVersion');
      logger.info('📌 Currently configured FVM version: $currentFvmVersion\n');

      // Compare versions
      final isNewer = _compareVersions(currentFvmVersion, originalVersion) > 0;

      if (isNewer) {
        logger.warn(
            '⚠️  You have a newer Flutter version configured ($currentFvmVersion)');
        logger.warn('   Using --original will downgrade to $originalVersion\n');
        logger.info(
            '💡 To keep the current version, run without --original flag:');
        logger.info('   flutterfix sync --fix-dependencies\n');
        logger
            .info('📦 Proceeding with recommended version: $originalVersion\n');
      }
    }

    logger.success('✅ Using Flutter version: $originalVersion\n');

    // Install Flutter and get the ACTUAL installed version
    final actualInstalledVersion =
        await _handleFlutterInstallation(originalVersion);

    // Check if updating SDK would cross null safety boundary
    final shouldUpdateSdk = await _shouldUpdateSdkConstraint(
      actualInstalledVersion,
      metadataVersion,
    );

    final pubspecPatcher = PubspecPatcher(logger, projectPath);
    await pubspecPatcher.createBackup();

    if (shouldUpdateSdk) {
      // Safe to update - stays within same era (pre/post null safety)
      logger.info(
          '📝 Updating SDK constraint for Flutter $actualInstalledVersion...\n');
      await pubspecPatcher.updateSdkConstraint(actualInstalledVersion,
          skipConfirmation: true);
      logger.info('');
    } else {
      // Would cross null safety boundary - RESTORE to pre-null safety constraint
      logger.info('📝 Restoring pre-null safety SDK constraint...\n');
      logger.detail(
          'Project was built pre-null safety (Flutter $metadataVersion)');
      logger.detail('Reverting SDK constraint to match original Flutter era');

      // Restore to pre-null safety SDK constraint for this Flutter version
      await pubspecPatcher.restorePreNullSafetySdk(actualInstalledVersion);

      // Check for packages that require newer SDK and handle them
      logger.info('');
      logger.info(
          '🔍 Checking for packages incompatible with pre-null safety...\n');
      await _handleIncompatiblePackages(pubspecPatcher, actualInstalledVersion);

      logger.info('');
    }

    // Use the ACTUAL installed version for Gradle configuration
    final flutterVersion = actualInstalledVersion;

    // Verify by checking FVM config if it exists
    if (FileUtils.fileExists(fvmConfigPath)) {
      final fvmConfig = await FileUtils.readFile(fvmConfigPath);
      final config = jsonDecode(fvmConfig) as Map<String, dynamic>;
      final fvmVersion = config['flutterSdkVersion'] as String?;
      if (fvmVersion != null) {
        logger.detail('Verified FVM version: $fvmVersion');
      }
    }

    logger.info('📦 Using Flutter $flutterVersion\n');

    final fixed = <String>[];
    final warnings = <String>[];
    final errors = <String>[];

    // Fix Android with version-specific configs
    if (FileUtils.hasAndroidFolder(projectPath)) {
      await _fixAndroid(flutterVersion, fixed, warnings, errors);
    }

    // Fix Dart dependencies if requested
    if (fixDependencies) {
      await _fixDartDependencies(flutterVersion);
    }

    // Clean and refresh
    await _cleanAndRefresh(fixed, warnings, flutterVersion);

    // Print summary
    _printSummary(fixed, warnings, errors);
  }

  Future<String> _handleFlutterInstallation(String version) async {
    if (autoInstallFlutter) {
      logger.info('📥 Installing Flutter $version...\n');

      final installer = FlutterInstaller(logger);
      await installer.loadVersionMap();

      // Resolve to stable version
      final stableVersion = await installer.resolveToStableVersion(version);

      // Try FVM first
      final hasFvm = await installer.isFvmInstalled();
      bool success = false;

      if (hasFvm) {
        logger.info('🔧 Installing with FVM...');
        success = await installer.installWithFvm(stableVersion);

        if (success) {
          // Use the version in the project
          await installer.useVersionInProject(projectPath, stableVersion);
        }
      } else {
        logger.info('🔧 FVM not found, installing FVM first...');
        final fvmInstalled = await installer.installFvm();

        if (fvmInstalled) {
          success = await installer.installWithFvm(stableVersion);
          if (success) {
            await installer.useVersionInProject(projectPath, stableVersion);
          }
        } else {
          logger.warn('⚠️  FVM installation failed, using standalone mode');
          success = await installer.installStandalone(stableVersion);
        }
      }

      if (!success) {
        logger.err('❌ Failed to install Flutter $version');
        return version; // Return requested version as fallback
      }

      logger.success('✅ Flutter $stableVersion installed successfully\n');
      return stableVersion; // Return the ACTUAL installed version
    } else {
      logger.info('💡 To install Flutter $version automatically, run:');
      logger.info('   flutterfix sync --original --install-flutter\n');
      logger.info('   OR manually:');
      logger.info('   fvm install $version && fvm use $version\n');
      return version;
    }
  }

  Future<void> _fixAndroid(
    String flutterVersion,
    List<String> fixed,
    List<String> warnings,
    List<String> errors,
  ) async {
    logger.info('🔧 Fixing Android configuration...\n');

    final versions = _getCompatibleVersions(flutterVersion);

    // Fix Gradle
    final gradleProgress = logger.progress('Updating Gradle version');
    final gradlePatcher = GradlePatcher(projectPath);
    if (await gradlePatcher
        .updateWrapperVersion(versions['gradle'].toString())) {
      fixed.add('Gradle ${versions['gradle']}');
    }

    await gradlePatcher.optimizeProperties();
    await gradlePatcher.ensureRepositories();
    gradleProgress.complete('Gradle configured');

    // Fix AGP
    final agpProgress = logger.progress('Updating Android Gradle Plugin');
    final agpPatcher = AgpPatcher(projectPath);
    if (await agpPatcher.updateVersion(versions['agp'].toString())) {
      fixed.add('AGP ${versions['agp']}');
    }

    await agpPatcher.ensureNamespace();
    await agpPatcher.updateSdkVersions(
      minSdk: versions['min_sdk'] is int
          ? versions['min_sdk'] as int
          : int.parse(versions['min_sdk']!),
      compileSdk: versions['compile_sdk'] is int
          ? versions['compile_sdk'] as int
          : int.parse(versions['compile_sdk']!),
      targetSdk: versions['target_sdk'] is int
          ? versions['target_sdk'] as int
          : int.parse(versions['target_sdk']!),
    );
    await agpPatcher.fixCompileOptions();
    agpProgress.complete('Android Gradle Plugin configured');

    // Fix Kotlin
    final kotlinProgress = logger.progress('Updating Kotlin version');
    final kotlinPatcher = KotlinPatcher(projectPath);
    if (await kotlinPatcher.updateVersion(versions['kotlin'].toString())) {
      fixed.add('Kotlin ${versions['kotlin']}');
    }

    await kotlinPatcher.ensureKotlinPlugin(versions['kotlin'].toString());
    await kotlinPatcher.applyKotlinAndroidPlugin();
    await kotlinPatcher.addKotlinOptions();
    kotlinProgress.complete('Kotlin configured');
  }

  Future<void> _cleanAndRefresh(
    List<String> fixed,
    List<String> warnings,
    String flutterVersion,
  ) async {
    // Check if using FVM
    final fvmConfigPath = p.join(projectPath, '.fvm', 'fvm_config.json');
    final useFvm = FileUtils.fileExists(fvmConfigPath);

    // Run flutter clean
    final cleanProgress = logger.progress('Running flutter clean');
    final cleanResult = useFvm
        ? await ProcessRunner.run('fvm', ['flutter', 'clean'],
            workingDirectory: projectPath, runInShell: true)
        : await ProcessRunner.flutter(['clean'], workingDirectory: projectPath);

    if (cleanResult.success) {
      cleanProgress.complete('Flutter clean completed');
      fixed.add('Flutter clean executed');
    } else {
      cleanProgress.complete();
    }

    // Clean Gradle cache
    final gradleProgress = logger.progress('Cleaning Gradle cache');
    final gradlePatcher = GradlePatcher(projectPath);
    if (await gradlePatcher.cleanCache()) {
      fixed.add('Gradle cache cleaned');
    }
    gradleProgress.complete();

    // Run flutter pub get
    final pubProgress = logger.progress('Running flutter pub get');
    final pubResult = useFvm
        ? await ProcessRunner.run('fvm', ['flutter', 'pub', 'get'],
            workingDirectory: projectPath, runInShell: true)
        : await ProcessRunner.flutter(['pub', 'get'],
            workingDirectory: projectPath);

    if (pubResult.success) {
      pubProgress.complete('Dependencies fetched');
      fixed.add('Dependencies updated');
    } else {
      pubProgress.fail('Failed to fetch dependencies');

      final errorOutput = pubResult.stderr + pubResult.stdout;

      // Check if it's a dependency conflict
      final hasVersionConflict =
          errorOutput.contains('version solving failed') ||
              errorOutput.contains('is incompatible with') ||
              errorOutput.contains('depends on');

      if (hasVersionConflict) {
        logger.warn('\n⚠️  Dependency version conflict detected!');
        logger.info('🔧 Attempting to auto-resolve conflicts...\n');

        // Try to fix dependencies automatically
        try {
          await _fixDartDependencies(flutterVersion);

          // Try pub get again after fixing
          logger.info('\n🔄 Retrying flutter pub get...\n');
          final retryProgress = logger.progress('Running flutter pub get');
          final retryResult = useFvm
              ? await ProcessRunner.run('fvm', ['flutter', 'pub', 'get'],
                  workingDirectory: projectPath, runInShell: true)
              : await ProcessRunner.flutter(['pub', 'get'],
                  workingDirectory: projectPath);

          if (retryResult.success) {
            retryProgress.complete('Dependencies fetched');
            fixed.add('Dependencies updated (conflicts resolved)');
          } else {
            retryProgress.fail('Still failed after conflict resolution');
            logger.err('\n${retryResult.stderr}');
            logger.detail('\n${retryResult.stdout}');
            warnings.add('Could not fetch dependencies');
            return;
          }
        } catch (e) {
          logger.err('Error during dependency resolution: $e');
          warnings.add('Could not fetch dependencies');
          return;
        }
      } else {
        // Show the actual error to help diagnose the issue
        if (pubResult.stderr.isNotEmpty) {
          logger.err('\n${pubResult.stderr}');
        }
        if (pubResult.stdout.isNotEmpty) {
          logger.detail('\n${pubResult.stdout}');
        }

        warnings.add('Could not fetch dependencies');
        return; // Don't proceed if pub get failed
      }
    }

    // Check if build_runner is in pubspec.yaml
    final pubspecPath = p.join(projectPath, 'pubspec.yaml');
    if (FileUtils.fileExists(pubspecPath)) {
      final pubspecContent = await FileUtils.readFile(pubspecPath);
      if (pubspecContent.contains('build_runner:')) {
        logger.info('📦 build_runner detected, running code generation...');
        final buildRunnerProgress =
            logger.progress('Running build_runner build');

        final buildRunnerResult = useFvm
            ? await ProcessRunner.run(
                'fvm', ['flutter', 'pub', 'run', 'build_runner', 'build', '-d'],
                workingDirectory: projectPath, runInShell: true)
            : await ProcessRunner.flutter(
                ['pub', 'run', 'build_runner', 'build', '-d'],
                workingDirectory: projectPath);

        if (buildRunnerResult.success) {
          buildRunnerProgress.complete('Code generation completed');
          fixed.add('build_runner executed');
        } else {
          buildRunnerProgress.fail('Code generation failed');
          warnings.add('build_runner execution failed');
        }
      }
    }
  }

  Future<void> _loadVersionMap() async {
    // Use FlutterInstaller to load version map with proper path resolution
    final installer = FlutterInstaller(logger);
    await installer.loadVersionMap();
    versionMap = {'flutter_compatibility': installer.versionMap};

    // Add defaults if not present
    if (!versionMap.containsKey('defaults')) {
      versionMap['defaults'] = {
        'gradle': '8.0',
        'agp': '8.0.0',
        'kotlin': '1.8.0',
        'java': '17',
      };
    }
  }

  int _compareVersions(String version1, String version2) {
    final v1Parts =
        version1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final v2Parts =
        version2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final v1 = i < v1Parts.length ? v1Parts[i] : 0;
      final v2 = i < v2Parts.length ? v2Parts[i] : 0;
      if (v1 != v2) return v1.compareTo(v2);
    }
    return 0;
  }

  /// Check if updating SDK constraint would cross null safety boundary
  /// Returns false if original was pre-null safety and target is null safety
  Future<bool> _shouldUpdateSdkConstraint(
    String targetFlutterVersion,
    String? originalFlutterVersion,
  ) async {
    if (originalFlutterVersion == null) return true;

    // Null safety introduced in Dart 2.12 (Flutter 2.0+)
    final isOriginalPreNullSafety = _isPreNullSafety(originalFlutterVersion);
    final isTargetPreNullSafety = _isPreNullSafety(targetFlutterVersion);

    // If both in same era, safe to update
    if (isOriginalPreNullSafety == isTargetPreNullSafety) {
      return true;
    }

    // Crossing from pre → post null safety: DON'T update
    // This would break the project as packages expect non-null safety
    if (isOriginalPreNullSafety && !isTargetPreNullSafety) {
      return false;
    }

    // Crossing from post → pre null safety: shouldn't happen, but allow
    return true;
  }

  /// Check if Flutter version is pre-null safety (< 2.0)
  bool _isPreNullSafety(String flutterVersion) {
    final version = flutterVersion.replaceAll(RegExp(r'[^0-9.]'), '');
    final parts = version.split('.').map((p) {
      final parsed = int.tryParse(p);
      return parsed ?? 0;
    }).toList();

    if (parts.isEmpty) return false;

    // Flutter < 2.0 is pre-null safety
    final major = parts[0];
    return major < 2;
  }

  /// Analyze project version from multiple sources with smart prioritization
  /// This is the BATTLE-PROOF strategy for determining the true original version
  Future<VersionAnalysis> _analyzeProjectVersion(
    String? metadataVersion,
    String? requiredVersion,
    String? fvmVersion,
  ) async {
    // Case 1: .metadata and pubspec.yaml SDK agree (ideal case)
    if (metadataVersion != null && requiredVersion != null) {
      final metadataCompatible =
          _isVersionCompatible(metadataVersion, requiredVersion);

      if (metadataCompatible) {
        // Perfect alignment - use metadata version
        return VersionAnalysis(
          recommendedVersion: metadataVersion,
          trueOriginalVersion: metadataVersion,
        );
      } else {
        // Conflict: .metadata says old, pubspec says new
        // Decision: Use the LOWER version (safer, original state)
        final useMetadata =
            _compareVersions(metadataVersion, requiredVersion) < 0;

        return VersionAnalysis(
          recommendedVersion: useMetadata ? metadataVersion : requiredVersion,
          hasConflict: true,
          conflictReason:
              'Version Mismatch: .metadata ($metadataVersion) vs pubspec.yaml (>=$requiredVersion)',
          resolutionStrategy: useMetadata
              ? 'Using .metadata version ($metadataVersion) - restoring original state\n'
                  '   Packages requiring >=$requiredVersion will be downgraded\n'
                  '   To upgrade instead, run: flutterfix sync (without --original)'
              : 'Using pubspec.yaml constraint ($requiredVersion) - respecting updated requirements\n'
                  '   .metadata appears outdated, using current SDK requirements',
          trueOriginalVersion: metadataVersion,
        );
      }
    }

    // Case 2: Only .metadata available (trust it)
    if (metadataVersion != null) {
      return VersionAnalysis(
        recommendedVersion: metadataVersion,
        trueOriginalVersion: metadataVersion,
      );
    }

    // Case 3: Only pubspec.yaml SDK constraint available
    if (requiredVersion != null) {
      return VersionAnalysis(
        recommendedVersion: requiredVersion,
        hasConflict: true,
        conflictReason: 'Missing .metadata file',
        resolutionStrategy:
            'Using pubspec.yaml SDK constraint ($requiredVersion)\n'
            '   .metadata not found - using current requirements',
      );
    }

    // Case 4: Only FVM config available (less reliable but better than nothing)
    if (fvmVersion != null) {
      return VersionAnalysis(
        recommendedVersion: fvmVersion,
        hasConflict: true,
        conflictReason: 'No version info in .metadata or pubspec.yaml',
        resolutionStrategy: 'Using FVM configured version ($fvmVersion)\n'
            '   This may not be the original version',
      );
    }

    // Case 5: No version info found anywhere
    return VersionAnalysis(
      recommendedVersion: null,
    );
  }

  /// Check if metadata version is compatible with required SDK constraint
  bool _isVersionCompatible(String flutterVersion, String requiredSdkMin) {
    // Get Dart SDK for this Flutter version
    final flutterParts =
        flutterVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    if (flutterParts.isEmpty) return false;

    final flutterMajor = flutterParts[0];
    final flutterMinor = flutterParts.length > 1 ? flutterParts[1] : 0;

    // Map Flutter to Dart SDK (approximate)
    String dartSdk;
    if (flutterMajor >= 3) {
      if (flutterMinor >= 24) {
        dartSdk = '3.5.0';
      } else if (flutterMinor >= 10) {
        dartSdk = '3.0.0';
      } else {
        dartSdk = '2.17.0';
      }
    } else if (flutterMajor == 2) {
      if (flutterMinor >= 8) {
        dartSdk = '2.15.0';
      } else if (flutterMinor >= 5) {
        dartSdk = '2.14.0';
      } else {
        dartSdk = '2.12.0';
      }
    } else {
      // Flutter 1.x
      if (flutterMinor >= 22) {
        dartSdk = '2.10.0';
      } else if (flutterMinor >= 20) {
        dartSdk = '2.9.0';
      } else {
        dartSdk = '2.7.0';
      }
    }

    // Check if Dart SDK meets requirement
    return _compareVersions(dartSdk, requiredSdkMin) >= 0;
  }

  /// Handle packages that are incompatible with pre-null safety
  Future<void> _handleIncompatiblePackages(
    PubspecPatcher patcher,
    String flutterVersion,
  ) async {
    try {
      // Run pub get to detect conflicts
      final result = await ProcessRunner.flutter(
        ['pub', 'get'],
        workingDirectory: projectPath,
      );

      if (result.success) {
        logger.success('✅ All packages are compatible!');
        return;
      }

      // Parse error output to find incompatible packages
      final output = result.stderr + result.stdout;
      final incompatiblePackages = <String, String>{};

      // Look for patterns like "package X requires SDK version >=Y.Y.Y"
      final sdkRequirementRegex = RegExp(
        r'(\w+).*requires SDK version >=(\d+\.\d+\.\d+)',
        multiLine: true,
      );

      for (final match in sdkRequirementRegex.allMatches(output)) {
        final packageName = match.group(1)!;
        final requiredSdk = match.group(2)!;
        incompatiblePackages[packageName] = requiredSdk;
      }

      if (incompatiblePackages.isEmpty) {
        logger.warn(
            '⚠️  Dependency resolution failed but no specific package conflicts detected');
        logger.info(
            '💡 Try manually reviewing pubspec.yaml for packages added after project creation');
        return;
      }

      logger.warn(
          '⚠️  Found ${incompatiblePackages.length} package(s) incompatible with pre-null safety:');
      for (final entry in incompatiblePackages.entries) {
        logger.warn('   • ${entry.key} (requires SDK >=${entry.value})');
      }
      logger.info('');

      logger.info('💡 Options to fix:');
      logger.info('   1. Downgrade these packages to pre-null safety versions');
      logger.info('   2. Remove these packages (if not essential)');
      logger.info(
          '   3. Upgrade to Flutter 2.0+ with: flutterfix sync (without --original)');
      logger.info('');

      if (autoApplyFixes) {
        logger.info('🔧 Auto-downgrading incompatible packages...\n');
        await _downgradePackages(
            patcher, incompatiblePackages.keys.toList(), flutterVersion);
      } else {
        final shouldFix = logger.confirm(
          'Would you like to auto-downgrade these packages to compatible versions?',
          defaultValue: true,
        );

        if (shouldFix) {
          logger.info('');
          await _downgradePackages(
              patcher, incompatiblePackages.keys.toList(), flutterVersion);
        } else {
          logger.info('⏭️  Skipping package downgrade');
          logger.info(
              '💡 You can manually edit pubspec.yaml to fix dependencies');
        }
      }
    } catch (e) {
      logger.err('Error handling incompatible packages: $e');
    }
  }

  /// Downgrade packages to versions compatible with given Flutter version
  Future<void> _downgradePackages(
    PubspecPatcher patcher,
    List<String> packages,
    String flutterVersion,
  ) async {
    final downgradedPackages = <String, String>{};

    for (final packageName in packages) {
      logger.info('🔍 Finding compatible version for $packageName...');

      final compatibleVersionMap =
          await FlutterDetector.findCompatiblePackageVersions(
        packageName,
        flutterVersion,
      );

      if (compatibleVersionMap.isNotEmpty) {
        // Get the latest compatible version
        final versions = compatibleVersionMap.keys.toList()
          ..sort((a, b) => b.compareTo(a)); // Sort descending
        final version = versions.first;
        downgradedPackages[packageName] = version;
        logger.success('   → Found $packageName: ^$version');
      } else {
        // Fallback: Try known compatible versions for common packages
        final fallbackVersion =
            _getKnownCompatibleVersion(packageName, flutterVersion);
        if (fallbackVersion != null) {
          downgradedPackages[packageName] = fallbackVersion;
          logger.success(
              '   → Found $packageName: ^$fallbackVersion (known compatible)');
        } else {
          logger.warn(
              '   → No compatible version found, consider removing $packageName');
        }
      }
    }

    if (downgradedPackages.isNotEmpty) {
      logger.info('');
      logger.info('📝 Updating pubspec.yaml with compatible versions...');
      await patcher.updateMultiplePackages(downgradedPackages);
      logger.success('✅ Packages downgraded successfully!');
      logger.info('');
      logger.info('🔄 Running pub get with updated versions...');

      final result = await ProcessRunner.flutter(
        ['pub', 'get'],
        workingDirectory: projectPath,
      );

      if (result.success) {
        logger.success('✅ Dependencies resolved successfully!');
      } else {
        logger
            .warn('⚠️  Some issues remain, manual intervention may be needed');
      }
    } else {
      // No compatible versions found - provide manual guidance
      logger.info('');
      logger.warn('⚠️  Could not find compatible versions automatically');
      logger.info('');
      logger.info('💡 Manual solutions:');
      logger.info('');
      logger
          .info('   Option 1: Remove incompatible packages from pubspec.yaml');
      for (final packageName in packages) {
        logger.info('      • $packageName');
      }
      logger.info('');
      logger.info('   Option 2: Find compatible versions manually on pub.dev');
      for (final packageName in packages) {
        logger.info('      • https://pub.dev/packages/$packageName/versions');
      }
      logger.info('');
      logger.info('   Option 3: Upgrade Flutter to get newer Dart SDK');
      logger.info('      • Run: flutterfix sync (without --original)');
      logger.info('      • This will use a newer Flutter with compatible SDK');
      logger.info('');
    }
  }

  /// Parse SDK incompatibility errors from pub get output
  Map<String, String> _parseSdkIncompatibilities(String output) {
    final incompatiblePackages = <String, String>{};

    // Pattern 1: "package_name >=version which requires SDK version >=X.Y.Z"
    // Example: "upgrader >=5.0.0-alpha.1 which requires SDK version >=2.17.1 <4.0.0"
    final pattern1 = RegExp(
      r'(\w+)\s+>=[\d\.\w-]+\s+which requires SDK version >=(\d+\.\d+\.\d+)',
      multiLine: true,
    );

    for (final match in pattern1.allMatches(output)) {
      final packageName = match.group(1)!;
      final requiredSdk = match.group(2)!;

      // Filter out common false positives (words that aren't package names)
      if (!_isReservedWord(packageName)) {
        incompatiblePackages[packageName] = requiredSdk;
      }
    }

    // Pattern 2: "depends on package_name which requires SDK version >=X.Y.Z"
    final pattern2 = RegExp(
      r'depends on (\w+)[^\w]*which requires SDK version >=(\d+\.\d+\.\d+)',
      multiLine: true,
    );

    for (final match in pattern2.allMatches(output)) {
      final packageName = match.group(1)!;
      final requiredSdk = match.group(2)!;

      if (!_isReservedWord(packageName)) {
        incompatiblePackages[packageName] = requiredSdk;
      }
    }

    return incompatiblePackages;
  }

  /// Get known compatible version for common packages
  String? _getKnownCompatibleVersion(
      String packageName, String flutterVersion) {
    // Known compatible versions for popular packages with different Flutter/Dart versions
    final knownVersions = <String, Map<String, String>>{
      'upgrader': {
        '1.22': '3.7.0', // Flutter 1.22 (Dart 2.10)
        '2.0': '4.2.0', // Flutter 2.0-2.9 (Dart 2.12-2.14)
        '2.10': '4.2.0', // Flutter 2.10+ (Dart 2.16)
        '2.17': '6.0.0', // Flutter 2.17+ (Dart 2.17)
        '3.0': '6.0.0', // Flutter 3.0+ (Dart 2.17+)
      },
      'url_launcher': {
        '1.22': '5.7.10',
        '2.0': '6.0.20',
        '2.10': '6.0.20',
        '3.0': '6.1.0',
      },
      'shared_preferences': {
        '1.22': '0.5.12',
        '2.0': '2.0.15',
        '2.10': '2.0.15',
        '3.0': '2.1.0',
      },
    };

    final packageVersions = knownVersions[packageName];
    if (packageVersions == null) return null;

    // Get Flutter major.minor version
    final parts = flutterVersion.split('.');
    if (parts.length < 2) return null;

    final majorMinor = '${parts[0]}.${parts[1]}';

    // Try exact match first
    if (packageVersions.containsKey(majorMinor)) {
      return packageVersions[majorMinor]!;
    }

    // Try major version match
    final major = parts[0];
    if (packageVersions.containsKey(major)) {
      return packageVersions[major]!;
    }

    return null;
  }

  /// Check if a word is a reserved word (not a package name)
  bool _isReservedWord(String word) {
    const reservedWords = {
      'Because',
      'pub',
      'get',
      'version',
      'solving',
      'failed',
      'And',
      'So',
      'Thus',
      'Therefore',
      'which',
      'requires',
    };
    return reservedWords.contains(word);
  }

  Map<String, dynamic> _getCompatibleVersions(String flutterVersion) {
    final compatibility = versionMap['flutter_compatibility'] as Map;
    final defaults = Map<String, dynamic>.from(versionMap['defaults'] as Map);

    // Normalize version for lookup (remove 'v' prefix and anything after '+')
    String normalizeVersion(String version) {
      return version.replaceFirst(RegExp(r'^v'), '').split('+').first;
    }

    final normalizedFlutter = normalizeVersion(flutterVersion);

    // Find exact or closest match
    if (compatibility.containsKey(flutterVersion)) {
      return Map<String, dynamic>.from(compatibility[flutterVersion] as Map);
    }
    if (compatibility.containsKey(normalizedFlutter)) {
      return Map<String, dynamic>.from(compatibility[normalizedFlutter] as Map);
    }

    // Try major.minor match (e.g., "3.5" for "3.5.3")
    final parts = normalizedFlutter.split('.');
    if (parts.length >= 2) {
      final majorMinor = '${parts[0]}.${parts[1]}';
      if (compatibility.containsKey(majorMinor)) {
        return Map<String, dynamic>.from(compatibility[majorMinor] as Map);
      }
    }

    // Find closest version using string comparison
    final versions = compatibility.keys.toList()
      ..sort((a, b) => b.toString().compareTo(a.toString()));
    for (var version in versions) {
      // Use string comparison for version ordering
      if (normalizedFlutter.compareTo(version.toString()) >= 0) {
        return Map<String, dynamic>.from(compatibility[version] as Map);
      }
    }

    return defaults;
  }

  void _printHeader() {
    print('');
    print('╔═══════════════════════════════════════════╗');
    print('║       🔄 FlutterFix Sync 🔄               ║');
    print('║   Auto-fix Flutter Build Errors           ║');
    print('╚═══════════════════════════════════════════╝');
    print('');
  }

  void _printSummary(
    List<String> fixed,
    List<String> warnings,
    List<String> errors,
  ) {
    print('');
    print('═══════════════════════════════════════════');
    print('📊 Summary');
    print('═══════════════════════════════════════════');

    if (fixed.isNotEmpty) {
      logger.success('✅ Fixed (${fixed.length}):');
      for (var item in fixed) {
        print('   • $item');
      }
    }

    if (warnings.isNotEmpty) {
      logger.warn('⚠️  Warnings (${warnings.length}):');
      for (var item in warnings) {
        print('   • $item');
      }
    }

    if (errors.isEmpty) {
      logger.success('\n✅ Project fixed successfully!');

      // Check if using FVM
      final fvmDir = Directory(p.join(projectPath, '.fvm'));
      if (fvmDir.existsSync()) {
        logger.info('You can now run: fvm flutter run');
      } else {
        logger.info('You can now run: flutter run');
      }
    }

    print('═══════════════════════════════════════════');
    print('');
  }

  /// Fixes Dart package dependency conflicts
  Future<void> _fixDartDependencies(String flutterVersion) async {
    logger.info('\n🔍 Checking Dart package dependencies...\n');

    final resolver = DependencyResolver(logger, projectPath);
    final patcher = PubspecPatcher(logger, projectPath);

    try {
      // Create backup first
      final backupProgress = logger.progress('Creating pubspec.yaml backup');
      await patcher.createBackup();
      backupProgress.complete();

      // Run pub get to detect conflicts
      final pubGetProgress =
          logger.progress('Running pub get to detect conflicts');
      final result = await resolver.runPubGet();
      pubGetProgress.complete();

      if (result.success) {
        logger.success('✅ No dependency conflicts detected');
        await patcher.deleteBackup();
        return;
      }

      if (!result.hasConflicts) {
        logger.warn('⚠️  pub get failed but no conflicts detected');
        logger.detail('Output: ${result.output}');

        // Check if it's an SDK version incompatibility (not a package conflict)
        final output = result.output;
        if (output.contains('requires SDK version') &&
            output.contains('version solving failed')) {
          logger.info('');
          logger.info('💡 Detected SDK version incompatibility');
          logger
              .info('   Some packages require a newer Dart SDK than available');
          logger.info('');

          // Parse the error to find incompatible packages
          final sdkIncompatiblePackages = _parseSdkIncompatibilities(output);

          if (sdkIncompatiblePackages.isNotEmpty) {
            logger.warn(
                '⚠️  Found ${sdkIncompatiblePackages.length} package(s) requiring newer SDK:');
            for (final entry in sdkIncompatiblePackages.entries) {
              logger.warn('   • ${entry.key} (requires SDK >=${entry.value})');
            }
            logger.info('');

            // Offer to downgrade these packages
            final shouldFix = autoApplyFixes ||
                logger.confirm(
                  'Would you like to downgrade these packages to compatible versions?',
                  defaultValue: true,
                );

            if (shouldFix) {
              logger.info('');
              await _downgradePackages(patcher,
                  sdkIncompatiblePackages.keys.toList(), flutterVersion);
              await patcher.deleteBackup();
              return;
            } else {
              logger.info('');
              logger.info('💡 Suggested solutions:');
              logger.info('   1. Manually downgrade packages in pubspec.yaml');
              logger.info('   2. Upgrade Flutter to get newer Dart SDK');
              logger.info('   3. Remove incompatible packages');
            }
          }
        }

        await patcher.deleteBackup();
        return;
      }

      logger.warn(
          '⚠️  Found ${result.conflicts.length} dependency conflict(s)\n');

      // Deduplicate conflicts by package name
      final uniqueConflicts = <String, DependencyConflict>{};
      for (final conflict in result.conflicts) {
        uniqueConflicts[conflict.package] = conflict;
      }

      logger.info('📋 Analyzing and resolving conflicts automatically...\n');

      // Get Dart SDK version
      final dartProgress = logger.progress('Getting Dart SDK version');
      final dartSdkVersion = await resolver.getDartSdkVersion();
      dartProgress.complete();

      if (dartSdkVersion == null) {
        logger.warn('Could not determine Dart SDK version');
        await patcher.deleteBackup();
        return;
      }

      // Try to find compatible versions for each unique conflict
      final resolutions = <String, String>{};
      final unresolvedConflicts = <DependencyConflict>[];

      final resolveProgress =
          logger.progress('Resolving ${uniqueConflicts.length} conflict(s)');
      for (final conflict in uniqueConflicts.values) {
        logger.info('   Checking ${conflict.package}...');

        final compatibleVersion = await resolver.findCompatibleVersion(
          conflict.package,
          dartSdkVersion,
        );

        if (compatibleVersion != null) {
          final currentVersion = conflict.currentVersion;
          resolutions[conflict.package] =
              '^$currentVersion → $compatibleVersion';
        } else {
          unresolvedConflicts.add(conflict);
        }
      }
      resolveProgress.complete();

      // Show proposed changes and ask for consent
      if (resolutions.isNotEmpty) {
        logger.info('\n📦 Proposed dependency updates:\n');

        for (final entry in resolutions.entries) {
          final package = entry.key;
          final change = entry.value;
          logger.info('   • $package: $change');
        }

        logger.info('\n⚠️  These changes will be made to your pubspec.yaml');
        logger.info('💡 A backup will be created at pubspec.yaml.backup\n');

        // Ask for confirmation (unless auto-fix mode)
        bool shouldApply = autoApplyFixes;

        if (!autoApplyFixes) {
          final response = logger.prompt(
            '❓ Apply these ${resolutions.length} dependency update(s)? (y/n)',
          );
          shouldApply =
              response.toLowerCase() == 'y' || response.toLowerCase() == 'yes';
        } else {
          logger.info(
              '🤖 Auto-fix mode enabled - applying changes automatically\n');
        }

        if (shouldApply) {
          logger.info('\n📝 Applying updates...\n');

          final applyProgress =
              logger.progress('Updating ${resolutions.length} package(s)');
          for (final entry in resolutions.entries) {
            final package = entry.key;
            final change = entry.value;
            final newVersion = change.split(' → ').last;

            await patcher.updatePackageVersion(package, newVersion);
          }
          applyProgress.complete();

          logger.success(
              '\n✅ Successfully updated ${resolutions.length} package(s)');
          logger.info('💡 Running pub get to verify...\n');

          // Verify the fix worked
          final verifyResult = await resolver.runPubGet();
          if (verifyResult.success) {
            logger.success('✅ All dependency conflicts resolved!');
            await patcher.deleteBackup();
          } else {
            logger.warn('⚠️  Some conflicts remain after updates');
          }
        } else {
          logger.info('\n❌ Updates cancelled by user');
          logger.info('💡 Restoring original pubspec.yaml...');
          await patcher.restoreFromBackup();
          logger.info('✅ No changes were made');
          return;
        }
      }

      // Handle unresolved conflicts with helpful guidance
      if (unresolvedConflicts.isNotEmpty) {
        // Analyze conflicts to determine if direct or transitive
        logger.detail('Analyzing dependency tree...');
        await resolver.analyzeConflicts(unresolvedConflicts);

        logger.warn(
            '\n⚠️  Could not auto-resolve ${unresolvedConflicts.length} conflict(s):\n');

        for (final conflict in unresolvedConflicts) {
          logger.info('   📦 ${conflict.package} ^${conflict.currentVersion}');
          logger.info('      Issue: Incompatible with Flutter $flutterVersion');
          logger.info('      Reason: No compatible version found on pub.dev');

          if (!conflict.isDirectDependency &&
              conflict.dependentPackages.isNotEmpty) {
            logger.info(
                '      Type: Transitive dependency (not in your pubspec.yaml)');
            logger.info(
                '      Required by: ${conflict.dependentPackages.join(", ")}');
          } else if (conflict.isDirectDependency) {
            logger.info('      Type: Direct dependency (in your pubspec.yaml)');
          }
          logger.info('');
        }

        logger.info('   💡 Recommended solutions:\n');

        // Find the minimum compatible Flutter version intelligently
        final recommendedProgress =
            logger.progress('Finding compatible Flutter version');
        final recommendedVersion = await resolver
            .findMinimumCompatibleFlutterVersion(unresolvedConflicts);
        recommendedProgress.complete();

        // Provide smart recommendations based on dependency type
        final directConflicts =
            unresolvedConflicts.where((c) => c.isDirectDependency).toList();
        final transitiveConflicts =
            unresolvedConflicts.where((c) => !c.isDirectDependency).toList();

        if (recommendedVersion != null) {
          // Compare with current version to see if upgrade is needed
          final currentVersion = flutterVersion;
          final needsUpgrade =
              _compareVersions(recommendedVersion, currentVersion) > 0;

          if (needsUpgrade) {
            logger.info('   Option 1: Upgrade Flutter (Most Effective) ✨');
            logger.info('      Current version: $currentVersion');
            logger.info('      Recommended version: $recommendedVersion');
            logger.info(
                '      Run: flutterfix install --version $recommendedVersion');
            logger.info('      This resolves SDK version pinning issues');
            logger.info('      and gives access to newer package versions');
          } else {
            logger.info(
                '   ℹ️  Your Flutter version ($currentVersion) is already compatible');
            logger.info(
                '      The conflict may be due to package-specific issues');
          }
        } else {
          logger.info('   Option 1: Upgrade Flutter (Recommended) ✨');
          logger.info('      Run: flutterfix install --list');
          logger.info('      To see available Flutter versions');
          logger.info('      Then: flutterfix install --version <VERSION>');
        }
        logger.info('');

        if (transitiveConflicts.isNotEmpty) {
          logger.info('   Option 2: Update parent packages 🔄');
          logger.info(
              '      These packages are pulled in by other dependencies:');
          for (final conflict in transitiveConflicts) {
            if (conflict.dependentPackages.isNotEmpty) {
              logger.info(
                  '      • Update ${conflict.dependentPackages.join(", ")}');
              logger.info('        (which depends on ${conflict.package})');
            }
          }
          logger.info('');
        }

        if (directConflicts.isNotEmpty) {
          logger.info('   Option 3: Replace direct dependencies 📦');
          logger.info('      Consider removing or replacing:');
          for (final conflict in directConflicts) {
            logger.info('      • ${conflict.package}');
            logger.info('        Search pub.dev for compatible alternatives');
          }
          logger.info('');
        }

        logger.info('   Option 4: Use dependency overrides (Temporary) ⚠️');
        logger.info(
            '      Add to pubspec.yaml (not recommended for production):');
        logger.info('      dependency_overrides:');
        for (final conflict in unresolvedConflicts) {
          logger
              .info('        ${conflict.package}: ^${conflict.currentVersion}');
        }
        logger.info('');

        if (resolutions.isEmpty) {
          // Nothing was fixed, restore backup
          await patcher.restoreFromBackup();
        } else {
          // Some packages were fixed, keep the partial progress
          logger.info(
              '   ℹ️  Keeping partial fixes (${resolutions.length} packages updated)');
        }
      }
    } catch (e, stackTrace) {
      logger.err('❌ Error during dependency resolution: $e');
      logger.detail('$stackTrace');
      logger.info('🔄 Rolling back changes...');
      try {
        await patcher.restoreFromBackup();
        logger.info('✅ Rollback successful');
      } catch (restoreError) {
        logger.err('❌ Failed to restore backup: $restoreError');
        logger.info('💡 Manual recovery: Restore from pubspec.yaml.backup');
      }
    }
  }
}
