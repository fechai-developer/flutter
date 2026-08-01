import 'package:flutter/foundation.dart';

/// Como uma despesa é dividida entre os participantes.
/// - [equal]: partes iguais entre os selecionados.
/// - [percentage]: cada um com um % do total (soma = 100%).
/// - [weight]: cada um com um peso/partes (ex.: 2 pra quem comeu mais).
/// - [exact]: valor exato por pessoa (soma = total).
enum SplitType { equal, percentage, weight, exact }

extension SplitTypeLabel on SplitType {
  String get label => switch (this) {
        SplitType.equal => 'Igual',
        SplitType.percentage => 'Porcentagem',
        SplitType.weight => 'Partes',
        SplitType.exact => 'Valor exato',
      };
}

/// Calcula quanto cada pessoa deve, a partir do tipo de divisão e dos inputs
/// brutos por pessoa. Arredonda em centavos e joga a sobra no primeiro
/// participante, garantindo que a soma feche exatamente com [amount].
Map<String, double> computeShares({
  required double amount,
  required SplitType type,
  required List<String> participantIds,
  Map<String, double> inputs = const {},
}) {
  if (participantIds.isEmpty) return {};
  double round2(double v) => double.parse(v.toStringAsFixed(2));

  final shares = <String, double>{};
  switch (type) {
    case SplitType.equal:
      final base = round2(amount / participantIds.length);
      for (final p in participantIds) {
        shares[p] = base;
      }
    case SplitType.percentage:
      for (final p in participantIds) {
        shares[p] = round2(amount * (inputs[p] ?? 0) / 100);
      }
    case SplitType.weight:
      final total = participantIds.fold<double>(0, (a, p) => a + (inputs[p] ?? 0));
      for (final p in participantIds) {
        shares[p] = total == 0 ? 0 : round2(amount * (inputs[p] ?? 0) / total);
      }
    case SplitType.exact:
      for (final p in participantIds) {
        shares[p] = round2(inputs[p] ?? 0);
      }
  }

  // Ajuste de sobra de arredondamento no primeiro participante.
  final sum = shares.values.fold<double>(0, (a, b) => a + b);
  final diff = round2(amount - sum);
  if (diff != 0) {
    shares[participantIds.first] = round2(shares[participantIds.first]! + diff);
  }
  return shares;
}

/// Uma despesa lançada num grupo de evento.
/// [shares] guarda o quanto CADA pessoa deve daquela despesa (em R$),
/// já resolvido a partir do [type]. Somatório de shares == amount.
/// Recorrência de uma despesa (#2).
enum Recurrence { none, monthly }

/// Sinaliza que uma despesa recorrente precisa de atenção porque alguém saiu
/// do grupo. Só se aplica a despesas com [Recurrence.monthly].
/// - [none]: sem pendência.
/// - [participantLeft]: um participante do rateio foi removido → a próxima
///   ocorrência será **redividida entre os ativos** (aviso, não bloqueia).
/// - [payerLeft]: quem **pagava** a recorrência saiu → precisa reatribuir o
///   pagador antes de gerar a próxima (bloqueia a geração da Fase E).
enum RecurrenceReview { none, participantLeft, payerLeft }

@immutable
class Expense {
  final String id;
  final String description;
  final double amount;
  final String paidByPersonId;
  final SplitType type;
  final Map<String, double> shares; // personId -> valor devido
  final DateTime date;
  final Recurrence recurrence;
  final DateTime? recurrenceUntil; // repete até esta data (inclusive)
  final int? recurrenceDay; // dia do mês em que repete (1–27); null se não recorrente
  /// Pendência de revisão da recorrência quando alguém envolvido saiu do grupo.
  final RecurrenceReview recurrenceReview;

  /// Se esta despesa é uma **ocorrência gerada** de uma recorrência, aponta para
  /// o id da despesa-molde. Null = molde ou despesa avulsa.
  final String? recurrenceParentId;

  /// Mês (1º dia) a que a ocorrência gerada pertence — usado para não duplicar
  /// a geração. Null nos moldes/avulsas.
  final DateTime? occurrencePeriod;

  /// Tipo (categoria) do gasto — texto livre sugerido (ver core/categories.dart).
  /// Null = sem tipo definido.
  final String? category;

  /// O que a pessoa DIGITOU no rateio, sob o [type] — "3, 2, 1" em partes,
  /// "50, 30, 20" em porcentagem, os valores em exato. Null quando a divisão é
  /// igual (não há o que digitar) ou em despesas antigas, salvas antes deste
  /// campo existir.
  ///
  /// Existe porque [shares] é **irreversível**: 3:2:1 de R$ 100 vira
  /// 50,00 / 33,33 / 16,67 e não há como voltar exatamente às partes originais
  /// a partir do dinheiro (o arredondamento em centavos come a razão). Guardar
  /// o que foi digitado é o que faz a tela de edição reabrir com "3x, 2x, 1x"
  /// em vez dos valores calculados.
  final Map<String, double>? splitInputs;

