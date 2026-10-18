// The screens against the masters of the Amalfi kit (silica-design `App · Clock`, masters
// `Apps/Clock/*`): frames in whole points, from the JSON of each master. The window of the kit
// is 1024 × 800 with the 52 pt toolbar, and so is the window here. Where the kit's frame is
// not what the app can do (the large numerals are positioned by the centre of their figures;
// the text frames are fixed boxes) the test names the deviation.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silica_clock/src/model/sounds.dart';
import 'package:silica_clock/src/alarms_view.dart';
import 'package:silica_clock/src/app.dart';
import 'package:silica_clock/src/controller.dart';
import 'package:silica_clock/src/model/alarms.dart';
import 'package:silica_clock/src/model/settings.dart';
import 'package:silica_clock/src/model/timers.dart';
import 'package:silica_clock/src/style.dart';
import 'package:silica_clock/src/system/notifier.dart';
import 'package:silica_clock/src/time/cities.dart';
import 'package:silica_clock/src/time/tzif.dart';
import 'package:silica_clock/src/widgets.dart';
import 'package:silica_clock/src/world_view.dart';
import 'package:silica_ui/silica_ui.dart';

class _Silent extends Ringer {
  @override
  void start({
    Duration limit = const Duration(minutes: 5),
    String sound = defaultSoundId,
  }) {}
  @override
  void preview(String sound) {}
  @override
  void stop() {}
}

