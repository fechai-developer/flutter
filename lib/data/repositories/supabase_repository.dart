import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/caixinha.dart';
import '../models/expense.dart';
import '../models/expense_group.dart';
import '../models/person.dart';
import '../models/plan_status.dart';
import '../models/subscription.dart';
import 'app_repository.dart';

/// Implementação real sobre o Supabase. Ativa quando `USE_SUPABASE=true` e o
/// usuário está logado. Ver schema em `supabase/migrations/`.
///
/// Normalização de identidade: para não mexer na UI (que compara `id == 'me'`),
/// o usuário logado sempre aparece como `Person(id: 'me')`. Os demais membros
/// usam o id da linha em `group_members`/`subscription_members`. A tradução
/// `personId ↔ rowId` acontece só aqui, na borda de dados.
class SupabaseRepository implements AppRepository {
  final SupabaseClient _c = Supabase.instance.client;

  String get _uid => _c.auth.currentUser!.id;

  /// Procura um perfil já existente pelo telefone (para ligar o membro à conta).
  Future<String?> _findProfileByPhone(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return null;
    final res = await _c.rpc('find_profile_by_phone', params: {'p': phone});
    return res as String?;
  }

  /// Conta a ligar num novo vínculo. Quando a pessoa veio da lista de
  /// conhecidos, já sabemos o `profile_id` dela — é o vínculo direto e estável.
  /// Só caímos na busca por telefone para quem foi digitado agora.
  Future<String?> _profileIdFor(Person member) async =>
      member.profileId ?? await _findProfileByPhone(member.phone);

  // ----------------- Perfil -----------------
  @override
  Future<Person> currentUser() async {
    final row = await _c.from('profiles').select().eq('id', _uid).maybeSingle();
    return Person(
      id: 'me',
      name: (row?['name'] as String?)?.trim().isNotEmpty == true
          ? row!['name'] as String
          : (_c.auth.currentUser?.email ?? 'Você'),
      lastName: row?['last_name'] as String?,
      phone: row?['phone'] as String?,
      photoUrl: row?['photo_url'] as String?,
      pixKey: row?['pix_key'] as String?,
    );
  }

  @override
  Future<PlanStatus> planStatus() async {
    final res = await _c.rpc('my_plan_status');
    if (res is Map) return PlanStatus.fromRpc(res.cast<String, dynamic>());
    return PlanStatus.free();
  }

  @override
  Future<List<PendingInvite>> pendingInvites() async {
    final invites = <PendingInvite>[];
    // Pendentes E recusados: um convite recusado continua listado para que a
    // pessoa possa aceitar depois (Etapa C, item 6).
    final gms = await _c
        .from('group_members')
        .select('id,group_id,status,groups(name,emoji)')
        .eq('profile_id', _uid)
        .inFilter('status', ['pending', 'declined']);
    for (final gm in gms) {
      final g = gm['groups'] as Map?;
      if (g != null) {
        invites.add(PendingInvite(
          kind: 'group',
          membershipId: gm['id'] as String,
          sourceId: gm['group_id'] as String?,
          title: g['name'] as String,
          emoji: g['emoji'] as String? ?? '💸',
          status: _statusFrom(gm['status'] as String?),
        ));
      }
    }
    final sms = await _c
        .from('subscription_members')
        .select('id,subscription_id,invite_status,subscriptions(service_name,emoji)')
        .eq('profile_id', _uid)
        .inFilter('invite_status', ['pending', 'declined']);
    for (final sm in sms) {
      final s = sm['subscriptions'] as Map?;
      if (s != null) {
        invites.add(PendingInvite(
          kind: 'subscription',
          membershipId: sm['id'] as String,
          sourceId: sm['subscription_id'] as String?,
          title: s['service_name'] as String,
          emoji: s['emoji'] as String? ?? '📺',
          status: _statusFrom(sm['invite_status'] as String?),
        ));
      }
    }
    // Caixinhas: convite de membro (tomadores externos não têm aceite).
    final cxms = await _c
        .from('caixinha_members')
        .select('id,caixinha_id,invite_status,caixinhas(name,emoji)')
        .eq('profile_id', _uid)
        .neq('role', 'borrower')
        .inFilter('invite_status', ['pending', 'declined']);
    for (final cm in cxms) {
      final cx = cm['caixinhas'] as Map?;
      if (cx != null) {
        invites.add(PendingInvite(
          kind: 'caixinha',
          membershipId: cm['id'] as String,
          sourceId: cm['caixinha_id'] as String?,
          title: cx['name'] as String,
          emoji: cx['emoji'] as String? ?? '🐷',
          status: _statusFrom(cm['invite_status'] as String?),
        ));
      }
    }
    return invites;
  }

  /// Traduz o texto de status do banco (pending/accepted/declined) para o enum.
  static MemberStatus _statusFrom(String? s) {
    switch (s) {
      case 'accepted':
        return MemberStatus.accepted;
      case 'declined':
        return MemberStatus.declined;
      default:
        return MemberStatus.pending;
    }
  }

  @override
  Future<void> acceptInvite(PendingInvite invite) async {
    switch (invite.kind) {
      case 'group':
        await _c.from('group_members').update({'status': 'accepted'}).eq('id', invite.membershipId);
      case 'caixinha':
        await _c.from('caixinha_members').update({'invite_status': 'accepted'}).eq('id', invite.membershipId);
      default:
        await _c.from('subscription_members').update({'invite_status': 'accepted'}).eq('id', invite.membershipId);
    }
  }