  const Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.paidByPersonId,
    required this.type,
    required this.shares,
    required this.date,
    this.recurrence = Recurrence.none,
    this.recurrenceUntil,
    this.recurrenceDay,
    this.recurrenceReview = RecurrenceReview.none,
    this.recurrenceParentId,
    this.occurrencePeriod,
    this.category,
    this.splitInputs,
  });

  bool get isRecurring => recurrence != Recurrence.none;

  /// Recorrência afetada por uma saída — o dono precisa revisar antes da próxima.
  bool get needsRecurrenceReview => recurrenceReview != RecurrenceReview.none;

  /// Factory geral: monta a despesa resolvendo os [shares] a partir do
  /// [type] e dos [inputs] brutos por pessoa (% / partes / valor exato).
  factory Expense.create({
    required String id,
    required String description,
    required double amount,
    required String paidByPersonId,
    required SplitType type,
    required List<String> participantIds,
    Map<String, double> inputs = const {},
    required DateTime date,
    Recurrence recurrence = Recurrence.none,
    DateTime? recurrenceUntil,
    int? recurrenceDay,
    RecurrenceReview recurrenceReview = RecurrenceReview.none,
    String? recurrenceParentId,
    DateTime? occurrencePeriod,
    String? category,
  }) {
    return Expense(
      id: id,
      description: description,
      amount: amount,
      paidByPersonId: paidByPersonId,
      type: type,
      shares: computeShares(
        amount: amount,
        type: type,
        participantIds: participantIds,
        inputs: inputs,
      ),
      // Guarda o que foi digitado para a edição reabrir igual (ver [splitInputs]).
      // Em divisão igual não há entrada do usuário.
      splitInputs: type == SplitType.equal
          ? null
          : {for (final p in participantIds) p: inputs[p] ?? 0},
      date: date,
      recurrence: recurrence,
      recurrenceUntil: recurrenceUntil,
      recurrenceDay: recurrenceDay,
      recurrenceReview: recurrenceReview,
      recurrenceParentId: recurrenceParentId,
      occurrencePeriod: occurrencePeriod,
      category: category,
    );
  }

  /// Divisão igualitária entre [participantIds].
  factory Expense.equalSplit({
    required String id,
    required String description,
    required double amount,
    required String paidByPersonId,
    required List<String> participantIds,
    required DateTime date,
    String? category,
  }) {
    final n = participantIds.length;
    final base = (amount / n);
    // arredonda em centavos e joga o resto no primeiro participante
    final rounded = double.parse(base.toStringAsFixed(2));
    final shares = <String, double>{for (final p in participantIds) p: rounded};
    final diff = double.parse((amount - rounded * n).toStringAsFixed(2));
    if (participantIds.isNotEmpty && diff != 0) {
      shares[participantIds.first] =
          double.parse((shares[participantIds.first]! + diff).toStringAsFixed(2));
    }
    return Expense(
      id: id,
      description: description,
      amount: amount,
      paidByPersonId: paidByPersonId,
      type: SplitType.equal,
      shares: shares,
      date: date,
      category: category,
    );
  }

  Expense copyWith({
    String? description,
    double? amount,
    String? paidByPersonId,
    SplitType? type,
    Map<String, double>? shares,
    DateTime? date,
    Recurrence? recurrence,
    DateTime? recurrenceUntil,
    int? recurrenceDay,
    RecurrenceReview? recurrenceReview,
    String? recurrenceParentId,
    DateTime? occurrencePeriod,
    String? category,
    Map<String, double>? splitInputs,
  }) =>
      Expense(
        id: id,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        paidByPersonId: paidByPersonId ?? this.paidByPersonId,
        type: type ?? this.type,
        shares: shares ?? this.shares,
        splitInputs: splitInputs ?? this.splitInputs,
        date: date ?? this.date,
        recurrence: recurrence ?? this.recurrence,
        recurrenceUntil: recurrenceUntil ?? this.recurrenceUntil,
        recurrenceDay: recurrenceDay ?? this.recurrenceDay,
        recurrenceReview: recurrenceReview ?? this.recurrenceReview,
        recurrenceParentId: recurrenceParentId ?? this.recurrenceParentId,
        occurrencePeriod: occurrencePeriod ?? this.occurrencePeriod,
        category: category ?? this.category,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'amount': amount,
        'paid_by': paidByPersonId,
        'type': type.name,
        'shares': shares,
        'date': date.toIso8601String(),
        'recurrence': recurrence.name,
        'recurrence_until': recurrenceUntil?.toIso8601String(),
        'recurrence_day': recurrenceDay,
        'recurrence_review': recurrenceReview.name,
        'recurrence_parent_id': recurrenceParentId,
        'occurrence_period': occurrencePeriod?.toIso8601String(),
        'category': category,
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        description: json['description'] as String,
        amount: (json['amount'] as num).toDouble(),
        paidByPersonId: json['paid_by'] as String,
        type: SplitType.values.byName(json['type'] as String),
        shares: (json['shares'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        date: DateTime.parse(json['date'] as String),
        recurrence: Recurrence.values.byName((json['recurrence'] as String?) ?? 'none'),
        recurrenceUntil: json['recurrence_until'] != null
            ? DateTime.parse(json['recurrence_until'] as String)
            : null,
        recurrenceDay: (json['recurrence_day'] as num?)?.toInt(),
        recurrenceReview: RecurrenceReview.values.byName((json['recurrence_review'] as String?) ?? 'none'),
        recurrenceParentId: json['recurrence_parent_id'] as String?,
        occurrencePeriod: json['occurrence_period'] != null
            ? DateTime.parse(json['occurrence_period'] as String)
            : null,
        category: json['category'] as String?,
      );
}
