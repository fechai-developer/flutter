import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/icons.dart';
import '../../core/limits.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/masks.dart';
import '../../core/widgets/emoji_picker.dart';
import '../../core/widgets/known_members_picker.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/sheet_handle.dart';
import '../../data/models/person.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

/// Abre a criação de caixinha como uma janela (modal) que sobe — em etapas.
/// `useRootNavigator` faz o overlay cobrir a tela toda (inclusive a barra de abas).
Future<void> showCreateCaixinhaSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateCaixinhaScreen(),
    );

/// Criação de uma caixinha (janela em etapas). Você vira o organizador
/// (tesoureiro); os demais entram como convidados.
class CreateCaixinhaScreen extends ConsumerStatefulWidget {
  const CreateCaixinhaScreen({super.key});

  @override
  ConsumerState<CreateCaixinhaScreen> createState() => _CreateCaixinhaScreenState();
}

class _CreateCaixinhaScreenState extends ConsumerState<CreateCaixinhaScreen> {
  final _nameController = TextEditingController();
  final _quotaController = TextEditingController();
  final _paymentDayController = TextEditingController();
  final _memberNameController = TextEditingController();
  final _memberLastNameController = TextEditingController();
  final _memberPhoneController = TextEditingController();
  final _uuid = const Uuid();
  final List<Person> _members = [];
  final Map<String, int> _quotas = {}; // person.id (e 'me') -> nº de cotas
  final Set<String> _treasurers = {}; // person.ids marcados como tesoureiro
  final Map<String, TextEditingController> _opening = {}; // saldo atual por pessoa
  String _emoji = '🐷';
  double _interest = 10; // juros padrão dos empréstimos (editável)
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _inProgress = false; // caixinha já em andamento (migração do caderno)
  bool _saving = false;
  int _step = 0; // etapa do assistente (0..2)

  int _q(String id) => _quotas[id] ?? 1;
  void _setQ(String id, int v) => setState(() => _quotas[id] = v.clamp(1, 99));
  TextEditingController _openingCtrl(String id) => _opening.putIfAbsent(id, TextEditingController.new);

