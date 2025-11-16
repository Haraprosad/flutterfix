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

class SyncCommand {
  final Logger logger;
  final String projectPath;
  final bool useOriginal;
  final bool autoInstallFlutter;
  final bool fixDependencies;
  late Map<String, dynamic> versionMap;

  SyncCommand(
    this.logger,
    this.projectPath, {
    this.useOriginal = false,
    this.autoInstallFlutter = false,
    this.fixDependencies = false,
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
          
          await _cleanAndRefresh(fixed, warnings);
          _printSummary(fixed, warnings, errors);
          return;
        }
      }
      
      // Try to auto-install based on project requirements
      logger.info('🤖 Attempting to auto-install compatible Flutter version...\n');
      
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
          
          await _cleanAndRefresh(fixed, warnings);
          _printSummary(fixed, warnings, errors);
          return;
        }
      }
      
      // Final fallback - cannot proceed
      logger.err('❌ Could not detect or install Flutter');
      logger.info('💡 Manual installation required:');
      logger.info('   1. Install Flutter: https://flutter.dev/docs/get-started/install');
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
    await _cleanAndRefresh(fixed, warnings);

    // Print summary
    _printSummary(fixed, warnings, errors);
  }

  Future<void> _executeWithOriginalVersion() async {
    logger.info('🔍 Detecting original Flutter version from .metadata...\n');

    // Detect original version
    final originalVersion =
        await FlutterDetector.detectOriginalVersion(projectPath);

    if (originalVersion == null) {
      logger
          .warn('⚠️  Could not detect original Flutter version from .metadata');
      logger.info('💡 Falling back to SDK constraint from pubspec.yaml\n');

      final recommended =
          await FlutterDetector.getRecommendedVersion(projectPath);
      if (recommended == null) {
        logger.err('❌ Could not determine Flutter version');
        logger
            .info('💡 Try running: flutterfix sync (without --original flag)');
        return;
      }

      logger.info('📦 Recommended version: $recommended\n');
      await _handleFlutterInstallation(recommended);
    } else {
      logger.success('✅ Original Flutter version detected: $originalVersion\n');
      await _handleFlutterInstallation(originalVersion);
    }

    // Now sync with the detected/installed version
    final flutterInfo = await FlutterDetector.detectInstalled();
    String? flutterVersion = flutterInfo.version;

    // If global Flutter not found, check FVM config
    if (flutterVersion == null || !flutterInfo.isInstalled) {
      final fvmConfigPath = p.join(projectPath, '.fvm', 'fvm_config.json');
      if (FileUtils.fileExists(fvmConfigPath)) {
        final fvmConfig = await FileUtils.readFile(fvmConfigPath);
        final config = jsonDecode(fvmConfig) as Map<String, dynamic>;
        flutterVersion = config['flutterSdkVersion'] as String?;
      }
    }

    if (flutterVersion == null) {
      logger.err('❌ Could not determine Flutter version');
      return;
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
    await _cleanAndRefresh(fixed, warnings);

    // Print summary
    _printSummary(fixed, warnings, errors);
  }

  Future<void> _handleFlutterInstallation(String version) async {
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
        return;
      }

      logger.success('✅ Flutter $stableVersion installed successfully\n');
    } else {
      logger.info('💡 To install Flutter $version automatically, run:');
      logger.info('   flutterfix sync --original --install-flutter\n');
      logger.info('   OR manually:');
      logger.info('   fvm install $version && fvm use $version\n');
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
    final gradlePatcher = GradlePatcher(projectPath);
    if (await gradlePatcher
        .updateWrapperVersion(versions['gradle'].toString())) {
      fixed.add('Gradle ${versions['gradle']}');
    }

    await gradlePatcher.optimizeProperties();
    await gradlePatcher.ensureRepositories();

    // Fix AGP
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

    // Fix Kotlin
    final kotlinPatcher = KotlinPatcher(projectPath);
    if (await kotlinPatcher.updateVersion(versions['kotlin'].toString())) {
      fixed.add('Kotlin ${versions['kotlin']}');
    }

    await kotlinPatcher.ensureKotlinPlugin(versions['kotlin'].toString());
    await kotlinPatcher.applyKotlinAndroidPlugin();
    await kotlinPatcher.addKotlinOptions();
  }

  Future<void> _cleanAndRefresh(
    List<String> fixed,
    List<String> warnings,
  ) async {
    final progress = logger.progress('Cleaning build cache');

    final gradlePatcher = GradlePatcher(projectPath);
    if (await gradlePatcher.cleanCache()) {
      fixed.add('Build cache cleaned');
    }

    progress.complete();

    // Run flutter pub get
    final pubProgress = logger.progress('Running flutter pub get');
    final result = await ProcessRunner.flutter(
      ['pub', 'get'],
      workingDirectory: projectPath,
    );

    if (result.success) {
      pubProgress.complete('Dependencies fetched');
      fixed.add('Dependencies updated');
    } else {
      pubProgress.fail('Failed to fetch dependencies');
      warnings.add('Could not fetch dependencies');
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
      await patcher.createBackup();

      // Run pub get to detect conflicts
      final result = await resolver.runPubGet();

      if (result.success) {
        logger.success('✅ No dependency conflicts detected');
        await patcher.deleteBackup();
        return;
      }

      if (!result.hasConflicts) {
        logger.warn('⚠️  pub get failed but no conflicts detected');
        logger.detail('Output: ${result.output}');
        await patcher.deleteBackup();
        return;
      }

      logger.warn('⚠️  Found ${result.conflicts.length} dependency conflict(s)\n');

      // Deduplicate conflicts by package name
      final uniqueConflicts = <String, DependencyConflict>{};
      for (final conflict in result.conflicts) {
        uniqueConflicts[conflict.package] = conflict;
      }

      logger.info('📋 Analyzing and resolving conflicts automatically...\n');

      // Get Dart SDK version
      final dartSdkVersion = await resolver.getDartSdkVersion();
      if (dartSdkVersion == null) {
        logger.warn('Could not determine Dart SDK version');
        await patcher.deleteBackup();
        return;
      }

      // Try to find compatible versions for each unique conflict
      final resolutions = <String, String>{};
      final unresolvedConflicts = <DependencyConflict>[];

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

      // Auto-apply compatible version updates
      if (resolutions.isNotEmpty) {
        logger.info('\n📦 Applying automatic dependency updates:\n');

        for (final entry in resolutions.entries) {
          final package = entry.key;
          final change = entry.value;
          final newVersion = change.split(' → ').last;

          logger.info('   ✓ $package: $change');
          await patcher.updatePackageVersion(package, newVersion);
        }

        logger.success('\n✅ Successfully updated ${resolutions.length} package(s)');
        logger.info('💡 Running pub get to verify...\n');
        
        // Verify the fix worked
        final verifyResult = await resolver.runPubGet();
        if (verifyResult.success) {
          logger.success('✅ All dependency conflicts resolved!');
          await patcher.deleteBackup();
        } else {
          logger.warn('⚠️  Some conflicts remain after updates');
        }
      }

      // Handle unresolved conflicts with helpful guidance
      if (unresolvedConflicts.isNotEmpty) {
        logger.warn(
            '\n⚠️  Could not auto-resolve ${unresolvedConflicts.length} conflict(s):\n');

        for (final conflict in unresolvedConflicts) {
          logger.info(
              '   📦 ${conflict.package} ^${conflict.currentVersion}');
          logger.info(
              '      Issue: Incompatible with Flutter $flutterVersion');
          logger.info(
              '      Reason: No compatible version found on pub.dev');
          logger.info('');
        }

        logger.info('   💡 Manual intervention required:');
        logger.info('');
        logger.info('   Option 1: Upgrade Flutter (Recommended)');
        logger.info('      Run: flutterfix install --version 3.27');
        logger.info('      This will give access to newer package versions');
        logger.info('');
        logger.info('   Option 2: Remove incompatible packages');
        for (final conflict in unresolvedConflicts) {
          logger.info('      • Remove ${conflict.package} from pubspec.yaml');
        }
        logger.info('');
        logger.info('   Option 3: Find alternative packages');
        logger.info('      Search pub.dev for compatible alternatives');
        logger.info('');
        
        if (resolutions.isEmpty) {
          // Nothing was fixed, restore backup
          await patcher.restoreFromBackup();
        } else {
          // Some packages were fixed, keep the partial progress
          logger.info('   ℹ️  Keeping partial fixes (${resolutions.length} packages updated)');
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
