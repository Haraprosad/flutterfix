import 'package:test/test.dart';
import 'package:flutterfix/src/detect/ios_detector.dart';
import 'dart:io';

void main() {
  group('IosDetector', () {
    test('detectAll returns IosInfo', () async {
      final info = await IosDetector.detectAll();
      expect(info, isA<IosInfo>());
    });

    test(
        'getRecommendedDeploymentTarget returns correct version for Flutter 3.19+',
        () {
      expect(
          IosDetector.getRecommendedDeploymentTarget('3.19.0'), equals('12.0'));
      expect(
          IosDetector.getRecommendedDeploymentTarget('3.24.0'), equals('12.0'));
    });

    test(
        'getRecommendedDeploymentTarget returns correct version for Flutter 3.13-3.18',
        () {
      expect(
          IosDetector.getRecommendedDeploymentTarget('3.13.0'), equals('11.0'));
      expect(
          IosDetector.getRecommendedDeploymentTarget('3.16.0'), equals('11.0'));
    });

    test('isXcodeInstalled returns boolean', () async {
      final isInstalled = await IosDetector.isXcodeInstalled();
      expect(isInstalled, isA<bool>());

      if (!Platform.isMacOS) {
        expect(isInstalled, isFalse);
      }
    });
  });
}