  @override
  Future<void> declineInvite(PendingInvite invite) async {
    switch (invite.kind) {
      case 'group':
        await _c.from('group_members').update({'status': 'declined'}).eq('id', invite.membershipId);
      case 'caixinha':
        await _c.from('caixinha_members').update({'invite_status': 'declined'}).eq('id', invite.membershipId);
      default:
        await _c.from('subscription_members').update({'invite_status': 'declined'}).eq('id', invite.membershipId);
    }
  }

  @override
  Future<void> updateProfile(Person user) async {
    final phone = (user.phone ?? '').trim();
    await _c.from('profiles').update({
      'name': user.name,
      'last_name': user.lastName,
      // '' não é telefone: gravar vazio quebraria o religamento por número.
      'phone': phone.isEmpty ? null : phone,
      'photo_url': user.photoUrl,
      'pix_key': user.pixKey,
    }).eq('id', _uid);

    // Religa os vínculos que já existiam para este número — quem te adicionou
    // numa conta antes de você ter cadastro. O banco também faz isso por
    // gatilho; chamar aqui garante que já apareça nesta carga.
    if (phone.isNotEmpty) {
      try {
        await _c.rpc('link_my_memberships');
      } catch (_) {
        // Ambiente sem a migração aplicada: o gatilho cobre o caso, e não vale
        // travar o cadastro por causa disto.
      }
    }
  }

  // ----------------- Grupos -----------------
  // group_members NÃO tem pix_key (fica em profiles, protegida por RLS).
  // A chave PIX de um recebedor é obtida sob demanda via [memberPixKey] (RPC payee_info).
  static const _groupSelect =
      'id,name,emoji,owner_id,monthly_interest_pct,created_at,'
      'group_members(id,profile_id,name,last_name,phone,status,removed_at),'
      'expenses(id,description,amount,paid_by,split_type,date,recurrence,recurrence_until,recurrence_day,recurrence_review,recurrence_parent_id,occurrence_period,category,expense_shares(member_id,share)),'
      'payments(id,from_member,to_member,amount,created_at)';

  @override
  Future<List<ExpenseGroup>> groups() async {
    final rows = await _c.from('groups').select(_groupSelect).order('created_at', ascending: false);
    return rows.map<ExpenseGroup>(_mapGroup).toList();
  }

  @override
  Future<ExpenseGroup> groupById(String id) async {
    final row = await _c.from('groups').select(_groupSelect).eq('id', id).single();
    return _mapGroup(row);
  }

