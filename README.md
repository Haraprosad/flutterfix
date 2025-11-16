# 🔧 FlutterFix

> **Make any Flutter project run instantly.**  
> Automatically fixes Flutter, Gradle, Kotlin, and Java version conflicts with a single command.

[![Pub Version](https://img.shields.io/pub/v/flutterfix?color=blue)](https://pub.dev/packages/flutterfix)
[![CI](https://github.com/haraprosad/flutterfix/workflows/CI/badge.svg)](https://github.com/haraprosad/flutterfix/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/haraprosad/flutterfix/branch/main/graph/badge.svg)](https://codecov.io/gh/haraprosad/flutterfix)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/haraprosad/flutterfix/pulls)

---

## 🚀 Why FlutterFix?

Ever cloned a Flutter project and spent hours debugging build errors?

```
❌ The Android Gradle plugin supports only Kotlin Gradle plugin version 1.5.20 and higher.
❌ Unsupported class file major version 61
❌ java.lang.NoClassDefFoundError: Could not initialize class org.codehaus.groovy
```

**FlutterFix solves this in seconds.**

It automatically:
- ✅ Detects incompatible Flutter/Gradle/Kotlin/Java versions
- ✅ Updates configuration files with correct versions
- ✅ Fixes Android SDK mismatches
- ✅ Cleans build caches
- ✅ Makes any project buildable instantly

---

## 📦 Installation

### Option 1: Global Installation (Recommended)

```bash
dart pub global activate flutterfix
```

### Option 2: Local Installation

```bash
dart pub global activate --source path .
```

### Verify Installation

```bash
flutterfix --version
```

---

## 🎯 Quick Start

### 🚀 Most Common Use Cases

#### **Scenario 1: Use Project's Original Flutter Version** (Recommended)

Perfect for cloned projects - preserves the exact development environment:

```bash
cd /path/to/your/flutter/project

# One command to detect, install, and configure everything
flutterfix sync --original --install-flutter
```

**What this does:**
1. 🔍 Detects original Flutter version from `.metadata` file
2. 📦 Auto-installs that Flutter version using FVM
3. ⚙️ Configures `.fvm/fvm_config.json` to use that version
4. 🔧 Applies version-compatible Gradle, AGP, and Kotlin configs
5. 🧹 Cleans caches and updates dependencies

**Then run your app:**
```bash
fvm flutter run
```

---

#### **Scenario 2: Upgrade to Latest Flutter & Compatible Configs**

Use the newest Flutter version with optimal build tool versions:

```bash
cd /path/to/your/flutter/project

# Install latest Flutter version
flutterfix install

# Apply latest compatible configurations
flutterfix sync
```

**Then run:**
```bash
flutter run
```

---

#### **Scenario 3: Quick Fix Without Installing Flutter**

Already have Flutter installed? Just fix the build configuration:

```bash
cd /path/to/your/flutter/project

flutterfix sync
```

This updates Gradle, AGP, Kotlin, and SDK versions to match your current Flutter version.

---

### 📋 Detailed Command Reference

#### **Sync Command**

Fix version conflicts and apply compatible configurations:

```bash
# Use current Flutter version
flutterfix sync

# Use original Flutter version (from .metadata)
flutterfix sync --original

# Use original version + auto-install if not present
flutterfix sync --original --install-flutter

# 🆕 Auto-fix Dart dependency conflicts (v1.3.0+)
flutterfix sync --original --install-flutter --fix-dependencies

# Sync specific project path
flutterfix sync --path /path/to/project
```

**🆕 New in v1.3.0: `--fix-dependencies` flag**

Automatically resolves Dart package dependency conflicts:

```bash
# Example: Fix http_parser incompatibility with Flutter 3.24.5
flutterfix sync --original --install-flutter --fix-dependencies
```

**What it does:**
- 🔍 Detects dependency conflicts from `pub get` errors
- 🌐 Queries pub.dev for compatible package versions
- ⬇️ Auto-downgrades incompatible packages (e.g., `http_parser 4.1.2 → 4.0.2`)
- 💾 Creates backup before changes (`pubspec.yaml.backup`)
- ✅ Verifies fixes by re-running pub get
- 🔄 Rolls back on failure - never breaks your app

**Example conflict it solves:**
```
❌ flutter_test from sdk is incompatible with http_parser ^4.1.2
   (requires collection ^1.19.0, but Flutter 3.24.5 has collection 1.18.0)

✅ After --fix-dependencies:
   Updated http_parser: 4.1.2 → 4.0.2
   All dependency conflicts resolved!
```

#### **Install Command**

Install Flutter versions:

```bash
# Auto-detect and install project's required version
flutterfix install

# List all available Flutter versions (176 stable versions)
flutterfix install --list

# Install specific version
flutterfix install --version 3.24

# Show version compatibility info
flutterfix install --version 3.24 --info

# Install without FVM (standalone mode)
flutterfix install --version 3.24 --no-fvm
```

#### **Other Commands**

```bash
# Diagnose project without fixing
flutterfix doctor

# Rollback last changes (interactive)
flutterfix rollback

# Rollback latest backup automatically
flutterfix rollback --latest

# List all backups
flutterfix rollback --list

# Restore specific backup by ID
flutterfix rollback --id <backup-id>

# Upgrade FlutterFix itself
flutterfix upgrade

# Show help
flutterfix --help
```

---

### 🎓 Installation Modes Explained

FlutterFix supports two installation modes for Flutter:

#### **1. FVM Mode** (Recommended)
- Uses [FVM (Flutter Version Management)](https://fvm.app/)
- Auto-installs FVM if not present
- Manages multiple Flutter versions per project
- Creates `.fvm/fvm_config.json` in your project
- **Run apps with:** `fvm flutter run`
- **Check version:** `fvm flutter --version`

#### **2. Standalone Mode** (Fallback)
- Direct git clone from Flutter repository
- Installs to `~/flutter-versions/[version]`
- **Auto-configures PATH** on macOS/Linux/Windows
- No FVM dependency
- **Run apps with:** `flutter run`
- Triggered with `--no-fvm` flag

---

### 💡 Pro Tips

**Check which Flutter version will be used:**
```bash
# For FVM projects
fvm flutter --version

# For standalone/system Flutter
flutter --version
```

**Switch between Flutter versions:**
```bash
# List all installed versions
fvm list

# Use different version
fvm use 3.24.5

# Run with specific version
fvm flutter run
```

**Clean everything before running:**
```bash
fvm flutter clean
fvm flutter pub get
fvm flutter run
```

---

## 📚 Complete Workflow Examples

### 🎯 Example 1: Clone & Run Any Flutter Project

```bash
# Clone a Flutter project
git clone https://github.com/example/flutter-app.git
cd flutter-app

# One command to set up everything
flutterfix sync --original --install-flutter

# Run the app with the correct Flutter version
fvm flutter run
```

**What happened:**
- ✅ Detected Flutter 3.24.5 from `.metadata`
- ✅ Installed Flutter 3.24.5 using FVM
- ✅ Configured `.fvm/fvm_config.json`
- ✅ Applied Gradle 8.7, AGP 8.5.0, Kotlin 2.0.10
- ✅ Cleaned caches and updated dependencies

---

### 🎯 Example 2: Fix Build Errors on Existing Project

```bash
cd /path/to/your/project

# Just fix the configuration
flutterfix sync

# Run with your current Flutter version
flutter run
```

---

### 🎯 Example 3: Upgrade Project to Latest Flutter

```bash
cd /path/to/your/project

# Install latest Flutter (3.38.1)
flutterfix install --version 3.38

# Apply latest compatible configs
flutterfix sync

# Run with the new version
fvm flutter run
```

---

### 🎯 Example 4: Rollback If Something Goes Wrong

```bash
# Undo the last changes
flutterfix rollback --latest

# Or choose from available backups
flutterfix rollback --list
flutterfix rollback --id <backup-id>
```

---

## 🔍 Understanding `--original` Flag

The `--original` flag is the **recommended approach** for cloned projects:

### Without `--original` (uses current system Flutter):
```bash
flutterfix sync
```
- Uses whatever Flutter version is currently active
- Applies compatible configs for that version
- May upgrade/downgrade build tools

### With `--original` (uses project's intended Flutter):
```bash
flutterfix sync --original --install-flutter
```
- Reads `.metadata` to find original Flutter version
- Installs that exact version
- Applies version-specific compatible configs
- **Preserves original development environment**

**Key difference:** `--original` ensures you use the same Flutter version the project was built with!

---

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🎯 **Smart Version Detection** | Automatically detects Flutter, Gradle, Kotlin, and Java versions |
| 📦 **Flutter Auto-Install** | Installs compatible Flutter version using FVM or standalone |
|  **Compatibility Matrix** | Supports Flutter 2.0 to 3.38 with tested compatibility mappings |
| 🛣️ **Auto PATH Config** | Automatically configures shell PATH for standalone installations |
| 📝 **Auto-Configuration** | Updates `build.gradle`, `gradle-wrapper.properties`, and SDK settings |
| 🔙 **Automatic Backups** | Creates backups before making changes - rollback anytime |
| 🧹 **Cache Cleaning** | Removes stale build artifacts that cause issues |
| 📊 **Detailed Reports** | Shows what was fixed and what needs attention |
| 💡 **Zero Config** | Works out of the box with sensible defaults |
| 🌍 **Cross-Platform** | Supports macOS, Linux, and Windows |

---

## 🛠️ What It Fixes

### 1. Gradle Version Issues
- Updates Gradle wrapper to compatible version
- Fixes Android Gradle Plugin (AGP) version
- Optimizes Gradle settings for performance

### 2. Kotlin Version Conflicts
- Sets correct Kotlin version based on Flutter version
- Ensures Kotlin plugin is properly configured
- Fixes `ext.kotlin_version` declarations

### 3. Java Compatibility
- Updates compile options (source/target compatibility)
- Checks Java version compatibility with Gradle
- Configures `kotlinOptions.jvmTarget`

### 4. Android SDK Configuration
- Updates `minSdkVersion` to modern standards (21+)
- Sets appropriate `compileSdk` and `targetSdk`
- Ensures AndroidX compatibility

### 5. Build Cache Issues
- Cleans Flutter build directory
- Removes Android build artifacts
- Clears Gradle cache

### 6. Flutter Version Management
- **Auto-installs compatible Flutter version** based on project requirements
- Uses **FVM (Flutter Version Management)** for easy version switching
- **Fallback to standalone** installation if FVM is unavailable
- **Auto-configures PATH** for standalone installations (macOS/Linux/Windows)
- Lists all available Flutter versions with compatibility info
- Install specific versions manually
- Supports Flutter 2.0.x to 3.38.x (all stable versions)

### 7. Backup & Rollback System
- **Automatic backups** before any file modifications
- Restore files to previous state with one command
- List all available backups with timestamps
- Clear old backups to save space
- Backup metadata includes descriptions and timestamps

---

## 📋 Example Output

```
╔═══════════════════════════════════════════╗
║       🔧 FlutterFix v1.0.0 🔧             ║
║   Auto-fix Flutter Build Errors           ║
╚═══════════════════════════════════════════╝

🔍 Detecting installed versions...
  Flutter: 3.24.0
  Dart: 3.5.0
  Java: 17
  Gradle: 7.5
  Kotlin: 1.7.10

🔎 Analyzing project structure...
  ✓ Valid Flutter project
  Project: my_app
  SDK: >=3.0.0 <4.0.0
  ✓ Android configuration found

🔧 Fixing Gradle configuration...
  ✓ Gradle version updated to 8.3
  ✓ Android Gradle Plugin updated to 8.1.0
  ✓ Gradle settings optimized

🔧 Fixing Kotlin configuration...
  ✓ Kotlin version updated to 1.9.0
  ✓ Kotlin plugin configured

🔧 Fixing Java & SDK configuration...
  ✓ Java 17 is compatible with Gradle 8.3
  ✓ Java compile options fixed
  ✓ Android SDK versions updated

═══════════════════════════════════════════
📊 Summary
═══════════════════════════════════════════
✅ Fixed (7):
   • Gradle configuration
   • Kotlin configuration
   • Java & SDK configuration
   • Build cache cleaned
   • Dependencies fetched

✅ Project fixed successfully!
You can now run: flutter run
```

---

## 🧪 Compatibility Matrix

FlutterFix supports **176 Flutter stable versions** from v1.0.0 to 3.38.1. Below are the major version families:

| Flutter | Gradle | AGP | Kotlin | Java | Min SDK | Compile/Target SDK |
|---------|--------|-----|--------|------|---------|-------------------|
| 3.38.x | 8.11 | 8.7.3 | 2.1.0 | 17+ | 24 | 35 |
| 3.35.x | 8.10 | 8.7.2 | 2.0.21 | 17+ | 24 | 35 |
| 3.32.x | 8.10 | 8.7.1 | 2.0.20 | 17+ | 24 | 35 |
| 3.29.x | 8.9 | 8.7.0 | 2.0.10 | 17+ | 24 | 35 |
| 3.27.x | 8.9 | 8.6.0 | 2.0.0 | 17+ | 24 | 35 |
| 3.24.x | 8.7 | 8.5.0 | 2.0.10 | 17+ | 21 | 34 |
| 3.22.x | 8.5 | 8.3.0 | 1.9.24 | 17+ | 21 | 34 |
| 3.19.x | 8.3 | 8.1.4 | 1.9.0 | 17+ | 21 | 34 |
| 3.16.x | 8.3 | 8.1.4 | 1.9.0 | 17+ | 21 | 34 |
| 3.13.x | 7.6 | 7.4.2 | 1.8.22 | 17+ | 21 | 33 |
| 3.10.x | 7.4 | 7.2.0 | 1.7.0 | 11+ | 21 | 32 |
| 3.7.x | 7.3 | 7.1.0 | 1.6.10 | 11+ | 21 | 31 |
| 3.3.x | 7.2 | 7.0.0 | 1.6.0 | 11+ | 21 | 30 |
| 3.0.x | 7.0 | 4.2.0 | 1.5.31 | 11+ | 21 | 30 |
| 2.10.x | 6.9 | 4.1.0 | 1.5.10 | 11+ | 21 | 30 |
| 2.8.x | 6.7 | 4.1.0 | 1.5.0 | 11+ | 21 | 29 |
| 2.5.x | 6.5 | 4.0.1 | 1.4.32 | 11+ | 16 | 29 |
| 2.2.x | 6.3 | 3.6.4 | 1.4.0 | 11+ | 16 | 29 |
| 2.0.x | 6.3 | 3.6.4 | 1.4.0 | 11+ | 16 | 29 |

**All patch versions supported** (e.g., 3.7.0, 3.7.1, ..., 3.7.12, 3.24.0, ..., 3.24.5, etc.)

### Recent Compatibility Updates (Nov 2025)
- ✅ **Flutter 3.16.x**: Updated to AGP 8.1.4, Gradle 8.3, Kotlin 1.9.0 for Android 14 support
- ✅ **Flutter 3.19.x**: Upgraded from deprecated AGP 8.0.0 to 8.1.4 with compile_sdk 34
- ✅ **Flutter 3.22.x**: Enhanced with AGP 8.3.0, Kotlin 1.9.24 for better Kotlin 2.0 compatibility
- ✅ **Flutter 3.24.x**: Updated to Kotlin 2.0.10 for improved stability
- ✅ **Flutter 3.13.x**: Upgraded to AGP 7.4.2 for better reliability

All versions tested and verified with official Flutter/Android requirements.

---

## 🚀 CI/CD Integration

FlutterFix can be integrated into your CI/CD pipeline to automatically fix version conflicts.

### GitHub Actions

Add FlutterFix to your GitHub Actions workflow:

```yaml
name: Flutter CI

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
      
      - name: Install FlutterFix
        run: dart pub global activate flutterfix
      
      - name: Fix version conflicts
        run: flutterfix sync
      
      - name: Run tests
        run: flutter test
```

For more examples, see `examples/ci-cd/` directory.

### Benefits in CI/CD

- ✅ **Automatic version fixing** - No manual intervention needed
- ✅ **Consistent builds** - Same configuration across all environments
- ✅ **Catch issues early** - Detect conflicts before merging
- ✅ **Zero configuration** - Works out of the box
- ✅ **Fast execution** - Completes in seconds

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. 🍴 Fork the repository
2. 🔨 Create a feature branch (`git checkout -b feature/amazing-feature`)
3. 💾 Commit your changes (`git commit -m 'Add amazing feature'`)
4. 📤 Push to the branch (`git push origin feature/amazing-feature`)
5. 🎉 Open a Pull Request

### Development Setup

```bash
# Clone the repo
git clone https://github.com/haraprosad/flutterfix.git
cd flutterfix

# Install dependencies
dart pub get

# Run tests
dart test

# Activate locally
dart pub global activate --source path .
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Built with ❤️ for the Flutter community
- Inspired by countless hours debugging version conflicts
- Thanks to all contributors and users

---

## 📞 Support

- 📧 **Issues**: [GitHub Issues](https://github.com/haraprosad/flutterfix/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/haraprosad/flutterfix/discussions)
- 🐦 **Twitter**: [@haraprosad](https://twitter.com/haraprosad)

---

<div align="center">

**Made with 🔧 by developers, for developers**

[⭐ Star on GitHub](https://github.com/haraprosad/flutterfix) | [📦 View on pub.dev](https://pub.dev/packages/flutterfix)

</div>