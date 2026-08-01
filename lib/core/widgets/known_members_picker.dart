import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/utils/masks.dart';
import '../../data/models/person.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';
import 'member_avatar.dart';

/// Sugestão de pessoas já conhecidas — quem já está em alguma conta, assinatura
/// ou caixinha sua. Um toque adiciona. Compartilhado entre criar grupo, criar
/// assinatura e criar caixinha (Etapa C, itens 4/5).
///
/// **Identidade pelo `profile_id`.** Depois que a pessoa cria conta, o vínculo
/// dela passa a apontar para um perfil — e é esse id que usamos aqui, tanto
/// para não listar a mesma pessoa duas vezes (nomes digitados diferente, número
/// que mudou) quanto para já nascer ligada no vínculo novo, sem depender do
/// telefone. Quem ainda não tem conta continua identificado por nome+telefone.
///
/// Privacidade: nada aqui vem de busca no banco — são só os membros das contas
/// das quais o próprio usuário participa, que ele já vê nessas telas.
class KnownMembersPicker extends ConsumerWidget {
  final List<Person> added;
  final ValueChanged<Person> onPick;
  const KnownMembersPicker({super.key, required this.added, required this.onPick});

  /// Chave de identidade: a conta, quando conhecida; senão nome+telefone.
  static String _keyOf(Person p) =>
      p.profileId ?? '${p.fullName.toLowerCase()}|${p.phone ?? ''}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groups = ref.watch(groupsProvider).valueOrNull ?? const [];
    final subs = ref.watch(subscriptionsProvider).valueOrNull ?? const [];
    final caixinhas = ref.watch(caixinhasProvider).valueOrNull ?? const [];

    // Pessoas únicas, excluindo você. Quando a mesma pessoa aparece em vários
    // lugares, fica a versão mais "completa": a que já está ligada a uma conta
    // e, entre essas, a que tem telefone.
    final known = <String, Person>{};
    void consider(Person m) {
      if (m.id == 'me') return;
      final key = _keyOf(m);
      final current = known[key];
      if (current == null || _better(m, current)) known[key] = m;
    }

    for (final g in groups) {
      for (final m in g.members) {
        consider(m);
      }
    }
    for (final s in subs) {
      for (final m in s.members) {
        consider(m.person);
      }
    }
    for (final c in caixinhas) {
      for (final m in c.members) {
        consider(m.person);
      }
    }

    final addedKeys = added.map(_keyOf).toSet();
    // Quem foi digitado agora (sem conta) ainda precisa ser reconhecido pelo
    // nome+telefone: senão a pessoa é sugerida de novo logo depois de add.
    final addedFallback =
        added.map((p) => '${p.fullName.toLowerCase()}|${p.phone ?? ''}').toSet();
    final suggestions = known.values
        .where((p) => !addedKeys.contains(_keyOf(p)))
        .where((p) => !addedFallback.contains('${p.fullName.toLowerCase()}|${p.phone ?? ''}'))
        .toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Conhecidos', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          for (final p in suggestions)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onPick(p.copyWith()),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    MemberAvatar.person(p, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.fullName, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          // Quem já tem conta é identificado por ela: o telefone
                          // vira detalhe (e pode nem estar preenchido).
                          if (p.profileId != null)
                            Text(
                              (p.phone ?? '').isEmpty ? 'já usa o Fechaí' : '${formatPhone(p.phone)} · já usa o Fechaí',
                              style: theme.textTheme.bodySmall,
                            )
                          else if ((p.phone ?? '').isNotEmpty)
                            Text(formatPhone(p.phone), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Icon(AppIcons.plus, color: AppColors.verdeAguaProfundo),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Entre duas versões da mesma pessoa, qual descreve melhor o vínculo.
  static bool _better(Person candidate, Person current) {
    final hasProfile = candidate.profileId != null;
    if (hasProfile != (current.profileId != null)) return hasProfile;
    final hasPhone = (candidate.phone ?? '').isNotEmpty;
    if (hasPhone != ((current.phone ?? '').isNotEmpty)) return hasPhone;
    // Empate: fica com quem tem sobrenome (nome completo é mais útil na lista).
    return (candidate.lastName ?? '').isNotEmpty && (current.lastName ?? '').isEmpty;
  }
}
