import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silica_ui/silica_ui.dart';
import 'package:silica_clock/src/model/sounds.dart';
import 'package:silica_clock/src/app.dart';
import 'package:silica_clock/src/controller.dart';
import 'package:silica_clock/src/model/alarms.dart';
import 'package:silica_clock/src/model/settings.dart';
import 'package:silica_clock/src/style.dart';
import 'package:silica_clock/src/system/notifier.dart';
import 'package:silica_clock/src/world_view.dart';
import 'package:silica_clock/src/widgets.dart';
import 'package:silica_clock/src/time/cities.dart';
import 'package:silica_clock/src/time/tzif.dart';

const rome = City(
  zone: 'Europe/Rome',
  name: 'Rome',
  country: 'Italy',
  latitude: 41.9,
  longitude: 12.48,
);
const tokyo = City(
  zone: 'Asia/Tokyo',
  name: 'Tokyo',
  country: 'Japan',
  latitude: 35.65,
  longitude: 139.74,
);

/// A ringer that only counts (no processes in tests).
class FakeRinger extends Ringer {
  int rings = 0;
  bool _on = false;
  @override
  bool get ringing => _on;
  @override
  void start({
    Duration limit = const Duration(minutes: 5),
    String sound = defaultSoundId,
  }) {
    rang.add(sound);
    rings++;
    _on = true;
  }

  final List<String> previews = [];
  final List<String> rang = [];
  @override
  void preview(String sound) => previews.add(sound);
  @override
  void stop() => _on = false;
}

