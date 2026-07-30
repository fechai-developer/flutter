import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';
import '../../features/auth/complete_profile_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/caixinha/caixinha_detail_screen.dart';
import '../../features/caixinha/caixinhas_list_screen.dart';
import '../../features/charge/settle_screen.dart';
import '../../features/groups/create_group_screen.dart';
import '../../features/groups/group_detail_screen.dart';
import '../../features/groups/groups_list_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/stats/indicators_screen.dart';
import '../../features/subscriptions/create_subscription_screen.dart';
import '../../features/subscriptions/subscription_detail_screen.dart';
import '../../features/subscriptions/subscriptions_list_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Adapta um Stream para Listenable, para o go_router reavaliar o redirect
/// quando a sessão muda (login/logout).
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final dynamic _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final client = SupabaseConfig.backendActive ? Supabase.instance.client : null;

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/onboarding',
    // Reage a login/logout para reavaliar o redirect (só com backend ligado).
    refreshListenable:
        client != null ? _StreamListenable(client.auth.onAuthStateChange) : null,
    redirect: (context, state) {
      if (client == null) return null; // sem backend: fluxo livre (mock)
      final loggedIn = client.auth.currentSession != null;
      // Deslogado só pode ficar no onboarding. Logado: a própria tela de
      // onboarding decide o pós-login (termo → completar perfil → home), então
      // não forçamos /home aqui (evita corrida com esse fluxo).
      if (!loggedIn && state.matchedLocation != '/onboarding') return '/onboarding';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/complete-profile',
        builder: (context, state) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      // Shell com navegação persistente (abas — DESIGN_SYSTEM.md).
      StatefulShellRoute.indexedStack(
        builder: (context, state, navShell) => AppShell(navigationShell: navShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/charge', builder: (context, state) => const SettleScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/groups',
              builder: (context, state) => const GroupsListScreen(),
              routes: [
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) => const CreateGroupScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) =>
                      GroupDetailScreen(groupId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/subscriptions',
              builder: (context, state) => const SubscriptionsListScreen(),
              routes: [
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) => const CreateSubscriptionScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) =>
                      SubscriptionDetailScreen(subscriptionId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/caixinhas',
              builder: (context, state) => const CaixinhasListScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) => CaixinhaDetailScreen(
                    caixinhaId: state.pathParameters['id']!,
                    showGuide: state.uri.queryParameters['guide'] == '1',
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/resumo', builder: (context, state) => const IndicatorsScreen()),
          ]),
        ],
      ),
    ],
  );
});
