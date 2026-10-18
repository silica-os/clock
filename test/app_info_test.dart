import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silica_clock/src/app_info.dart';

void main() {
  test(
    'the About panel names the app and shows the version of pubspec.yaml',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*([^\s+]+)',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1);
      expect(appInfo.version, version);
      expect(appInfo.name, 'Clock');
    },
  );
}
