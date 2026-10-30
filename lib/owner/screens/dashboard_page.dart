import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../owner_store.dart';
import '../widgets/charts.dart';
import '../widgets/owner_ui.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Json? _data;
  bool _loading = false;
  String? _error;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.watch<OwnerStore>();
    final key = '${s.storeId}|${s.dates.from}|${s.dates.to}';
    if (key != _key) {
      _key = key;
      _load(s);
    }
  }

  Future<void> _load(OwnerStore s) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = s.dates;
      final res = await s.api.get('/owner/dashboard', query: {'storeId': s.storeId, 'from': d.from, 'to': d.to});
      if (mounted) setState(() => _data = res);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OwnerStore>();
    final data = _data;
    return OwnerPageScaffold(
      title: 'Dashboard',
      subtitle: '${s.selectedStore?.shortName ?? 'All stores'} · ${s.rangeLabel}',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => _load(s),
          icon: const Icon(Icons.refresh_rounded, color: AlsColors.brown),
        ),
      ],
      child: data == null
          ? (_error != null ? Text(_error!, style: AlsText.body(15, color: AlsColors.red)) : const _Skeleton())
          // Refetch keeps the frame: hold the previous render at reduced opacity.
          : AnimatedOpacity(
              opacity: _loading ? 0.5 : 1,
              duration: const Duration(milliseconds: 200),
              child: _Content(data: data),
            ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.data});

  final Json data;

  @override
  Widget build(BuildContext context) {
    final k = data['kpis'] as Json;
    final d = data['deltas'] as Json;
    final spark = data['sparklines'] as Json;
    final range = data['range'] as Json;
    final days = (range['days'] as num).toInt();
    final daily = (data['daily'] as List).cast<Json>();
    final hourly = (data['hourly'] as List).cast<Json>();
    final prevLabel = days == 1 ? 'vs prior day' : 'vs prior $days days';
    double n(dynamic v) => (v as num).toDouble();
    List<num> sp(String key) => ((spark[key] as List?) ?? const []).cast<num>();

    // Single day → hourly trend; longer ranges → daily trend.
    final trendLabels = days == 1
        ? [for (final h in hourly) _hour(h['hour'] as int)]
        : [for (final row in daily) DateFormat('MMM d').format(DateTime.parse(row['date'] as String))];
    final trendValues = days == 1 ? [for (final h in hourly) n(h['netSalesCents']) / 100] : [for (final row in daily) n(row['netSalesCents']) / 100];
    final activeHours = hourly.where((h) => (h['orders'] as num) > 0).map((h) => h['hour'] as int).toList();
    final firstHour = activeHours.isEmpty ? 11 : activeHours.reduce((a, b) => a < b ? a : b);
    final lastHour = activeHours.isEmpty ? 22 : activeHours.reduce((a, b) => a > b ? a : b);
    final hourWindow = hourly.where((h) => (h['hour'] as int) >= firstHour && (h['hour'] as int) <= lastHour).toList();

    final kpis = [
      KpiTile(label: 'Orders', value: compactNumber(k['orders'] as num), delta: n(d['orders']), sub: prevLabel, spark: sp('orders')),
      KpiTile(label: 'Average order', value: money(k['aovCents'] as num), delta: n(d['aov']), sub: prevLabel, spark: sp('aov')),
      KpiTile(
        label: 'App users',
        value: compactNumber(k['totalUsers'] as num),
        delta: n(d['newUsers']),
        sub: '${k['newUsers']} new · ${k['registeredUsers']} with accounts',
      ),
      KpiTile(
        label: 'Repeat customers',
        value: percent(n(k['repeatRate'])),
        delta: n(d['repeatRate']),
        deltaText: '${(n(d['repeatRate']).abs() * 100).toStringAsFixed(1)} pts',
        sub: '${k['returningCustomers']} of ${k['customers']} came back',
      ),
      KpiTile(label: 'In the kitchen now', value: '${k['inProgress']}', live: true, sub: 'orders in progress'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth > 1180 ? 5 : (box.maxWidth > 760 ? 3 : 2);
            final w = (box.maxWidth - (cols - 1) * 14) / cols;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final (i, t) in kpis.indexed)
                  SizedBox(
                    width: w,
                    child: Reveal(delay: Reveal.stagger(i, ms: 60), child: t),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Panel(
          title: 'Net sales',
          subtitle: 'Food + delivery fees − discounts · excludes tax (${money(k['taxCents'] as num)}) and driver tips (${money(k['tipCents'] as num)})',
          table: SimpleTable(
            columns: [days == 1 ? 'Hour' : 'Day', 'Net sales'],
            numeric: const {1},
            rows: [
              for (final (i, l) in trendLabels.indexed)
                if (trendValues[i] > 0 || days > 1) [Text(l), Text(money(trendValues[i] * 100))],
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  // The one hero figure on this page.
                  Text(
                    money(k['netSalesCents'] as num),
                    style: AlsText.body(48, color: AlsColors.ink, weight: FontWeight.w800, height: 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _Delta(value: n(d['netSales']), label: prevLabel),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('Total collected ${money(k['totalCollectedCents'] as num)}', style: AlsText.body(12, color: AlsColors.muted)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TrendChart(labels: trendLabels, values: trendValues, format: (v) => money(v * 100)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ResponsiveRow(
          flex: const [3, 2],
          children: [
            Panel(
              title: 'Orders by hour',
              subtitle: 'When the rush hits · store time',
              table: SimpleTable(
                columns: const ['Hour', 'Orders', 'Net sales'],
                numeric: const {1, 2},
                rows: [
                  for (final h in hourWindow) [Text(_hour(h['hour'] as int)), Text('${h['orders']}'), Text(money(h['netSalesCents'] as num))],
                ],
              ),
              child: ColumnChart(
                labels: [for (final h in hourWindow) _hour(h['hour'] as int)],
                values: [for (final h in hourWindow) n(h['orders'])],
                tooltip: (i) => '${_hour(hourWindow[i]['hour'] as int)} · ${hourWindow[i]['orders']} orders',
              ),
            ),
            Panel(
              title: 'How orders arrive',
              subtitle: 'Share of orders in this range',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SplitBar(
                    title: 'Pickup vs delivery',
                    segments: [
                      for (final (i, f) in (data['fulfillment'] as List).cast<Json>().indexed)
                        Segment(f['key'] == 'pickup' ? 'Pickup' : 'Delivery', n(f['orders']), [AlsColors.series1, AlsColors.series2][i % 2]),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SplitBar(
                    title: 'Who delivered',
                    segments: [
                      for (final (i, f) in (data['fleet'] as List).cast<Json>().take(3).indexed)
                        Segment(providerLabel(f['key'] as String), n(f['orders']), [AlsColors.series1, AlsColors.series2, AlsColors.series3][i]),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SplitBar(
                    title: 'Ordering from',
                    segments: [
                      for (final (i, f) in (data['platforms'] as List).cast<Json>().take(3).indexed)
                        Segment(platformLabel(f['key'] as String), n(f['orders']), [AlsColors.series1, AlsColors.series2, AlsColors.series3][i]),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ResponsiveRow(
          children: [
            Panel(
              title: 'Top sellers',
              subtitle: 'By revenue',
              table: SimpleTable(
                columns: const ['Item', 'Sold', 'Revenue'],
                numeric: const {1, 2},
                flex: const [3, 1, 1],
                rows: [
                  for (final i in (data['topItems'] as List).cast<Json>())
                    [Text(i['name'] as String), Text('${i['quantity']}'), Text(money(i['revenueCents'] as num))],
                ],
              ),
              child: RankedBars(
                labelWidth: isCompact(context) ? 110 : 150,
                rows: [
                  for (final i in (data['topItems'] as List).cast<Json>())
                    RankedRow(
                      i['name'] as String,
                      n(i['revenueCents']),
                      moneyCompact(i['revenueCents'] as num),
                      detail: '${i['quantity']} sold',
                      tooltip: '${i['name']} · ${i['quantity']} sold · ${money(i['revenueCents'] as num)}',
                    ),
                ],
              ),
            ),
            Panel(
              title: 'Which marketing worked',
              subtitle: 'Net sales from orders that used each channel’s promo codes',
              table: SimpleTable(
                columns: const ['Channel', 'Orders', 'Net sales', 'New cust.', 'Sign-ups'],
                numeric: const {1, 2, 3, 4},
                flex: const [2, 1, 1, 1, 1],
                rows: [
                  for (final c in (data['channels'] as List).cast<Json>())
                    [
                      Text(c['channel'] as String),
                      Text('${c['orders']}'),
                      Text(money(c['netSalesCents'] as num)),
                      Text('${c['newCustomers']}'),
                      Text('${c['signups']}'),
                    ],
                ],
              ),
              child: RankedBars(
                labelWidth: isCompact(context) ? 100 : 130,
                rows: [
                  for (final c in (data['channels'] as List).cast<Json>().where((c) => (c['orders'] as num) > 0))
                    RankedRow(
                      c['channel'] as String,
                      n(c['netSalesCents']),
                      moneyCompact(c['netSalesCents'] as num),
                      detail: '${c['orders']} orders · ${c['newCustomers']} new',
                      tooltip:
                          '${c['channel']}: ${c['orders']} orders, ${money(c['netSalesCents'] as num)} net sales, ${money(c['discountCents'] as num)} in discounts, ${c['newCustomers']} new customers, ${c['signups']} app sign-ups',
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Panel(
          title: 'Promo code performance',
          subtitle: 'Each code is tied to the channel it was shared on',
          child: SimpleTable(
            columns: const ['Code', 'Channel', 'Campaign', 'Uses', 'Net sales', 'Discount', 'New cust.', r'Sales per $1 off'],
            numeric: const {3, 4, 5, 6, 7},
            flex: const [2, 2, 3, 1, 2, 2, 1, 2],
            rows: [
              for (final p in (data['promos'] as List).cast<Json>())
                [
                  Row(
                    children: [
                      Text(p['code'] as String, style: AlsText.body(13, weight: FontWeight.w900)),
                      if (p['isActive'] != true) const Padding(padding: EdgeInsets.only(left: 6), child: Badge2('ended')),
                    ],
                  ),
                  Text(p['channel'] as String),
                  Text((p['campaign'] as String?) ?? '—', overflow: TextOverflow.ellipsis),
                  Text('${p['uses']}'),
                  Text(money(p['netSalesCents'] as num)),
                  Text(money(p['discountCents'] as num)),
                  Text('${p['newCustomers']}'),
                  Text(p['returnOnDiscount'] == null ? '—' : r'$' + n(p['returnOnDiscount']).toStringAsFixed(2)),
                ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        ResponsiveRow(
          children: [
            Panel(
              title: 'Payment methods',
              child: RankedBars(
                rows: [
                  for (final p in (data['payments'] as List).cast<Json>())
                    RankedRow(p['key'] as String, n(p['orders']), '${p['orders']}', detail: money(p['netSalesCents'] as num)),
                ],
              ),
            ),
            Panel(
              title: 'How new customers heard about us',
              subtitle: 'Answers from app sign-up in this range',
              child: RankedBars(
                empty: 'No sign-ups in this range',
                rows: [
                  for (final c
                      in (data['channels'] as List).cast<Json>().where((c) => (c['signups'] as num) > 0).toList()
                        ..sort((a, b) => (b['signups'] as num).compareTo(a['signups'] as num)))
                    RankedRow(c['channel'] as String, n(c['signups']), '${c['signups']}'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _hour(int h) => '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? 'a' : 'p'}';
}

class _Delta extends StatelessWidget {
  const _Delta({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final up = value >= 0;
    final color = value == 0 ? AlsColors.muted : (up ? AlsColors.deltaGood : AlsColors.deltaBad);
    return Row(
      children: [
        Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16, color: color),
        Text(
          '${(value.abs() * 100).toStringAsFixed(1)}%',
          style: AlsText.body(14, color: color, weight: FontWeight.w900),
        ),
        const SizedBox(width: 6),
        Text(label, style: AlsText.body(12, color: AlsColors.muted)),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Row(
        children: [
          Expanded(child: Skeleton(height: 120)),
          SizedBox(width: 14),
          Expanded(child: Skeleton(height: 120)),
          SizedBox(width: 14),
          Expanded(child: Skeleton(height: 120)),
        ],
      ),
      SizedBox(height: 18),
      Skeleton(height: 340, radius: 22),
    ],
  );
}
