import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../theme.dart';

/// Squishes on press like a physical button. Wrap anything tappable with it.
class TapScale extends StatefulWidget {
  const TapScale({super.key, required this.child, this.onTap, this.scale = 0.95, this.haptic = true});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => _set(true),
    onTapCancel: () => _set(false),
    onTapUp: (_) => _set(false),
    onTap: widget.onTap == null
        ? null
        : () {
            if (widget.haptic) HapticFeedback.selectionClick();
            widget.onTap!();
          },
    child: AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: Duration(milliseconds: _down ? 90 : 220),
      curve: _down ? Curves.easeOut : Curves.easeOutBack,
      child: widget.child,
    ),
  );
}

enum AlsButtonStyle { primary, dark, outline, ghost }

class AlsButton extends StatelessWidget {
  const AlsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.style = AlsButtonStyle.primary,
    this.loading = false,
    this.trailing,
    this.height = 56,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AlsButtonStyle style;
  final bool loading;
  final Widget? trailing;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final (bg, fg, border) = switch (style) {
      AlsButtonStyle.primary => (null, AlsColors.brown, Colors.transparent),
      AlsButtonStyle.dark => (AlsColors.brown, AlsColors.cream, Colors.transparent),
      AlsButtonStyle.outline => (Colors.white, AlsColors.brown, AlsColors.line),
      AlsButtonStyle.ghost => (Colors.transparent, AlsColors.brown, Colors.transparent),
    };
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: trailing == null ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.6, color: fg))
            else if (icon != null)
              Icon(icon, color: fg, size: 22),
            if (loading || icon != null) const SizedBox(width: 10),
            Text(
              label,
              style: AlsText.display(18, color: fg, weight: FontWeight.w600),
            ),
          ],
        ),
        ?trailing,
      ],
    );
    return TapScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled || loading ? 1 : 0.45,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: bg,
            gradient: style == AlsButtonStyle.primary ? const LinearGradient(colors: [AlsColors.orangeLight, AlsColors.orange]) : null,
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: border, width: 1.5),
            boxShadow: style == AlsButtonStyle.primary || style == AlsButtonStyle.dark
                ? const [BoxShadow(color: Color(0x335A210F), blurRadius: 16, offset: Offset(0, 6))]
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Price text that bumps and cross-fades when the value changes.
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney(this.cents, {super.key, this.style});

  final int cents;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 280),
    transitionBuilder: (child, anim) => ScaleTransition(
      scale: Tween(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
      child: FadeTransition(opacity: anim, child: child),
    ),
    child: Text(money(cents), key: ValueKey(cents), style: style ?? AlsText.display(18)),
  );
}

/// Fades and slides its child in after [delay]. Use with increasing delays for stagger.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.12),
    this.duration = const Duration(milliseconds: 520),
  });

  final Widget child;
  final Duration delay;
  final Offset offset;
  final Duration duration;

  static Duration stagger(int index, {int ms = 55, int max = 10}) => Duration(milliseconds: ms * (index.clamp(0, max)));

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration);
  late final _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(
      position: Tween(begin: widget.offset, end: Offset.zero).animate(_curve),
      child: widget.child,
    ),
  );
}

/// Gentle endless bob (used on hero illustrations).
class Floaty extends StatefulWidget {
  const Floaty({super.key, required this.child, this.amplitude = 6, this.period = const Duration(milliseconds: 2600), this.rotate = 0.0});

  final Widget child;
  final double amplitude;
  final Duration period;
  final double rotate;

  @override
  State<Floaty> createState() => _FloatyState();
}

class _FloatyState extends State<Floaty> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      final t = Curves.easeInOut.transform(_c.value);
      return Transform.translate(
        offset: Offset(0, -widget.amplitude + t * widget.amplitude * 2),
        child: Transform.rotate(angle: (t - 0.5) * widget.rotate, child: child),
      );
    },
    child: widget.child,
  );
}

/// Slow continuous spin (pizza on the builder, loading states).
class Spin extends StatefulWidget {
  const Spin({super.key, required this.child, this.period = const Duration(seconds: 40)});

