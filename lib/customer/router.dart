import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/account_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/deals_screen.dart';
import 'screens/home_screen.dart';
import 'screens/item_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/onboarding/auth_screen.dart';
import 'screens/onboarding/location_screen.dart';
import 'screens/onboarding/mode_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/shell.dart';
import 'screens/tracking_screen.dart';
import 'state/session.dart';

const _onboarding = {'/welcome', '/auth', '/location', '/mode'};

/// Slide-up modal transition (item builder, cart, checkout).
CustomTransitionPage<void> _sheetPage(GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 420),
  reverseTransitionDuration: const Duration(milliseconds: 320),
  transitionsBuilder: (context, animation, secondary, child) {
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curve),
      child: child,
    );
  },
);

/// Soft fade + scale for onboarding steps and full screens.
CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 450),
  transitionsBuilder: (context, animation, secondary, child) {
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curve), child: child),
    );
  },
);

GoRouter buildRouter(SessionStore session) => GoRouter(
  initialLocation: '/home',
  refreshListenable: session,
  redirect: (context, state) {
    final path = state.matchedLocation;
    final allowedBeforeOnboarding = _onboarding.contains(path) || path.startsWith('/order/');
    if (!session.onboarded && !allowedBeforeOnboarding) return '/welcome';
    return null;
  },
  routes: [
    GoRoute(path: '/welcome', pageBuilder: (c, s) => _fadePage(s, const WelcomeScreen())),
    GoRoute(
      path: '/auth',
      pageBuilder: (c, s) =>
          _fadePage(s, AuthScreen(signIn: s.uri.queryParameters['mode'] == 'signin', fromAccount: s.uri.queryParameters['from'] == 'account')),
    ),
    GoRoute(path: '/location', pageBuilder: (c, s) => _fadePage(s, const LocationScreen())),
    GoRoute(path: '/mode', pageBuilder: (c, s) => _fadePage(s, const ModeScreen())),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/home', builder: (c, s) => const HomeScreen())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/menu',
              builder: (c, s) => MenuScreen(category: s.uri.queryParameters['category']),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/deals', builder: (c, s) => const DealsScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/orders', builder: (c, s) => const OrdersScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/account', builder: (c, s) => const AccountScreen())],
        ),
      ],
    ),
    GoRoute(
      path: '/item/:id',
      pageBuilder: (c, s) => _sheetPage(s, ItemScreen(itemId: s.pathParameters['id']!)),
    ),
    GoRoute(path: '/cart', pageBuilder: (c, s) => _sheetPage(s, const CartScreen())),
    GoRoute(
      path: '/checkout',
      pageBuilder: (c, s) => _fadePage(s, CheckoutScreen(cancelledOrderId: s.uri.queryParameters['cancelled'])),
    ),
    GoRoute(
      path: '/order/:id',
      pageBuilder: (c, s) => _fadePage(
        s,
        TrackingScreen(
          orderId: s.pathParameters['id']!,
          justPaid: s.uri.queryParameters.containsKey('checkout') || s.uri.queryParameters.containsKey('paid') || s.uri.queryParameters.containsKey('new'),
        ),
      ),
      routes: [
        GoRoute(
          path: 'chat',
          pageBuilder: (c, s) => _sheetPage(s, ChatScreen(orderId: s.pathParameters['id']!)),
        ),
      ],
    ),
  ],
);
