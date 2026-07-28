import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';
import '../../features/auth/auth_controller.dart';
import '../repositories/providers.dart';

/// Sincronização em tempo real.
///
/// A leitura do app é toda `FutureProvider` (busca rica com joins aninhados;
/// ver `SupabaseRepository`). Trocar isso por `.stream()` não funciona — o
/// stream do Supabase é de uma tabela só, sem joins. Então aqui usamos o
/// Realtime apenas como **sinal de invalidação**: escutamos `postgres_changes`
/// nas tabelas COLABORATIVAS (as que outro usuário pode alterar) e, ao receber
/// um evento, invalidamos o provider de leitura afetado — com **debounce**, de
/// modo que uma rajada de eventos vira uma única rebusca.
///
/// Eficiência: 1 canal por sessão (a RLS filtra no servidor o que cada usuário
/// recebe), 1 refetch por rajada. No mock/offline/deslogado é no-op. O canal
/// fecha em logout/dispose (sem sockets órfãos).
///
/// Mantido vivo por `ref.watch(realtimeSyncProvider)` no `AppShell`.
final realtimeSyncProvider = Provider<void>((ref) {
  // Reabre o canal só ao trocar de USUÁRIO (login/logout), não a cada renovação
  // de token — senão o socket reconectava sem motivo (e re-disparava eventos).
  ref.watch(sessionProvider.select((s) => s?.user.id));

  // Só com backend real E logado. Caso contrário não há o que escutar.
  if (!SupabaseConfig.backendActive ||
      Supabase.instance.client.auth.currentUser == null) {
    return;
  }

  final client = Supabase.instance.client;
  final debouncer = _InvalidationDebouncer(ref);
  final channel = client.channel('public:fechai-sync');

  // Registra o listener de uma tabela apontando para os providers que ela afeta.
  void listen(
    String table, {
    bool groups = false,
    bool subs = false,
    bool invites = false,
    bool caixinhas = false,
  }) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (_) =>
          debouncer.mark(groups: groups, subs: subs, invites: invites, caixinhas: caixinhas),
    );
  }

  // Grupos: membros (aceite de convite = o bug relatado), despesas, rateios e
  // acertos. `group_members` também mexe nos convites pendentes.
  listen('group_members', groups: true, invites: true);
  listen('expenses', groups: true);
  listen('expense_shares', groups: true);
  listen('payments', groups: true);
  listen('groups', groups: true);

  // Assinaturas: participantes (cota/aceite) e a própria assinatura.
  listen('subscription_members', subs: true, invites: true);
  listen('subscriptions', subs: true);

  // Caixinhas: membros (aceite de convite), aportes, rendimentos, empréstimos
  // e pagamentos. `caixinha_members` também mexe nos convites pendentes.
  listen('caixinha_members', caixinhas: true, invites: true);
  listen('caixinha_contributions', caixinhas: true);
  listen('caixinha_earnings', caixinhas: true);
  listen('caixinha_loans', caixinhas: true);
  listen('caixinha_loan_payments', caixinhas: true);
  listen('caixinha_exits', caixinhas: true);
  listen('caixinha_adjustments', caixinhas: true);
  listen('caixinhas', caixinhas: true);

  channel.subscribe();

  ref.onDispose(() {
    debouncer.dispose();
    client.removeChannel(channel);
  });
});

/// Agrupa eventos numa janela curta e invalida cada provider no máximo uma vez
/// por rajada. Evita N rebuscas quando várias linhas mudam de uma vez (ex.:
/// uma despesa nova insere em `expenses` + várias em `expense_shares`).
class _InvalidationDebouncer {
  final Ref _ref;
  Timer? _timer;
  bool _groups = false;
  bool _subs = false;
  bool _invites = false;
  bool _caixinhas = false;

  _InvalidationDebouncer(this._ref);

  void mark({bool groups = false, bool subs = false, bool invites = false, bool caixinhas = false}) {
    _groups |= groups;
    _subs |= subs;
    _invites |= invites;
    _caixinhas |= caixinhas;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), _flush);
  }

  void _flush() {
    // Invalidar as listas propaga para os detalhes (groupByIdProvider /
    // subscriptionByIdProvider / caixinhaByIdProvider observam as listas).
    if (_groups) _ref.invalidate(groupsProvider);
    if (_subs) _ref.invalidate(subscriptionsProvider);
    if (_invites) _ref.invalidate(pendingInvitesProvider);
    if (_caixinhas) _ref.invalidate(caixinhasProvider);
    _groups = _subs = _invites = _caixinhas = false;
  }

  void dispose() => _timer?.cancel();
}
