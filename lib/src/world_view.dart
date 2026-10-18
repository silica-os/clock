// The World section (kit `Apps/Clock/World`, CL-01): a map with the day/night line and a pin
// per city on top, a grid of 220 pt tall cards (184 wide at 1024 pt, 20 pt margins, 16 pt
// gaps) below, each with a 120 pt analog face (white by day, black by night), the city and its
// time, the day and offset, sunrise and sunset.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:silica_ui/silica_ui.dart';

import '../l10n/gen/app_localizations.dart';
import 'controller.dart';
import 'style.dart';
import 'time/cities.dart';
import 'time/tzif.dart';
import 'widgets.dart' show Sheet;

/// `HH:MM`, or `h:MM AM` when the system does not use the 24-hour clock.
String formatTime(BuildContext context, int hour, int minute) {
  final mm = minute.toString().padLeft(2, '0');
  if (MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? true) {
    return '${hour.toString().padLeft(2, '0')}:$mm';
  }
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:$mm ${hour < 12 ? 'AM' : 'PM'}';
}

class WorldView extends StatefulWidget {
  const WorldView({super.key, required this.controller});
  final ClockController controller;

  @override
  State<WorldView> createState() => _WorldViewState();
}

class _WorldViewState extends State<WorldView> {
  Timer? _tick;
  List<Float32List> _landRings = const [];

  @override
  void initState() {
    super.initState();
    loadLand().then((rings) {
      if (mounted) setState(() => _landRings = rings);
    });
    _scheduleTick();
  }

  /// The view changes only at the map's time steps (the minute shown on the pins and cards is
  /// one of them); the faces redraw on their own. One rebuild per step, not per second (#202).
  void _scheduleTick() {
    _tick = Timer(WorldMapPainter.untilNextStep(widget.controller.now()), () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _openMenu(City city, Offset at) {
    final l = AppLocalizations.of(context);
    showAmalfiMenu(
      context: context,
      position: at,
      entries: [
        AmalfiMenuAction(
          l.removeClock,
          onSelected: () => widget.controller.removeCity(city.zone),
        ),
      ],
    ).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cities = c.worldCities;
    final now = c.now();
    final localZone =
        c.zones.zone(c.zones.localName() ?? 'UTC') ?? TimeZone.utc;
    final pins = [
      for (final city in cities)
        (
          city,
          formatTime(
            context,
            c.timeIn(city.zone).hour,
            c.timeIn(city.zone).minute,
          ),
        ),
    ];
    // CLOCK-WORLD (#95, measured): the map has no fixed size, it takes the full width (480 pt
    // at 1024, the kit's) and never scrolls sideways; the map and the cards scroll together in
    // one vertical view under the toolbar. The cards sit in a grid of fixed 220 pt height
    // whose columns come from the window width, not from the number of cities (CardGrid): a
    // single city is one card of one slot (184 pt at 1024 pt), never the whole row.
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final grid = CardGrid.of(width);
        return SingleChildScrollView(
          key: const ValueKey('world scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Its own layer: the faces below redraw every 72 ms, the map only when its
              // content changes (#202).
              RepaintBoundary(
                child: SizedBox(
                  width: width,
                  height: width * ClockMetrics.worldMapRatio,
                  child: CustomPaint(
                    key: const ValueKey('world map'),
                    painter: WorldMapPainter(
                      now: WorldMapPainter.step(now),
                      land: _landRings,
                      pins: pins,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: ClockMetrics.mapGap),
              if (cities.isEmpty)
                SizedBox(
                  height: ClockMetrics.worldCardHeight,
                  width: width,
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context).worldEmpty,
                      style: AmalfiType.body(
                        color: AmalfiTheme.of(context).colors.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClockMetrics.cardsMargin,
                  ),
                  child: Wrap(
                    key: const ValueKey('world cards'),
                    spacing: CardGrid.gap,
                    runSpacing: CardGrid.gap,
                    children: [
                      for (final city in cities)
                        GestureDetector(
                          onSecondaryTapUp: (d) =>
                              _openMenu(city, d.globalPosition),
                          child: WorldCard(
                            key: ValueKey('card ${city.zone}'),
                            city: city,
                            zone: c.zones.zone(city.zone) ?? TimeZone.utc,
                            local: localZone,
                            now: now,
                            clock: c.now,
                            width: grid.cardWidth,
                          ),
                        ),
                    ],
                  ),
                ),
              // Kit Apps/Clock/World: the cards end at 768 of the 800 pt window.
              const SizedBox(height: ClockMetrics.worldBottomMargin),
            ],
          ),
        );
      },
    );
  }
}

/// A world clock card (kit `City Card Day|Night`): 220 pt tall, `App/Clock/Card`, radius 12,
/// the face 20 pt from the top.
class WorldCard extends StatelessWidget {
  const WorldCard({
    super.key,
    required this.city,
    required this.zone,
    required this.local,
    required this.now,
    this.clock,
    this.width = 186,
  });

