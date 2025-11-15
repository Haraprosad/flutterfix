import 'package:mason_logger/mason_logger.dart';
import '../detect/flutter_detector.dart';
import '../detect/gradle_detector.dart';
import '../detect/ios_detector.dart';
import '../utils/file_utils.dart';

class DoctorCommand {
  final Logger logger;
  final String projectPath;

  DoctorCommand(this.logger, this.projectPath);

  Future<void> execute() async {
    _printHeader();

    // Check if it's a Flutter project
    if (!FileUtils.isFlutterProject(projectPath)) {
      logger.err('❌ Not a Flutter project');
      return;
    }

    logger.info('🔍 Running diagnostics...\n');

    // Detect Flutter
    await _checkFlutter();

    // Detect Android setup
    if (FileUtils.hasAndroidFolder(projectPath)) {
      await _checkAndroid();
    } else {
      logger.warn('⚠️  No Android folder found');
    }

    // Detect iOS setup
    if (FileUtils.hasIosFolder(projectPath)) {
      await _checkIos();
    } else {
      logger.info('ℹ️  No iOS folder found');
    }

    _printSummary();
  }

  Future<void> _checkFlutter() async {
    final progress = logger.progress('Checking Flutter installation');

    final flutterInfo = await FlutterDetector.detectInstalled();

    if (!flutterInfo.isInstalled) {
      progress.fail('Flutter not found');
      return;
    }

    progress.complete('Flutter ${flutterInfo.version} detected');

    final projectInfo = await FlutterDetector.detectFromProject(projectPath);
    logger.detail('  Project: ${projectInfo.projectName}');
    logger.detail('  SDK Constraint: ${projectInfo.sdkConstraint}');
  }

  Future<void> _checkAndroid() async {
    final progress = logger.progress('Checking Android configuration');

    final gradleInfo = await GradleDetector.detectAll(projectPath);

    progress.complete('Android configuration found');

    logger.detail('  Gradle: ${gradleInfo.version ?? "Unknown"}');
    logger.detail('  AGP: ${gradleInfo.agpVersion ?? "Unknown"}');
    logger.detail('  Kotlin: ${gradleInfo.kotlinVersion ?? "Unknown"}');
    logger.detail('  Java: ${gradleInfo.javaVersion ?? "Unknown"}');

    // Check compatibility
    if (gradleInfo.version != null && gradleInfo.javaVersion != null) {
      final compatible = GradleDetector.isCompatibleWithJava(
        gradleInfo.version!,
        gradleInfo.javaVersion!,
      );

      if (!compatible) {
        logger.warn(
            '  ⚠️  Java ${gradleInfo.javaVersion} may not be compatible with Gradle ${gradleInfo.version}');
      }
    }
  }

  Future<void> _checkIos() async {
    final progress = logger.progress('Checking iOS configuration');

    final iosInfo = await IosDetector.detectAll();

    if (!iosInfo.isXcodeInstalled) {
      progress.fail('Xcode not installed');
      return;
    }

    progress.complete('iOS configuration found');

    logger.detail('  Xcode: ${iosInfo.xcodeVersion}');
    logger.detail('  Swift: ${iosInfo.swiftVersion}');
    logger
        .detail('  CocoaPods: ${iosInfo.cocoaPodsVersion ?? "Not installed"}');
  }

  void _printHeader() {
    print('');
    print('╔═══════════════════════════════════════════╗');
    print('║       🏥 FlutterFix Doctor 🏥             ║');
    print('║   Diagnose Flutter Project Issues         ║');
    print('╚═══════════════════════════════════════════╝');
    print('');
  }

  void _printSummary() {
    print('');
    print('═══════════════════════════════════════════');
    logger.info('💡 Tip: Run "flutterfix sync" to fix detected issues');
    print('═══════════════════════════════════════════');
    print('');
  }
}
