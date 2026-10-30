import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/art/pizza_art.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../owner_store.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  ({String email, String password})? _demo;

  @override
  void initState() {
    super.initState();
    context.read<OwnerStore>().demoAccount().then((d) {
      if (mounted) setState(() => _demo = d);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim()) || _password.text.isEmpty) {
      setState(() => _error = 'Enter your owner email and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<OwnerStore>().login(_email.text.trim(), _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final form = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) const Center(child: AlsLogo(height: 110)),
              Text('Owner sign in', style: AlsText.display(32)),
              const SizedBox(height: 4),
              Text('Orders, sales and reports for every Al’s location.', style: AlsText.body(15, color: AlsColors.muted)),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(hintText: 'Password', prefixIcon: Icon(Icons.lock_outline_rounded)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: AlsText.body(14, color: AlsColors.red)),
                ),
              const SizedBox(height: 20),
              AlsButton(label: 'Sign in', loading: _busy, onPressed: _login),
              if (_demo != null) ...[
                const SizedBox(height: 12),
                AlsButton(
                  label: 'Use demo account',
                  icon: Icons.bolt_rounded,
                  style: AlsButtonStyle.outline,
                  onPressed: _busy
                      ? null
                      : () {
                          _email.text = _demo!.email;
                          _password.text = _demo!.password;
                          _login();
                        },
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      body: Row(
        children: [
          if (wide)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF8A3B1F), Color(0xFF3B1508)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Stack(
                  children: [
                    const Positioned(
                      right: -120,
                      bottom: -120,
                      child: SizedBox.square(
                        dimension: 520,
                        child: Spin(child: PizzaArt(toppings: ['pepperoni', 'mushroom', 'basil'], seed: 12)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: AlsColors.cream, borderRadius: BorderRadius.circular(24)),
                            child: const AlsLogo(height: 110),
                          ),
                          const Spacer(),
                          Text('Every order.\nEvery store.\nLive.', style: AlsText.display(52, color: AlsColors.cream)),
                          const SizedBox(height: 14),
                          Text(
                            'Live kitchen board · sales & marketing analytics · nightly Excel reports',
                            style: AlsText.body(16, color: AlsColors.orangeLight),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: form),
        ],
      ),
    );
  }
}
