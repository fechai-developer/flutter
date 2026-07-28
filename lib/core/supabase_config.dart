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
  /// no boot. Com `useBackend` ligado, se a inicialização falhar o app mostra
  /// uma tela de reconexão (não cai no mock — isso reabriria o login livre).
  static bool booted = false;

  /// Backend realmente disponível para uso (ligado por flag E inicializado).
  static bool get backendActive => useBackend && booted;

  /// Login real fica LIGADO por padrão — qualquer `flutter build web` já sai
  /// com autenticação de verdade (e-mail + senha) e a guarda de sessão ativa.
  ///
  /// Para desenvolver offline com dados mock (sem fricção de login):
  ///   flutter run --dart-define=USE_SUPABASE=false
  static const bool useBackend =
      bool.fromEnvironment('USE_SUPABASE', defaultValue: true);

  /// Versão vigente do termo de uso (#10). Bump quando o texto mudar.
  static const String termsVersion = '2026-07-20';
}