  @override
  void dispose() {
    _nameController.dispose();
    _quotaController.dispose();
    _paymentDayController.dispose();
    _memberNameController.dispose();
    _memberLastNameController.dispose();
    _memberPhoneController.dispose();
    for (final c in _opening.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _pickMember(Person p) => setState(() => _members.add(p));

  void _addMember() {
    final name = _memberNameController.text.trim();
    if (name.isEmpty) return;
    if (isReservedName(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('"Você" é reservado — use o nome da pessoa.')),
      );
      return;
    }
    final last = _memberLastNameController.text.trim();
    setState(() {
      _members.add(Person(
        id: _uuid.v4(),
        name: name,
        lastName: last.isEmpty ? null : last,
        phone: digitsOf(_memberPhoneController.text),
      ));
      _memberNameController.clear();
      _memberLastNameController.clear();
      _memberPhoneController.clear();
    });
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dê um nome pra caixinha')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      // Saldo atual de cada um (só no modo "já em andamento") → aporte semente.
      final opening = <String, double>{};
      if (_inProgress) {
        for (final id in ['me', ..._members.map((m) => m.id)]) {
          final v = Money.parse(_openingCtrl(id).text) ?? 0;
          if (v > 0) opening[id] = v;
        }
      }
      final created = await ref.read(repositoryControllerProvider).createCaixinha(
            name: name,
            emoji: _emoji,
            defaultInterestPct: _interest,
            monthlyQuota: Money.parse(_quotaController.text) ?? 0,
            members: _members,
            quotas: {'me': _q('me'), for (final m in _members) m.id: _q(m.id)},
            openingBalances: opening,
            treasurers: _treasurers,
            // "Do zero" começa hoje; só "em andamento" usa o início escolhido.
            startDate: _inProgress ? _startDate : DateTime.now(),
            endDate: _endDate,
            paymentDay: int.tryParse(_paymentDayController.text.trim())?.clamp(1, 31),
          );
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop(); // fecha a janela (modal)
      // "Já em andamento" abre com o guia de preenchimento do histórico.
      router.go('/caixinhas/${created.id}${_inProgress ? '?guide=1' : ''}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível criar a caixinha: $e')),
      );
    }
  }

  static const _stepTitles = ['A caixinha', 'Período', 'Participantes'];

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Valida a etapa atual antes de avançar. Campos críticos não deixam passar.
  bool _validateStep() {
    if (_step == 0) {
      if (_nameController.text.trim().isEmpty) {
        _snack('Dê um nome pra caixinha');
        return false;
      }
      if ((Money.parse(_quotaController.text) ?? 0) <= 0) {
        _snack('Informe o valor da cota por participante');
        return false;
      }
      final day = int.tryParse(_paymentDayController.text.trim());
      if (day == null || day < 1 || day > 31) {
        _snack('Informe o dia de vencimento da cota (1 a 31)');
        return false;
      }
    }
    return true;
  }

  void _next() {
    if (!_validateStep()) return;
    setState(() => _step++);
  }

  Widget _currentStep(ThemeData theme) => switch (_step) {
        0 => _stepBasico(theme),
        1 => _stepPeriodo(theme),
        _ => _stepParticipantes(theme),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      // Material (não Container com cor) para o ListTile/ink pintar certo e
      // evitar o assert do DecoratedBox.
      child: Material(
        color: theme.scaffoldBackgroundColor,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ConstrainedBox(
          // Ajusta ao conteúdo da etapa; teto de 92% da tela.
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Nova caixinha · ${_stepTitles[_step]}', style: theme.textTheme.titleLarge),
                ),
              ),
              Flexible(child: _currentStep(theme)),
            // Barra inferior: Voltar (esq) · bolinhas (centro) · Próximo/Criar (dir)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _step > 0
                            ? TextButton(onPressed: () => setState(() => _step--), child: const Text('Voltar'))
                            : const SizedBox.shrink(),
                      ),
                    ),
                    _StepDots(count: 3, current: _step),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _step < 2
                            ? ElevatedButton(onPressed: _next, child: const Text('Próximo'))
                            : ElevatedButton(
                                onPressed: _saving ? null : _create,
                                child: _saving
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Criar'),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ---------- Etapa 1: a caixinha ----------
  Widget _stepBasico(ThemeData theme) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        shrinkWrap: true,
        children: [
          Text('Ícone', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          EmojiPicker(
            value: _emoji,
            presets: const ['🐷', '💰', '🏦', '💵', '🤝', '👨‍👩‍👧', '🏠', '🎯', '📈', '🪙'],
            onChanged: (e) => setState(() => _emoji = e),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome', hintText: 'Caixinha da Família, Amigos do trampo...'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quotaController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor da cota por participante',
              prefixText: r'R$ ',
              helperText: 'Quanto cada participante coloca por mês.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 20),
          // Situação (nova vs. em andamento) fica aqui, junto do valor, porque é
          // ela que muda a lógica de como os aportes entram.
          Text('A caixinha já está rolando?', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Começar do zero')),
              ButtonSegment(value: true, label: Text('Já em andamento')),
            ],
            selected: {_inProgress},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _inProgress = s.first),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.mentaViva.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.info, size: 18, color: AppColors.verdeAguaProfundo),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _inProgress
                        ? 'Já roda: na etapa dos participantes você informa o saldo atual de cada um '
                            '(a foto de hoje) e, no período, quando ela começou. Movimentações antigas '
                            '(ex.: um empréstimo do passado) dá pra registrar depois, com a data certa.'
                        : 'Nova: começa hoje. Você lança o aporte de cada um a cada mês, daqui pra frente.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _paymentDayController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
            decoration: const InputDecoration(
              labelText: 'Dia do vencimento (todo mês)',
              hintText: 'ex.: 10',
              helperText: 'A partir desse dia, a cota não paga passa a render juros (como empréstimo).',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 24),
          _InterestField(value: _interest, onChanged: (v) => setState(() => _interest = v)),
        ],
      );

  // ---------- Etapa 2: período (início só quando já em andamento) + fim ----------
  Widget _stepPeriodo(ThemeData theme) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        shrinkWrap: true,
        children: [
          Text(
            _inProgress
                ? 'Quando a caixinha começou e até quando vai (se tiver prazo).'
                : 'A caixinha começa hoje. Defina só até quando vai, se tiver prazo.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text('Período', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              // "Do zero" começa hoje: não precisa escolher o início. "Já em
              // andamento" escolhe quando começou (pode ser no passado).
              if (_inProgress) ...[
                Expanded(
                  child: _DateField(
                    label: 'Quando começou',
                    value: _startDate,
                    onTap: () async {
                      final d = await _pickDate(_startDate);
                      if (d != null) setState(() => _startDate = d);
                    },
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: _DateField(
                  label: 'Até (opcional)',
                  value: _endDate,
                  onClear: _endDate == null ? null : () => setState(() => _endDate = null),
                  onTap: () async {
                    final d = await _pickDate(_endDate ?? _startDate);
                    if (d != null) setState(() => _endDate = d);
                  },
                ),
              ),
            ],
          ),
        ],
      );

  // ---------- Etapa 3: participantes ----------
  Widget _stepParticipantes(ThemeData theme) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        shrinkWrap: true,
        children: [
          Text(
            _inProgress
                ? 'Marque quem também é tesoureiro (pode lançar) e informe o saldo atual de cada um.'
                : 'Convide quem vai participar e marque quem também pode lançar. O aporte de cada um vem depois.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          KnownMembersPicker(added: _members, onPick: _pickMember),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _memberLastNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Sobrenome'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberPhoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [BrPhoneInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Celular', hintText: '(11) 9...'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _addMember,
                style: IconButton.styleFrom(backgroundColor: AppColors.verdeAguaProfundo),
                icon: Icon(AppIcons.plus, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MemberRow(
            name: 'Você (organizador)',
            isOwner: true,
            removable: false,
            quotas: _q('me'),
            onQuotasChanged: (v) => _setQ('me', v),
            showOpening: _inProgress,
            openingController: _openingCtrl('me'),
          ),
          for (final m in _members)
            _MemberRow(
              name: m.fullName,
              lastName: m.lastName,
              subtitle: formatPhone(m.phone),
              quotas: _q(m.id),
              onQuotasChanged: (v) => _setQ(m.id, v),
              isTreasurer: _treasurers.contains(m.id),
              onTreasurerChanged: (v) => setState(() => v ? _treasurers.add(m.id) : _treasurers.remove(m.id)),
              showOpening: _inProgress,
              openingController: _openingCtrl(m.id),
              onRemove: () => setState(() => _members.remove(m)),
            ),
        ],
      );
}

/// Indicador de etapas (bolinhas) no topo do assistente.
class _StepDots extends StatelessWidget {
  final int count;
  final int current;
  const _StepDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < count; i++) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == current ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i <= current ? AppColors.verdeAguaProfundo : AppColors.areiaNeutra,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            if (i < count - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// Slider de juros dos empréstimos da caixinha (0–20% a.m.), com enquadramento
/// ilustrativo. Diferente do slider de "atraso" (grupos/assinaturas): aqui o
/// juro é o combinado do empréstimo (ex.: 10% pra dentro ou pra fora).
class _InterestField extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _InterestField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = value > 10; // acima do usual (10% é a referência das caixinhas)
    final accent = warn ? AppColors.coralAceso : AppColors.verdeAguaProfundo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Juros dos empréstimos', style: theme.textTheme.labelLarge),
            const Spacer(),
            Text('${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}% ao mês',
                style: AppTheme.moneyStyle(fontSize: 16, color: accent)),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: InterestPolicy.maxPct,
          divisions: (InterestPolicy.maxPct * 2).toInt(),
          activeColor: accent,
          label: '${value.toStringAsFixed(1)}%',
          onChanged: onChanged,
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: warn ? AppColors.coralAceso.withValues(alpha: 0.1) : AppColors.mentaViva.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(warn ? Icons.warning_amber_rounded : Icons.info_outline, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Taxa combinada entre vocês para os empréstimos da caixinha. '
                  'Vale como padrão — dá pra ajustar em cada empréstimo. É ilustrativa: '
                  'o Fechaí só organiza, não cobra nem empresta.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final String name;
  final String? lastName;
  final String? subtitle;
  final bool removable;
  final VoidCallback? onRemove;
  final int quotas;
  final ValueChanged<int>? onQuotasChanged;
  final bool isOwner;
  final bool isTreasurer;
  final ValueChanged<bool>? onTreasurerChanged;
  final bool showOpening;
  final TextEditingController? openingController;
  const _MemberRow({
    required this.name,
    this.lastName,
    this.subtitle,
    this.removable = true,
    this.onRemove,
    this.quotas = 1,
    this.onQuotasChanged,
    this.isOwner = false,
    this.isTreasurer = false,
    this.onTreasurerChanged,
    this.showOpening = false,
    this.openingController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Column(
        children: [
          Row(
            children: [
              MemberAvatar(name: name, lastName: lastName, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (onQuotasChanged != null) _CotaStepper(quotas: quotas, onChanged: onQuotasChanged!),
              if (removable)
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(AppIcons.trash, size: 18, color: AppColors.coralAceso),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              // Papel: dono fixo; demais têm toggle de tesoureiro.
              if (isOwner)
                _RoleChip(label: 'Dono', selected: true, onTap: null)
              else if (onTreasurerChanged != null)
                _RoleChip(
                  label: 'Tesoureiro',
                  selected: isTreasurer,
                  onTap: () => onTreasurerChanged!(!isTreasurer),
                ),
              const Spacer(),
              if (showOpening)
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: openingController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Saldo hoje',
                      prefixText: r'R$ ',
                      isDense: true,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chip de papel (Dono fixo / Tesoureiro alternável).
class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _RoleChip({required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.verdeAguaProfundo : AppColors.textoSuave;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.verdeAguaProfundo.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: selected ? AppColors.verdeAguaProfundo : AppColors.areiaNeutra),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? Icons.check : Icons.person_outline, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Campo de data (tappável) usado na criação da caixinha.
class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _DateField({required this.label, required this.value, required this.onTap, this.onClear});

  String get _text => value == null
      ? '—'
      : '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.areiaNeutra),
        ),
        child: Row(
          children: [
            Icon(AppIconsFill.calendarBlank, size: 18, color: AppColors.verdeAguaProfundo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  Text(_text, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            if (onClear != null)
              InkWell(onTap: onClear, child: Icon(AppIcons.close, size: 16, color: AppColors.textoSuave)),
          ],
        ),
      ),
    );
  }
}

/// Stepper compacto de nº de cotas (mín. 1).
class _CotaStepper extends StatelessWidget {
  final int quotas;
  final ValueChanged<int> onChanged;
  const _CotaStepper({required this.quotas, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: quotas > 1 ? () => onChanged(quotas - 1) : null,
          borderRadius: BorderRadius.circular(100),
          child: Icon(Icons.remove_circle_outline, size: 22, color: quotas > 1 ? AppColors.verdeAguaProfundo : AppColors.areiaNeutra),
        ),
        SizedBox(
          width: 34,
          child: Text('$quotas\ncota${quotas > 1 ? 's' : ''}',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ),
        InkWell(
          onTap: () => onChanged(quotas + 1),
          borderRadius: BorderRadius.circular(100),
          child: const Icon(Icons.add_circle_outline, size: 22, color: AppColors.verdeAguaProfundo),
        ),
      ],
    );
  }
}
