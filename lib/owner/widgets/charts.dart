import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';

// Chart conventions (see the dataviz checklist): one hue per series in fixed
// order, 2px lines with a ~10% area wash, ≤24px columns with 4px rounded tops,
// solid hairline grids, text in ink tokens (never series colors), a hover
// tooltip on every mark, and a table view behind every chart.

final _axisStyle = AlsText.body(11, color: AlsColors.axis, weight: FontWeight.w700).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
final _tipValue = AlsText.body(14, color: Colors.white, weight: FontWeight.w900);
final _tipLabel = AlsText.body(12, color: const Color(0xFFF3E2C7), weight: FontWeight.w600);

/// Rounds an axis max up to a clean number and returns (max, interval).
(double, double) niceScale(double maxValue, {int ticks = 4}) {
  if (maxValue <= 0) return (1, 0.25);
  final raw = maxValue / ticks;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final step = [1.0, 2.0, 2.5, 5.0, 10.0].map((m) => m * mag).firstWhere((s) => s >= raw, orElse: () => 10 * mag);
  return ((maxValue / step).ceil() * step, step);
}

String compactAxis(double v, {bool money = false}) {
  final prefix = money ? r'$' : '';
  if (v.abs() >= 1000) return '$prefix${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
  return '$prefix${v.toStringAsFixed(0)}';
}

/// Single-series trend (net sales over time) with crosshair + tooltip.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.labels, required this.values, required this.format, this.money = true, this.height = 240});

  final List<String> labels;
  final List<double> values;
  final String Function(double) format;
  final bool money;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return SizedBox(height: height);
    final (maxY, interval) = niceScale(values.reduce(math.max));
    final step = math.max(1, (labels.length / 6).ceil());
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(1, values.length - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => const FlLine(color: AlsColors.grid, strokeWidth: 1),
          ),
          borderData: FlBorderData(
            show: true,
            border: const Border(bottom: BorderSide(color: Color(0xFFD9CCB8))),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: interval,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(compactAxis(v, money: money), style: _axisStyle),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= labels.length || i % step != 0) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(labels[i], style: _axisStyle),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            getTouchedSpotIndicator: (bar, indexes) => indexes
                .map(
                  (_) => TouchedSpotIndicatorData(
                    const FlLine(color: AlsColors.axis, strokeWidth: 1),
                    FlDotData(
                      getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 5, color: AlsColors.series1, strokeWidth: 2, strokeColor: Colors.white),
                    ),
                  ),
                )
                .toList(),
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AlsColors.brown,
              tooltipBorderRadius: BorderRadius.circular(10),
              fitInsideHorizontally: true,
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      '${format(s.y)}\n',
                      _tipValue,
                      children: [TextSpan(text: labels[s.x.round()], style: _tipLabel)],
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final (i, v) in values.indexed) FlSpot(i.toDouble(), v)],
              isCurved: true,
              curveSmoothness: 0.22,
              preventCurveOverShooting: true,
              color: AlsColors.series1,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                checkToShowDot: (spot, _) => spot.x == values.length - 1,
                getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 4.5, color: AlsColors.series1, strokeWidth: 2, strokeColor: Colors.white),
              ),
              belowBarData: BarAreaData(show: true, color: AlsColors.series1.withValues(alpha: 0.10)),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

/// One-series column chart (orders by hour).
class ColumnChart extends StatelessWidget {
  const ColumnChart({super.key, required this.labels, required this.values, required this.tooltip, this.height = 220});

  final List<String> labels;
  final List<double> values;
  final String Function(int index) tooltip;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return SizedBox(height: height);
    final (maxY, interval) = niceScale(values.reduce(math.max));
    final step = math.max(1, (labels.length / 8).ceil());
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = math.min(24.0, (box.maxWidth - 50) / values.length * 0.62);
          return BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => const FlLine(color: AlsColors.grid, strokeWidth: 1),
              ),
              borderData: FlBorderData(
                show: true,
                border: const Border(bottom: BorderSide(color: Color(0xFFD9CCB8))),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: interval,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(compactAxis(v), style: _axisStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i % step != 0 || i >= labels.length) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(labels[i], style: _axisStyle),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AlsColors.brown,
                  tooltipBorderRadius: BorderRadius.circular(10),
                  fitInsideHorizontally: true,
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(tooltip(group.x), _tipValue),
                ),
              ),
              barGroups: [
                for (final (i, v) in values.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: v,
                        color: AlsColors.series1,
                        width: width,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 450),
          );
        },
      ),
    );
  }
}

class RankedRow {
  const RankedRow(this.label, this.value, this.valueLabel, {this.detail, this.tooltip});
  final String label;
  final double value;
  final String valueLabel;
  final String? detail;
  final String? tooltip;
}

/// Horizontal ranked bars (one hue, value at the tip, tooltip on hover).
class RankedBars extends StatelessWidget {
  const RankedBars({super.key, required this.rows, this.labelWidth = 150, this.empty = 'No data for this range yet'});

