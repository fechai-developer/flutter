import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/icons.dart';

import '../../core/widgets/brand_mark.dart';
import '../../data/models/person.dart';
import '../../data/realtime/realtime_sync.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

/// Casca de navegação. Mobile: bottom tabs (4 itens). Web/tela larga: sidebar
/// equivalente (DESIGN_SYSTEM.md). O breakpoint troca automaticamente.
///
/// É aqui que a sincronização em tempo real fica "viva": enquanto o shell está
/// montado, `realtimeSyncProvider` mantém o canal do Supabase aberto. Ao voltar
/// do background (`resumed`), recarregamos os dados colaborativos — cobre o
/// intervalo em que o socket ficou dormindo.
class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  static const _destinations = [
    _Dest('Início', AppIcons.waveSine, AppIconsFill.waveSine),
    _Dest('Acertar', AppIcons.payments, AppIconsFill.payments),
    _Dest('Contas', AppIcons.usersThree, AppIconsFill.usersThree),
    _Dest('Assinaturas', AppIcons.repeat, AppIconsFill.repeat),
    _Dest('Caixinha', AppIcons.piggyBank, AppIconsFill.piggyBank),
  ];

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  /// Momento em que o app foi para segundo plano de verdade (paused/hidden).
  /// Usado para decidir se vale recarregar ao voltar.
  DateTime? _backgroundedAt;

  /// Só recarrega ao voltar se ficou fora por mais que isto — enquanto ativo, o
  /// Realtime já mantém tudo em dia. Evita o "piscar" a cada foco de janela.
  static const _resyncThreshold = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    // No desktop/web um simples alt-tab dispara `resumed` (às vezes sem passar
    // por paused/hidden). Só recarregamos após um background REAL e longo — o
    // suficiente para o Realtime possivelmente ter perdido eventos.
    final away = _backgroundedAt;
    _backgroundedAt = null;
    if (away == null || DateTime.now().difference(away) < _resyncThreshold) return;

    ref.invalidate(groupsProvider);
    ref.invalidate(subscriptionsProvider);
    ref.invalidate(caixinhasProvider);
    ref.invalidate(pendingInvitesProvider);
  }

  void _go(int index) => widget.navigationShell.goBranch(
        index,
        initialLocation: index == widget.navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    // Mantém o canal de tempo real aberto enquanto o shell existir.
    ref.watch(realtimeSyncProvider);

    // Contadores de convite pendente por tipo (para o badge nas abas).
    final invites = ref.watch(pendingInvitesProvider).valueOrNull ?? const [];
    final groupInvites = invites
        .where((i) => i.kind == 'group' && i.status == MemberStatus.pending)
        .length;
    final subInvites = invites
        .where((i) => i.kind == 'subscription' && i.status == MemberStatus.pending)
        .length;
    final caixinhaInvites = invites
        .where((i) => i.kind == 'caixinha' && i.status == MemberStatus.pending)
        .length;
    int badgeFor(int index) =>
        switch (index) { 2 => groupInvites, 3 => subInvites, 4 => caixinhaInvites, _ => 0 };

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final current = widget.navigationShell.currentIndex;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(current: current, onSelect: _go, badgeFor: badgeFor),
            const VerticalDivider(width: 1),
            Expanded(child: widget.navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Theme.of(context).cardTheme.color,
          indicatorColor: AppColors.mentaViva.withValues(alpha: 0.35),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        child: NavigationBar(
          selectedIndex: current,
          onDestinationSelected: _go,
          height: 68,
          destinations: [
            for (int i = 0; i < AppShell._destinations.length; i++)
              NavigationDestination(
                icon: _Badged(count: badgeFor(i), child: Icon(AppShell._destinations[i].icon, size: 24)),
                selectedIcon: _Badged(
                  count: badgeFor(i),
                  child: Icon(AppShell._destinations[i].activeIcon,
                      size: 24, color: AppColors.verdeAguaProfundo),
                ),
                label: AppShell._destinations[i].label,
              ),
          ],
        ),
      ),
    );
  }
}

/// Envolve um ícone com um contador vermelho quando `count > 0`.
class _Badged extends StatelessWidget {
  final int count;
  final Widget child;
  const _Badged({required this.count, required this.child});

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: child,
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onSelect;
  final int Function(int index) badgeFor;
  const _Sidebar({required this.current, required this.onSelect, required this.badgeFor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const BrandMark(size: 34),
                const SizedBox(width: 10),
                Text('Fechaí', style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
          ),
          const SizedBox(height: 32),
          for (int i = 0; i < AppShell._destinations.length; i++)
            _SidebarItem(
              dest: AppShell._destinations[i],
              selected: i == current,
              badgeCount: badgeFor(i),
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          _SidebarItem(
            dest: const _Dest('Perfil', AppIcons.userCircle, AppIconsFill.userCircle),
            selected: false,
            badgeCount: 0,
            onTap: () => context.push('/profile'),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _Dest dest;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;
  const _SidebarItem({
    required this.dest,
    required this.selected,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.verdeAguaProfundo : Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? AppColors.mentaViva.withValues(alpha: 0.22) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _Badged(
                  count: badgeCount,
                  child: Icon(selected ? dest.activeIcon : dest.icon, size: 22, color: color),
                ),
                const SizedBox(width: 12),
                Text(
                  dest.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 15,
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

class _Dest {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _Dest(this.label, this.icon, this.activeIcon);
}
