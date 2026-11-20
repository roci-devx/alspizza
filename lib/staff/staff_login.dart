import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets/ui.dart';
import 'staff_session.dart';

/// Sign-in for Al's Kitchen and Al's Driver. The owner creates these logins in the owner app → Staff.
class StaffLoginPage extends StatefulWidget {
  const StaffLoginPage({super.key, required this.title, required this.subtitle, required this.icon, required this.accent});

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  State<StaffLoginPage> createState() => _StaffLoginPageState();
}

class _StaffLoginPageState extends State<StaffLoginPage> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  ({String email, String password})? _demo;

  @override
  void initState() {
    super.initState();
    context.read<StaffSession>().demoAccount().then((d) {
      if (mounted) setState(() => _demo = d);
    });
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_login.text.trim().length < 3 || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email or phone number and your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<StaffSession>().login(_login.text, _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AlsColors.cream,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AlsLogo(height: 96)),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: widget.accent, borderRadius: BorderRadius.circular(12)),
                      child: Icon(widget.icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Text(widget.title, style: AlsText.display(30)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(widget.subtitle, textAlign: TextAlign.center, style: AlsText.body(15, color: AlsColors.muted)),
                const SizedBox(height: 26),
                TextField(
                  controller: _login,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(hintText: 'Email or phone number', prefixIcon: Icon(Icons.person_outline_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(hintText: 'Password', prefixIcon: Icon(Icons.lock_outline_rounded)),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: AlsText.body(14, color: AlsColors.red)),
                  ),
                const SizedBox(height: 20),
                AlsButton(label: 'Sign in', loading: _busy, onPressed: _submit),
                if (_demo != null) ...[
                  const SizedBox(height: 12),
                  AlsButton(
                    label: 'Use demo account',
                    icon: Icons.bolt_rounded,
                    style: AlsButtonStyle.outline,
                    onPressed: _busy
                        ? null
                        : () {
                            _login.text = _demo!.email;
                            _password.text = _demo!.password;
                            _submit();
                          },
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'No login yet? The owner adds you in the Al’s Owner app → Staff.',
                  textAlign: TextAlign.center,
                  style: AlsText.body(13, color: AlsColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
