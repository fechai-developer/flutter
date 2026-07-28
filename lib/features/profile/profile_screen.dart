import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/icons.dart';

import '../../core/supabase_config.dart';
import '../../core/utils/masks.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/pix_key_field.dart';
import '../../core/widgets/premium.dart';
import '../../data/models/person.dart';
import '../../data/models/plan_status.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';
import '../auth/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final planAsync = ref.watch(planStatusProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Perfil'),
      ),
      body: user.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (u) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Column(
                children: [
                  MemberAvatar.person(u, size: 88),
                  const SizedBox(height: 12),
                  Text(u.fullName, style: theme.textTheme.headlineMedium),
                  if (u.phone != null)
                    Text('+${u.phone}', style: theme.textTheme.bodyMedium),
                  TextButton.icon(
                    onPressed: () => _editName(context, ref, u),
                    icon: Icon(AppIcons.pencilSimple, size: 16),
                    label: const Text('Editar nome'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Chave PIX
            _Tile(
              icon: AppIcons.qrCode,
              title: 'Chave PIX',
              subtitle: u.pixKey ?? 'Não cadastrada',
              trailing: TextButton(
                onPressed: () => _editPix(context, ref, u.pixKey),
                child: const Text('Editar'),
              ),
            ),
            _Tile(
              icon: AppIcons.bell,
              title: 'Notificações',
              subtitle: 'Lembretes de vencimento e confirmações',
              trailing: Switch(value: true, activeColor: AppColors.verdeAguaProfundo, onChanged: (_) {}),
            ),

            const SizedBox(height: 20),
            // Plano freemium (PRD seção 7) — reflete o status real do plano.
            // Em erro do provider, cai no free (não trava em "carregando").
            _PlanCard(
              plan: planAsync.valueOrNull,
              loading: planAsync.isLoading && !planAsync.hasValue,
            ),

            const SizedBox(height: 20),
            _Tile(icon: AppIcons.shieldCheck, title: 'Privacidade e LGPD', subtitle: 'Seus dados e consentimento'),
            _Tile(
              icon: AppIcons.signOut,
              title: 'Sair',
              subtitle: '',
              danger: true,
              onTap: () async {
                if (SupabaseConfig.backendActive) {
                  await ref.read(authControllerProvider).signOut();
                }
                if (context.mounted) context.go('/onboarding');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, Person u) async {
    final nameCtrl = TextEditingController(text: u.name == 'Você' ? '' : u.name);
    final lastCtrl = TextEditingController(text: u.lastName ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nome e sobrenome'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Sobrenome'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe seu nome.')));
      }
      return;
    }
    if (isReservedName(name)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escolha um nome diferente de "Você".')),
        );
      }
      return;
    }
    final last = lastCtrl.text.trim();
    await ref.read(repositoryControllerProvider).updateProfile(
          u.copyWith(name: name, lastName: last.isEmpty ? null : last),
        );
  }

  Future<void> _editPix(BuildContext context, WidgetRef ref, String? current) async {
    final controller = TextEditingController(text: current);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chave PIX'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(child: PixKeyField(controller: controller)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (saved == true) {
      final u = ref.read(currentUserProvider).valueOrNull;
      if (u != null) {
        await ref.read(repositoryControllerProvider).updateProfile(
              u.copyWith(pixKey: normalizePixKey(controller.text)),
            );
      }
    }
  }
}

/// Card do plano no perfil: mostra o Premium ativo ou, no free, o uso atual
/// (X de N grupos/assinaturas) com o convite para assinar.
///
/// [plan] null + [loading] true → só enquanto carrega de fato. Se o provider
/// falhar (plan null, loading false), cai no free para não travar em "carregando".
class _PlanCard extends StatelessWidget {
  final PlanStatus? plan;
  final bool loading;
  const _PlanCard({required this.plan, this.loading = false});

  @override
  Widget build(BuildContext context) {
    const gradient = LinearGradient(colors: [AppColors.verdeAguaProfundo, Color(0xFF17A78F)]);

    if (loading && plan == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
        child: const Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Carregando seu plano…', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      );
    }

    // Fallback seguro: sem dado (erro) → trata como free.
    final p = plan ?? PlanStatus.free();
    final isPremium = p.isPremium;

    String usageLine() {
      final g = p.maxGroups == null
          ? '${p.activeGroups} contas'
          : '${p.activeGroups} de ${p.maxGroups} contas';
      final s = p.maxSubscriptions == null
          ? '${p.activeSubscriptions} assinaturas'
          : '${p.activeSubscriptions} de ${p.maxSubscriptions} assinaturas';
      return '$g · $s ativas.\nJuros e cobrança automática são recursos Premium.';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIconsFill.sparkle, color: AppColors.mentaViva),
              const SizedBox(width: 8),
              Text(isPremium ? 'Premium ativo' : 'Plano Grátis',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isPremium
                ? 'Contas e assinaturas com folga, juros por atraso, Cobra Aí sem limite e cobrança automática.'
                : usageLine(),
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          if (!isPremium) ...[
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.verdeAguaProfundo),
              onPressed: () => PremiumUpsell.show(context),
              child: const Text('Conhecer o Premium'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool danger;
  final VoidCallback? onTap;
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? AppColors.coralAceso : AppColors.verdeAguaProfundo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: AppColors.areiaNeutra),
            ),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium?.copyWith(color: danger ? AppColors.coralAceso : null)),
                      if (subtitle.isNotEmpty) Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
