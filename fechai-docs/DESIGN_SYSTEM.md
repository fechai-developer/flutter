# Design System — Fechaí

Direção: tom de verde-água, dinâmico, mas fugindo do "verde-água genérico de fintech". Gancho conceitual: **água/fluidez** como metáfora de dinheiro circulando entre pessoas — dívida que "flui" e se resolve, em vez de ficar parada numa planilha.

A implementação em código (Flutter `ThemeData`) está em `app_theme.dart`, nesta mesma pasta.

## Paleta (tokens)

| Nome | Hex | Uso |
|---|---|---|
| Verde-água Profundo | `#0E6E64` | Cor primária — headers, botões principais, ícone do app |
| Menta Viva | `#5EEAC0` | Accent/destaque — saldos positivos, sucesso, gradientes |
| Coral Aceso | `#FF6B4A` | Contraste quente — CTA de cobrança ("Cobra Aí"), alertas de atraso |
| Tinta Profunda | `#0B211E` | Texto principal — preto "esverdeado", não preto puro |
| Texto Suave | `#5B726C` | Texto secundário (subtítulos, legendas) — mais leve que opacity |
| Névoa Clara | `#F5FBF9` | Fundo — branco levemente mint, bem claro e arejado |
| Areia Neutra | `#EAF1EE` | Bordas hairline, divisores (suave, moderno) |
| Areia Neutra Forte | `#DCE6E2` | Traço/borda quando precisa de mais definição |

> **Refresh 2026-07 (tema claro por padrão):** o app agora abre sempre no **tema claro**
> (`themeMode: ThemeMode.light` em `main.dart`) — mais leve e moderno, mantendo a identidade
> verde-água. Ajustes: bordas hairline (Areia Neutra mais clara), **sombra difusa em 2 camadas**
> (`AppTheme.softShadow`, sensação "flutuante"), `cardRadius` 18 → 20 e texto secundário em Texto
> Suave. O tema escuro segue implementado para uma futura opção de preferência do usuário.

O Coral Aceso é o contraponto proposital ao verde-água: cria tensão visual só onde importa (cobrar alguém, alertar atraso), sem competir com a identidade principal. **Não usar Coral fora desse contexto.**

## Tipografia

- **Display** (títulos, valores em destaque): geométrica com curvas suaves — Cabinet Grotesk ou General Sans. No código atual, `app_theme.dart` usa Space Grotesk (Google Fonts) como substituto rápido até as fontes custom serem adicionadas como assets.
- **Corpo/texto**: Sora (Google Fonts).
- **Números/valores em R$**: IBM Plex Mono, com `tabularFigures` — só pra valores monetários, nunca pra texto comum. Ver `AppTheme.moneyStyle()`.

## Ícones

- Sistema dual-tone (contorno + preenchimento parcial em Menta Viva ou Coral). Base sugerida: **Phosphor Icons** (variante duotone) via pacote `phosphor_flutter`, customizados com a paleta.
- Ícones autorais só para os 3–4 conceitos centrais (grupo, assinatura, cobrança, PIX) — o resto usa a biblioteca.

## Layout e motion — elemento de assinatura

**Conceito central**: bordas em "corte de onda" (wave-cut) no lugar de cards retangulares comuns — o rodapé de cada card de despesa/cobrança tem uma leve ondulação, reforçando a metáfora fluida sem exagerar.

- Cards com cantos arredondados generosos (16–20px, ver `AppTheme.cardRadius`) + corte de onda **só** na borda inferior dos cards de "saldo"/"cobrança" — não em todo elemento.
- Micro-interação ao marcar pagamento como quitado: pequena onda/ripple se propaga do botão — não usar animação genérica de confete.
- Gradiente sutil (Verde-água Profundo → Menta Viva) só atrás do número de saldo total na tela inicial — não espalhar pelo app.
- Navegação mobile: bottom tabs com 4 itens (Início, Contas, Assinaturas, Cobrar). Web: sidebar equivalente.

## Modo escuro

Tinta Profunda vira o fundo, Névoa Clara vira o texto, Menta Viva ganha mais saturação (`mentaVivaDark`, já implementado em `app_theme.dart`) pra manter contraste.

## Pendências de implementação

- [ ] Baixar e adicionar Cabinet Grotesk/General Sans como fontes custom (Fontshare) e trocar `Space Grotesk` no `_display()` de `app_theme.dart`
- [x] Corte de onda implementado como `CustomClipper` em `lib/core/widgets/wave_clipper.dart`, exposto pelo `WaveCard` (`lib/core/widgets/wave_card.dart`). Usado só nos cards de saldo (Início), resumo de assinatura e onboarding.
- [ ] **Phosphor Icons bloqueado**: `phosphor_flutter` 2.1.0 é incompatível com Flutter 3.44+ (o `IconData` virou `final class` e o pacote tenta estendê-lo). Enquanto o pacote não atualiza, usamos uma camada própria em `lib/core/icons.dart` (`AppIcons` = contorno, `AppIconsFill` = preenchido) mapeada pra Material Icons, preservando a intenção. Ponto único de troca quando o pacote suportar 3.44.
- [ ] Mapear os ícones autorais dos 4 conceitos centrais (grupo, assinatura, cobrança, PIX) — hoje usando Material como base.

## Como a paleta aparece no app (implementado)

- **Card de saldo** (Início): gradiente `WaveCard.balanceGradient` (Verde-água → Menta) + corte de onda — único lugar que espalha o gradiente.
- **Coral Aceso**: usado exclusivamente em CTAs "Cobra Aí", pills de cobrança, FAB "Cobrar tudo" e resumo "A pagar" da aba **Acertar**, alertas de atraso e slider de juros acima do teto. Nunca fora de cobrança/alerta.
- **Modo escuro**: validado — fundo Tinta Profunda, Menta Viva saturada, contraste ok (ver screenshots da sessão de setup).
