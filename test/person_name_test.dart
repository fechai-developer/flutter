import 'package:flutter_test/flutter_test.dart';
import 'package:fechai/data/models/person.dart';

void main() {
  group('Person — nome e sobrenome', () {
    test('fullName junta nome e sobrenome', () {
      const p = Person(id: 'p', name: 'Ana', lastName: 'Prado');
      expect(p.fullName, 'Ana Prado');
    });

    test('fullName cai só no nome quando não há sobrenome', () {
      const p = Person(id: 'p', name: 'Ana');
      expect(p.fullName, 'Ana');
      const q = Person(id: 'q', name: 'Ana', lastName: '   ');
      expect(q.fullName, 'Ana');
    });

    test('iniciais: 1ª do nome + 1ª do sobrenome, sempre maiúsculas', () {
      expect(const Person(id: 'p', name: 'ana', lastName: 'prado').initials, 'AP');
      expect(const Person(id: 'p', name: 'Bruno', lastName: 'Lima').initials, 'BL');
    });

    test('iniciais sem sobrenome: uma letra ou desmembra nome completo legado', () {
      expect(const Person(id: 'p', name: 'Ana').initials, 'A');
      // Compatibilidade com nome completo num campo só (dados legados).
      expect(const Person(id: 'p', name: 'Ana Prado').initials, 'AP');
    });

    test('initialsOf ignora tokens sem letra (ex.: "(organizador)")', () {
      expect(initialsOf('Você (organizador)'), 'V');
      expect(initialsOf(''), '?');
    });

    test('copyWith limpa o sobrenome só com null explícito', () {
      const p = Person(id: 'p', name: 'Ana', lastName: 'Prado');
      // omitir mantém
      expect(p.copyWith(name: 'Aninha').lastName, 'Prado');
      // null explícito apaga
      expect(p.copyWith(lastName: null).lastName, isNull);
      // novo valor troca
      expect(p.copyWith(lastName: 'Souza').lastName, 'Souza');
    });

    test('round-trip de JSON preserva o sobrenome', () {
      const p = Person(id: 'p', name: 'Ana', lastName: 'Prado', phone: '5511999998888');
      final back = Person.fromJson(p.toJson());
      expect(back.name, 'Ana');
      expect(back.lastName, 'Prado');
      expect(back.fullName, 'Ana Prado');
    });
  });
}
