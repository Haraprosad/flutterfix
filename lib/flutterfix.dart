library flutterfix;

// CLI Commands
export 'src/cli/doctor_command.dart';
export 'src/cli/sync_command.dart';
export 'src/cli/upgrade_command.dart';
export 'src/cli/install_command.dart';

// Detectors
export 'src/detect/flutter_detector.dart';
export 'src/detect/gradle_detector.dart';
export 'src/detect/ios_detector.dart';

// Patchers
export 'src/patcher/gradle_patcher.dart';
export 'src/patcher/agp_patcher.dart';
export 'src/patcher/kotlin_patcher.dart';
export 'src/patcher/ios_patcher.dart';

// Installer
export 'src/installer/flutter_installer.dart';

// Utilities
export 'src/runner/process_runner.dart';
export 'src/utils/file_utils.dart';
