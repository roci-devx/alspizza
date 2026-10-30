import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/ui.dart';
import '../../state/ordering.dart';
import '../../widgets/places.dart';

/// "Find your nearest Al's": share location or type an address, then pick a store.
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  List<StoreInfo>? _stores;
  PlaceAddress? _address;
  bool _loading = false;
  String? _error;

  Future<void> _onAddress(PlaceAddress a) async {
    final ordering = context.read<OrderingStore>();
    setState(() {
      _address = a;
      _loading = true;
      _error = null;
    });
    try {
      await ordering.setAddress(a);
      final stores = await ordering.loadStores(lat: a.lat ?? ordering.here?.lat, lng: a.lng ?? ordering.here?.lng);
      if (mounted) setState(() => _stores = stores);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose(StoreInfo s) async {
    await context.read<OrderingStore>().setStore(s);
    if (mounted) context.go('/mode');
  }

  Future<void> _browse() async {
    final ordering = context.read<OrderingStore>();
    setState(() => _loading = true);
    try {
      final stores = await ordering.loadStores();
      if (stores.isNotEmpty) await ordering.setStore(stores.first);
      if (mounted) context.go('/mode');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stores = _stores;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/auth'),
                      icon: const Icon(Icons.arrow_back_rounded, color: AlsColors.brown),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _loading ? null : _browse,
                      child: Text(
                        'Just browsing',
                        style: AlsText.body(14, color: AlsColors.brownSoft, weight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                Center(child: RadarPin(size: 150, active: _loading || stores == null)),
                Text(stores == null ? 'Find your nearest Al’s' : 'Pick your Al’s', textAlign: TextAlign.center, style: AlsText.display(30)),
                const SizedBox(height: 6),
                Text(
                  stores == null
                      ? 'Share your location or type an address — we’ll match you with the closest kitchen.'
                      : 'Closest first. You can switch stores any time.',
                  textAlign: TextAlign.center,
                  style: AlsText.body(15, color: AlsColors.muted),
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: stores == null
                      ? AddressSearch(key: const ValueKey('search'), onSelected: _onAddress)
                      : Column(
                          key: const ValueKey('stores'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_address != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Row(
                                  children: [
                                    const Icon(Icons.place_rounded, color: AlsColors.orangeDeep, size: 20),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _address!.full,
                                        style: AlsText.body(14, weight: FontWeight.w800),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(() => _stores = null),
                                      child: Text(
                                        'Change',
                                        style: AlsText.body(14, color: AlsColors.orangeDeep, weight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            for (final (i, s) in stores.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Reveal(
                                  delay: Reveal.stagger(i, ms: 90),
                                  child: StoreCard(store: s, selected: i == 0, onTap: () => _choose(s)),
                                ),
                              ),
                          ],
                        ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AlsText.body(14, color: AlsColors.red),
                    ),
                  ),
                if (_loading && stores == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(child: CircularProgressIndicator(color: AlsColors.orange)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
