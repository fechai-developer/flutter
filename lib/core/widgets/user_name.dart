import 'package:flutter/material.dart';

/// Estilo de destaque para nomes de usuário: apenas negrito (sem sublinhado).
TextStyle userNameStyle(BuildContext context, {TextStyle? base}) {
  final b = base ?? DefaultTextStyle.of(context).style;
  return b.copyWith(fontWeight: FontWeight.w600);
}

/// Nome de usuário sublinhado (uso avulso).
class UserName extends StatelessWidget {
  final String name;
  final TextStyle? style;
  final int? maxLines;
  const UserName(this.name, {super.key, this.style, this.maxLines});

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
      style: userNameStyle(context, base: style),
    );
  }
}

/// Span de nome sublinhado, para usar dentro de frases (feed, saldos).
TextSpan userNameSpan(BuildContext context, String name, {TextStyle? base}) =>
    TextSpan(text: name, style: userNameStyle(context, base: base));
