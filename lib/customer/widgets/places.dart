import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../state/ordering.dart';

/// Animated map pin with radar rings — "finding your nearest Al's".
class RadarPin extends StatefulWidget {
  const RadarPin({super.key, this.size = 160, this.active = true});

  final double size;
  final bool active;

  @override
  State<RadarPin> createState() => _RadarPinState();
}

class _RadarPinState extends State<RadarPin> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _RadarPainter(widget.active ? _c.value : 0),
        child: Center(
          child: Transform.translate(
            offset: Offset(0, -widget.size * 0.12 - (widget.active ? (1 - (2 * _c.value - 1).abs()) * 8 : 0)),
            child: Icon(
              Icons.location_on_rounded,
              size: widget.size * 0.42,
              color: AlsColors.red,
              shadows: const [Shadow(color: Color(0x445A210F), blurRadius: 10, offset: Offset(0, 6))],
            ),
          ),
        ),
      ),
    ),
  );
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.62);
    canvas.drawOval(Rect.fromCenter(center: c, width: size.width * 0.3, height: size.width * 0.1), Paint()..color = const Color(0x335A210F));
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      canvas.drawOval(
        Rect.fromCenter(center: c, width: size.width * (0.25 + p * 0.75), height: size.width * (0.08 + p * 0.25)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AlsColors.orange.withValues(alpha: (1 - p) * 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t;
}

/// Search-as-you-pause address lookup with "use my location" and a manual fallback.
class AddressSearch extends StatefulWidget {
  const AddressSearch({super.key, required this.onSelected, this.showLocate = true, this.autofocus = false});

  final ValueChanged<PlaceAddress> onSelected;
  final bool showLocate;
  final bool autofocus;

  @override
  State<AddressSearch> createState() => _AddressSearchState();
}

class _AddressSearchState extends State<AddressSearch> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<PlaceAddress> _results = const [];
  bool _searching = false;
  bool _locating = false;
  bool _manual = false;
  String? _message;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 6) return;
    _debounce = Timer(const Duration(milliseconds: 750), () => _search(v));
  }

  Future<void> _search(String v) async {
    setState(() {
      _searching = true;
      _message = null;
    });
    try {
      final results = await context.read<OrderingStore>().search(v.trim());
      if (!mounted) return;
      setState(() {
        _results = results;
        _message = results.isEmpty ? 'We couldn’t find that one. Try adding the city or ZIP — or enter it manually.' : null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _locate() async {
    final ordering = context.read<OrderingStore>();
    setState(() {
      _locating = true;
      _message = null;
    });
    try {
      final here = await ordering.locate();
      if (here == null) return;
      final address = await ordering.reverse(here.lat, here.lng);
      if (!mounted) return;
      widget.onSelected(address ?? PlaceAddress(line1: 'Current location', city: '', state: '', zip: '', lat: here.lat, lng: here.lng));
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'We couldn’t get your location. Type your address instead.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showLocate) ...[
          AlsButton(label: 'Use my current location', icon: Icons.my_location_rounded, loading: _locating, onPressed: _locate),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: AlsText.body(13, color: AlsColors.muted)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (!_manual)
          TextField(
            controller: _q,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Street address, city or ZIP',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
                    )
                  : null,
            ),
          )
        else
          _ManualAddress(onDone: widget.onSelected),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_message!, style: AlsText.body(13, color: AlsColors.brownSoft)),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          child: Column(
            children: [
              for (final (i, r) in _results.indexed)
                Reveal(
                  delay: Reveal.stagger(i, ms: 40),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const CircleAvatar(
                      backgroundColor: AlsColors.creamDeep,
                      child: Icon(Icons.place_rounded, color: AlsColors.orangeDeep),
                    ),
                    title: Text(r.line1, style: AlsText.body(15, weight: FontWeight.w800)),
                    subtitle: Text([r.city, r.state, r.zip].where((x) => x.isNotEmpty).join(', '), style: AlsText.body(13, color: AlsColors.muted)),
                    onTap: () => widget.onSelected(r),
                  ),
                ),
            ],
          ),
        ),
        if (!_manual)
          TextButton(
            onPressed: () => setState(() => _manual = true),
            child: Text(
              'Enter address manually',
              style: AlsText.body(14, color: AlsColors.orangeDeep, weight: FontWeight.w800),
            ),
          ),
      ],
    );
  }
}

