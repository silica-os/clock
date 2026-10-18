// Clock, the clock app of Silica: world clocks, alarms, stopwatch and timers.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:silica_ui/silica_ui.dart';

import 'src/app.dart';
import 'src/app_info.dart';
import 'src/controller.dart';
import 'src/model/settings.dart';
import 'src/style.dart';
import 'src/time/cities.dart';
import 'src/time/tzif.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // About Clock and the standard app menu (silica-ui#99).
  SilicaApp.info = appInfo;
  // The toolbar is unified with the window: Ossido draws only the window buttons.
  SilicaWindow.setFullSizeContent(AmalfiToolbarMetrics.toolbarHeight).ignore();
  // The smallest window that still shows every section (CL-13); no maximum.
  SilicaWindow.setSizeLimits(min: ClockMetrics.minWindow).ignore();
  // A single-window app: it quits with its window and comes back in the same place
  // (APP-LC; Ossido remembers where the window was).
  SilicaApp.quitWhenLastWindowCloses = true;
  final env = Platform.environment;
  final zones = ZoneDatabase();
  runApp(
    ClockApp(
      controller: ClockController(
        settings: Settings.forUser(env),
        zones: zones,
        cities: loadCities(directory: zones.directory),
      ),
    ),
  );
}