  ExpenseGroup _mapGroup(Map<String, dynamic> g) {
    final gms = (g['group_members'] as List).cast<Map<String, dynamic>>();
    // id da linha (gm) -> personId exposto ('me' se for eu)
    final gmToPerson = <String, String>{};
    final members = <Person>[];
    final memberStatus = <String, MemberStatus>{};
    final removedMemberIds = <String>{};
    var viewerRemoved = false;
    for (final gm in gms) {
      final isMe = gm['profile_id'] == _uid;
      final pid = isMe ? 'me' : gm['id'] as String;
      final removed = gm['removed_at'] != null;
      gmToPerson[gm['id'] as String] = pid;
      if (!isMe) memberStatus[pid] = _statusFrom(gm['status'] as String?);
      if (removed) removedMemberIds.add(pid);
      if (isMe && removed) viewerRemoved = true;
      members.add(Person(
        id: pid,
        name: isMe ? 'Você' : gm['name'] as String,
        lastName: isMe ? null : gm['last_name'] as String?,
        phone: gm['phone'] as String?,
        profileId: gm['profile_id'] as String?,
      ));
    }

    final expenses = <Expense>[];
    for (final e in (g['expenses'] as List).cast<Map<String, dynamic>>()) {
      final shares = <String, double>{};
      for (final s in (e['expense_shares'] as List).cast<Map<String, dynamic>>()) {
        final pid = gmToPerson[s['member_id']];
        if (pid != null) shares[pid] = (s['share'] as num).toDouble();
      }
      expenses.add(Expense(
        id: e['id'] as String,
        description: e['description'] as String,
        amount: (e['amount'] as num).toDouble(),
        paidByPersonId: gmToPerson[e['paid_by']] ?? 'me',
        type: SplitType.values.byName(e['split_type'] as String),
        shares: shares,
        date: DateTime.parse(e['date'] as String),
        recurrence: Recurrence.values.byName((e['recurrence'] as String?) ?? 'none'),
        recurrenceUntil: e['recurrence_until'] != null
            ? DateTime.parse(e['recurrence_until'] as String)
            : null,
        recurrenceDay: (e['recurrence_day'] as num?)?.toInt(),
        recurrenceReview: RecurrenceReview.values.byName((e['recurrence_review'] as String?) ?? 'none'),
        recurrenceParentId: e['recurrence_parent_id'] as String?,
        occurrencePeriod: e['occurrence_period'] != null
            ? DateTime.parse(e['occurrence_period'] as String)
            : null,
        category: e['category'] as String?,
      ));
    }

    final payments = <Payment>[];
    for (final p in (g['payments'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      payments.add(Payment(
        id: p['id'] as String,
        fromId: gmToPerson[p['from_member']] ?? '',
        toId: gmToPerson[p['to_member']] ?? '',
        amount: (p['amount'] as num).toDouble(),
        date: DateTime.parse(p['created_at'] as String),
      ));
    }

    return ExpenseGroup(
      id: g['id'] as String,
      name: g['name'] as String,
      emoji: g['emoji'] as String,
      members: members,
      expenses: expenses,
      payments: payments,
      monthlyInterestPct: (g['monthly_interest_pct'] as num).toDouble(),
      ownerId: g['owner_id'] == _uid ? 'me' : g['owner_id'] as String,
      memberStatus: memberStatus,
      removedMemberIds: removedMemberIds,
      viewerRemoved: viewerRemoved,
      createdAt: DateTime.parse(g['created_at'] as String),
    );
  }

  /// Busca o mapa personId->group_members.id de um grupo (para escritas).
  Future<Map<String, String>> _personToGm(String groupId) async {
    final gms = await _c.from('group_members').select('id,profile_id').eq('group_id', groupId);
    final map = <String, String>{};
    for (final gm in gms) {
      final pid = gm['profile_id'] == _uid ? 'me' : gm['id'] as String;
      map[pid] = gm['id'] as String;
    }
    return map;
  }

  @override
  Future<ExpenseGroup> createGroup({
    required String name,
    required String emoji,
    required List<Person> members,
    double monthlyInterestPct = 0,
  }) async {
    final me = await currentUser();
    final g = await _c.from('groups').insert({
      'name': name,
      'emoji': emoji,
      'owner_id': _uid,
      'monthly_interest_pct': monthlyInterestPct,
    }).select('id').single();
    final groupId = g['id'] as String;

    // eu (aceito) + demais (pendentes, ligados ao perfil se já têm conta)
    final rows = <Map<String, dynamic>>[
      {'group_id': groupId, 'profile_id': _uid, 'name': me.name, 'last_name': me.lastName, 'phone': me.phone, 'status': 'accepted'},
    ];
    for (final m in members.where((m) => m.id != 'me')) {
      final pid = await _profileIdFor(m);
      rows.add({
        'group_id': groupId,
        if (pid != null) 'profile_id': pid,
        'name': m.name,
        'last_name': m.lastName,
        'phone': m.phone,
        'status': 'pending',
      });
    }
    await _c.from('group_members').insert(rows);
    return groupById(groupId);
  }

  Future<void> _writeExpense(String groupId, Expense e, Map<String, String> p2gm) async {
    final expenseId = e.id.length == 36 ? e.id : null; // ids do mock não são uuid
    final inserted = await _c
        .from('expenses')
        .upsert({
          if (expenseId != null) 'id': expenseId,
          'group_id': groupId,
          'description': e.description,
          'amount': e.amount,
          'paid_by': p2gm[e.paidByPersonId],
          'split_type': e.type.name,
          'date': e.date.toIso8601String(),
          'recurrence': e.recurrence.name,
          'recurrence_until': e.recurrenceUntil?.toIso8601String(),
          'recurrence_day': e.recurrenceDay,
          'recurrence_review': e.recurrenceReview.name,
          'recurrence_parent_id': e.recurrenceParentId,
          'occurrence_period': e.occurrencePeriod?.toIso8601String(),
          'category': e.category,
        })
        .select('id')
        .single();
    final id = inserted['id'] as String;
    await _c.from('expense_shares').delete().eq('expense_id', id);
    final shares = e.shares.entries
        .where((s) => p2gm[s.key] != null)
        .map((s) => {'expense_id': id, 'member_id': p2gm[s.key], 'share': s.value})
        .toList();
    if (shares.isNotEmpty) await _c.from('expense_shares').insert(shares);
  }

  @override
  Future<ExpenseGroup> addExpense(String groupId, Expense expense) async {
    await _writeExpense(groupId, expense, await _personToGm(groupId));
    return groupById(groupId);
  }

  @override
  Future<ExpenseGroup> updateExpense(String groupId, Expense expense) async {
    await _writeExpense(groupId, expense, await _personToGm(groupId));
    return groupById(groupId);
  }

  @override
  Future<ExpenseGroup> deleteExpense(String groupId, String expenseId) async {
    await _c.from('expenses').delete().eq('id', expenseId);
    return groupById(groupId);
  }

  @override
  Future<ExpenseGroup> addMember(String groupId, Person member) async {
    final pid = await _profileIdFor(member);
    await _c.from('group_members').insert({
      'group_id': groupId,
      if (pid != null) 'profile_id': pid,
      'name': member.name,
      'last_name': member.lastName,
      'phone': member.phone,
      'status': 'pending',
    });
    return groupById(groupId);
  }

  @override
  Future<ExpenseGroup> removeMember(String groupId, String personId) async {
    // Resolve o id da linha em group_members ('me' → a minha própria linha).
    String? memberId = personId == 'me' ? null : personId;
    if (memberId == null) {
      final mine = await _c
          .from('group_members')
          .select('id')
          .eq('group_id', groupId)
          .eq('profile_id', _uid)
          .maybeSingle();
      memberId = mine?['id'] as String?;
    }
    if (memberId != null) {
      // RPC autoritativa: checa saldo e decide entre soft-remove (mantém
      // histórico) e hard-delete (some). Lança se houver saldo em aberto.
      await _c.rpc('remove_group_member', params: {'p_member_id': memberId});
    }
    return groupById(groupId);
  }

  @override
  Future<ExpenseGroup> settleUp(String groupId, {required String fromId, required String toId, required double amount}) async {
    final p2gm = await _personToGm(groupId);
    await _c.from('payments').insert({
      'group_id': groupId,
      'from_member': p2gm[fromId],
      'to_member': p2gm[toId],
      'amount': amount,
    });
    return groupById(groupId);
  }

  @override
  Future<ExpenseGroup> undoPayment(String groupId, String paymentId) async {
    await _c.from('payments').delete().eq('id', paymentId);
    return groupById(groupId);
  }

  @override
  Future<String?> memberPixKey(String groupId, String personId) async {
    // resolve o profile_id do membro
    String? profileId;
    if (personId == 'me') {
      profileId = _uid;
    } else {
      final gm = await _c.from('group_members').select('profile_id').eq('id', personId).maybeSingle();
      profileId = gm?['profile_id'] as String?;
    }
    if (profileId == null) return null;
    if (profileId == _uid) {
      final row = await _c.from('profiles').select('pix_key').eq('id', _uid).maybeSingle();
      return row?['pix_key'] as String?;
    }
    // payee_info só retorna se houver vínculo aceito (#7)
    final res = await _c.rpc('payee_info', params: {'other': profileId}) as List;
    if (res.isEmpty) return null;
    return (res.first as Map)['pix_key'] as String?;
  }

  @override
  Future<ExpenseGroup> updateGroup(String groupId, {String? name, String? emoji, double? monthlyInterestPct}) async {
    await _c.from('groups').update({
      if (name != null) 'name': name,
      if (emoji != null) 'emoji': emoji,
      if (monthlyInterestPct != null) 'monthly_interest_pct': monthlyInterestPct,
    }).eq('id', groupId);
    return groupById(groupId);
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    await _c.from('groups').delete().eq('id', groupId);
  }

  @override
  Future<ExpenseGroup> generateRecurrences(String groupId) async {
    // A função é idempotente e escopada ao grupo (checa membership no servidor).
    await _c.rpc('generate_due_recurrences', params: {'p_group_id': groupId});
    return groupById(groupId);
  }

  // ----------------- Assinaturas -----------------
  static const _subSelect =
      'id,service_name,emoji,total_amount,billing_day,quota_count,monthly_interest_pct,owner_id,category,'
      'subscription_members(id,profile_id,name,last_name,phone,quota,status,months_late,invite_status,removed_at)';

  @override
  Future<List<Subscription>> subscriptions() async {
    final rows = await _c.from('subscriptions').select(_subSelect).order('created_at', ascending: false);
    return rows.map<Subscription>(_mapSub).toList();
  }

  @override
  Future<Subscription> subscriptionById(String id) async {
    final row = await _c.from('subscriptions').select(_subSelect).eq('id', id).single();
    return _mapSub(row);
  }

  Subscription _mapSub(Map<String, dynamic> s) {
    final members = <SubscriptionMember>[];
    var viewerRemoved = false;
    for (final m in (s['subscription_members'] as List).cast<Map<String, dynamic>>()) {
      final isMe = m['profile_id'] == _uid;
      final removed = m['removed_at'] != null;
      if (isMe && removed) viewerRemoved = true;
      members.add(SubscriptionMember(
        person: Person(
          id: isMe ? 'me' : m['id'] as String,
          name: isMe ? 'Você' : m['name'] as String,
          lastName: isMe ? null : m['last_name'] as String?,
          phone: m['phone'] as String?,
          profileId: m['profile_id'] as String?,
        ),
        quota: (m['quota'] as num).toDouble(),
        status: QuotaStatus.values.byName(m['status'] as String),
        monthsLate: (m['months_late'] as num?)?.toInt() ?? 0,
        inviteStatus: _statusFrom(m['invite_status'] as String?),
        removed: removed,
      ));
    }
    return Subscription(
      id: s['id'] as String,
      serviceName: s['service_name'] as String,
      emoji: s['emoji'] as String,
      totalAmount: (s['total_amount'] as num).toDouble(),
      billingDay: (s['billing_day'] as num).toInt(),
      quotaCount: (s['quota_count'] as num).toInt(),
      monthlyInterestPct: (s['monthly_interest_pct'] as num).toDouble(),
      ownerId: s['owner_id'] == _uid ? 'me' : s['owner_id'] as String,
      members: members,
      viewerRemoved: viewerRemoved,
      category: s['category'] as String?,
    );
  }

  @override
  Future<Subscription> createSubscription(Subscription subscription) async {
    final me = await currentUser();
    final s = await _c.from('subscriptions').insert({
      'service_name': subscription.serviceName,
      'emoji': subscription.emoji,
      'total_amount': subscription.totalAmount,
      'billing_day': subscription.billingDay,
      'quota_count': subscription.quotaCount,
      'monthly_interest_pct': subscription.monthlyInterestPct,
      'category': subscription.category,
      'owner_id': _uid,
    }).select('id').single();
    final subId = s['id'] as String;
    final rows = subscription.members.map((m) => {
          'subscription_id': subId,
          if (m.person.id == 'me') 'profile_id': _uid,
          'name': m.person.id == 'me' ? me.name : m.person.name,
          'last_name': m.person.id == 'me' ? me.lastName : m.person.lastName,
          'phone': m.person.phone,
          'quota': m.quota,
          'status': m.status.name,
          // o dono não precisa aceitar convite da própria assinatura (#1)
          'invite_status': m.person.id == 'me' ? 'accepted' : 'pending',
        }).toList();
    if (rows.isNotEmpty) await _c.from('subscription_members').insert(rows);
    return subscriptionById(subId);
  }

  @override
  Future<Subscription> updateSubscription(
    String id, {
    String? serviceName,
    String? emoji,
    double? totalAmount,
    int? billingDay,
    int? quotaCount,
    double? monthlyInterestPct,
    String? category,
  }) async {
    await _c.from('subscriptions').update({
      if (serviceName != null) 'service_name': serviceName,
      if (emoji != null) 'emoji': emoji,
      if (totalAmount != null) 'total_amount': totalAmount,
      if (billingDay != null) 'billing_day': billingDay,
      if (quotaCount != null) 'quota_count': quotaCount,
      if (monthlyInterestPct != null) 'monthly_interest_pct': monthlyInterestPct,
      if (category != null) 'category': category,
    }).eq('id', id);
    return subscriptionById(id);
  }

  @override
  Future<Subscription> setQuotaStatus(String subscriptionId, String personId, QuotaStatus status) async {
    final query = _c.from('subscription_members').update({'status': status.name}).eq('subscription_id', subscriptionId);
    if (personId == 'me') {
      await query.eq('profile_id', _uid);
    } else {
      await query.eq('id', personId);
    }
    return subscriptionById(subscriptionId);
  }

  @override
  Future<Subscription> addSubscriptionMember(String subscriptionId, SubscriptionMember member) async {
    final pid = await _profileIdFor(member.person);
    await _c.from('subscription_members').insert({
      'subscription_id': subscriptionId,
      if (pid != null) 'profile_id': pid,
      'name': member.person.name,
      'last_name': member.person.lastName,
      'phone': member.person.phone,
      'quota': member.quota,
      'status': member.status.name,
      'invite_status': 'pending',
    });
    return subscriptionById(subscriptionId);
  }

  @override
  Future<Subscription> removeSubscriptionMember(String subscriptionId, String personId) async {
    String? memberId = personId == 'me' ? null : personId;
    if (memberId == null) {
      final mine = await _c
          .from('subscription_members')
          .select('id')
          .eq('subscription_id', subscriptionId)
          .eq('profile_id', _uid)
          .maybeSingle();
      memberId = mine?['id'] as String?;
    }
    if (memberId != null) {
      await _c.rpc('remove_subscription_member', params: {'p_member_id': memberId});
    }
    return subscriptionById(subscriptionId);
  }

  // ---- Caixinhas ----
  // A RLS (migração ..._caixinha.sql) filtra por papel: o borrower só recebe as
  // próprias linhas de empréstimo/pagamento e o próprio cadastro, então o
  // mapeamento abaixo já chega "restrito" para ele — a UI complementa a visão.
  static const _caixinhaSelect =
      'id,name,emoji,owner_id,default_interest_pct,monthly_quota,payment_day,status,created_at,closed_at,start_date,end_date,'
      'caixinha_members(id,profile_id,name,last_name,phone,role,invite_status,quotas),'
      'caixinha_contributions(id,member_id,amount,date,recorded_by,note),'
      'caixinha_loans(id,borrower_member_id,borrower_name,principal,interest_pct,date,due_date),'
      'caixinha_earnings(id,amount,source,loan_id,note,date,recorded_by),'
      'caixinha_loan_payments(id,loan_id,amount,note,date),'
      'caixinha_exits(id,member_id,refund,date,recorded_by),'
      'caixinha_adjustments(id,member_id,delta,note,date,recorded_by),'
      'caixinha_cota_charges(id,member_id,amount,paid_amount,note,date,recorded_by)';

  Caixinha _mapCaixinha(Map<String, dynamic> c) {
    final cms = (c['caixinha_members'] as List? ?? const []).cast<Map<String, dynamic>>();
    final idToPerson = <String, String>{}; // id da linha -> personId ('me' ou id)
    final profileToPerson = <String, String>{}; // profile_id -> personId (autoria)
    final members = <CaixinhaMember>[];
    for (final m in cms) {
      final isMe = m['profile_id'] == _uid;
      final pid = isMe ? 'me' : m['id'] as String;
      idToPerson[m['id'] as String] = pid;
      if (m['profile_id'] != null) profileToPerson[m['profile_id'] as String] = pid;
      members.add(CaixinhaMember(
        person: Person(
          id: pid,
          name: isMe ? 'Você' : m['name'] as String,
          lastName: isMe ? null : m['last_name'] as String?,
          phone: m['phone'] as String?,
          profileId: m['profile_id'] as String?,
        ),
        role: CaixinhaRole.values.byName(m['role'] as String),
        inviteStatus: _statusFrom(m['invite_status'] as String?),
        quotas: (m['quotas'] as num?)?.toInt() ?? 1,
      ));
    }

    String person(dynamic memberRowId) => idToPerson[memberRowId] ?? memberRowId as String;
    // Autoria: recorded_by é um profile_id. Traduz p/ personId ('me' ou id da
    // linha do membro); null quando desconhecido (lançamento antigo/perfil fora).
    String? recorder(dynamic profileId) => profileId == null ? null : profileToPerson[profileId as String];

    return Caixinha(
      id: c['id'] as String,
      name: c['name'] as String,
      emoji: c['emoji'] as String? ?? '🐷',
      ownerId: c['owner_id'] == _uid ? 'me' : c['owner_id'] as String,
      defaultInterestPct: (c['default_interest_pct'] as num).toDouble(),
      monthlyQuota: (c['monthly_quota'] as num).toDouble(),
      paymentDay: (c['payment_day'] as num?)?.toInt(),
      status: c['status'] == 'closed' ? CaixinhaStatus.closed : CaixinhaStatus.open,
      createdAt: DateTime.parse(c['created_at'] as String),
      closedAt: c['closed_at'] != null ? DateTime.parse(c['closed_at'] as String) : null,
      startDate: c['start_date'] != null ? DateTime.parse(c['start_date'] as String) : null,
      endDate: c['end_date'] != null ? DateTime.parse(c['end_date'] as String) : null,
      members: members,
      contributions: [
        for (final x in (c['caixinha_contributions'] as List? ?? const []).cast<Map<String, dynamic>>())
          Contribution(
            id: x['id'] as String,
            personId: person(x['member_id']),
            amount: (x['amount'] as num).toDouble(),
            date: DateTime.parse(x['date'] as String),
            recordedBy: recorder(x['recorded_by']),
            note: x['note'] as String?,
          ),
      ],
      loans: [
        for (final x in (c['caixinha_loans'] as List? ?? const []).cast<Map<String, dynamic>>())
          Loan(
            id: x['id'] as String,
            borrowerName: x['borrower_name'] as String,
            borrowerPersonId: person(x['borrower_member_id']),
            principal: (x['principal'] as num).toDouble(),
            interestPct: (x['interest_pct'] as num).toDouble(),
            date: DateTime.parse(x['date'] as String),
            dueDate: x['due_date'] != null ? DateTime.parse(x['due_date'] as String) : null,
          ),
      ],
      earnings: [
        for (final x in (c['caixinha_earnings'] as List? ?? const []).cast<Map<String, dynamic>>())
          Earning(
            id: x['id'] as String,
            amount: (x['amount'] as num).toDouble(),
            source: EarningSource.values.byName(x['source'] as String),
            loanId: x['loan_id'] as String?,
            note: x['note'] as String?,
            date: DateTime.parse(x['date'] as String),
            recordedBy: recorder(x['recorded_by']),
          ),
      ],
      loanPayments: [
        for (final x in (c['caixinha_loan_payments'] as List? ?? const []).cast<Map<String, dynamic>>())
          LoanPayment(id: x['id'] as String, loanId: x['loan_id'] as String, amount: (x['amount'] as num).toDouble(), note: x['note'] as String?, date: DateTime.parse(x['date'] as String)),
      ],
      exits: [
        for (final x in (c['caixinha_exits'] as List? ?? const []).cast<Map<String, dynamic>>())
          MemberExit(id: x['id'] as String, memberId: person(x['member_id']), refund: (x['refund'] as num).toDouble(), date: DateTime.parse(x['date'] as String), recordedBy: recorder(x['recorded_by'])),
      ],
      adjustments: [
        for (final x in (c['caixinha_adjustments'] as List? ?? const []).cast<Map<String, dynamic>>())
          Adjustment(id: x['id'] as String, memberId: person(x['member_id']), delta: (x['delta'] as num).toDouble(), note: x['note'] as String?, date: DateTime.parse(x['date'] as String), recordedBy: recorder(x['recorded_by'])),
      ],
      cotaCharges: [
        for (final x in (c['caixinha_cota_charges'] as List? ?? const []).cast<Map<String, dynamic>>())
          CotaInterestCharge(
            id: x['id'] as String,
            memberId: person(x['member_id']),
            amount: (x['amount'] as num).toDouble(),
            paidAmount: (x['paid_amount'] as num?)?.toDouble() ?? 0,
            note: x['note'] as String?,
            date: DateTime.parse(x['date'] as String),
            recordedBy: recorder(x['recorded_by']),
          ),
      ],
    );
  }

  Future<String> _myCaixinhaMemberId(String caixinhaId) async {
    final r = await _c.from('caixinha_members').select('id').eq('caixinha_id', caixinhaId).eq('profile_id', _uid).single();
    return r['id'] as String;
  }

  @override
  Future<List<Caixinha>> caixinhas() async {
    final rows = await _c.from('caixinhas').select(_caixinhaSelect).order('created_at', ascending: false);
    return rows.map<Caixinha>(_mapCaixinha).toList();
  }

  @override
  Future<Caixinha> caixinhaById(String id) async {
    final row = await _c.from('caixinhas').select(_caixinhaSelect).eq('id', id).single();
    return _mapCaixinha(row);
  }

  @override
  Future<Caixinha> createCaixinha({required String name, required String emoji, required double defaultInterestPct, required double monthlyQuota, required List<Person> members, Map<String, int> quotas = const {}, Map<String, double> openingBalances = const {}, Set<String> treasurers = const {}, DateTime? startDate, DateTime? endDate, int? paymentDay}) async {
    final me = await currentUser();
    // Ids gerados no cliente: evitam o SELECT pós-insert (INSERT...RETURNING) —
    // fonte comum de erro de RLS — e permitem amarrar os aportes semente aos
    // membros sem uma segunda ida ao banco.
    final cid = const Uuid().v4();
    await _c.from('caixinhas').insert({
      'id': cid,
      'name': name,
      'emoji': emoji,
      'owner_id': _uid,
      'default_interest_pct': defaultInterestPct,
      'monthly_quota': monthlyQuota,
      if (paymentDay != null) 'payment_day': paymentDay,
      if (startDate != null) 'start_date': _dateOnly(startDate),
      if (endDate != null) 'end_date': _dateOnly(endDate),
    });

    // person.id ('me' ou id do Person convidado) -> id da linha de membro.
    final memberRowId = <String, String>{'me': const Uuid().v4()};
    final rows = <Map<String, dynamic>>[
      {'id': memberRowId['me'], 'caixinha_id': cid, 'profile_id': _uid, 'name': me.name, 'last_name': me.lastName, 'phone': me.phone, 'role': 'owner', 'invite_status': 'accepted', 'quotas': quotas['me'] ?? 1},
    ];
    for (final m in members.where((m) => m.id != 'me')) {
      final pid = await _profileIdFor(m);
      memberRowId[m.id] = const Uuid().v4();
      rows.add({
        'id': memberRowId[m.id],
        'caixinha_id': cid,
        if (pid != null) 'profile_id': pid,
        'name': m.name,
        'last_name': m.lastName,
        'phone': m.phone,
        'role': treasurers.contains(m.id) ? 'treasurer' : 'member',
        'invite_status': 'pending',
        'quotas': quotas[m.id] ?? 1,
      });
    }
    await _c.from('caixinha_members').insert(rows);

    // Aporte semente (caixinha em andamento): saldo atual de cada um → 1 aporte
    // na abertura. Só para quem tem linha de membro e saldo > 0.
    final seed = <Map<String, dynamic>>[
      for (final e in openingBalances.entries)
        if (e.value > 0 && memberRowId[e.key] != null)
          {'caixinha_id': cid, 'member_id': memberRowId[e.key], 'amount': e.value},
    ];
    if (seed.isNotEmpty) await _c.from('caixinha_contributions').insert(seed);

    return caixinhaById(cid);
  }

  @override
  Future<Caixinha> updateCaixinha(String id, {String? name, String? emoji, double? defaultInterestPct, double? monthlyQuota, DateTime? startDate, DateTime? endDate, int? paymentDay}) async {
    await _c.from('caixinhas').update({
      if (name != null) 'name': name,
      if (emoji != null) 'emoji': emoji,
      if (defaultInterestPct != null) 'default_interest_pct': defaultInterestPct,
      if (monthlyQuota != null) 'monthly_quota': monthlyQuota,
      if (paymentDay != null) 'payment_day': paymentDay,
      if (startDate != null) 'start_date': _dateOnly(startDate),
      if (endDate != null) 'end_date': _dateOnly(endDate),
    }).eq('id', id);
    return caixinhaById(id);
  }

  static String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  @override
  Future<Caixinha> addContribution(String caixinhaId, {required String personId, required double amount, DateTime? date}) async {
    final memberId = personId == 'me' ? await _myCaixinhaMemberId(caixinhaId) : personId;
    await _c.from('caixinha_contributions').insert({
      'caixinha_id': caixinhaId,
      'member_id': memberId,
      'amount': amount,
      if (date != null) 'date': date.toUtc().toIso8601String(),
    });
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> addEarning(String caixinhaId, {required double amount, required EarningSource source, String? loanId, String? note, DateTime? date}) async {
    await _c.from('caixinha_earnings').insert({
      'caixinha_id': caixinhaId,
      'amount': amount,
      'source': source.name,
      if (loanId != null) 'loan_id': loanId,
      if (note != null) 'note': note,
      if (date != null) 'date': date.toUtc().toIso8601String(),
    });
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> addLoan(String caixinhaId, {required Person borrower, required bool external, required double principal, required double interestPct, DateTime? dueDate, DateTime? date}) async {
    String memberId;
    if (borrower.id == 'me') {
      memberId = await _myCaixinhaMemberId(caixinhaId);
    } else {
      // Já existe essa linha de membro nesta caixinha? (membro contribuinte ou
      // tomador externo já cadastrado).
      final existing = await _c.from('caixinha_members').select('id').eq('caixinha_id', caixinhaId).eq('id', borrower.id).maybeSingle();
      if (existing != null) {
        memberId = existing['id'] as String;
      } else {
        // Novo tomador externo: cadastra a pessoa (papel borrower, sem aceite).
        final pid = await _profileIdFor(borrower);
        final inserted = await _c.from('caixinha_members').insert({
          'caixinha_id': caixinhaId,
          if (pid != null) 'profile_id': pid,
          'name': borrower.name,
          'last_name': borrower.lastName,
          'phone': borrower.phone,
          'role': 'borrower',
          'invite_status': 'accepted',
        }).select('id').single();
        memberId = inserted['id'] as String;
      }
    }
    final loanDate = date ?? DateTime.now();
    final loanId = const Uuid().v4();
    await _c.from('caixinha_loans').insert({
      'id': loanId,
      'caixinha_id': caixinhaId,
      'borrower_member_id': memberId,
      'borrower_name': borrower.name,
      'principal': principal,
      'interest_pct': interestPct,
      if (dueDate != null) 'due_date': dueDate.toIso8601String(),
      'date': loanDate.toUtc().toIso8601String(),
    });
    // Retroativo: juros cheios mês a mês até hoje.
    final retro = retroactiveLoanInterest(loanDate: loanDate, principal: principal, interestPct: interestPct, now: DateTime.now());
    if (retro.isNotEmpty) {
      await _c.from('caixinha_earnings').insert([
        for (final e in retro)
          {'caixinha_id': caixinhaId, 'amount': e.amount, 'source': 'loanInterest', 'loan_id': loanId, 'note': 'Juros de ${borrower.name}', 'date': e.date.toUtc().toIso8601String()},
      ]);
    }
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> updateLoan(String caixinhaId, String loanId, {double? principal, double? interestPct, DateTime? date, DateTime? dueDate}) async {
    await _c.from('caixinha_loans').update({
      if (principal != null) 'principal': principal,
      if (interestPct != null) 'interest_pct': interestPct,
      if (date != null) 'date': date.toUtc().toIso8601String(),
      if (dueDate != null) 'due_date': dueDate.toIso8601String(),
    }).eq('id', loanId);
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> settleCotaArrears(
    String caixinhaId, {
    required String personId,
    required List<({DateTime date, double amount})> contributions,
    required double interestPaid,
    required List<({String chargeId, double amount})> chargePayments,
    required double newCharge,
    DateTime? date,
  }) async {
    final memberId = personId == 'me' ? await _myCaixinhaMemberId(caixinhaId) : personId;
    final when = date ?? DateTime.now();

    // 1) Aportes retroativos (datados no vencimento de cada mês).
    if (contributions.isNotEmpty) {
      await _c.from('caixinha_contributions').insert([
        for (final f in contributions)
          {
            'caixinha_id': caixinhaId,
            'member_id': memberId,
            'amount': f.amount,
            'date': f.date.toUtc().toIso8601String(),
            'note': 'Quitação de atraso',
          },
      ]);
    }
    // 2) Juro pago vira rendimento da caixinha.
    if (interestPaid > 0.005) {
      final nome = (await caixinhaById(caixinhaId)).fullNameOf(personId);
      await _c.from('caixinha_earnings').insert({
        'caixinha_id': caixinhaId,
        'amount': interestPaid,
        'source': 'loanInterest',
        'note': 'Juros por atraso — $nome',
        'date': when.toUtc().toIso8601String(),
      });
    }
    // 3) Abate juros já cristalizados (paid_amount += valor).
    for (final p in chargePayments) {
      final row = await _c.from('caixinha_cota_charges').select('paid_amount').eq('id', p.chargeId).single();
      final atual = (row['paid_amount'] as num?)?.toDouble() ?? 0;
      await _c.from('caixinha_cota_charges').update({
        'paid_amount': double.parse((atual + p.amount).toStringAsFixed(2)),
      }).eq('id', p.chargeId);
    }
    // 4) Cristaliza o juro que saiu do derivado sem ter sido pago.
    if (newCharge > 0.005) {
      await _c.from('caixinha_cota_charges').insert({
        'caixinha_id': caixinhaId,
        'member_id': memberId,
        'amount': newCharge,
        'note': 'Juros de atraso pendentes',
        'date': when.toUtc().toIso8601String(),
      });
    }
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> recordLoanInterest(String caixinhaId, String loanId, double amount, {DateTime? date}) async {
    await _c.from('caixinha_earnings').insert({
      'caixinha_id': caixinhaId,
      'amount': amount,
      'source': 'loanInterest',
      'loan_id': loanId,
      if (date != null) 'date': date.toUtc().toIso8601String(),
    });
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> addLoanPayment(String caixinhaId, String loanId, {required double amount, String? note, DateTime? date}) async {
    await _c.from('caixinha_loan_payments').insert({
      'caixinha_id': caixinhaId,
      'loan_id': loanId,
      'amount': amount,
      if (note != null) 'note': note,
      if (date != null) 'date': date.toUtc().toIso8601String(),
    });
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> setTreasurer(String caixinhaId, String personId, bool isTreasurer) async {
    await _c.from('caixinha_members').update({'role': isTreasurer ? 'treasurer' : 'member'}).eq('id', personId).inFilter('role', ['member', 'treasurer']);
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> setMemberQuotas(String caixinhaId, String personId, int quotas) async {
    final memberId = personId == 'me' ? await _myCaixinhaMemberId(caixinhaId) : personId;
    await _c.from('caixinha_members').update({'quotas': quotas}).eq('id', memberId);
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> exitMember(String caixinhaId, String personId, {required double refund}) async {
    final memberId = personId == 'me' ? await _myCaixinhaMemberId(caixinhaId) : personId;
    await _c.from('caixinha_exits').insert({'caixinha_id': caixinhaId, 'member_id': memberId, 'refund': refund});
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> adjustBalance(String caixinhaId, String personId, {required double delta, String? note, DateTime? date}) async {
    final memberId = personId == 'me' ? await _myCaixinhaMemberId(caixinhaId) : personId;
    await _c.from('caixinha_adjustments').insert({
      'caixinha_id': caixinhaId,
      'member_id': memberId,
      'delta': delta,
      if (note != null) 'note': note,
      if (date != null) 'date': date.toUtc().toIso8601String(),
    });
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> undoMovement(String caixinhaId, {required MovementKind kind, required String sourceId}) async {
    final table = switch (kind) {
      MovementKind.contribution => 'caixinha_contributions',
      MovementKind.earning => 'caixinha_earnings',
      MovementKind.adjustment => 'caixinha_adjustments',
      MovementKind.exit => 'caixinha_exits',
    };
    await _c.from(table).delete().eq('id', sourceId);
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> addCaixinhaMember(String caixinhaId, Person member) async {
    final pid = await _profileIdFor(member);
    await _c.from('caixinha_members').insert({
      'caixinha_id': caixinhaId,
      if (pid != null) 'profile_id': pid,
      'name': member.name,
      'last_name': member.lastName,
      'phone': member.phone,
      'role': 'member',
      'invite_status': 'pending',
    });
    return caixinhaById(caixinhaId);
  }

  @override
  Future<Caixinha> closeCaixinha(String caixinhaId) async {
    await _c.from('caixinhas').update({'status': 'closed', 'closed_at': DateTime.now().toUtc().toIso8601String()}).eq('id', caixinhaId);
    return caixinhaById(caixinhaId);
  }

  @override
  Future<void> deleteCaixinha(String caixinhaId) async {
    await _c.from('caixinhas').delete().eq('id', caixinhaId);
  }
}
