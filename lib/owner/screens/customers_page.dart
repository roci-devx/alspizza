import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../owner_store.dart';
import '../widgets/owner_ui.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  List<Json> _rows = [];
  bool _loading = true;
  String? _scope;
  String _q = '';
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.watch<OwnerStore>().storeId;
    if (scope != _scope) {
      _scope = scope;
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = context.read<OwnerStore>();
    setState(() => _loading = true);
    final res = await s.api.get('/owner/customers', query: {'storeId': s.storeId, 'q': _q.isEmpty ? null : _q});
    if (mounted) {
      setState(() {
        _rows = ((res['customers'] as List?) ?? const []).cast<Json>();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repeat = _rows.where((r) => r['repeat'] == true).length;
    return OwnerPageScaffold(
      title: 'Customers',
      subtitle: '${_rows.length} customers · $repeat ordered more than once',
      showRange: false,
      child: Panel(
        title: 'Everyone who has ordered',
        subtitle: 'Matched by phone number, so guests and account holders line up',
        trailing: isCompact(context) ? null : SizedBox(width: 260, child: _search()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isCompact(context)) Padding(padding: const EdgeInsets.only(bottom: 12), child: _search()),
            AnimatedOpacity(
              opacity: _loading ? 0.5 : 1,
              duration: const Duration(milliseconds: 200),
              child: SimpleTable(
                columns: const ['Customer', 'Phone', 'Orders', 'Net sales', 'First order', 'Last order', 'Heard about us', 'Type'],
                numeric: const {2, 3},
                flex: const [3, 2, 1, 2, 2, 2, 2, 1],
                rows: [
                  for (final r in _rows.take(300))
                    [
                      Row(
                        children: [
                          Flexible(child: Text(r['name'] as String, overflow: TextOverflow.ellipsis)),
                          if (r['repeat'] == true)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Badge2('REPEAT', color: AlsColors.basil),
                            ),
                        ],
                      ),
                      Text(r['phone'] == null ? '—' : prettyPhone(r['phone'] as String)),
                      Text('${r['orders']}'),
                      Text(money(r['netSalesCents'] as num)),
                      Text(dayLabel(DateTime.parse(r['firstOrderAt'] as String))),
                      Text(ago(DateTime.parse(r['lastOrderAt'] as String))),
                      Text((r['source'] as String?) ?? '—'),
                      Text(r['registered'] == true ? 'Account' : 'Guest'),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _search() => TextField(
    onChanged: (v) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () {
        _q = v.trim();
        _load();
      });
    },
    decoration: const InputDecoration(hintText: 'Search name, phone, email', prefixIcon: Icon(Icons.search_rounded), isDense: true),
  );
}
