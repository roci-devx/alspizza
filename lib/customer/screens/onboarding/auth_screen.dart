import 'dart:math' as math;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/art/pizza_art.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/ui.dart';
import '../../state/catalog.dart';
import '../../state/session.dart';

/// Optional account creation. The X (top right) skips straight to ordering as a guest.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.signIn = false, this.fromAccount = false});

  final bool signIn;
  final bool fromAccount;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late bool _signIn = widget.signIn;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String? _source;
  String? _error;
  bool _busy = false;
  bool _showPassword = false;
  bool _triedSubmit = false;
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  static const _sources = ['Instagram', 'TikTok', 'Friend', 'Google', 'Flyer', 'Facebook', 'Other'];

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    _shake.dispose();
    super.dispose();
  }

  void _continue() {
    if (widget.fromAccount) {
      context.pop();
    } else {
      context.go('/location');
    }
  }

  Future<void> _submit() async {
    setState(() => _triedSubmit = true);
    if (!_form.currentState!.validate()) {
      _shake.forward(from: 0);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<SessionStore>();
    try {
      if (_signIn) {
        await session.signIn(_email.text.trim(), _password.text);
      } else {
        await session.register(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          phone: _phone.text.trim(),
          marketingSource: _source,
        );
      }
      if (!mounted) return;
      showToast(context, 'Welcome${session.user?.firstName.isNotEmpty == true ? ', ${session.user!.firstName}' : ''}! 🍕');
      if (session.onboarded && !widget.fromAccount) {
        context.go('/home');
      } else {
        _continue();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      _shake.forward(from: 0);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    try {
      await context.read<SessionStore>().ensureSession();
    } catch (_) {}
    if (mounted) _continue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TapScale(
                    onTap: _skip,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: alsShadow),
                      child: const Icon(Icons.close_rounded, color: AlsColors.brown),
                    ),
                  ),
                ),
                Center(
                  child: SizedBox.square(
                    dimension: 120,
                    child: Floaty(
                      child: Spin(child: PizzaArt(toppings: const ['pepperoni', 'mushroom', 'basil'], seed: 9)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(_signIn ? 'Welcome back!' : 'Join Al’s', key: ValueKey(_signIn), textAlign: TextAlign.center, style: AlsText.display(32)),
                ),
                const SizedBox(height: 6),
                Text(
                  _signIn ? 'Sign in to see your orders and saved favorites.' : 'Save your address, reorder favorites in one tap and get member-only deals.',
                  textAlign: TextAlign.center,
                  style: AlsText.body(15, color: AlsColors.muted),
                ),
                const SizedBox(height: 22),
                _Segmented(
                  signIn: _signIn,
                  onChanged: (v) => setState(() {
                    _signIn = v;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 20),
                AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) =>
                      Transform.translate(offset: Offset(math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value), 0), child: child),
                  child: Form(
                    key: _form,
                    autovalidateMode: _triedSubmit ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: Column(
                        children: [
                          if (!_signIn) ...[
                            TextFormField(
                              controller: _name,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(hintText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
                              validator: (v) => (v ?? '').trim().isEmpty ? 'What should we call you?' : null,
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
                            validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
                          ),
                          const SizedBox(height: 12),
                          if (!_signIn) ...[
                            TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(hintText: 'Mobile number (for order updates)', prefixIcon: Icon(Icons.phone_iphone_rounded)),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _password,
                            obscureText: !_showPassword,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                                onPressed: () => setState(() => _showPassword = !_showPassword),
                              ),
                            ),
                            validator: (v) => (v ?? '').length < (_signIn ? 1 : 8) ? (_signIn ? 'Enter your password' : 'Use at least 8 characters') : null,
                          ),
                          if (!_signIn) ...[
                            const SizedBox(height: 20),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('How did you hear about Al’s? (optional)', style: AlsText.body(14, weight: FontWeight.w800)),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final s in _sources)
                                  ChoicePill(label: s, selected: _source == s, onTap: () => setState(() => _source = _source == s ? null : s)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _error == null
                      ? const SizedBox(height: 16)
                      : Padding(
                          key: ValueKey(_error),
                          padding: const EdgeInsets.only(top: 14),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AlsColors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!, style: AlsText.body(14, color: AlsColors.red)),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                AlsButton(label: _signIn ? 'Sign in' : 'Create my account', loading: _busy, onPressed: _submit),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Continue as guest',
                    style: AlsText.body(15, color: AlsColors.brownSoft, weight: FontWeight.w800),
                  ),
                ),
                if (context.watch<CatalogStore>().demoCustomer case final demo?)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() {
                              _signIn = true;
                              _email.text = demo.email;
                              _password.text = demo.password;
                            });
                            _submit();
                          },
                    icon: const Icon(Icons.bolt_rounded, color: AlsColors.orangeDeep),
                    label: Text(
                      'Use the demo account',
                      style: AlsText.body(15, color: AlsColors.orangeDeep, weight: FontWeight.w900),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.signIn, required this.onChanged});

  final bool signIn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: AlsColors.creamDeep, borderRadius: BorderRadius.circular(25)),
    child: Stack(
      children: [
        AnimatedAlign(
          alignment: signIn ? Alignment.centerRight : Alignment.centerLeft,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: alsShadow),
            ),
          ),
        ),
        Row(
          children: [
            for (final (value, label) in const [(false, 'Create account'), (true, 'Sign in')])
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(value),
                  child: Center(
                    child: Text(
                      label,
                      style: AlsText.body(15, color: signIn == value ? AlsColors.brown : AlsColors.muted, weight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