  final List<RankedRow> rows;
  final double labelWidth;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(empty, style: AlsText.body(13, color: AlsColors.muted)),
        ),
      );
    }
    final maxV = rows.map((r) => r.value).fold<double>(0, math.max);
    return Column(
      children: [
        for (final (i, r) in rows.indexed)
          Tooltip(
            message: r.tooltip ?? '${r.label} · ${r.valueLabel}',
            waitDuration: const Duration(milliseconds: 150),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AlsText.body(13, weight: FontWeight.w800),
                        ),
                        if (r.detail != null)
                          Text(
                            r.detail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AlsText.body(11, color: AlsColors.muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final valueWidth = 64.0;
                        final w = maxV == 0 ? 0.0 : (box.maxWidth - valueWidth) * (r.value / maxV);
                        return Row(
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: w),
                              duration: Duration(milliseconds: 500 + i * 60),
                              curve: Curves.easeOutCubic,
                              builder: (context, v, _) => Container(
                                width: math.max(2, v),
                                height: 14,
                                decoration: const BoxDecoration(
                                  color: AlsColors.series1,
                                  borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              r.valueLabel,
                              style: AlsText.body(12, weight: FontWeight.w900).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class Segment {
  const Segment(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// 100% stacked bar with 2px surface gaps, direct labels when they fit, and a legend.
class SplitBar extends StatelessWidget {
  const SplitBar({super.key, required this.title, required this.segments, this.unit = 'orders'});

  final String title;
  final List<Segment> segments;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (s, x) => s + x.value);
    final visible = segments.where((s) => s.value > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AlsText.body(13, weight: FontWeight.w800)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 26,
            child: total == 0
                ? Container(color: AlsColors.grid)
                : LayoutBuilder(
                    builder: (context, box) {
                      final gaps = (visible.length - 1) * 2.0;
                      return Row(
                        children: [
                          for (final (i, s) in visible.indexed) ...[
                            if (i > 0) const SizedBox(width: 2),
                            Tooltip(
                              message: '${s.label} · ${s.value.round()} $unit (${(s.value / total * 100).round()}%)',
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: (box.maxWidth - gaps) * s.value / total),
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeOutCubic,
                                builder: (context, w, _) {
                                  final label = '${(s.value / total * 100).round()}%';
                                  return Container(
                                    width: w,
                                    color: s.color,
                                    alignment: Alignment.center,
                                    child: w > 44
                                        ? Text(
                                            label,
                                            maxLines: 1,
                                            style: AlsText.body(11, color: Colors.white, weight: FontWeight.w900),
                                          )
                                        : null,
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final s in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${s.label} ${s.value.round()}',
                    style: AlsText.body(12, color: AlsColors.brownSoft, weight: FontWeight.w700),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// 12-point sparkline in the de-emphasis gray with the current period in the accent.
class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.height = 30});

  final List<num> values;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(painter: _SparkPainter(values), size: Size.infinite),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values);

  final List<num> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.map((v) => v.toDouble()).reduce(math.max);
    final minV = values.map((v) => v.toDouble()).reduce(math.min);
    final span = (maxV - minV) == 0 ? 1 : (maxV - minV);
    Offset at(int i) => Offset(i / (values.length - 1) * (size.width - 6) + 3, size.height - 4 - (values[i] - minV) / span * (size.height - 8));
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFC9BFB2),
    );
    final last = at(values.length - 1);
    canvas.drawCircle(last, 4, Paint()..color = Colors.white);
    canvas.drawCircle(last, 3, Paint()..color = AlsColors.series1);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values;
}

/// Stat tile: label · value · signed delta vs previous period · sparkline.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.deltaText,
    this.upIsGood = true,
    this.sub,
    this.spark,
    this.live = false,
  });

  final String label;
  final String value;
  final double? delta;
  final String? deltaText;
  final bool upIsGood;
  final String? sub;
  final List<num>? spark;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final good = d == null || d == 0 ? null : (d > 0) == upIsGood;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: alsShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AlsText.body(13, color: AlsColors.muted, weight: FontWeight.w800),
                ),
              ),
              if (live) const _LivePulse(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AlsText.body(28, color: AlsColors.ink, weight: FontWeight.w800, height: 1.05),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (d != null) ...[
                Icon(
                  d > 0 ? Icons.arrow_upward_rounded : (d < 0 ? Icons.arrow_downward_rounded : Icons.remove_rounded),
                  size: 14,
                  color: good == null ? AlsColors.muted : (good ? AlsColors.deltaGood : AlsColors.deltaBad),
                ),
                const SizedBox(width: 2),
                Text(
                  deltaText ?? '${(d.abs() * 100).toStringAsFixed(d.abs() < 0.1 ? 1 : 0)}%',
                  style: AlsText.body(12, color: good == null ? AlsColors.muted : (good ? AlsColors.deltaGood : AlsColors.deltaBad), weight: FontWeight.w900),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  sub ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AlsText.body(12, color: AlsColors.muted),
                ),
              ),
            ],
          ),
          if (spark != null && spark!.length > 1) ...[const SizedBox(height: 8), Sparkline(spark!)],
        ],
      ),
    );
  }
}

class _LivePulse extends StatefulWidget {
  const _LivePulse();

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: Color.lerp(AlsColors.success, AlsColors.success.withValues(alpha: 0.2), _c.value), shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('LIVE', style: AlsText.label(10, color: AlsColors.success)),
      ],
    ),
  );
}
