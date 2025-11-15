import 'package:mason_logger/mason_logger.dart';
import 'package:yaml/yaml.dart';
import '../detect/flutter_detector.dart';
import '../patcher/gradle_patcher.dart';
import '../patcher/agp_patcher.dart';
import '../patcher/kotlin_patcher.dart';
import '../utils/file_utils.dart';
import '../runner/process_runner.dart';

class SyncCommand {
  final Logger logger;
  final String projectPath;
  late Map<String, dynamic> versionMap;

  SyncCommand(this.logger, this.projectPath);

  Future<void> execute() async {
    _printHeader();

    // Load version compatibility map
    await _loadVersionMap();

    // Detect versions
    final flutterInfo = await FlutterDetector.detectInstalled();
    if (!flutterInfo.isInstalled) {
      logger.err('❌ Flutter not installed');
      return;
    }

    logger.info('📦 Flutter ${flutterInfo.version} detected\n');

    final fixed = <String>[];
    final warnings = <String>[];
    final errors = <String>[];

    // Fix Android
    if (FileUtils.hasAndroidFolder(projectPath)) {
      await _fixAndroid(flutterInfo, fixed, warnings, errors);
    }

    // Clean and refresh
    await _cleanAndRefresh(fixed, warnings);

    // Print summary
    _printSummary(fixed, warnings, errors);
  }

  Future<void> _fixAndroid(
    FlutterInfo flutterInfo,
    List<String> fixed,
    List<String> warnings,
    List<String> errors,
  ) async {
    logger.info('🔧 Fixing Android configuration...\n');

    final versions = _getCompatibleVersions(flutterInfo.majorMinorVersion);

    // Fix Gradle
    final gradlePatcher = GradlePatcher(projectPath);
    if (await gradlePatcher.updateWrapperVersion(versions['gradle']!)) {
      fixed.add('Gradle ${versions['gradle']}');
    }

    await gradlePatcher.optimizeProperties();
    await gradlePatcher.ensureRepositories();

    // Fix AGP
    final agpPatcher = AgpPatcher(projectPath);
    if (await agpPatcher.updateVersion(versions['agp']!)) {
      fixed.add('AGP ${versions['agp']}');
    }

    await agpPatcher.ensureNamespace();
    await agpPatcher.updateSdkVersions(
      minSdk: int.parse(versions['min_sdk']!),
      compileSdk: int.parse(versions['compile_sdk']!),
      targetSdk: int.parse(versions['target_sdk']!),
    );
    await agpPatcher.fixCompileOptions();

    // Fix Kotlin
    final kotlinPatcher = KotlinPatcher(projectPath);
    if (await kotlinPatcher.updateVersion(versions['kotlin']!)) {
      fixed.add('Kotlin ${versions['kotlin']}');
    }

    await kotlinPatcher.ensureKotlinPlugin(versions['kotlin']!);
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
    // Load from embedded config
    final configPath = 'lib/src/config/version_map.yaml';
    final content = await FileUtils.readFile(configPath);
    final yaml = loadYaml(content);
    versionMap = Map<String, dynamic>.from(yaml as Map);
  }

  Map<String, String> _getCompatibleVersions(String flutterVersion) {
    final compatibility = versionMap['flutter_compatibility'] as Map;
    final defaults = Map<String, String>.from(versionMap['defaults'] as Map);

    // Find exact or closest match
    if (compatibility.containsKey(flutterVersion)) {
      return Map<String, String>.from(compatibility[flutterVersion] as Map);
    }

    // Find closest version
    final versions = compatibility.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    for (var version in versions) {
      if (double.parse(flutterVersion) >= double.parse(version)) {
        return Map<String, String>.from(compatibility[version] as Map);
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
      logger.info('You can now run: flutter run');
    }

    print('═══════════════════════════════════════════');
    print('');
  }
}
