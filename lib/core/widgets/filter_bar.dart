import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Barra de filtro das listas: 60% busca por texto, 20% filtro por pessoas,
/// 20% filtro por status/tag. (#1)
class FilterBar extends StatelessWidget {
  final ValueChanged<String> onQueryChanged;
  final List<String> people; // nomes disponíveis
  final Set<String> selectedPeople;
  final ValueChanged<Set<String>> onPeopleChanged;
  final List<String> statuses;
  final String? selectedStatus;
  final ValueChanged<String?> onStatusChanged;

  const FilterBar({
    super.key,
    required this.onQueryChanged,
    required this.people,
    required this.selectedPeople,
    required this.onPeopleChanged,
    required this.statuses,
    required this.selectedStatus,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: 'Buscar',
              prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF8FA39E)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.areiaNeutra),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: _FilterButton(
            icon: Icons.group_outlined,
            active: selectedPeople.isNotEmpty,
            badge: selectedPeople.length,
            onTap: () => _pickPeople(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: _FilterButton(
            icon: Icons.filter_list,
            active: selectedStatus != null,
            onTap: () => _pickStatus(context),
          ),
        ),
      ],
    );
  }

  Future<void> _pickPeople(BuildContext context) async {
    final sel = {...selectedPeople};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SheetContainer(
        title: 'Filtrar por pessoa',
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (people.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Ninguém para filtrar ainda.')),
              ...people.map((p) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: sel.contains(p),
                    activeColor: AppColors.verdeAguaProfundo,
                    title: Text(p),
                    onChanged: (v) => setSheet(() => (v ?? false) ? sel.add(p) : sel.remove(p)),
                  )),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx, <String>{}), child: const Text('Limpar')),
                  const Spacer(),
                  ElevatedButton(onPressed: () => Navigator.pop(ctx, sel), child: const Text('Aplicar')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) onPeopleChanged(result);
  }

  Future<void> _pickStatus(BuildContext context) async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SheetContainer(
        title: 'Filtrar por status',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: '__all__',
              groupValue: selectedStatus ?? '__all__',
              activeColor: AppColors.verdeAguaProfundo,
              title: const Text('Todos'),
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
            ...statuses.map((s) => RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: s,
                  groupValue: selectedStatus ?? '__all__',
                  activeColor: AppColors.verdeAguaProfundo,
                  title: Text(s),
                  onChanged: (v) => Navigator.pop(ctx, v),
                )),
          ],
        ),
      ),
    );
    if (result == null) return; // fechou sem escolher
    onStatusChanged(result == '__all__' ? null : result);
  }
}

class _FilterButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final int badge;
  final VoidCallback onTap;
  const _FilterButton({required this.icon, required this.active, this.badge = 0, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: active ? AppColors.mentaViva.withValues(alpha: 0.25) : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? AppColors.verdeAguaProfundo : AppColors.areiaNeutra),
        ),
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 20, color: active ? AppColors.verdeAguaProfundo : const Color(0xFF8FA39E)),
            if (badge > 0)
              Positioned(
                right: -8,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: AppColors.verdeAguaProfundo, shape: BoxShape.circle),
                  child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetContainer extends StatelessWidget {
  final String title;
  final Widget child;
  const _SheetContainer({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