void main() {
  dialTests();
  late List<MethodCall> dbus;

  setUp(() {
    dbus = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('silica/dbus', JSONMethodCodec()),
          (call) async {
            dbus.add(call);
            return call.method == 'subscribe'
                ? 1
                : call.method == 'unsubscribe'
                ? true
                : [7];
          },
        );
  });

  Future<ClockController> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = const Size(1024, 800),
    FakeRinger? ringer,
    bool fakeClock = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ClockController(
      settings: Settings(null),
      zones: ZoneDatabase(),
      cities: const [rome, tokyo],
      ringer: ringer ?? FakeRinger(),
      // The test clock: alarms and timers follow the fake time of `pump`.
      now: fakeClock ? () => tester.binding.clock.now().toLocal() : null,
      micros: fakeClock
          ? () => tester.binding.clock.now().microsecondsSinceEpoch
          : null,
    );
    await tester.pumpWidget(ClockApp(controller: controller, locale: locale));
    return controller;
  }

  /// Unmounts the app and stops its timers before the test ends.
  Future<void> done(WidgetTester tester, ClockController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
    'segmented control: kit Segmented Text piece, centred between spacers',
    (tester) async {
      final c = await pump(tester);
      final control = tester.getRect(
        find.byKey(const ValueKey('section control')),
      );
      // Kit `Apps/Clock/Toolbar`: the control is 360 × 36 at x 354, y 8 of the 52 pt bar.
      expect(control, const Rect.fromLTWH(354, 8, 360, 36));
      await tester.tap(find.text('Stopwatch'));
      // The content changes at once; the lens and the thumb settle through their springs.
      await tester.pump();
      expect(c.section, Section.stopwatch);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('section control')), findsOneWidget);
      // The stopwatch has no "+", and the control stays where it was.
      expect(
        tester.getRect(find.byKey(const ValueKey('section control'))),
        control,
      );
      await done(tester, c);
    },
  );

  testWidgets('analog stopwatch: dial at 142, 360 pt, laps table at 562', (
    tester,
  ) async {
    final c = await pump(tester);
    c.analogStopwatch = true;
    c.select(Section.stopwatch);
    await tester.pump();
    final dial = tester.getRect(find.byKey(const ValueKey('analog dial')));
    expect(dial.left, 142);
    expect(dial.top, 192);
    expect(dial.size, const Size(360, 360));
    expect(find.text('00:00.00'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    await done(tester, c);
  });

  testWidgets('stopwatch: digits, start and laps, Italian comma', (
    tester,
  ) async {
    final c = await pump(tester, locale: const Locale('it'));
    c.select(Section.stopwatch);
    await tester.pump();
    expect(find.text('00:00,00'), findsOneWidget);
    expect(find.text('Cronometro'), findsOneWidget);
    final buttons = [
      tester.getRect(find.byKey(const ValueKey('lap reset'))),
      tester.getRect(find.byKey(const ValueKey('start stop'))),
    ];
    // Kit `Stopwatch`: Lap and Start are 68 × 28, 96 apart, 68 pt above the window's bottom.
    expect(buttons[0].size, const Size(68, 28));
    expect(buttons[1].size, const Size(68, 28));
    expect(buttons[1].left - buttons[0].right, 96);
    expect(buttons[1].top, 704);
    expect(buttons[0].center.dx + buttons[1].center.dx, 1024);
    await tester.tap(find.text('Avvia'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Ferma'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lap reset')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('lap 0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start stop')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lap reset')));
    await tester.pump();
    expect(find.text('00:00,00'), findsOneWidget);
    await done(tester, c);
  });

  testWidgets('alarms: empty state, editor, card and switch', (tester) async {
    final c = await pump(tester);
    c.select(Section.alarms);
    await tester.pump();
    expect(find.text('No alarms'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add')));
    await tester.pump();
    expect(find.text('New alarm'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('day 6')));
    await tester.tap(find.byKey(const ValueKey('day 7')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save')));
    await tester.pump();
    expect(c.alarms, hasLength(1));
    expect(c.alarms.single.repeat, {6, 7});
    final card = tester.getSize(
      find.byKey(ValueKey('alarm ${c.alarms.single.id}')),
    );
    expect(card, const Size(184, 180));
    // The grid starts at the left margin, whatever the window width (#7).
    expect(
      tester.getTopLeft(find.byKey(ValueKey('alarm ${c.alarms.single.id}'))).dx,
      ClockMetrics.cardsMargin,
    );
    // Kit `Alarm Card On`: the switch (40 × 24) at 128, 136 of the 184 × 180 card.
    final cardRect = tester.getRect(
      find.byKey(ValueKey('alarm ${c.alarms.single.id}')),
    );
    final switchRect = tester.getRect(
      find.byKey(ValueKey('switch ${c.alarms.single.id}')),
    );
    expect(switchRect.size, const Size(40, 24));
    expect(switchRect.topLeft - cardRect.topLeft, const Offset(128, 136));
    expect(find.text('Weekends'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('switch ${c.alarms.single.id}')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.alarms.single.enabled, isFalse);
    await done(tester, c);
  });

  testWidgets(
    'timers: picker, running ring and list; the section control does not move',
    (tester) async {
      final ringer = FakeRinger();
      final c = await pump(tester, ringer: ringer);
      c.select(Section.timers);
      await tester.pump();
      expect(find.text('15'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('timer start')));
      await tester.pump();
      expect(c.timers, hasLength(1));
      expect(
        tester.getSize(find.byKey(const ValueKey('timer ring'))),
        const Size(360, 360),
      );
      final control = tester.getRect(
        find.byKey(const ValueKey('section control')),
      );
      // Kit: the toolbar is the same with or without the list.
      expect(control, const Rect.fromLTWH(354, 8, 360, 36));
      // The ring centres on the area right of the 320 pt list.
      expect(
        tester.getCenter(find.byKey(const ValueKey('timer ring'))).dx,
        closeTo(672, 0.5),
      );
      await tester.tap(find.byKey(const ValueKey('timer cancel')));
      await tester.pump();
      expect(c.timers, isEmpty);
      // A timer that ends rings and notifies.
      c.startTimer(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      c.check();
      await tester.pump(const Duration(milliseconds: 300));
      expect(ringer.rings, 1);
      expect(dbus.where((m) => m.method == 'call'), isNotEmpty);
      await done(tester, c);
    },
  );

  testWidgets('at the minimum width the section control still fits', (
    tester,
  ) async {
    final c = await pump(tester, size: const Size(690, 640));
    c.startTimer(const Duration(minutes: 5));
    await tester.pump();
    final control = tester.getRect(
      find.byKey(const ValueKey('section control')),
    );
    // Between the 96 pt window-button slot and the 44 pt "+" piece.
    expect(control.left, greaterThanOrEqualTo(100));
    expect(control.right, lessThanOrEqualTo(690 - 8 - 44));
    await done(tester, c);
  });

  testWidgets(
    'world: add a city from the sheet; a single card is one 184 × 220 slot',
    (tester) async {
      final c = await pump(tester);
      expect(c.section, Section.world);
      await tester.tap(find.byKey(const ValueKey('add')));
      await tester.pump();
      expect(find.text('Add a City'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'tok');
      await tester.pump();
      expect(find.text('Rome, Italy'), findsNothing);
      await tester.tap(find.text('Tokyo, Japan'));
      await tester.pump();
      expect(c.settings.cities, ['Asia/Tokyo']);
      expect(
        tester.getSize(find.byKey(const ValueKey('card Asia/Tokyo'))),
        const Size(184, 220),
      );
      await done(tester, c);
    },
  );

  Iterable<MethodCall> notifies() => dbus.where(
    (m) => m.method == 'call' && (m.arguments as Map)['method'] == 'Notify',
  );

  Color fillOf(WidgetTester tester, Key key) {
    final box = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(DecoratedBox),
          ),
        )
        .firstWhere((b) => b.decoration is ShapeDecoration);
    return (box.decoration as ShapeDecoration).color!;
  }

  testWidgets('capsules take the pressed fill at once (CL-02)', (tester) async {
    expect(pressedFill(clockPalette.start), const Color(0xFF4CD669));
    expect(pressedFill(clockPalette.stop), const Color(0xFFFF5858));
    expect(pressedFill(clockPalette.lapButton), const Color(0xFF434343));
    final c = await pump(tester);
    c.select(Section.stopwatch);
    await tester.pump();
    const start = ValueKey('start stop');
    expect(fillOf(tester, start), clockPalette.start);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(start)),
    );
    await tester.pump();
    expect(fillOf(tester, start), const Color(0xFF4CD669));
    // The action fires on release.
    expect(c.stopwatch.running, isFalse);
    await gesture.up();
    await tester.pump();
    expect(c.stopwatch.running, isTrue);
    await done(tester, c);
  });

  testWidgets(
    'the toolbar "+" acts on release, like silica_ui\'s toolbar buttons',
    (tester) async {
      final c = await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('add'))),
      );
      await tester.pump();
      expect(find.text('Add a City'), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(find.text('Add a City'), findsOneWidget);
      await done(tester, c);
    },
  );

  // A choice closes the pop-up menu 150 ms later with a 190 ms fade (silica_ui, measured):
  // the delay, then the frames of the fade.
  Future<void> menuClosed(WidgetTester tester) async {
    await tester.pump(AmalfiPopUpMenuMetrics.chooseFadeDelay);
    await tester.pump(AmalfiPopUpMenuMetrics.fadeOut);
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('the Sound pop-ups choose, preview and keep the sound', (
    tester,
  ) async {
    final ringer = FakeRinger();
    final c = await pump(tester, ringer: ringer);
    c.select(Section.alarms);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('alarm sound')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Bell').last);
    await menuClosed(tester);
    expect(ringer.previews, ['bell']);
    await tester.tap(find.byKey(const ValueKey('save')));
    await tester.pump();
    expect(c.alarms.single.sound, 'bell');
    expect(find.text('Bell'), findsOneWidget);
    c.select(Section.timers);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('timer sound')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Complete').last);
    await menuClosed(tester);
    expect(ringer.previews, ['bell', 'complete']);
    await tester.tap(find.byKey(const ValueKey('timer start')));
    await tester.pump();
    expect(c.currentTimer!.timer.sound, 'complete');
    expect(c.settings.recents.first.sound, 'complete');
    await tester.tap(find.byKey(const ValueKey('timer running sound')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Ring').last);
    await menuClosed(tester);
    expect(c.currentTimer!.timer.sound, 'phone-incoming-call');
    await done(tester, c);
  });

  testWidgets('an alarm rings on time: switch, banner after 227 ms, sound '
      'after 389 ms; Snooze rings again after the snooze length', (
    tester,
  ) async {
    final ringer = FakeRinger();
    final c = await pump(tester, ringer: ringer, fakeClock: true);
    final now = tester.binding.clock.now().toLocal();
    final at = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    c.saveAlarm(
      Alarm(id: 1, hour: at.hour, minute: at.minute, snoozeMinutes: 1),
    );
    await tester.pump(at.difference(now));
    // One-off: the switch goes off as it rings.
    expect(c.alarms.single.enabled, isFalse);
    await tester.pump(const Duration(milliseconds: 226));
    expect(notifies(), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    final notify = notifies().single.arguments as Map;
    expect((notify['args'] as List)[3], 'Clock');
    expect((notify['args'] as List)[4], 'Alarm');
    expect((notify['args'] as List)[5], ['stop', 'Stop', 'snooze', 'Snooze']);
    await tester.pump(const Duration(milliseconds: 161));
    expect(ringer.rings, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(ringer.rings, 1);

    // Snooze from the banner: the sound stops, the switch turns back on.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'silica/dbus',
      const JSONMethodCodec().encodeMethodCall(
        const MethodCall('signal', {
          'id': 1,
          'member': 'ActionInvoked',
          'args': [7, 'snooze'],
        }),
      ),
      (_) {},
    );
    await tester.pump();
    expect(ringer.ringing, isFalse);
    expect(c.alarms.single.enabled, isTrue);
    await tester.pump(
      const Duration(seconds: 60) - const Duration(milliseconds: 1),
    );
    expect(notifies(), hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(c.alarms.single.enabled, isFalse);
    await tester.pump(const Duration(milliseconds: 389));
    expect(notifies(), hasLength(2));
    expect(ringer.rings, 2);
    await done(tester, c);
  });

  testWidgets('a timer ends: back to the picker, banner after 147 ms, sound '
      'after 290 ms, Restart runs it again', (tester) async {
    final ringer = FakeRinger();
    final c = await pump(tester, ringer: ringer, fakeClock: true);
    c.select(Section.timers);
    c.startTimer(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(c.timers, isEmpty);
    await tester.pump(const Duration(milliseconds: 146));
    expect(notifies(), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect((notifies().single.arguments as Map)['args'][5], [
      'stop',
      'Stop',
      'repeat',
      'Restart',
    ]);
    await tester.pump(const Duration(milliseconds: 142));
    expect(ringer.rings, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(ringer.rings, 1);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'silica/dbus',
      const JSONMethodCodec().encodeMethodCall(
        const MethodCall('signal', {
          'id': 1,
          'member': 'ActionInvoked',
          'args': [7, 'repeat'],
        }),
      ),
      (_) {},
    );
    await tester.pump();
    expect(ringer.ringing, isFalse);
    expect(c.timers.single.timer.duration, const Duration(seconds: 5));
    expect(
      dbus.where(
        (m) => (m.arguments as Map?)?['method'] == 'CloseNotification',
      ),
      hasLength(1),
    );
    await done(tester, c);
  });

  testWidgets(
    'the toolbar "+" is the silica_ui toolbar button, 36 pt at x 972 (#2)',
    (tester) async {
      final c = await pump(tester);
      expect(
        tester.widget(find.byKey(const ValueKey('add'))),
        isA<AmalfiToolbarButton>(),
      );
      // Kit `Toolbar`: the `Add` piece is 968 + 48, its 36 pt button 4 pt inside, centred.
      expect(
        tester.getRect(find.byKey(const ValueKey('add'))),
        const Rect.fromLTWH(972, 8, 36, 36),
      );
      await done(tester, c);
    },
  );

  test('the hands sweep continuously (#3, CLOCK-HANDS)', () {
    final t = DateTime(2026, 1, 1, 3, 20, 7, 0);
    final p0 = HandMotion.position(t, Duration.zero);
    expect(p0, 3 * 3600 + 20 * 60 + 7);
    // One redraw (72 ms) moves the second hand by ~0.43 degrees, no snap, no overshoot.
    final p1 = HandMotion.position(t, HandMotion.redraw);
    expect((p1 - p0) * 6, closeTo(0.432, 1e-9));
    expect(HandMotion.position(t, const Duration(seconds: 1)) - p0, 1);
    // Wraps at 12 hours.
    expect(
      HandMotion.position(
        DateTime(2026, 1, 1, 11, 59, 59),
        const Duration(seconds: 2),
      ),
      1,
    );
  });

  testWidgets(
    'the face redraws every 72 ms and the hands move between seconds',
    (tester) async {
      var t = DateTime(2026, 1, 1, 3, 20, 7);
      final start = t;
      final painters = <ClockFacePainter>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.square(
            dimension: 120,
            child: AnalogFace(
              time: start,
              day: true,
              now: start,
              clock: () => t,
            ),
          ),
        ),
      );
      CustomPaint paint() =>
          tester.widget<CustomPaint>(find.byKey(const ValueKey('hands')));
      painters.add(paint().painter! as ClockFacePainter);
      t = t.add(const Duration(milliseconds: 100));
      await tester.pump(HandMotion.redraw);
      painters.add(paint().painter! as ClockFacePainter);
      expect(painters[1].seconds - painters[0].seconds, closeTo(0.1, 1e-9));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a redraw of the hands repaints neither the dial nor the map (#202)',
    (tester) async {
      var t = DateTime(2026, 1, 1, 3, 20, 7);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.square(
            dimension: 120,
            child: AnalogFace(time: t, day: true, now: t, clock: () => t),
          ),
        ),
      );
      final hands = tester.renderObject(find.byKey(const ValueKey('hands')));
      final dial = tester.renderObject<RenderCustomPaint>(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is AnalogDialPainter,
        ),
      );
      // The dial sits in its own layer, the hands in the face's: neither is the card's.
      expect(dial.parent, isA<RenderRepaintBoundary>());
      RenderObject? boundary = hands.parent;
      while (boundary != null && !boundary.isRepaintBoundary) {
        boundary = boundary.parent;
      }
      final face = tester.renderObject(
        find
            .descendant(
              of: find.byType(AnalogFace),
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      expect(boundary, same(face));
      t = t.add(HandMotion.redraw);
      await tester.pump(HandMotion.redraw);
      expect(dial.debugNeedsPaint, isFalse);
      expect(
        AnalogDialPainter(
          day: true,
        ).shouldRepaint(AnalogDialPainter(day: true)),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('the map repaints when its time step, pins or land change (#202)', () {
    final t = DateTime.utc(2026, 1, 1, 3, 20, 7, 500);
    expect(WorldMapPainter.step(t), DateTime.utc(2026, 1, 1, 3, 20));
    expect(
      WorldMapPainter.step(t.add(const Duration(seconds: 2))),
      WorldMapPainter.step(t),
    );
    // The view rebuilds at the next step: 2.5 s after 03:20:07.5, and a full step at a boundary.
    expect(
      WorldMapPainter.untilNextStep(t),
      const Duration(milliseconds: 2500),
    );
    expect(
      WorldMapPainter.untilNextStep(DateTime.utc(2026, 1, 1, 3, 20, 10)),
      WorldMapPainter.timeStep,
    );
    WorldMapPainter map(DateTime now, String time) =>
        WorldMapPainter(now: WorldMapPainter.step(now), pins: [(rome, time)]);
    final first = map(t, '04:20');
    expect(
      map(t.add(const Duration(seconds: 1)), '04:20').shouldRepaint(first),
      isFalse,
    );
    expect(
      map(t.add(const Duration(seconds: 10)), '04:20').shouldRepaint(first),
      isTrue,
    );
    expect(map(t, '04:21').shouldRepaint(first), isTrue);
    expect(
      WorldMapPainter(
        now: first.now,
        pins: first.pins,
        land: [Float32List(2)],
      ).shouldRepaint(first),
      isTrue,
    );
  });

  testWidgets('at rest the stopwatch and the timers ask for no frames (#202)', (
    tester,
  ) async {
    final c = await pump(tester);
    for (final section in [Section.stopwatch, Section.timers]) {
      c.select(section);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse, reason: '$section');
    }
    c.select(Section.stopwatch);
    await tester.pumpAndSettle();
    c.stopwatchStartStop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
    c.stopwatchStartStop();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await done(tester, c);
  });

  test('card grid: 20 pt margins, 16 pt gaps, cards of at least 160 pt', () {
    // Window width -> (cards per row, card width).
    const expected = {
      1400: (7, 180.57),
      1024: (5, 184.0),
      900: (4, 203.0),
      800: (4, 178.0),
      690: (3, 206.0),
    };
    expected.forEach((width, e) {
      final grid = CardGrid.of(width.toDouble());
      expect(grid.columns, e.$1, reason: '$width');
      expect(grid.cardWidth, closeTo(e.$2, 0.01), reason: '$width');
      expect(grid.cardWidth, greaterThanOrEqualTo(160));
    });
  });

  testWidgets(
    'world: the map takes the full width and the content scrolls (#4)',
    (tester) async {
      final c = await pump(tester);
      expect(c.section, Section.world);
      final map = find.byKey(const ValueKey('world map'));
      // Kit `World`: the map is 1024 × 480 at 0, 52; the cards start 16 pt below it.
      expect(tester.getSize(map), const Size(1024, 480));
      expect(tester.getTopLeft(map), const Offset(0, 52));
      await done(tester, c);

      final small = await pump(tester, size: const Size(700, 600));
      small.settings.cities = ['Asia/Tokyo', 'Europe/Rome'];
      small.notifyListeners();
      await tester.pump();
      expect(
        tester.getSize(find.byType(WorldCard).first),
        const Size(628 / 3, 220),
      );
      expect(
        tester.getSize(map),
        const Size(700, 700 * ClockMetrics.worldMapRatio),
      );
      final top = tester.getTopLeft(map);
      // Scrolling is vertical and moves the map and the cards together.
      final card = tester.getTopLeft(find.byType(WorldCard).first);
      await tester.drag(
        find.byKey(const ValueKey('world scroll')),
        const Offset(0, -30),
      );
      await tester.pump();
      expect(
        tester.getSize(map),
        const Size(700, 700 * ClockMetrics.worldMapRatio),
      );
      expect(tester.getTopLeft(map).dy, top.dy - 30);
      expect(tester.getTopLeft(find.byType(WorldCard).first).dy, card.dy - 30);
      expect(tester.getTopLeft(map).dx, 0);
      await done(tester, small);
    },
  );

  testWidgets(
    'always dark: the library resolves dark in a light system and Ossido is told',
    (tester) async {
      final window = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SilicaWindow.channel, (call) async {
            window.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SilicaWindow.channel, null),
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final c = await pump(tester);
      final context = tester.element(find.byType(ClockWindow));
      expect(MediaQuery.platformBrightnessOf(context), Brightness.dark);
      expect(SilicaAppearance.isDark(context), isTrue);
      final theme = AmalfiTheme.of(context);
      expect(theme.brightness, Brightness.dark);
      expect(theme.appColors, same(AmalfiClockColors.dark));
      expect(
        window
            .where((call) => call.method == 'setAppearance')
            .map((call) => call.arguments),
        [
          {'appearance': 'dark'},
        ],
      );
      await done(tester, c);
    },
  );
}

void dialTests() {
  test('the day face has dark ink, the night face white', () {
    expect(ClockFace.dayInk.computeLuminance(), lessThan(0.2));
    expect(ClockFace.nightInk, const Color(0xFFFFFFFF));
    expect(
      ClockFace.dayInk.computeLuminance(),
      isNot(closeTo(ClockFace.dayFace.computeLuminance(), 0.5)),
    );
  });
}
