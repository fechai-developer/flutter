import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/utils/masks.dart';
import '../../data/models/person.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';
import 'member_avatar.dart';

/// Sugestão de pessoas já conhecidas (usadas em outros grupos/assinaturas),
/// mostrando **nome + telefone** para desambiguar homônimos. Um toque adiciona.
/// Compartilhado entre criar grupo e criar assinatura (Etapa C, itens 4/5).
class KnownMembersPicker extends ConsumerWidget {
  final List<Person> added;
  final ValueChanged<Person> onPick;
  const KnownMembersPicker({super.key, required this.added, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groups = ref.watch(groupsProvider).valueOrNull ?? const [];
    final subs = ref.watch(subscriptionsProvider).valueOrNull ?? const [];

    // Pessoas únicas (por nome completo+telefone), excluindo você.
    final seen = <String>{};
    final known = <Person>[];
    void consider(Person m) {
      if (m.id == 'me') return;
      final key = '${m.fullName.toLowerCase()}|${m.phone ?? ''}';
      if (seen.add(key)) known.add(m);
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

    final addedKeys = added.map((p) => '${p.fullName.toLowerCase()}|${p.phone ?? ''}').toSet();
    final suggestions =
        known.where((p) => !addedKeys.contains('${p.fullName.toLowerCase()}|${p.phone ?? ''}')).toList()
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
                          if ((p.phone ?? '').isNotEmpty)
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
}
