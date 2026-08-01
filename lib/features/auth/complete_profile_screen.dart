import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/masks.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/pix_key_field.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

/// Primeiro acesso: completar dados básicos (nome + telefone + chave PIX).
/// A chave PIX é o que permite receber cobranças, então é incentivada.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _name = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _pix = TextEditingController();
  bool _loading = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _name.dispose();
    _lastName.dispose();
    _phone.dispose();
    _pix.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Como você quer ser chamado?')));
      return;
    }
    if (isReservedName(_name.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha um nome diferente de "Você".')),
      );
      return;
    }
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    setState(() => _loading = true);
    final last = _lastName.text.trim();
    // Campo em branco não pode gravar '': o telefone é a chave que religa os
    // vínculos criados antes do cadastro, e '' não casa com número nenhum.
    // Null aqui simplesmente não mexe no que já estava no perfil.
    final phone = digitsOf(_phone.text);
    await ref.read(repositoryControllerProvider).updateProfile(
          me.copyWith(
            name: _name.text.trim(),
            lastName: last.isEmpty ? null : last,
            phone: phone.isEmpty ? null : phone,
            pixKey: normalizePixKey(_pix.text),
          ),
        );
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // pré-preenche só o nome (identidade já conhecida); celular e PIX ficam
    // em branco — são dados que a pessoa completa agora, não repete o que
    // já tinha, mesmo que o perfil já tenha algo salvo.
    final me = ref.watch(currentUserProvider).valueOrNull;
    if (me != null && !_prefilled) {
      _prefilled = true;
      if (me.name.isNotEmpty && me.name != 'Você' && me.name != 'Novo usuário') _name.text = me.name;
      if (me.lastName != null) _lastName.text = me.lastName!;
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const Center(child: BrandMark(size: 72)),
                  const SizedBox(height: 20),
                  Text('Bem-vindo(a)!', textAlign: TextAlign.center, style: theme.textTheme.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    'Complete seu perfil para começar a dividir e cobrar.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  Text('Nome', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(hintText: 'Nome'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _lastName,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(hintText: 'Sobrenome'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Celular', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  // É por este número que reconhecemos quem já te incluiu numa
                  // conta antes de você ter cadastro. Sem ele, esses convites
                  // não aparecem — por isso a explicação em vez de "(opcional)".
                  Text('É assim que a gente acha as contas em que já te incluíram.',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [BrPhoneInputFormatter()],
                    decoration: const InputDecoration(prefixText: '+55  ', hintText: '(11) 99999-8888'),
                  ),
                  const SizedBox(height: 14),
                  // A dúvida recorrente aqui é "qual Pix eu ponho?". O rótulo
                  // fala na 1ª pessoa e o apoio explica o para quê: é a SUA
                  // chave, e ela serve para os outros te pagarem.
                  Row(
                    children: [
                      Text('Sua chave Pix', style: theme.textTheme.labelLarge),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.mentaViva.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text('é por onde você recebe', style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Compartilhe sua chave Pix para que os outros consigam te pagar.',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  PixKeyField(controller: _pix),
                  const SizedBox(height: 6),
                  Text('Ela só aparece para quem divide contas com você, na hora de te pagar. '
                      'Sem chave Pix dá pra dividir normalmente — só não dá pra receber pelo app.',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Começar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
