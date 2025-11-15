# 🔧 FlutterFix

> **Make any Flutter project run instantly.**  
> Automatically fixes Flutter, Gradle, Kotlin, and Java version conflicts with a single command.

[![Pub Version](https://img.shields.io/pub/v/flutterfix?color=blue)](https://pub.dev/packages/flutterfix)
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

### Basic Usage

Navigate to your Flutter project and run:

```bash
flutterfix
```

That's it! The tool will:
1. 🔍 Analyze your project
2. 🔧 Fix version conflicts
3. 🧹 Clean build caches
4. ✅ Make your project ready to run

### Install Compatible Flutter Version

**Auto-install based on project requirements:**
```bash
flutterfix install
```

This will:
1. 🔍 Detect your project's Flutter version requirement
2. 📦 Install FVM (Flutter Version Management) if needed
3. ⬇️ Download and install the compatible Flutter version
4. 🔧 Configure your project to use the installed version

**List all available Flutter versions:**
```bash
flutterfix install --list
```

**Install a specific Flutter version:**
```bash
flutterfix install --version 3.24
```

**Show version compatibility information:**
```bash
flutterfix install --version 3.24 --info
```

### Common Use Cases

**Fix a specific project:**
```bash
flutterfix sync --path /path/to/flutter/project
```

**Install compatible Flutter version:**
```bash
flutterfix install
```

**List available Flutter versions:**
```bash
flutterfix install --list
```

**Install specific Flutter version:**
```bash
flutterfix install --version 3.24
```

**Diagnose without fixing:**
```bash
flutterfix doctor
```

**Rollback changes (restore from backup):**
```bash
flutterfix rollback
```

**List all backups:**
```bash
flutterfix rollback --list
```

**Restore latest backup:**
```bash
flutterfix rollback --latest
```

**Upgrade FlutterFix:**
```bash
flutterfix upgrade
```

**Get help:**
```bash
flutterfix --help
```

### Rollback & Backup System

FlutterFix automatically creates backups before modifying any files. You can easily restore previous versions:

**Undo last changes (interactive):**
```bash
flutterfix rollback
```

**List all backups:**
```bash
flutterfix rollback --list
```

**Restore most recent backup:**
```bash
flutterfix rollback --latest
```

**Restore specific backup by ID:**
```bash
flutterfix rollback --id <backup-id>
```

**Clear all backups:**
```bash
flutterfix rollback --clear
```

Backups are stored in `.flutterfix/backups/` directory within your project. Each backup includes:
- Original file path
- Timestamp
- Description of changes
- Unique backup ID

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🎯 **Smart Version Detection** | Automatically detects Flutter, Gradle, Kotlin, and Java versions |
| � **Flutter Auto-Install** | Installs compatible Flutter version using FVM or standalone |
| �🔄 **Compatibility Matrix** | Uses tested compatibility mappings for seamless fixes |
| 📝 **Auto-Configuration** | Updates `build.gradle`, `gradle-wrapper.properties`, and SDK settings |
| 🔙 **Automatic Backups** | Creates backups before making changes - rollback anytime |
| 🧹 **Cache Cleaning** | Removes stale build artifacts that cause issues |
| 📊 **Detailed Reports** | Shows what was fixed and what needs attention |
| 💡 **Zero Config** | Works out of the box with sensible defaults |

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
- Auto-installs compatible Flutter version
- Uses FVM (Flutter Version Management) for easy switching
- Supports standalone installations
- Lists available Flutter versions

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

| Flutter | Gradle | AGP | Kotlin | Java | Min SDK | Compile/Target SDK |
|---------|--------|-----|--------|------|---------|-------------------|
| 3.38.x | 8.9 | 8.7.0 | 2.0.20 | 17+ | 21 | 35 |
| 3.35.x | 8.8 | 8.6.0 | 2.0.10 | 17+ | 21 | 35 |
| 3.32.x | 8.7 | 8.5.0 | 2.0.0 | 17+ | 21 | 35 |
| 3.29.x | 8.6 | 8.4.0 | 1.9.24 | 17+ | 21 | 34 |
| 3.27.x | 8.5 | 8.3.0 | 1.9.22 | 17+ | 21 | 34 |
| 3.24.x | 8.3 | 8.1.0 | 1.9.0 | 17+ | 21 | 34 |
| 3.22.x | 8.0 | 8.0.0 | 1.8.22 | 17+ | 21 | 34 |
| 3.19.x | 7.6 | 7.4.0 | 1.8.0 | 17+ | 21 | 33 |
| 3.16.x | 7.5 | 7.3.0 | 1.7.10 | 11+ | 21 | 33 |
| 3.13.x | 7.4 | 7.2.0 | 1.7.0 | 11+ | 21 | 33 |
| 3.10.x | 7.3 | 7.1.0 | 1.6.10 | 11+ | 21 | 32 |
| 3.7.x | 7.2 | 7.0.0 | 1.6.0 | 11+ | 21 | 31 |
| 3.3.x | 6.7 | 4.1.0 | 1.5.31 | 11+ | 21 | 30 |

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