const _cities = [
  City(
    zone: 'Europe/Rome',
    name: 'Rome',
    country: 'Italy',
    latitude: 41.9,
    longitude: 12.48,
  ),
  City(
    zone: 'America/New_York',
    name: 'New York',
    country: 'United States',
    latitude: 40.71,
    longitude: -74.0,
  ),
  City(
    zone: 'Asia/Tokyo',
    name: 'Tokyo',
    country: 'Japan',
    latitude: 35.65,
    longitude: 139.74,
  ),
  City(
    zone: 'Australia/Sydney',
    name: 'Sydney',
    country: 'Australia',
    latitude: -33.87,
    longitude: 151.21,
  ),
  City(
    zone: 'Europe/London',
    name: 'London',
    country: 'United Kingdom',
    latitude: 51.5,
    longitude: -0.12,
  ),
];

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('silica/dbus', JSONMethodCodec()),
          (call) async => call.method == 'subscribe'
              ? 1
              : call.method == 'unsubscribe'
              ? true
              : [7],
        );
  });

  Future<ClockController> pump(
    WidgetTester tester,
    Section section, {
    void Function(ClockController c)? setup,
  }) async {
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ClockController(
      settings: Settings(null),
      zones: ZoneDatabase(),
      cities: _cities,
      ringer: _Silent(),
    );
    c.settings.cities = [for (final city in _cities) city.zone];
    setup?.call(c);
    c.select(section);
    // The kit shows 24-hour times.
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(alwaysUse24HourFormat: true),
        child: ClockApp(controller: c, locale: const Locale('en')),
      ),
    );
    await tester.pump();
    return c;
  }

  Future<void> done(WidgetTester tester, ClockController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  Rect rectOf(WidgetTester tester, Finder f) => tester.getRect(f);

  /// The 1 pt separators (`Line/Separator` boxes) on screen.
  List<Rect> separators(WidgetTester tester) {
    final colors = AmalfiColors.dark;
    return [
      for (final e in find.byType(ColoredBox).evaluate())
        if ((e.widget as ColoredBox).color == colors.lineSeparator)
          tester.getRect(find.byWidget(e.widget)),
    ];
  }

  testWidgets('Toolbar: controls slot, section control, add piece', (
    tester,
  ) async {
    final c = await pump(tester, Section.world);
    // Apps/Clock/Toolbar: Controls 4,0 96×52; Segmented Text 350,0 368×52 with the 360×36
    // control at +4,+8; Add 968,0 48×52 with the 36×36 button at +4,+8; 52 tall.
    expect(tester.getSize(find.byType(AmalfiToolbar)), const Size(1024, 52));
    expect(
      rectOf(tester, find.byKey(const ValueKey('section control'))),
      const Rect.fromLTWH(354, 8, 360, 36),
    );
    expect(
      rectOf(tester, find.byKey(const ValueKey('add'))),
      const Rect.fromLTWH(972, 8, 36, 36),
    );
    await done(tester, c);
  });

  // Masters `Apps/Clock/Toolbar` (World), `Toolbar Alarms|Stopwatch|Timers` and `Tabs ...`: the
  // same 360 x 36 control with four 88 pt segments (the track 4 pt inside), the selected one
  // being 0 World, 1 Alarms, 2 Stopwatch, 3 Timers (kit segments 1..4 filled in turn).
  for (final (section, index) in [
    (Section.world, 0),
    (Section.alarms, 1),
    (Section.stopwatch, 2),
    (Section.timers, 3),
  ]) {
    testWidgets('Toolbar ${section.name}: segment ${index + 1} selected', (
      tester,
    ) async {
      final c = await pump(tester, section);
      expect(
        rectOf(tester, find.byKey(const ValueKey('section control'))),
        const Rect.fromLTWH(354, 8, 360, 36),
      );
      final control = tester.widget<AmalfiSegmentedControl>(
        find.byType(AmalfiSegmentedControl),
      );
      expect(control.selected, {index});
      expect(control.segments, hasLength(4));
      await done(tester, c);
    });
  }

  testWidgets('World: map, pins and the five city cards', (tester) async {
    final c = await pump(tester, Section.world);
    // Apps/Clock/World: Map 0,52 1024×480; cards 184×220 at x 20 + 200 i, y 548.
    expect(
      rectOf(tester, find.byKey(const ValueKey('world map'))),
      const Rect.fromLTWH(0, 52, 1024, 480),
    );
    for (var i = 0; i < 5; i++) {
      expect(
        rectOf(tester, find.byType(WorldCard).at(i)),
        Rect.fromLTWH(20 + 200.0 * i, 548, 184, 220),
        reason: 'card $i',
      );
    }
    // The pins: the kit's 8 pt dots (centres 548,176 Rome; 304,180 New York; 908,192 Tokyo;
    // 944,388 Sydney; 512,148 London) are placed by eye, the map projects the coordinates:
    // within 4 pt.
    const size = Size(1024, 480);
    const centres = {
      'Rome': Offset(548, 176),
      'New York': Offset(304, 180),
      'Tokyo': Offset(908, 192),
      'Sydney': Offset(944, 388),
      'London': Offset(512, 148),
    };
    for (final city in _cities) {
      final p =
          WorldMapPainter.project(city.latitude, city.longitude, size) +
          const Offset(0, 52);
      expect(
        (p - centres[city.name]!).distance,
        lessThan(5),
        reason: city.name,
      );
    }
    // Card contents (Apps/Clock/City Card Day): face 32,20 120×120; city 0,152 184×18;
    // offset 0,172 184×16; sun 0,192 184×14.
    final card = rectOf(tester, find.byType(WorldCard).first);
    final face = rectOf(
      tester,
      find
          .descendant(
            of: find.byType(WorldCard).first,
            matching: find.byType(AnalogFace),
          )
          .first,
    );
    expect(face, Rect.fromLTWH(card.left + 32, card.top + 20, 120, 120));
    final city = rectOf(
      tester,
      find.descendant(
        of: find.byType(WorldCard).first,
        matching: find.textContaining('Rome, '),
      ),
    );
    expect(city.top - card.top, 152);
    expect(city.height, 18);
    final sun = rectOf(
      tester,
      find.descendant(
        of: find.byType(WorldCard).first,
        matching: find.textContaining('Rise '),
      ),
    );
    expect(sun.top - card.top, 192);
    expect(sun.height, 14);
    await done(tester, c);
  });

  testWidgets('Alarms: five 184 × 180 cards with the switch at 128, 136', (
    tester,
  ) async {
    final c = await pump(
      tester,
      Section.alarms,
      setup: (c) {
        final data = [
          (7, 30, 'Wake up', {1, 2, 3, 4, 5}, true),
          (8, 15, 'Gym', {2, 4}, false),
          (22, 30, 'Sleep', {1, 2, 3, 4, 5, 6, 7}, true),
          (9, 0, 'Weekend', {6, 7}, false),
          (6, 45, 'Flight', <int>{}, true),
        ];
        for (var i = 0; i < data.length; i++) {
          c.settings.alarms.add(
            Alarm(
              id: i + 1,
              hour: data[i].$1,
              minute: data[i].$2,
              label: data[i].$3,
              repeat: data[i].$4,
              enabled: data[i].$5,
            ),
          );
        }
      },
    );
    for (var i = 0; i < 5; i++) {
      final card = rectOf(tester, find.byKey(ValueKey('alarm ${i + 1}')));
      expect(card, Rect.fromLTWH(20 + 200.0 * i, 72, 184, 180));
      final sw = rectOf(tester, find.byKey(ValueKey('switch ${i + 1}')));
      expect(sw, Rect.fromLTWH(card.left + 128, card.top + 136, 40, 24));
    }
    // Apps/Clock/Alarm Card On: Time 16,16 152×40; Label 16,72 152×18; Repeat 16,96 152×16;
    // Sound 16,116 152×16 (the kit's is 100 wide).
    final card = rectOf(tester, find.byKey(const ValueKey('alarm 1')));
    expect(
      rectOf(tester, find.text('07:30')),
      Rect.fromLTWH(card.left + 16, card.top + 16, 152, 40),
    );
    expect(
      rectOf(tester, find.text('Wake up')),
      Rect.fromLTWH(card.left + 16, card.top + 72, 152, 18),
    );
    expect(
      rectOf(tester, find.text('Weekdays')),
      Rect.fromLTWH(card.left + 16, card.top + 96, 152, 16),
    );
    expect(
      rectOf(tester, find.text('Default').first),
      Rect.fromLTWH(card.left + 16, card.top + 116, 152, 16),
    );
    // An off alarm dims every text (Alarm Card Off: Text/Tertiary).
    final colors = AmalfiColors.dark;
    Color ink(String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;
    expect(ink('07:30'), colors.textPrimary);
    expect(ink('08:15'), colors.textTertiary);
    expect(ink('Gym'), colors.textTertiary);
    await done(tester, c);
  });

  testWidgets('Alarms Empty: symbol 496,352 32×32, title at 400', (
    tester,
  ) async {
    final c = await pump(tester, Section.alarms);
    expect(
      rectOf(tester, find.byType(ClockGlyph)),
      const Rect.fromLTWH(496, 352, 32, 32),
    );
    final title = rectOf(tester, find.text('No alarms'));
    expect(title.top, 400);
    expect(title.height, 26);
    expect(title.center.dx, 512);
    await done(tester, c);
  });

  testWidgets('Alarm Editor: sheet 256,204 512×392 and its controls', (
    tester,
  ) async {
    final c = await pump(tester, Section.alarms);
    await tester.tap(find.byKey(const ValueKey('add')));
    await tester.pump();
    await tester.pump();
    final editor = tester.getRect(find.byType(AlarmEditor));
    // The scrim covers the whole window, toolbar included.
    expect(editor, const Rect.fromLTWH(0, 0, 1024, 800));
    final sheet = Rect.fromLTWH(256, 204, 512, 392);
    Rect local(Finder f) => tester.getRect(f).shift(-sheet.topLeft);
    expect(
      tester.getRect(
        find
            .descendant(
              of: find.byType(AlarmEditor),
              matching: find.byType(DecoratedBox),
            )
            .first,
      ),
      sheet,
    );
    expect(local(find.text('New alarm')), const Rect.fromLTWH(24, 20, 464, 22));
    expect(
      local(find.byKey(const ValueKey('hour part'))),
      const Rect.fromLTWH(168, 64, 80, 64),
    );
    expect(
      local(find.byKey(const ValueKey('minute part'))),
      const Rect.fromLTWH(268, 64, 80, 64),
    );
    for (var d = 1; d <= 7; d++) {
      expect(
        local(find.byKey(ValueKey('day $d'))),
        Rect.fromLTWH(132 + (d - 1) * 40.0, 144, 32, 32),
      );
    }
    expect(
      local(find.byKey(const ValueKey('alarm label'))),
      const Rect.fromLTWH(132, 192, 224, 28),
    );
    expect(
      local(find.byKey(const ValueKey('alarm sound'))),
      const Rect.fromLTWH(132, 232, 224, 28),
    );
    expect(
      local(find.byKey(const ValueKey('snooze length'))),
      const Rect.fromLTWH(132, 304, 108, 28),
    );
    expect(
      local(find.byKey(const ValueKey('cancel'))),
      const Rect.fromLTWH(352, 348, 72, 28),
    );
    expect(
      local(find.byKey(const ValueKey('save'))),
      const Rect.fromLTWH(432, 348, 68, 28),
    );
    // The snooze checkbox starts at 132, 272 and is 20 tall.
    final snooze = local(find.byKey(const ValueKey('snooze')));
    expect(snooze.topLeft, const Offset(132, 272));
    expect(snooze.height, 20);
    // The focused hour is the accent, the minute `Surface/Sunken` (Hour field, Minute field).
    Color fill(Key key) =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byKey(key),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as ShapeDecoration)
            .color!;
    expect(fill(const ValueKey('hour part')), clockPalette.accent);
    expect(
      fill(const ValueKey('minute part')),
      AmalfiColors.dark.surfaceSunken,
    );
    await done(tester, c);
  });

  testWidgets('Stopwatch Idle: digits, laps header, Lap disabled, Start', (
    tester,
  ) async {
    final c = await pump(tester, Section.stopwatch);
    // The 104 pt digits are centred at y 121 in the kit's PNG (the master's 40 pt text frame
    // at 120 is a fixed box, not the glyphs).
    final digits = rectOf(
      tester,
      find.byKey(const ValueKey('stopwatch digits')),
    );
    expect(digits.center.dy, 121);
    expect(digits.center.dx, 512);
    // Header: Lap 352,296; Lap time 464,296 100×14; Total 576,296 96×14.
    expect(
      rectOf(tester, find.text('Lap time')),
      const Rect.fromLTWH(464, 296, 100, 14),
    );
    expect(
      rectOf(tester, find.text('Total')),
      const Rect.fromLTWH(576, 296, 96, 14),
    );
    expect(
      rectOf(tester, find.text('Lap').first).topLeft,
      const Offset(352, 296),
    );
    // At rest no line: Stopwatch Idle has no separators.
    expect(separators(tester), isEmpty);
    // Buttons: 68×28, y 704 (the pair is centred, the kit's sits 8 pt to the right).
    final lap = rectOf(tester, find.byKey(const ValueKey('lap reset')));
    final start = rectOf(tester, find.byKey(const ValueKey('start stop')));
    expect(lap.size, const Size(68, 28));
    expect(start.size, const Size(68, 28));
    expect(lap.top, 704);
    expect(start.left - lap.right, 96);
    await done(tester, c);
  });

  testWidgets('Stopwatch: the laps table rows are 32 pt, lines at 316 + 32 n', (
    tester,
  ) async {
    final c = await pump(tester, Section.stopwatch);
    c.stopwatchStartStop();
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 0; i < 3; i++) {
      c.stopwatchLapReset();
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Four rows (the current lap and three laps), a line under the header and each row.
    final lines = separators(tester).where((r) => r.width == 320).toList()
      ..sort((a, b) => a.top.compareTo(b.top));
    expect(lines, [
      for (var n = 0; n < 5; n++) Rect.fromLTWH(352, 316 + 32.0 * n, 320, 1),
    ]);
    // Row texts (Lap 4 …): name 352,324 and the times at 464 and 576, 18 tall.
    final name = rectOf(tester, find.text('Lap 4'));
    expect(name.topLeft, const Offset(352, 324));
    expect(name.height, 18);
    final row = find.byKey(const ValueKey('current lap'));
    final cells = find.descendant(of: row, matching: find.byType(Text));
    expect(tester.getRect(cells.at(1)).left, 464);
    expect(tester.getRect(cells.at(1)).width, 100);
    expect(tester.getRect(cells.at(2)).left, 576);
    expect(tester.getRect(cells.at(2)).width, 96);
    await done(tester, c);
  });

  testWidgets('Timer Picker: units, digits, label, sound, buttons', (
    tester,
  ) async {
    final c = await pump(tester, Section.timers);
    // Apps/Clock/Timer Picker: units at y 176 (14 tall), the 72 pt digits centred at 223,
    // label field 412,340 200×28, sound 412,380 200×28, buttons at y 464.
    expect(rectOf(tester, find.text('Hours')).top, 176);
    expect(rectOf(tester, find.text('Hours')).height, 14);
    final digits = rectOf(tester, find.text('15'));
    expect(digits.center.dy, 223);
    expect(
      rectOf(tester, find.byKey(const ValueKey('timer label'))),
      const Rect.fromLTWH(412, 340, 200, 28),
    );
    expect(
      rectOf(tester, find.byKey(const ValueKey('timer sound'))),
      const Rect.fromLTWH(412, 380, 200, 28),
    );
    final cancel = rectOf(tester, find.byKey(const ValueKey('timer cancel')));
    final start = rectOf(tester, find.byKey(const ValueKey('timer start')));
    expect(cancel.size, const Size(72, 28));
    expect(start.size, const Size(68, 28));
    expect(cancel.top, 464);
    expect(start.left - cancel.right, 96);
    // Cancel is disabled until a timer runs (the kit draws it at 35 %).
    expect(
      tester
          .widget<ClockButton>(find.byKey(const ValueKey('timer cancel')))
          .onPressed,
      isNull,
    );
    await done(tester, c);
  });

  testWidgets('Timer Running: list 320 wide, card, recents, ring and buttons', (
    tester,
  ) async {
    final c = await pump(
      tester,
      Section.timers,
      setup: (c) {
        c.startTimer(const Duration(minutes: 1));
        c.settings.recents = [
          const RecentTimer(Duration(minutes: 5), ''),
          const RecentTimer(Duration(minutes: 1), ''),
          const RecentTimer(Duration(minutes: 10), ''),
        ];
      },
    );
    await tester.pump(const Duration(milliseconds: 100));
    // List region 0,52 320×748 and its separator at 320.
    expect(
      separators(tester).where((r) => r.height == 696 + 52),
      contains(const Rect.fromLTWH(320, 52, 1, 748)),
    );
    // Active card 12,68 300×92 with the 32 pt pause button at 260,96.
    expect(
      rectOf(tester, find.byKey(const ValueKey('timer card 0'))),
      const Rect.fromLTWH(12, 68, 300, 92),
    );
    expect(
      rectOf(tester, find.byKey(const ValueKey('timer card pause 0'))),
      const Rect.fromLTWH(260, 96, 32, 32),
    );
    // Recent header 20,184 (18 tall); lines at 216, 272, 328, 280 wide; titles at +8; the
    // 28 pt buttons at 268.
    expect(rectOf(tester, find.text('Recent')).topLeft, const Offset(20, 184));
    expect(rectOf(tester, find.text('Recent')).height, 18);
    final lines = separators(tester).where((r) => r.width == 280).toList()
      ..sort((a, b) => a.top.compareTo(b.top));
    expect(lines, [
      for (var n = 0; n < 3; n++) Rect.fromLTWH(20, 216 + 56.0 * n, 280, 1),
    ]);
    expect(
      rectOf(tester, find.text('00:05:00')).topLeft,
      const Offset(20, 224),
    );
    expect(rectOf(tester, find.text('00:05:00')).height, 22);
    expect(
      rectOf(tester, find.byKey(const ValueKey('recent 300 '))),
      const Rect.fromLTWH(268, 224, 28, 28),
    );
    // Ring 492,148 360×360; the 64 pt digits centred at 313; sound 572,540; buttons at 620.
    expect(
      rectOf(tester, find.byKey(const ValueKey('timer ring'))),
      const Rect.fromLTWH(492, 148, 360, 360),
    );
    expect(
      rectOf(tester, find.byKey(const ValueKey('remaining'))).center.dy,
      313,
    );
    expect(
      rectOf(tester, find.byKey(const ValueKey('timer running sound'))),
      const Rect.fromLTWH(572, 540, 200, 28),
    );
    final cancel = rectOf(tester, find.byKey(const ValueKey('timer cancel')));
    final pause = rectOf(tester, find.byKey(const ValueKey('timer pause')));
    expect(cancel.size, const Size(72, 28));
    expect(pause.size, const Size(72, 28));
    expect(cancel.top, 620);
    // The kit's pair (484, 652) is off the ring's centre (672): here it is centred on it.
    expect((cancel.center.dx + pause.center.dx) / 2, 672);
    expect(pause.left - cancel.right, 96);
    await done(tester, c);
  });

  test('the palette is the kit\'s App/Clock one (Dark)', () {
    expect(clockPalette.window, const Color(0xFF1E1E1E));
    expect(clockPalette.card, const Color(0xFF323232));
    expect(clockPalette.accent, const Color(0xFFFF9230));
    expect(clockPalette.switchOn, const Color(0xFFFD9435));
    expect(clockPalette.start, const Color(0xFF30D159));
    expect(clockPalette.stop, const Color(0xFFFF4245));
    expect(clockPalette.lapButton, const Color(0xFF2F2F2F));
    expect(clockPalette.ringTrack, const Color(0xFF3B3B3D));
    expect(clockPalette.sheet, const Color(0xFF272727));
    expect(clockPalette.timerCard, const Color(0xFF48484A));
  });

  test('the numerals are the Numeral 40/64/72/104 tokens', () {
    for (final size in [40.0, 64.0, 72.0, 104.0]) {
      final style = numeral(size);
      expect(style.fontSize, size);
      expect(style.fontFamily, endsWith('Inter'));
      expect(style.fontWeight, FontWeight.w400);
    }
  });
}
