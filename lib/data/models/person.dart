import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

/// Sentinela p/ distinguir "não informado" de "null" no [Person.copyWith].
const Object _unset = Object();

/// Situação do vínculo de um membro num grupo/assinatura (Convite/Social — Etapa C).
/// - [pending]: convidado, ainda não respondeu.
/// - [accepted]: aceitou o convite; nome real "liberado" (some as aspas).
/// - [declined]: recusou; continua no grupo com indicativo, podendo aceitar depois.
enum MemberStatus { pending, accepted, declined }

/// Pessoa: pode ser o usuário logado ou um membro adicionado por contato.
/// No MVP membros podem existir só como nome+telefone antes de terem conta.
@immutable
class Person {
  final String id;

  /// **Primeiro nome** — é o que se exibe por padrão no feed, grupos,
  /// assinaturas e despesas. Nunca use direto onde precisa do nome completo:
  /// prefira [fullName].
  final String name;

  /// Sobrenome (pode ser composto). Null/vazio para quem só tem primeiro nome.
  final String? lastName;
  final String? phone; // com DDI, só dígitos, ex.: 5511999998888
  final String? photoUrl;
  final String? pixKey;

  const Person({
    required this.id,
    required this.name,
    this.lastName,
    this.phone,
    this.photoUrl,
    this.pixKey,
  });

  /// Nome completo "Nome Sobrenome" (só o primeiro nome quando não há sobrenome).
  String get fullName {
    final l = lastName?.trim() ?? '';
    return l.isEmpty ? name : '$name $l';
  }

  /// Iniciais para o avatar: 1ª letra do nome + 1ª do sobrenome, sempre em
  /// MAIÚSCULAS (duas letras quando há sobrenome). Sem sobrenome, cai no
  /// desmembramento do próprio nome (ex.: nomes completos legados).
  String get initials => initialsOf(name, lastName);

  /// [lastName] usa sentinela para permitir **limpar** o sobrenome: omitir
  /// mantém o atual; passar `null` explícito apaga. Ex.: `copyWith(lastName: null)`.
  Person copyWith({String? name, Object? lastName = _unset, String? phone, String? photoUrl, String? pixKey}) => Person(
        id: id,
        name: name ?? this.name,
        lastName: identical(lastName, _unset) ? this.lastName : lastName as String?,
        phone: phone ?? this.phone,
        photoUrl: photoUrl ?? this.photoUrl,
        pixKey: pixKey ?? this.pixKey,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'last_name': lastName,
        'phone': phone,
        'photo_url': photoUrl,
        'pix_key': pixKey,
      };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'] as String,
        name: json['name'] as String,
        lastName: json['last_name'] as String?,
        phone: json['phone'] as String?,
        photoUrl: json['photo_url'] as String?,
        pixKey: json['pix_key'] as String?,
      );
}

/// Iniciais de exibição a partir de um primeiro nome + sobrenome (ambos podem
/// vir soltos). Regra: 1ª letra do nome + 1ª do sobrenome, em MAIÚSCULAS.
/// Quando não há sobrenome, desmembra o próprio [name] (1ª+última palavra),
/// tolerando nomes completos digitados num campo só.
String initialsOf(String name, [String? lastName]) {
  String pick(String s) => s.isEmpty ? '' : s.characters.first.toUpperCase();
  final first = name.trim();
  final last = (lastName ?? '').trim();
  if (last.isNotEmpty) {
    final i = pick(first) + pick(last);
    return i.isEmpty ? '?' : i;
  }
  // Só palavras que começam com letra/dígito (ignora "(organizador)" etc.).
  final letter = RegExp(r'^[\p{L}\p{N}]', unicode: true);
  final parts = first
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && letter.hasMatch(p))
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return pick(parts.first);
  return pick(parts.first) + pick(parts.last);
}
