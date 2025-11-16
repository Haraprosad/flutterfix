import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final response = await http.get(
    Uri.parse('https://pub.dev/api/packages/http_parser'),
  );
  
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  final versions = data['versions'] as List<dynamic>;
  
  // Check versions 4.0.x
  for (final versionData in versions) {
    final version = versionData['version'] as String;
    if (!version.startsWith('4.0')) continue;
    
    final pubspec = versionData['pubspec'] as Map<String, dynamic>;
    final environment = pubspec['environment'] as Map<String, dynamic>?;
    final dependencies = pubspec['dependencies'] as Map<String, dynamic>?;
    
    print('Version: $version');
    print('  SDK: ${environment?['sdk']}');
    print('  collection: ${dependencies?['collection']}');
    print('');
  }
}
