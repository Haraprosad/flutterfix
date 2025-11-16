import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final response = await http.get(
    Uri.parse('https://pub.dev/api/packages/http_parser'),
  );
  
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  final versions = data['versions'] as List<dynamic>;
  
  print('Checking all http_parser versions for Dart 3.5.4 compatibility...\n');
  
  for (final versionData in versions) {
    final version = versionData['version'] as String;
    final pubspec = versionData['pubspec'] as Map<String, dynamic>;
    final environment = pubspec['environment'] as Map<String, dynamic>?;
    final dependencies = pubspec['dependencies'] as Map<String, dynamic>?;
    
    final sdkConstraint = environment?['sdk'] as String?;
    final collectionDep = dependencies?['collection'] as String?;
    
    // Check if SDK constraint allows 3.5.4
    if (sdkConstraint != null) {
      if (sdkConstraint.contains('>=3.') || sdkConstraint.contains('^3.')) {
        // And doesn't require collection 1.19+
        if (collectionDep == null || 
            (!collectionDep.contains('1.19') && !collectionDep.contains('>=1.19'))) {
          print('✓ Version: $version');
          print('  SDK: $sdkConstraint');
          print('  collection: ${collectionDep ?? "none"}');
          print('');
        }
      }
    }
  }
}