class _ManualAddress extends StatefulWidget {
  const _ManualAddress({required this.onDone});

  final ValueChanged<PlaceAddress> onDone;

  @override
  State<_ManualAddress> createState() => _ManualAddressState();
}

class _ManualAddressState extends State<_ManualAddress> {
  final _form = GlobalKey<FormState>();
  final _line1 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _zip = TextEditingController();

  @override
  void dispose() {
    for (final c in [_line1, _city, _state, _zip]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;
    return Form(
      key: _form,
      child: Column(
        children: [
          TextFormField(
            controller: _line1,
            decoration: const InputDecoration(hintText: 'Street address'),
            validator: required,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _city,
                  decoration: const InputDecoration(hintText: 'City'),
                  validator: required,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _state,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'State'),
                  validator: required,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _zip,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'ZIP code'),
            validator: required,
          ),
          const SizedBox(height: 14),
          AlsButton(
            label: 'Use this address',
            style: AlsButtonStyle.dark,
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              widget.onDone(PlaceAddress(line1: _line1.text.trim(), city: _city.text.trim(), state: _state.text.trim().toUpperCase(), zip: _zip.text.trim()));
            },
          ),
        ],
      ),
    );
  }
}

class StoreCard extends StatelessWidget {
  const StoreCard({super.key, required this.store, this.selected = false, this.onTap});

  final StoreInfo store;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => CardBox(
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    border: Border.all(color: selected ? AlsColors.orange : Colors.transparent, width: 2),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: store.isOpen ? AlsColors.orange.withValues(alpha: 0.2) : AlsColors.creamDeep,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.storefront_rounded, color: AlsColors.brown),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(store.shortName, style: AlsText.display(18)),
              const SizedBox(height: 2),
              Text(store.address.line1, style: AlsText.body(13, color: AlsColors.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Dot(color: store.isOpen ? AlsColors.success : AlsColors.red),
                  Text(
                    store.isOpen ? 'Open · ${store.hoursToday}' : 'Closed now',
                    style: AlsText.body(12, color: store.isOpen ? AlsColors.success : AlsColors.red, weight: FontWeight.w800),
                  ),
                  if (store.pickupEtaMinutes != null) Text('· Ready in ~${store.pickupEtaMinutes} min', style: AlsText.body(12, color: AlsColors.muted)),
                ],
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (store.distanceMiles != null) Text('${store.distanceMiles!.toStringAsFixed(1)} mi', style: AlsText.display(16, color: AlsColors.orangeDeep)),
            if (store.deliversToYou == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Tag('DELIVERS', color: AlsColors.basil.withValues(alpha: 0.9)),
              ),
          ],
        ),
      ],
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

Future<T?> showAlsSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AlsColors.cream,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
  builder: (ctx) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(color: AlsColors.line, borderRadius: BorderRadius.circular(3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
            child: Row(
              children: [
                Expanded(child: Text(title, style: AlsText.display(22))),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded, color: AlsColors.brown),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: builder(ctx)),
          ),
        ],
      ),
    ),
  ),
);

Future<PlaceAddress?> pickAddress(BuildContext context) => showAlsSheet<PlaceAddress>(
  context,
  title: 'Delivery address',
  builder: (ctx) => AddressSearch(autofocus: false, onSelected: (a) => Navigator.pop(ctx, a)),
);

Future<StoreInfo?> pickStore(BuildContext context) async {
  final ordering = context.read<OrderingStore>();
  final here = ordering.here;
  final stores = ordering.nearby.isNotEmpty ? ordering.nearby : await ordering.loadStores(lat: here?.lat, lng: here?.lng);
  if (!context.mounted) return null;
  return showAlsSheet<StoreInfo>(
    context,
    title: 'Choose your Al’s',
    builder: (ctx) => Column(
      children: [
        for (final (i, s) in stores.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Reveal(
              delay: Reveal.stagger(i),
              child: StoreCard(store: s, selected: s.id == ordering.store?.id, onTap: () => Navigator.pop(ctx, s)),
            ),
          ),
      ],
    ),
  );
}
