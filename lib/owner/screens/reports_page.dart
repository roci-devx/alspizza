import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../owner_store.dart';
import '../widgets/owner_ui.dart';

/// End-of-day Excel reports: generated automatically each night, or on demand.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  List<Json> _reports = [];
  bool _loading = true;
  bool _generating = false;
  String? _scope;
  DateTime _date = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.watch<OwnerStore>().storeId;
    if (scope != _scope) {
      _scope = scope;
      _load();
    }
  }

  Future<void> _load() async {
    final s = context.read<OwnerStore>();
    final res = await s.api.get('/owner/reports', query: {'storeId': s.storeId});
    if (mounted) {
      setState(() {
        _reports = ((res['reports'] as List?) ?? const []).cast<Json>();
        _loading = false;
      });
    }
  }

  Future<void> _download(Json r) async {
    try {
      final link = await context.read<OwnerStore>().api.get('/owner/reports/${r['id']}/link');
      await launchUrl(
        Uri.parse(link['url'] as String),
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _generate() async {
    final s = context.read<OwnerStore>();
    final stores = s.storeId == 'all' ? s.stores : s.stores.where((x) => x.id == s.storeId).toList();
    setState(() => _generating = true);
    try {
      for (final store in stores) {
        await s.api.post('/owner/reports', {'storeId': store.id, 'date': DateFormat('yyyy-MM-dd').format(_date)});
      }
      await _load();
      if (mounted) showToast(context, 'Report${stores.length > 1 ? 's' : ''} ready for ${DateFormat('MMM d').format(_date)}');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) => OwnerPageScaffold(
    title: 'Reports',
    subtitle: 'An Excel workbook per store per day: summary, every order, items, promo codes, hourly sales and payments',
    showRange: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          title: 'Generate a report',
          subtitle: 'Reports also build automatically at each store’s closing-report time (Settings → Reports) and email out if SMTP is configured.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                    initialDate: _date,
                  );
                  if (d != null) setState(() => _date = d);
                },
                icon: const Icon(Icons.event_rounded),
                label: Text(DateFormat('EEE, MMM d, yyyy').format(_date), style: AlsText.body(14, weight: FontWeight.w800)),
              ),
              AlsButton(label: 'Generate .xlsx', icon: Icons.table_chart_rounded, expand: false, height: 46, loading: _generating, onPressed: _generate),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          title: 'Daily reports',
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AlsColors.orange))
              : SimpleTable(
                  columns: const ['Date', 'Store', 'Orders', 'Net sales', 'Avg order', 'New cust.', 'Courier fees', 'Generated', ''],
                  numeric: const {2, 3, 4, 5, 6},
                  flex: const [2, 2, 1, 2, 2, 1, 2, 2, 2],
                  rows: [
                    for (final r in _reports)
                      [
                        Text(DateFormat('EEE, MMM d').format(DateTime.parse(r['date'] as String)), style: AlsText.body(13, weight: FontWeight.w900)),
                        Text((r['storeName'] as String).split('—').last.trim()),
                        Text('${(r['summary'] as Json)['orders'] ?? 0}'),
                        Text(money(((r['summary'] as Json)['netSalesCents'] as num?) ?? 0)),
                        Text(money(((r['summary'] as Json)['aovCents'] as num?) ?? 0)),
                        Text('${(r['summary'] as Json)['newCustomers'] ?? 0}'),
                        Text(money(((r['summary'] as Json)['courierFeesCents'] as num?) ?? 0)),
                        Text(ago(DateTime.parse(r['createdAt'] as String))),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _download(r),
                            icon: const Icon(Icons.download_rounded, size: 18, color: AlsColors.orangeDeep),
                            label: Text(
                              'Excel',
                              style: AlsText.body(13, color: AlsColors.orangeDeep, weight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                  ],
                ),
        ),
      ],
    ),
  );
}
