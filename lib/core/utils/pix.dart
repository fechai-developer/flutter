/// Gerador de PIX "copia e cola" (BR Code / padrão EMV do Banco Central).
///
/// IMPORTANTE (regra de negócio, ver CLAUDE.md): o app **não custodia dinheiro**.
/// Este payload apenas monta o código que o próprio pagador usa no banco dele —
/// o Fechaí só orquestra a comunicação da cobrança.
///
/// Nunca chamar de "Pix" em nome de produto/marca — é marca do Banco Central.
class PixPayload {
  PixPayload._();

  /// Monta o BR Code estático com valor.
  ///
  /// [pixKey] chave PIX do recebedor (cpf, e-mail, telefone ou aleatória).
  /// [merchantName] nome de quem recebe (máx. 25 chars no padrão).
  /// [merchantCity] cidade (máx. 15 chars).
  /// [amount] valor da cobrança; se null, gera código sem valor definido.
  /// [txid] identificador da transação (máx. 25 chars); "***" quando ausente.
  static String build({
    required String pixKey,
    required String merchantName,
    required String merchantCity,
    double? amount,
    String txid = '***',
  }) {
    final gui = _tlv('00', 'BR.GOV.BCB.PIX');
    final key = _tlv('01', pixKey);
    final merchantAccountInfo = _tlv('26', '$gui$key');

    final additionalData = _tlv('62', _tlv('05', _sanitizeTxid(txid)));

    final buffer = StringBuffer()
      ..write(_tlv('00', '01')) // Payload Format Indicator
      ..write(_tlv('01', amount != null ? '12' : '11')) // one-time se tem valor
      ..write(merchantAccountInfo)
      ..write(_tlv('52', '0000')) // Merchant Category Code
      ..write(_tlv('53', '986')); // BRL

    if (amount != null) {
      buffer.write(_tlv('54', amount.toStringAsFixed(2)));
    }

    buffer
      ..write(_tlv('58', 'BR'))
      ..write(_tlv('59', _clamp(merchantName, 25)))
      ..write(_tlv('60', _clamp(merchantCity, 15)))
      ..write(additionalData);

    // CRC16 é calculado sobre tudo + o campo "6304".
    final partial = '${buffer.toString()}6304';
    final crc = _crc16(partial);
    return '$partial$crc';
  }

  /// Type-Length-Value: id (2) + length (2, zero-padded) + valor.
  static String _tlv(String id, String value) {
    final len = value.length.toString().padLeft(2, '0');
    return '$id$len$value';
  }

  static String _clamp(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  static String _sanitizeTxid(String txid) {
    final cleaned = txid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (cleaned.isEmpty) return '***';
    return _clamp(cleaned, 25);
  }

  /// CRC16-CCITT (polinômio 0x1021, init 0xFFFF) — em maiúsculas, 4 dígitos hex.
  static String _crc16(String payload) {
    const int polynomial = 0x1021;
    int crc = 0xFFFF;

    for (final codeUnit in payload.codeUnits) {
      crc ^= (codeUnit << 8) & 0xFFFF;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ polynomial) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }
}
