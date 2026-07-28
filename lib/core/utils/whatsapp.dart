import 'package:url_launcher/url_launcher.dart';

/// Monta e abre o deep link do WhatsApp (`wa.me`) com a mensagem de cobrança
/// pré-formatada — coração do "Cobra Aí". Ver PRD seção 5.4.
class WhatsApp {
  WhatsApp._();

  /// Monta a URL `https://wa.me/<phone>?text=<msg>`.
  /// [phone] só dígitos, com DDI (ex.: 5511999998888). Se vazio, abre sem destinatário.
  static Uri buildUri({required String message, String? phone}) {
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    final encoded = Uri.encodeComponent(message);
    final base = digits.isEmpty ? 'https://wa.me/' : 'https://wa.me/$digits';
    return Uri.parse('$base?text=$encoded');
  }

  /// Abre o WhatsApp. Retorna false se não foi possível lançar.
  static Future<bool> send({required String message, String? phone}) async {
    final uri = buildUri(message: message, phone: phone);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Texto padrão de cobrança. Mantém tom leve/neutro (o app é o canal neutro
  /// que resolve o constrangimento de cobrar — PRD seção 2).
  static String chargeMessage({
    required String fromName,
    required String toName,
    required String amountLabel,
    required String reason,
    required String pixCode,
  }) {
    return 'Oi, $toName! 👋\n\n'
        'Fechando as contas do $reason: sua parte deu $amountLabel.\n\n'
        'Dá pra pagar por PIX copia e cola 👇\n'
        '$pixCode\n\n'
        'Assim que pagar, me avisa que eu dou baixa aqui no Fechaí. Valeu! 🙌';
  }

  /// Link de entrada do app usado nos convites (Etapa C). Quando a pessoa se
  /// cadastra com o mesmo telefone, o vínculo pendente é religado
  /// automaticamente (ver migração `member_linking`).
  static const String appLink = 'https://fechai.app/entrar';

  /// Mensagem de convite para um grupo/assinatura enviada via WhatsApp
  /// (Etapa C — "convite via deep link"). Tom leve, sem cobrança.
  static String inviteMessage({
    required String toName,
    required String contextName, // nome do grupo/assinatura
    required bool isGroup,
  }) {
    final tipo = isGroup ? 'na conta' : 'na assinatura';
    return 'Oi, $toName! 👋\n\n'
        'Te adicionei $tipo *$contextName* no Fechaí pra a gente organizar as contas juntos.\n\n'
        'Baixa o app e entra com este mesmo número que eu já te encontro por aqui 👇\n'
        '$appLink\n\n'
        'Aí é só aceitar o convite. Valeu! 🙌';
  }
}