  final Widget child;
  final Duration period;

  @override
  State<Spin> createState() => _SpinState();
}

class _SpinState extends State<Spin> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: widget.child);
}

class AlsLogo extends StatelessWidget {
  const AlsLogo({super.key, this.height = 48});

  final double height;

  @override
  Widget build(BuildContext context) => Image.asset('assets/images/logo_mark_640.png', height: height, filterQuality: FilterQuality.medium);
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.action, this.onAction});

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 12, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AlsText.display(22)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: AlsText.body(13, color: AlsColors.muted)),
                ),
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              action!,
              style: AlsText.body(14, color: AlsColors.orangeDeep, weight: FontWeight.w800),
            ),
          ),
      ],
    ),
  );
}

/// Selectable pill used for sizes, crusts, sauces, flavors…
class ChoicePill extends StatelessWidget {
  const ChoicePill({super.key, required this.label, required this.selected, this.onTap, this.sublabel, this.leading, this.enabled = true});

  final String label;
  final String? sublabel;
  final bool selected;
  final bool enabled;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TapScale(
    onTap: enabled ? onTap : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(leading == null ? 16 : 8, 10, 16, 10),
      decoration: BoxDecoration(
        color: selected ? AlsColors.brown : (enabled ? Colors.white : AlsColors.creamDeep),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? AlsColors.brown : AlsColors.line, width: 1.5),
        boxShadow: selected ? const [BoxShadow(color: Color(0x335A210F), blurRadius: 12, offset: Offset(0, 4))] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AlsText.body(14, color: selected ? AlsColors.cream : (enabled ? AlsColors.ink : AlsColors.muted), weight: FontWeight.w800),
              ),
              if (sublabel != null)
                Text(
                  sublabel!,
                  style: AlsText.body(12, color: selected ? AlsColors.orangeLight : AlsColors.muted, weight: FontWeight.w700),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 25, this.compact = false});

  final int value;
  final int min;
  final int max;
  final bool compact;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 40.0;
    Widget btn(IconData icon, int next, bool enabled) => TapScale(
      onTap: enabled ? () => onChanged(next) : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: enabled ? AlsColors.brown : AlsColors.line, shape: BoxShape.circle),
        child: Icon(icon, size: compact ? 16 : 20, color: AlsColors.cream),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(value <= min && min == 0 ? Icons.delete_outline_rounded : Icons.remove_rounded, value - 1, value > min),
        SizedBox(
          width: compact ? 30 : 40,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Text('$value', key: ValueKey(value), textAlign: TextAlign.center, style: AlsText.display(compact ? 16 : 20)),
          ),
        ),
        btn(Icons.add_rounded, value + 1, value < max),
      ],
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = AlsColors.red, this.textColor = Colors.white});

  final String text;
  final Color color;
  final Color textColor;

  factory Tag.forKey(String key) => switch (key) {
    'popular' => const Tag('POPULAR', color: AlsColors.red),
    'new' => const Tag('NEW', color: AlsColors.basil),
    'spicy' => const Tag('SPICY', color: Color(0xFFE0592A)),
    'veg' => const Tag('VEGGIE', color: Color(0xFF5E8C31)),
    _ => Tag(key.toUpperCase(), color: AlsColors.brownSoft),
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: AlsText.label(10, color: textColor)),
  );
}

/// Pulsing placeholder while content loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 12});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
    child: Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(color: AlsColors.creamDeep, borderRadius: BorderRadius.circular(widget.radius)),
    ),
  );
}

class CardBox extends StatelessWidget {
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
    this.radius = 24,
    this.onTap,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final VoidCallback? onTap;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), boxShadow: alsShadow, border: border),
      child: child,
    );
    return onTap == null ? box : TapScale(onTap: onTap, scale: 0.98, child: box);
  }
}

void showToast(BuildContext context, String message, {IconData icon = Icons.check_circle_rounded}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 1800),
      content: Row(
        children: [
          Icon(icon, color: AlsColors.orangeLight),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

void showError(BuildContext context, Object error) => showToast(context, error.toString(), icon: Icons.error_outline_rounded);
