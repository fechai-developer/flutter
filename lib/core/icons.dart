import 'package:flutter/material.dart';

/// Camada de ícones do Fechaí.
///
/// O DESIGN_SYSTEM.md pede Phosphor Icons (duotone). Porém `phosphor_flutter`
/// (2.1.0) ainda não é compatível com Flutter 3.44+ — o `IconData` virou
/// `final class` e o pacote tenta estendê-lo, quebrando o build. Enquanto o
/// pacote não atualiza, mapeamos para Material Icons preservando a intenção:
/// [AppIcons] = traço/contorno (Regular), [AppIconsFill] = preenchido (Fill).
///
/// Ponto único de troca: quando o phosphor_flutter suportar Flutter 3.44,
/// basta reapontar estas constantes (ou voltar a importar o pacote).
class AppIcons {
  AppIcons._();

  static const IconData waveSine = Icons.waves; // metáfora água/fluidez
  static const IconData usersThree = Icons.groups_outlined;
  static const IconData repeat = Icons.repeat;
  static const IconData handCoins = Icons.volunteer_activism_outlined;
  static const IconData userCircle = Icons.account_circle_outlined;
  static const IconData plus = Icons.add;
  static const IconData close = Icons.close_rounded;
  static const IconData arrowLeft = Icons.arrow_back;
  static const IconData copy = Icons.content_copy;
  static const IconData check = Icons.check;
  static const IconData checkCircle = Icons.check_circle_outline;
  static const IconData receipt = Icons.receipt_long_outlined;
  static const IconData clockCountdown = Icons.schedule;
  static const IconData warningCircle = Icons.error_outline;
  static const IconData caretRight = Icons.chevron_right;
  static const IconData percent = Icons.percent;
  static const IconData info = Icons.info_outline;
  static const IconData trash = Icons.delete_outline;
  static const IconData qrCode = Icons.qr_code_2;
  static const IconData bell = Icons.notifications_outlined;
  static const IconData shieldCheck = Icons.verified_user_outlined;
  static const IconData signOut = Icons.logout;
  static const IconData pencilSimple = Icons.edit_outlined;
  static const IconData chartBar = Icons.bar_chart;
  static const IconData whatsappLogo = Icons.chat_outlined; // WhatsApp não existe no Material stable
  static const IconData payments = Icons.payments_outlined; // dinheiro (aba Acertar) — Phosphor hand-coins bloqueado
  static const IconData caretDown = Icons.keyboard_arrow_down_rounded;
  static const IconData caretUp = Icons.keyboard_arrow_up_rounded;
  static const IconData lock = Icons.lock_outline;
  static const IconData piggyBank = Icons.savings_outlined; // Caixinha (poupança coletiva)
  static const IconData handshake = Icons.handshake_outlined; // empréstimo
  static const IconData trendingUp = Icons.trending_up; // rendimento
  static const IconData pdf = Icons.picture_as_pdf_outlined; // relatório
}

class AppIconsFill {
  AppIconsFill._();

  static const IconData waveSine = Icons.waves;
  static const IconData usersThree = Icons.groups;
  static const IconData repeat = Icons.repeat_on;
  static const IconData handCoins = Icons.volunteer_activism;
  static const IconData userCircle = Icons.account_circle;
  static const IconData checkCircle = Icons.check_circle;
  static const IconData whatsappLogo = Icons.chat; // WhatsApp não existe no Material stable
  static const IconData payments = Icons.payments; // dinheiro (aba Acertar)
  static const IconData receipt = Icons.receipt_long;
  static const IconData arrowDown = Icons.arrow_downward;
  static const IconData arrowUp = Icons.arrow_upward;
  static const IconData calendarBlank = Icons.calendar_today;
  static const IconData coins = Icons.paid;
  static const IconData warningCircle = Icons.error;
  static const IconData sparkle = Icons.auto_awesome;
  static const IconData piggyBank = Icons.savings; // Caixinha (poupança coletiva)
}
