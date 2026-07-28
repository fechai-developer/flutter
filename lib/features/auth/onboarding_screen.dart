import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import '../../core/supabase_config.dart';
import '../../core/widgets/brand_mark.dart';
import '../../theme/app_theme.dart';
import 'auth_controller.dart';

/// Login. Com backend ligado: **e-mail + senha** (contas de teste pré-criadas;
/// sem depender de inbox). O OTP por e-mail fica para a fase final.
/// Sem backend (mock): fluxo simulado, entra com qualquer e-mail.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showTerms = false;
  bool _acceptedTerms = false;
  bool _loading = false;
  String? _error;

  bool get _backend => SupabaseConfig.backendActive;

  @override
  void initState() {
    super.initState();
    // Usuário que já tem sessão (voltou ao app) é roteado direto.
    if (_backend && ref.read(authControllerProvider).currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _postLogin());
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  String _friendly(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('invalid') || s.contains('credentials')) return 'E-mail ou senha inválidos.';
    if (s.contains('rate') || s.contains('limit')) return 'Muitas tentativas. Aguarde um pouco.';
    return 'Não foi possível entrar. Verifique a conexão e tente de novo.';
  }

  /// Decide para onde ir após autenticar: termo → completar perfil → home.
  Future<void> _postLogin() async {
    final auth = ref.read(authControllerProvider);
    if (!await auth.hasAcceptedTerms()) {
      if (mounted) setState(() => _showTerms = true);
      return;
    }
    if (!await auth.profileComplete()) {
      if (mounted) context.go('/complete-profile');
      return;
    }
    if (mounted) context.go('/home');
  }

  Future<void> _enter() async {
    if (!_validEmail(_emailController.text)) {
      setState(() => _error = 'Digite um e-mail válido.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_backend) {
        await ref.read(authControllerProvider).signInWithPassword(
              _emailController.text,
              _passwordController.text,
            );
        await _postLogin();
      } else {
        if (mounted) context.go('/home');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acceptTermsAndContinue() async {
    if (!_acceptedTerms) return;
    setState(() => _loading = true);
    try {
      if (_backend) await ref.read(authControllerProvider).acceptTerms();
      if (_backend) {
        await _postLogin();
      } else if (mounted) {
        context.go('/home');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  const SizedBox(height: 24),
                  const Center(child: BrandMark(size: 88)),
                  const SizedBox(height: 24),
                  Text('Fechaí', textAlign: TextAlign.center, style: theme.textTheme.displayMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Divida despesas e assinaturas.\nCobre pelo WhatsApp, receba no PIX.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 40),
                  if (_showTerms) ..._termsStep(theme) else ..._loginStep(theme),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(AppIcons.warningCircle, size: 16, color: AppColors.coralAceso),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.coralAceso))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 28),
                  _LgpdNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _loginStep(ThemeData theme) {
    return [
      Text('Seu e-mail', style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(hintText: 'voce@email.com'),
        onSubmitted: (_) => _backend ? null : _enter(),
      ),
      if (_backend) ...[
        const SizedBox(height: 12),
        Text('Senha', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(hintText: '••••••••'),
          onSubmitted: (_) => _enter(),
        ),
      ],
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: _loading ? null : _enter,
        child: _loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Entrar'),
      ),
    ];
  }

  List<Widget> _termsStep(ThemeData theme) {
    return [
      Text('Antes de começar', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.areiaNeutra),
        ),
        child: Text(
          'O Fechaí é uma ferramenta de organização de despesas pessoais. '
          'Não somos instituição de pagamento nem plataforma de cobrança, não '
          'processamos ou custodiamos valores e não interferimos na relação '
          'entre os usuários. Eventuais juros são ilustrativos, definidos entre '
          'as pessoas da conta, para apoiar a gestão informal das despesas.',
          style: theme.textTheme.bodySmall,
        ),
      ),
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _acceptedTerms,
        activeColor: AppColors.verdeAguaProfundo,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text('Li e aceito os termos de uso', style: theme.textTheme.bodyMedium),
        onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: (!_acceptedTerms || _loading) ? null : _acceptTermsAndContinue,
        child: const Text('Aceitar e continuar'),
      ),
    ];
  }
}

class _LgpdNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(AppIcons.shieldCheck, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Não guardamos dados bancários — só sua chave PIX. '
            'O Fechaí não custodia dinheiro.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
