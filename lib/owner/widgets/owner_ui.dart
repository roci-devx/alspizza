import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../owner_store.dart';

/// Phones get a bottom tab bar and card layouts instead of the sidebar and wide tables.
bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 700;

/// Standard page: title row, one shared filter row, scrollable content.
class OwnerPageScaffold extends StatelessWidget {
  const OwnerPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
    this.showFilters = true,
    this.showRange = true,
    this.allowAllStores = true,
    this.scroll = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final bool showFilters;
  final bool showRange;
  final bool allowAllStores;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final pad = compact ? 16.0 : 28.0;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(pad, compact ? 12 : 24, pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // On phones the app bar already shows the page name.
                    if (!compact) Text(title, style: AlsText.display(30)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: AlsText.body(compact ? 13 : 14, color: AlsColors.muted)),
                      ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          if (showFilters) ...[const SizedBox(height: 16), FilterBar(showRange: showRange, allowAll: allowAllStores)],
          const SizedBox(height: 18),
        ],
      ),
    );
    if (!scroll) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(child: child),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        header,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: child,
        ),
      ],
    );
  }
}

class FilterBar extends StatelessWidget {
  const FilterBar({super.key, this.showRange = true, this.allowAll = true});

  final bool showRange;
  final bool allowAll;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OwnerStore>();
    final value = !allowAll && s.storeId == 'all' && s.stores.isNotEmpty ? s.stores.first.id : s.storeId;
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AlsColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              icon: const Icon(Icons.expand_more_rounded),
              style: AlsText.body(14, weight: FontWeight.w800),
              borderRadius: BorderRadius.circular(14),
              items: [
                if (allowAll) DropdownMenuItem(value: 'all', child: Text('All stores (${s.stores.length})')),
                for (final st in s.stores) DropdownMenuItem(value: st.id, child: Text(st.shortName)),
              ],
              onChanged: (v) => s.setStore(v ?? 'all'),
            ),
          ),
        ),
        if (showRange)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AlsColors.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in RangePreset.values)
                    GestureDetector(
                      onTap: () async {
                        if (p != RangePreset.custom) return s.setRange(p);
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: now.subtract(const Duration(days: 365 * 2)),
                          lastDate: now,
                          initialDateRange: s.customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 13)), end: now),
                        );
                        if (picked != null) s.setRange(RangePreset.custom, picked);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: s.range == p ? AlsColors.brown : Colors.transparent, borderRadius: BorderRadius.circular(11)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (p == RangePreset.custom) Icon(Icons.date_range_rounded, size: 15, color: s.range == p ? AlsColors.cream : AlsColors.brownSoft),
                            if (p == RangePreset.custom) const SizedBox(width: 4),
                            Text(
                              p == RangePreset.custom && s.range == p ? s.rangeLabel : p.label,
                              style: AlsText.body(13, color: s.range == p ? AlsColors.cream : AlsColors.brownSoft, weight: FontWeight.w800),
                            ),
                          ],
                        ),
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

/// White card with a title, optional subtitle, and an optional Chart ⇄ Table switch.
class Panel extends StatefulWidget {
  const Panel({super.key, required this.title, this.subtitle, required this.child, this.table, this.trailing, this.padding = const EdgeInsets.all(20)});

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? table;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  bool _table = false;

  @override
  Widget build(BuildContext context) => Container(
    padding: widget.padding,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: alsShadow),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: AlsText.display(18, weight: FontWeight.w600)),
                  if (widget.subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(widget.subtitle!, style: AlsText.body(12, color: AlsColors.muted)),
                    ),
                ],
              ),
            ),
            ?widget.trailing,
            if (widget.table != null)
              TextButton.icon(
                onPressed: () => setState(() => _table = !_table),
                icon: Icon(_table ? Icons.bar_chart_rounded : Icons.table_rows_rounded, size: 18, color: AlsColors.brownSoft),
                label: Text(
                  _table ? 'Chart' : 'Table',
                  style: AlsText.body(12, color: AlsColors.brownSoft, weight: FontWeight.w800),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(key: ValueKey(_table), child: _table ? widget.table! : widget.child),
        ),
      ],
    ),
  );
}

