import 'package:flutter/material.dart';

import '../../data/models/person.dart';
import '../../theme/app_theme.dart';

/// Avatar circular com iniciais e cor derivada do nome — usado em membros de
/// grupos e participantes de assinaturas. Fallback quando não há foto.
///
/// As iniciais são a 1ª letra do [name] + a 1ª do [lastName] (duas maiúsculas).
/// Quando [lastName] é nulo, desmembra o próprio [name] (compatível com nomes
/// completos passados num campo só).
class MemberAvatar extends StatelessWidget {
  final String name;
  final String? lastName;
  final double size;
  final String? photoUrl;

  const MemberAvatar({
    super.key,
    required this.name,
    this.lastName,
    this.size = 40,
    this.photoUrl,
  });

  /// Conveniência: monta a partir de uma [Person] (nome + sobrenome + foto).
  MemberAvatar.person(Person person, {super.key, this.size = 40})
      : name = person.name,
        lastName = person.lastName,
        photoUrl = person.photoUrl;

  static const List<Color> _palette = [
    AppColors.verdeAguaProfundo,
    Color(0xFF17A78F),
    Color(0xFF2E8B8B),
    Color(0xFF3A7D6E),
    Color(0xFF4C9A7A),
  ];

  String get _initials => initialsOf(name, lastName);

  Color get _bg {
    // Hash sobre nome+sobrenome → cor estável para a mesma pessoa.
    final seed = '$name${lastName ?? ''}';
    final hash = seed.codeUnits.fold<int>(0, (acc, c) => acc + c);
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(radius: size / 2, backgroundImage: NetworkImage(photoUrl!));
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}
