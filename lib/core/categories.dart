import 'package:flutter/material.dart';

/// Tipo (categoria) de um gasto — usado tanto em despesas de conta quanto em
/// assinaturas. É texto livre no banco (coluna `category`): as listas abaixo são
/// SUGESTÕES; o usuário também pode digitar um tipo próprio (ver [CategoryLimits]).
///
/// Aqui só mora a apresentação (rótulo + ícone + cor). A resolução de ícone/cor
/// aceita qualquer string, então tipos custom continuam bonitos na UI.
@immutable
class SpendCategory {
  final String label;
  final IconData icon;
  const SpendCategory(this.label, this.icon);
}

/// Sugestões para despesas de conta (eventos, viagens, restaurante, república…).
const List<SpendCategory> kExpenseCategories = [
  SpendCategory('Mercado', Icons.shopping_cart_outlined),
  SpendCategory('Restaurante', Icons.restaurant_outlined),
  SpendCategory('Bar', Icons.local_bar_outlined),
  SpendCategory('Transporte', Icons.local_taxi_outlined),
  SpendCategory('Viagem', Icons.flight_outlined),
  SpendCategory('Hospedagem', Icons.hotel_outlined),
  SpendCategory('Passeio', Icons.attractions_outlined),
  SpendCategory('Compras', Icons.shopping_bag_outlined),
  SpendCategory('Casa', Icons.home_outlined),
  SpendCategory('Saúde', Icons.medical_services_outlined),
  SpendCategory('Taxa', Icons.request_quote_outlined),
  SpendCategory('Outros', Icons.category_outlined),
];

/// Sugestões para assinaturas compartilhadas.
const List<SpendCategory> kSubscriptionCategories = [
  SpendCategory('Streaming', Icons.live_tv_outlined),
  SpendCategory('Música', Icons.music_note_outlined),
  SpendCategory('Software', Icons.apps_outlined),
  SpendCategory('Jogos', Icons.sports_esports_outlined),
  SpendCategory('Nuvem', Icons.cloud_outlined),
  SpendCategory('Notícias', Icons.newspaper_outlined),
  SpendCategory('Educação', Icons.school_outlined),
  SpendCategory('IA', Icons.auto_awesome_outlined),
  SpendCategory('Outros', Icons.category_outlined),
];

/// Ícone genérico para tipo custom / desconhecido / ausente.
const IconData kCategoryFallbackIcon = Icons.label_outline;

/// Rótulo mostrado quando uma despesa não tem tipo.
const String kNoCategoryLabel = 'Sem tipo';

final Map<String, IconData> _iconByLabel = {
  for (final c in [...kExpenseCategories, ...kSubscriptionCategories])
    c.label.toLowerCase(): c.icon,
};

/// Ícone de um rótulo arbitrário (case-insensitive). Custom/nulo → etiqueta.
IconData categoryIcon(String? label) {
  if (label == null || label.trim().isEmpty) return kCategoryFallbackIcon;
  return _iconByLabel[label.trim().toLowerCase()] ?? kCategoryFallbackIcon;
}

/// Paleta categórica pequena e coesa, derivada da marca (verde-água/menta) com
/// alguns tons extras equilibrados. Evita o coral do tema (reservado a
/// alerta/cobrança) para não confundir "tipo de gasto" com "atraso".
const List<Color> kCategoryPalette = [
  Color(0xFF0E6E64), // verde-água profundo (marca)
  Color(0xFF2BA6A0), // verde-água claro
  Color(0xFF4C86C6), // azul
  Color(0xFF7A6FF0), // índigo
  Color(0xFFB65FA6), // malva
  Color(0xFFE0A32E), // âmbar
  Color(0xFF6FBF73), // verde
  Color(0xFFC97B5A), // terracota
];

/// Cor estável para um segmento de gráfico, pelo índice de ordenação.
Color categoryColor(int index) => kCategoryPalette[index % kCategoryPalette.length];
