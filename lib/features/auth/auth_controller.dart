import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';

/// Auth via Supabase — login sem senha por **código de e-mail** (OTP).
/// Só é usado quando `SupabaseConfig.backendActive` está ligado; caso contrário
/// o app segue no fluxo simulado do mock (permite rodar offline).
///
/// Requer no painel Supabase:
///  - Authentication → Providers → Email habilitado.
///  - O template de e-mail de OTP deve conter `{{ .Token }}` para o usuário
///    receber o código de 6 dígitos (e não só o magic link).
class AuthController {
  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  /// Envia o código de verificação para o e-mail. Cria o usuário se novo.
  Future<void> sendCode(String email) {
    return _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: true,
    );
  }

  /// Verifica o código digitado e abre a sessão (persistida automaticamente).
  Future<AuthResponse> verifyCode(String email, String token) {
    return _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
  }

  /// Login por e-mail + senha (usado nos testes com contas pré-criadas no
  /// painel; sem depender de inbox). O OTP por e-mail fica para a fase final.
  Future<AuthResponse> signInWithPassword(String email, String password) {
    return _client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  /// Cadastro por e-mail + senha. Se a confirmação por e-mail estiver
  /// habilitada no painel Supabase, a resposta vem sem `session` (usuário
  /// precisa confirmar antes de logar); caso contrário a sessão já abre.
  Future<AuthResponse> signUp(String email, String password) {
    return _client.auth.signUp(email: email.trim(), password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Perfil está completo o suficiente para usar o app? (tem nome + chave PIX)
  Future<bool> profileComplete() async {
    final uid = currentUser?.id;
    if (uid == null) return false;
    final row = await _client.from('profiles').select('name,pix_key').eq('id', uid).maybeSingle();
    final name = (row?['name'] as String?)?.trim() ?? '';
    final pix = (row?['pix_key'] as String?)?.trim() ?? '';
    return name.isNotEmpty && name != 'Novo usuário' && pix.isNotEmpty;
  }

  /// Já aceitou a versão vigente do termo de uso? (#10)
  Future<bool> hasAcceptedTerms() async {
    final uid = currentUser?.id;
    if (uid == null) return false;
    final rows = await _client
        .from('user_terms')
        .select('version')
        .eq('user_id', uid)
        .eq('version', SupabaseConfig.termsVersion);
    return rows.isNotEmpty;
  }

  /// Grava o aceite do termo de uso vigente.
  Future<void> acceptTerms() async {
    final uid = currentUser!.id;
    await _client.from('user_terms').upsert({
      'user_id': uid,
      'version': SupabaseConfig.termsVersion,
    });
  }
}

final authControllerProvider = Provider<AuthController>((ref) => AuthController());

/// Fluxo de mudanças de sessão do Supabase (login/logout). Fonte para o
/// redirect do go_router. Vazio quando o backend está desligado.
final authChangesProvider = StreamProvider<AuthState?>((ref) {
  if (!SupabaseConfig.backendActive) return const Stream.empty();
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// Sessão atual (null = deslogado / backend desligado).
final sessionProvider = Provider<Session?>((ref) {
  ref.watch(authChangesProvider);
  if (!SupabaseConfig.backendActive) return null;
  return Supabase.instance.client.auth.currentSession;
});
