import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router/app_router.dart';
import 'core/supabase_config.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Formatação de datas em pt-BR (usada nos históricos de despesa).
  await initializeDateFormatting('pt_BR', null);

  // Inicializa o Supabase quando o backend estiver ligado (USE_SUPABASE=true).
  // Guardado em try/catch para não derrubar o boot offline com o mock.
  if (SupabaseConfig.useBackend && SupabaseConfig.isConfigured) {
    try {
      // Timeout para não travar o boot se a rede estiver indisponível.
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      ).timeout(const Duration(seconds: 8));
      SupabaseConfig.booted = true;
    } catch (e) {
      debugPrint('Supabase.initialize falhou (seguindo com mock): $e');
    }
  }

  runApp(const ProviderScope(child: FechaiApp()));
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