  final City city;
  final TimeZone zone;
  final TimeZone local;
  final DateTime now;
  final DateTime Function()? clock;
  final double width;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final wall = zone.wallTime(now);
    final here = local.wallTime(now);
    final utcSeconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final offset =
        zone.offsetAt(utcSeconds).seconds - local.offsetAt(utcSeconds).seconds;
    final dayDiff = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
    ).difference(DateTime.utc(here.year, here.month, here.day)).inDays;
    final day = dayDiff > 0
        ? l.dayTomorrow
        : dayDiff < 0
        ? l.dayYesterday
        : l.dayToday;
    final hours = offset / 3600;
    final offsetText =
        '${hours >= 0 ? '+' : '−'}'
        '${hours.abs() == hours.abs().roundToDouble() ? hours.abs().round() : hours.abs().toStringAsFixed(1).replaceAll('.', l.decimalSeparator)}';
    final sun = sunTimes(wall, city.latitude, city.longitude);
    final daylight = sun == null
        ? wall.hour >= 6 && wall.hour < 18
        : now.toUtc().isAfter(sun.$1) && now.toUtc().isBefore(sun.$2);
    String sunText(DateTime utc) {
      final w = zone.wallTime(utc);
      return formatTime(context, w.hour, w.minute);
    }

    final colors = AmalfiTheme.of(context).colors;
    return SizedBox(
      width: width,
      height: ClockMetrics.worldCardHeight,
      child: DecoratedBox(
        decoration: AmalfiShapeDecoration(
          color: clockPalette.card,
          shape: AmalfiSmoothBorder(radius: ClockMetrics.cardRadius),
        ),
        child: Column(
          children: [
            const SizedBox(height: ClockMetrics.faceTop),
            SizedBox.square(
              dimension: ClockMetrics.face,
              child: AnalogFace(
                time: wall,
                day: daylight,
                now: now,
                clock: clock,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                l.cityTime(
                  city.name,
                  formatTime(context, wall.hour, wall.minute),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AmalfiType.headline(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l.hoursOffset(day, offsetText),
              style: AmalfiType.callout(color: colors.textSecondary),
            ),
            const SizedBox(height: 4),
            if (sun != null)
              Text(
                l.sunTimes(sunText(sun.$1), sunText(sun.$2)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AmalfiType.caption(color: colors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}

/// How the hands move (CLOCK-HANDS, silica-reference #95, measured): never in steps, all three
/// sweep continuously. macOS redraws the face about every 72 ms; the second hand advances
/// ~0.45 degrees per redraw (5.99 degrees per second), without a snap or an overshoot.
abstract final class HandMotion {
  static const Duration redraw = Duration(milliseconds: 72);

  /// The position within 12 hours, in seconds, of the wall time [t] [elapsed] later.
  static double position(DateTime t, Duration elapsed) =>
      ((t.hour % 12) * 3600 +
          t.minute * 60 +
          t.second +
          t.millisecond / 1000 +
          t.microsecond / 1e6 +
          elapsed.inMicroseconds / 1e6) %
      43200;
}

/// The analog face of a card: [ClockFacePainter] with all the hands sweeping continuously.
/// [time] is the wall time at the instant [now]; the face then follows [clock].
class AnalogFace extends StatefulWidget {
  const AnalogFace({
    super.key,
    required this.time,
    required this.day,
    this.now,
    this.clock,
  });
  final DateTime time;
  final bool day;
  final DateTime? now;
  final DateTime Function()? clock;

  @override
  State<AnalogFace> createState() => _AnalogFaceState();
}

class _AnalogFaceState extends State<AnalogFace> {
  Timer? _redraw;

  @override
  void initState() {
    super.initState();
    if (widget.clock != null) {
      _redraw = Timer.periodic(HandMotion.redraw, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _redraw?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock = widget.clock;
    final now = widget.now;
    final elapsed = clock == null || now == null
        ? Duration.zero
        : clock().difference(now);
    // The face in its own layer, and the dial in another below the hands: a redraw every
    // 72 ms repaints only the hands, not the card, the map or the dial (#202).
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: AnalogDialPainter(day: widget.day)),
          ),
          CustomPaint(
            key: const ValueKey('hands'),
            painter: ClockFacePainter(
              seconds: HandMotion.position(widget.time, elapsed),
              day: widget.day,
            ),
          ),
        ],
      ),
    );
  }
}

/// The dial of the analog face (kit `City Card Day|Night`): white with dark numerals by day,
/// `Surface/Sunken` with white numerals by night.
class AnalogDialPainter extends CustomPainter {
  AnalogDialPainter({required this.day});

  final bool day;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final face = day ? ClockFace.dayFace : ClockFace.nightFace;
    final ink = day ? ClockFace.dayInk : ClockFace.nightInk;
    canvas.drawCircle(c, r, Paint()..color = face);
    for (var n = 1; n <= 12; n++) {
      final a = n * math.pi / 6 - math.pi / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: '$n',
          style: AmalfiType.label(color: ink),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = c + Offset(math.cos(a), math.sin(a)) * (r * 0.78);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(AnalogDialPainter old) => old.day != day;
}

/// The hands of the analog face, over [AnalogDialPainter]: dark by day, white by night; the
/// second hand is a thin one in `App/Clock/Accent` with an accent pivot (kit: hour and minute
/// hands 4 pt wide, 60 and 88 pt long, second hand 1 pt wide, pivot 8 pt).
class ClockFacePainter extends CustomPainter {
  ClockFacePainter({required this.seconds, required this.day});

  /// The position within 12 hours, in seconds.
  final double seconds;
  final bool day;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final ink = day ? ClockFace.dayInk : ClockFace.nightInk;
    void hand(double fraction, double length, double width, Color color) {
      final a = fraction * 2 * math.pi - math.pi / 2;
      canvas.drawLine(
        c,
        c + Offset(math.cos(a), math.sin(a)) * length,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    final secondHand = seconds % 60;
    final minuteHand = seconds / 60 % 60;
    final hourHand = seconds / 3600 % 12;
    hand(hourHand / 12, r * 0.5, 4, ink);
    hand(minuteHand / 60, r * 0.73, 4, ink);
    hand(secondHand / 60, r * 0.83, 1, clockPalette.accent);
    canvas.drawCircle(c, 4, Paint()..color = clockPalette.accent);
  }

  @override
  bool shouldRepaint(ClockFacePainter old) =>
      old.seconds != seconds || old.day != day;
}

/// The land of the map (Natural Earth 1:110m, public domain): rings of longitude/latitude
/// pairs, loaded once from the asset.
Future<List<Float32List>>? _land;
Future<List<Float32List>> loadLand() => _land ??= () async {
  try {
    final json = jsonDecode(
      await rootBundle.loadString('assets/map/land.json'),
    );
    final scale = (json['scale'] as num?)?.toDouble() ?? 1;
    return [
      for (final ring in json['rings'] as List)
        Float32List.fromList([
          for (final v in ring as List) (v as num) / scale,
        ]),
    ];
  } on Object {
    // No map data: oceans and lines only.
    return <Float32List>[];
  }
}();

/// The map: an equirectangular world, black oceans and dark gray land, the time-zone lines,
/// the day/night line and a pin (orange dot, bold name, time) per city.
class WorldMapPainter extends CustomPainter {
  WorldMapPainter({
    required this.now,
    required this.pins,
    this.land = const [],
  });
  final DateTime now;
  final List<(City, String)> pins;
  final List<Float32List> land;

  /// How often the day/night line moves: it shifts by about 0.1 px per 10 s at 1024 pt, so
  /// a coarser [now] draws the same map without repainting it every second (#202).
  static const Duration timeStep = Duration(seconds: 10);

  /// [now] rounded down to [timeStep]: the time the map is drawn for.
  static DateTime step(DateTime now) {
    final micros = now.microsecondsSinceEpoch;
    final unit = timeStep.inMicroseconds;
    return DateTime.fromMicrosecondsSinceEpoch(
      micros - micros % unit,
      isUtc: now.isUtc,
    );
  }

  /// From [now] to the next [timeStep] (never zero, so a timer does not spin).
  static Duration untilNextStep(DateTime now) {
    final unit = timeStep.inMicroseconds;
    final left = unit - now.microsecondsSinceEpoch % unit;
    return Duration(microseconds: left);
  }

  /// Where [lat], [lon] fall on a map of [size]: equirectangular, one degree is `width / 360`
  /// in both directions, the equator in the middle.
  static Offset project(double lat, double lon, Size size) => Offset(
    (lon + 180) / 360 * size.width,
    size.height / 2 - lat * size.width / 360,
  );

  @override
  void paint(Canvas canvas, Size size) {
    // Cropped at the poles: what falls outside (Antarctica, about 5.6° below the crop) stays
    // inside the map's box instead of covering the 16 pt gap to the cards (clock#8).
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = ClockMap.ocean);
    // Equirectangular, centred on the equator and cropped at the poles as the kit's map is:
    // one degree is width / 360 in both directions.
    Offset point(double lat, double lon) => project(lat, lon, size);
    final ground = Paint()..color = ClockMap.land;
    for (final ring in land) {
      final path = Path();
      for (var k = 0; k + 1 < ring.length; k += 2) {
        final p = point(ring[k + 1], ring[k]);
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path..close(), ground);
    }
    final zones = Paint()
      ..color = ClockMap.zoneLine
      ..strokeWidth = 1;
    for (var lon = -172.5; lon <= 180; lon += 15) {
      final x = (lon + 180) / 360 * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), zones);
    }
    // The subsolar point and the day/night line.
    final utc = now.toUtc();
    final n = utc.difference(DateTime.utc(utc.year)).inMinutes / 1440;
    final gamma = 2 * math.pi / 365 * n;
    final decl =
        0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2 * gamma);
    final hours = utc.hour + utc.minute / 60 + utc.second / 3600;
    final subLon = -(hours - 12) * 15;
    final night = Path();
    final line = Path();
    final tanD = math.tan(decl);
    for (var i = 0; i <= 360; i++) {
      final lon = -180.0 + i;
      final lat =
          math.atan(
            -math.cos((lon - subLon) * math.pi / 180) /
                (tanD == 0 ? 1e-9 : tanD),
          ) *
          180 /
          math.pi;
      final p = point(lat, lon);
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
        night.moveTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
        night.lineTo(p.dx, p.dy);
      }
    }
    // The night is on the side of the pole the sun leans away from.
    final nightTop = decl < 0;
    night
      ..lineTo(size.width, nightTop ? 0 : size.height)
      ..lineTo(0, nightTop ? 0 : size.height)
      ..close();
    canvas.drawPath(night, Paint()..color = ClockMap.night);
    canvas.drawPath(
      line,
      Paint()
        ..color = ClockMap.boundary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    for (final (city, time) in pins) {
      final p = point(city.latitude, city.longitude);
      canvas.drawCircle(
        p,
        ClockMetrics.pinRadius,
        Paint()..color = clockPalette.accent,
      );
      TextPainter text(String s, TextStyle style) => TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final name = text(
        city.name,
        AmalfiType.label(color: darkColors.textPrimary),
      );
      final clock = text(
        time,
        AmalfiType.caption(color: darkColors.textSecondary),
      );
      // The kit: the name 8 pt right of the pin's centre and 8 above it, the time 5 below.
      // Near the right edge the label goes on the left of the pin.
      final width = math.max(name.width, clock.width);
      final right = p.dx + 8 + width <= size.width;
      final x = right ? p.dx + 8 : p.dx - 8 - width;
      name.paint(canvas, Offset(x, p.dy - 8));
      clock.paint(canvas, Offset(x, p.dy + 5));
    }
  }

  @override
  bool shouldRepaint(WorldMapPainter old) =>
      old.now != now ||
      !identical(old.land, land) ||
      !_samePins(old.pins, pins);

  static bool _samePins(List<(City, String)> a, List<(City, String)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final (ca, ta) = a[i];
      final (cb, tb) = b[i];
      if (ta != tb ||
          ca.name != cb.name ||
          ca.latitude != cb.latitude ||
          ca.longitude != cb.longitude) {
        return false;
      }
    }
    return true;
  }
}

/// The sheet that adds a city (no kit master: built from the Amalfi pieces on the editor's
/// sheet): 620 × 680, a round × and the title on one line, a search field and 28 pt rows.
class AddCitySheet extends StatefulWidget {
  const AddCitySheet({
    super.key,
    required this.cities,
    required this.onPick,
    required this.onClose,
  });

  final List<City> cities;
  final ValueChanged<City> onPick;
  final VoidCallback onClose;

  @override
  State<AddCitySheet> createState() => _AddCitySheetState();
}

class _AddCitySheetState extends State<AddCitySheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = AmalfiTheme.of(context).colors;
    final results = searchCities(widget.cities, _query.text);
    return Sheet(
      size: const Size(620, 680),
      onDismiss: widget.onClose,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AmalfiIconButton(
                  key: const ValueKey('close sheet'),
                  icon: const AmalfiGlyph(AmalfiGlyphs.xmark),
                  semanticLabel: l.cancel,
                  onPressed: widget.onClose,
                ),
                Expanded(
                  child: Text(
                    l.addCity,
                    textAlign: TextAlign.center,
                    style: AmalfiType.title3(color: colors.textPrimary),
                  ),
                ),
                const SizedBox(width: 28),
              ],
            ),
            const SizedBox(height: 16),
            AmalfiSearchField(
              key: const ValueKey('city search'),
              controller: _query,
              placeholder: l.searchCities,
              size: AmalfiFieldSize.large,
              width: double.infinity,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onCleared: () => setState(() {}),
              onSubmitted: (_) {
                if (results.isNotEmpty) widget.onPick(results.first);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        l.noResults,
                        style: AmalfiType.body(color: colors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemExtent: 28,
                      itemBuilder: (context, i) => _CityRow(
                        city: results[i],
                        onTap: () => widget.onPick(results[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CityRow extends StatefulWidget {
  const _CityRow({required this.city, required this.onTap});
  final City city;
  final VoidCallback onTap;

  @override
  State<_CityRow> createState() => _CityRowState();
}

class _CityRowState extends State<_CityRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = AmalfiTheme.of(context).colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: ValueKey('city ${widget.city.zone}'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: AmalfiShapeDecoration(
            color: _hover ? colors.accentAmalfi : null,
            shape: AmalfiSmoothBorder(radius: AmalfiRadii.smallControl),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                widget.city.country.isEmpty
                    ? widget.city.name
                    : '${widget.city.name}, ${widget.city.country}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AmalfiType.body(
                  color: _hover ? colors.textOnAccent : colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
