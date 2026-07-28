import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router/app_router.dart';
import 'core/supabase_config.dart';
import 'theme/app_theme.dart';

/// Inicializa o Supabase (idempotente). Retorna `true` se o backend está
/// pronto para uso. Extraído para poder tentar de novo na tela de reconexão.
Future<bool> initSupabase() async {
  if (SupabaseConfig.booted) return true;
  if (!SupabaseConfig.useBackend || !SupabaseConfig.isConfigured) return false;
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    ).timeout(const Duration(seconds: 15));
    SupabaseConfig.booted = true;
    return true;
  } catch (e) {
    debugPrint('Supabase.initialize falhou: $e');
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Formatação de datas em pt-BR (usada nos históricos de despesa).
  await initializeDateFormatting('pt_BR', null);

  // Com o backend ligado (padrão), a inicialização precisa dar certo: se
  // falhar, mostramos uma tela de reconexão em vez de cair no mock — que
  // reabriria o "entrar com qualquer conta". Só rodamos em modo mock quando
  // ele foi pedido explicitamente (USE_SUPABASE=false).
  if (SupabaseConfig.useBackend) {
    final ok = await initSupabase();
    if (!ok) {
      runApp(const _BackendUnavailableApp());
      return;
    }
  }

  runApp(const ProviderScope(child: FechaiApp()));
}

/// Tela mínima exibida quando o backend não pôde ser inicializado. Oferece
/// "Tentar de novo" — em caso de sucesso, sobe o app de verdade por cima.
class _BackendUnavailableApp extends StatefulWidget {
  const _BackendUnavailableApp();

  @override
  State<_BackendUnavailableApp> createState() => _BackendUnavailableAppState();
}

class _BackendUnavailableAppState extends State<_BackendUnavailableApp> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    if (await initSupabase()) {
      runApp(const ProviderScope(child: FechaiApp()));
      return;
    }
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fechaí',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Sem conexão com o servidor',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Não foi possível conectar ao Fechaí. '
                    'Verifique sua internet e tente de novo.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _retrying ? null : _retry,
                    child: _retrying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Tentar de novo'),
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

class FechaiApp extends ConsumerWidget {
  const FechaiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Fechaí',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Fixado no claro: identidade verde-água num tema leve e moderno. O tema
      // escuro segue definido para uma futura opção de preferência do usuário.
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
