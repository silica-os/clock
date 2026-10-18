// Clock's menus in Silica's menu bar (silica-desktop#175): the model the app publishes on
// `silica/menu`, the choices that come back and the ⌘ shortcuts.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silica_clock/src/app.dart';
import 'package:silica_clock/src/controller.dart';
import 'package:silica_clock/src/model/settings.dart';
import 'package:silica_clock/src/model/timers.dart';
import 'package:silica_clock/src/time/cities.dart';
import 'package:silica_clock/src/time/tzif.dart';
import 'package:silica_ui/silica_ui.dart' show SilicaMenuDelegate;

void main() {
  late List<MethodCall> calls;

  Future<ClockController> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    List<RecentTimer> recents = const [],
  }) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    calls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SilicaMenuDelegate.defaultChannel,
      (call) async {
        calls.add(call);
        return true;
      },
    );
    final controller = ClockController(
      settings: Settings(null)..recents = [...recents],
      zones: ZoneDatabase(),
      cities: const <City>[],
    );
    await tester.pumpWidget(ClockApp(controller: controller, locale: locale));
    await tester.pump();
    return controller;
  }

  Future<void> done(WidgetTester tester, ClockController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  List<Map<Object?, Object?>> menus() =>
      ((calls.lastWhere((c) => c.method == 'setMenus').arguments
                  as Map)['menus']
              as List)
          .cast<Map<Object?, Object?>>();

  List<Map<Object?, Object?>> items(String menu) =>
      (menus().firstWhere((m) => m['label'] == menu)['items'] as List)
          .cast<Map<Object?, Object?>>();

  Map<Object?, Object?> item(String menu, String label) =>
      items(menu).firstWhere((i) => i['label'] == label);

  Future<void> choose(WidgetTester tester, Object? id) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SilicaMenuDelegate.defaultChannel.name,
      const JSONMethodCodec().encodeMethodCall(MethodCall('activated', id)),
      (_) {},
    );
    await tester.pump();
  }

  testWidgets('the menus as measured: app, File, Edit, View, Window, Help', (
    tester,
  ) async {
    final c = await pump(tester);
    expect(menus().map((m) => m['label']), [
      'Clock',
      'File',
      'Edit',
      'View',
      // Window and Help are the standard ones (silica-ui#99): the bar gives their titles.
      '',
      '',
    ]);
    expect(menus().map((m) => m['role']).last, 'help');
    // The standard app menu: About enabled, no Settings… (Clock has none).
    final app = menus().first['items'] as List;
    expect(
      [for (final i in app.cast<Map<Object?, Object?>>()) i['role'] ?? '—'],
      [
        'about',
        '—',
        'services',
        '—',
        'hide',
        'hide_others',
        'show_all',
        '—',
        'quit',
      ],
    );
    expect((app.first as Map)['enabled'], isTrue);
    // File: the recent timers submenu (empty here), Close (system) and Close All (enabled, the Close All role).
    final recent = item('File', 'Start Recent Timer')['items'] as List;
    expect(recent.single, containsPair('enabled', false));
    expect(items('File').any((i) => i['role'] == 'close'), isTrue);
    expect(item('File', 'Close All')['enabled'], isTrue);
    // Edit: every item is there, disabled.
    final edit = items('Edit').where((i) => i['separator'] != true);
    expect(edit.map((i) => i['role']), [
      'undo',
      'redo',
      'cut',
      'copy',
      'paste',
      'delete',
      'select_all',
    ]);
    expect(edit.every((i) => i['enabled'] == false), isTrue);
    // View: the four sections with ⌘1–4, World checked; Digital Stopwatch checked.
    expect(item('View', 'World Clock')['checked'], isTrue);
    expect(item('View', 'Alarms')['shortcut'], {'key': '2', 'meta': true});
    expect(item('View', 'Stopwatch')['shortcut'], {'key': '3', 'meta': true});
    expect(item('View', 'Timers')['shortcut'], {'key': '4', 'meta': true});
    expect(item('View', 'Show Digital Stopwatch')['checked'], isTrue);
    expect(item('View', 'Show Digital Stopwatch')['enabled'], isTrue);
    expect(item('View', 'Show Analog Stopwatch')['enabled'], isTrue);
    expect(item('View', 'Show Analog Stopwatch')['checked'], isNull);
    await done(tester, c);
  });

  testWidgets('choosing a section in View, the checkmark follows', (
    tester,
  ) async {
    final c = await pump(tester);
    await choose(tester, item('View', 'Stopwatch')['id']);
    expect(c.section, Section.stopwatch);
    expect(item('View', 'Stopwatch')['checked'], isTrue);
    expect(item('View', 'World Clock')['checked'], isNull);
    await done(tester, c);
  });

  testWidgets('choosing the analog stopwatch is kept in the settings', (
    tester,
  ) async {
    final c = await pump(tester);
    await choose(tester, item('View', 'Show Analog Stopwatch')['id']);
    expect(c.analogStopwatch, isTrue);
    expect(c.settings.analogStopwatch, isTrue);
    expect(item('View', 'Show Analog Stopwatch')['checked'], isTrue);
    expect(item('View', 'Show Digital Stopwatch')['checked'], isNull);
    await done(tester, c);
  });

  testWidgets('⌘1–⌘4 switch the section', (tester) async {
    final c = await pump(tester);
    for (final (key, section) in [
      (LogicalKeyboardKey.digit4, Section.timers),
      (LogicalKeyboardKey.digit2, Section.alarms),
      (LogicalKeyboardKey.digit3, Section.stopwatch),
      (LogicalKeyboardKey.digit1, Section.world),
    ]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(c.section, section);
    }
    await done(tester, c);
  });

  testWidgets('Start Recent Timer lists the recents and starts one', (
    tester,
  ) async {
    final c = await pump(
      tester,
      recents: const [
        RecentTimer(Duration(minutes: 5), ''),
        RecentTimer(Duration(minutes: 10), 'Tea'),
      ],
    );
    final recent = (item('File', 'Start Recent Timer')['items'] as List)
        .cast<Map<Object?, Object?>>();
    expect(recent.map((i) => i['label']), ['05:00', '10:00 · Tea']);
    await choose(tester, recent[1]['id']);
    expect(c.section, Section.timers);
    expect(c.timers.single.timer.duration, const Duration(minutes: 10));
    expect(c.timers.single.timer.label, 'Tea');
    await done(tester, c);
  });

  testWidgets('Italian titles', (tester) async {
    final c = await pump(tester, locale: const Locale('it'));
    expect(menus().map((m) => m['label']), [
      'Orologio',
      'File',
      'Modifica',
      'Vista',
      '',
      '',
    ]);
    expect(item('Vista', 'Ore locali')['checked'], isTrue);
    expect(item('File', 'Chiudi tutto')['enabled'], isTrue);
    await done(tester, c);
  });
}
