/// Configuração do Supabase.
///
/// A `publishableKey` (`sb_publishable_...`) é feita para rodar no client —
/// quem protege os dados é a RLS (ver `supabase/schema.sql`), não o sigilo da
/// chave. Pode ficar no repositório. **Nunca** coloque aqui a `secret key`
/// (`sb_secret_...`): essa só vai em Edge Functions/servidor.
///
/// Dá pra sobrescrever em build via:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://arjndxyyyoygppfxegwb.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_4trl9BGGfrrTG1bYHsbZTg_Tu-cOTzA',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// Marcado `true` só depois que `Supabase.initialize` conclui com sucesso
  /// no boot. Se a rede falhar/estourar timeout, permanece `false` e o app
  /// cai no mock — nunca fica travado numa tela em branco.
  static bool booted = false;

  /// Backend realmente disponível para uso (ligado por flag E inicializado).
  static bool get backendActive => useBackend && booted;

  /// Login real fica DESLIGADO por padrão durante o desenvolvimento — a
  /// ativação do backend/login é a AÇÃO FINAL do roadmap (exige testes em
  /// conjunto). Enquanto isso, o app roda com dados mock, sem fricção de login.
  ///
  /// Toda a integração (auth por código de e-mail, perfil, termo, guard) já
  /// está pronta; para testar o login real quando for a hora:
  ///   flutter run --dart-define=USE_SUPABASE=true
  static const bool useBackend =
      bool.fromEnvironment('USE_SUPABASE', defaultValue: false);

  /// Versão vigente do termo de uso (#10). Bump quando o texto mudar.
  static const String termsVersion = '2026-07-20';
}