/// Lightweight striped table (tabular figures in number columns).
class SimpleTable extends StatelessWidget {
  const SimpleTable({super.key, required this.columns, required this.rows, this.numeric = const {}, this.flex});

  final List<String> columns;
  final List<List<Widget>> rows;
  final Set<int> numeric;
  final List<int>? flex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) => box.maxWidth < 560 ? _cards() : _table());

  /// Phone layout: first column is the card title, the rest become label/value lines.
  Widget _cards() => Column(
    children: [
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Nothing here yet', style: AlsText.body(13, color: AlsColors.muted)),
        ),
      for (final (r, row) in rows.indexed)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: r.isOdd ? const Color(0xFFFBF7F0) : const Color(0xFFFDFBF7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AlsColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DefaultTextStyle(
                style: AlsText.body(14, weight: FontWeight.w900),
                child: row.first,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  for (final (i, c) in row.indexed.skip(1))
                    if (columns.length > i && columns[i].isNotEmpty)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(columns[i].toUpperCase(), style: AlsText.label(9)),
                          DefaultTextStyle(
                            style: AlsText.body(13, weight: FontWeight.w700),
                            child: c,
                          ),
                        ],
                      )
                    else
                      c,
                ],
              ),
            ],
          ),
        ),
    ],
  );

  Widget _table() {
    Widget cell(int i, Widget child, {bool head = false}) => Expanded(
      flex: flex?[i] ?? 1,
      child: Align(
        alignment: numeric.contains(i) ? Alignment.centerRight : Alignment.centerLeft,
        child: DefaultTextStyle(
          style: head ? AlsText.label(11) : AlsText.body(13, weight: FontWeight.w700).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          child: child,
        ),
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [for (final (i, c) in columns.indexed) cell(i, Text(c.toUpperCase()), head: true)]),
        ),
        const Divider(height: 1),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Nothing here yet', style: AlsText.body(13, color: AlsColors.muted)),
          ),
        for (final (r, row) in rows.indexed)
          Container(
            color: r.isOdd ? const Color(0xFFFBF7F0) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(children: [for (final (i, c) in row.indexed) cell(i, c)]),
          ),
      ],
    );
  }
}

class Badge2 extends StatelessWidget {
  const Badge2(this.text, {super.key, this.color = AlsColors.brownSoft, this.filled = false, this.icon});

  final String text;
  final Color color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: filled ? color : color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: filled ? Colors.white : color), const SizedBox(width: 4)],
        Text(
          text,
          style: AlsText.body(11, color: filled ? Colors.white : color, weight: FontWeight.w900),
        ),
      ],
    ),
  );
}

String providerLabel(String? p) => switch (p) {
  'doordash' => 'DoorDash',
  'uber' => 'Uber Direct',
  'own' => 'Own driver',
  'simulated' => 'Courier (demo)',
  'unassigned' => 'Unassigned',
  _ => p ?? '—',
};

String platformLabel(String? p) => switch (p) {
  'ios' => 'iOS',
  'android' => 'Android',
  'web' => 'Web',
  _ => p ?? '—',
};

/// Two-column responsive row: side by side on wide screens, stacked on narrow ones.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({super.key, required this.children, this.flex, this.breakpoint = 980, this.gap = 18});

  final List<Widget> children;
  final List<int>? flex;
  final double breakpoint;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, c) in children.indexed) ...[if (i > 0) SizedBox(height: gap), c],
          ],
        );
      }
      // Top-aligned rather than IntrinsicHeight: charts use LayoutBuilder, which can't report intrinsic sizes.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, c) in children.indexed) ...[if (i > 0) SizedBox(width: gap), Expanded(flex: flex?[i] ?? 1, child: c)],
        ],
      );
    },
  );
}
