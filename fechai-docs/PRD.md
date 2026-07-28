# PRD — Fechaí
### App de Divisão de Despesas e Assinaturas

---

## 1. Visão geral

App brasileiro para organizar dívidas entre pessoas, cobrindo dois cenários que hoje são resolvidos por apps separados:

1. **Despesas de grupo/evento** (estilo Splitwise): viagens, repúblicas, churrascos, rateio de casa.
2. **Assinaturas compartilhadas** (estilo Splitfee/Kotas): planos família de Netflix, Spotify, Microsoft 365, Disney+ etc.

**Diferencial**: nenhum concorrente nacional junta as duas frentes num único app, com cobrança automatizada via WhatsApp, PIX copia-e-cola nativo e juros configuráveis por atraso.

---

## 2. Problema que resolve

- Grupos de amigos/família usam planilha, papel ou apps em inglês para dividir contas.
- Quem "segura" a assinatura de streaming/serviço tem que cobrar manualmente todo mês, sem controle de atraso.
- Cobrança informal é constrangedora — falta um canal neutro e automático.

---

## 3. Público-alvo

- Jovens adultos (18–35 anos), usuários de PIX e WhatsApp no dia a dia.
- Grupos de amigos, repúblicas, casais, famílias que dividem assinaturas.
- Perfil: já usa apps de pagamento, mas não usa Splitwise por ser "gringo" ou pouco intuitivo.

---

## 4. Proposta de valor

| Recurso | Splitwise | Splitfee/Kotas | Nosso app |
|---|---|---|---|
| Despesas de grupo/evento | ✅ | ❌ | ✅ |
| Divisão de assinaturas recorrentes | ❌ | ✅ | ✅ |
| Cobrança via WhatsApp | ❌ | ❌ | ✅ |
| PIX copia e cola integrado | ❌ (manual) | ✅ | ✅ |
| Juros configuráveis por atraso | ❌ | ❌ | ✅ |
| Interface em português/BR | parcial | ✅ | ✅ |

---

## 5. Escopo do MVP

Como definido: **as duas frentes juntas desde o início**.

### 5.1 Conta e cadastro
- Cadastro por celular (número + OTP via SMS/WhatsApp)
- Perfil com nome, foto, chave PIX salva

### 5.2 Módulo "Contas" (grupos de despesas / eventos)
> Nome na UI: **"Contas"** (casa com "fechar a conta"; ver changelog no `IMPLEMENTATION_TODO.md`). O domínio interno segue `ExpenseGroup`/`groups`.
- Criar grupo, adicionar membros (por contato/telefone)
- Lançar despesa: valor, quem pagou, como dividir (igual, %, valores customizados)
- Saldo consolidado por pessoa (quem deve pra quem, com simplificação de transações — igual Splitwise)
- Histórico do grupo

### 5.3 Módulo "Assinaturas compartilhadas"
- Cadastrar assinatura (nome do serviço, valor total, dia de cobrança, quantidade de cotas)
- Adicionar participantes com valor da cota calculado automaticamente
- Recorrência mensal automática (gera cobrança todo mês na data definida)
- Configuração de **juros ao mês** para atraso (% definido pelo dono do grupo)

### 5.4 "Cobra Aí" — cobrança
- Botão para gerar mensagem de cobrança pré-formatada
- Envio via WhatsApp (deep link `wa.me` ou API oficial, a definir)
- Copiar código PIX copia-e-cola direto na mensagem
- Marcar como pago manualmente (v1) — conciliação automática fica pra v2

### 5.5 Notificações
- Lembrete de vencimento (push)
- Confirmação de pagamento

---

## 6. Fora do escopo do MVP (backlog v2+)

- Conciliação automática de pagamento (webhook de PSP/PIX)
- OCR de recibo/nota fiscal
- Split por porcentagem com múltiplas moedas
- Integração direta com bancos (open finance)
- Web widget para embutir em outros produtos
- Programa de indicação

---

## 7. Modelo de negócio — Freemium

> **Implementado (Etapa S):** os limites vivem na tabela `plan_limits` no Supabase
> (editável no painel) e são **impostos por trigger no servidor** — o cliente não
> consegue burlar. A UI reflete via RPC `my_plan_status()` (recursos travados +
> upsell). Números abaixo = padrão atual; ajustáveis sem redeploy.

**Grátis (`free`):**
- Até **3 grupos ativos** ao mesmo tempo (arquivar libera vaga)
- Até **2 assinaturas ativas** ao mesmo tempo
- **Cobra Aí** até **30/mês**
- **Sem juros** por atraso (campo travado, com upsell)
- Sem cobrança automática

**Premium (`premium`, 1 assinatura paga):**
- **+3 grupos** e **+2 assinaturas** ativos (6 e 4 no padrão atual)
- **Cobra Aí sem limite** mensal
- **Juros por atraso** configuráveis (teto de 20%/mês no banco)
- **Cobrança automática** recorrente (D+3/D+10/D+30…) — Fase E
- Relatórios/exportação, histórico completo

Fonte da verdade do plano: `profiles.plan` + `plan_valid_until`, alterável **só por
service_role** (checkout/Edge Function ou painel) — o usuário não se auto-promove.

*(Definir preço depois de validar demanda — referência: Splitwise Pro cobra na faixa de US$3–4/mês.
Checkout/pagamento ainda não implementado — ver `IMPLEMENTATION_TODO.md` → Etapa S.)*

---

## 8. Stack técnica

**Definido: Flutter (web + mobile no mesmo código-base).**

Faz sentido pro time já dominar Flutter e pro requisito de "validar rápido na web, levar pra loja depois sem reescrever":

- Um único código Dart compila pra **web, iOS e Android** — não existe fase separada de "empacotar pra loja", o app mobile nasce junto com o web.
- Performance nativa de verdade quando publicar nas lojas — sem a camada intermediária que soluções tipo Capacitor/Ionic exigiriam.
- Pacotes prontos cobrem tudo que o MVP precisa:
  - `url_launcher` → abrir WhatsApp via link `wa.me` com mensagem pré-formatada
  - `firebase_auth` → OTP por SMS/telefone
  - `cloud_firestore` ou backend próprio (Node/NestJS + PostgreSQL) para dados de grupos/despesas
  - geração de payload PIX copia-e-cola: é só texto formatado (BR Code), dá pra gerar client-side sem depender de gateway, ou usar `pix_utils`
  - `qr_flutter` → renderizar QR Code do PIX na tela
  - `flutter_local_notifications` + Firebase Cloud Messaging → lembretes de vencimento

**Ponto de atenção — Flutter Web:**
O maior público vai clicar num link de cobrança vindo do WhatsApp (pessoa cobrada, não necessariamente já cadastrada). Essa página de "pagar/ver cobrança" precisa carregar rápido:
- Usar `renderer: html` (não CanvasKit) pra essa rota específica de landing/cobrança, que é mais leve no primeiro load
- Considerar essa tela de cobrança pública como uma página web enxuta separada do app principal (que aí sim carrega CanvasKit completo, já logado)
- Aplicar tree-shaking e lazy loading de rotas menos usadas

**Backend:** Node.js (NestJS) + PostgreSQL, ou Firebase/Supabase pra acelerar o MVP e migrar depois se precisar de mais controle.

---

## 9. Requisitos não funcionais

- **LGPD**: dados financeiros e PIX são sensíveis — necessário termo de consentimento, criptografia em repouso, política de privacidade clara.
- **Segurança**: nunca armazenar dados bancários completos; chave PIX é o suficiente, sem custódia de dinheiro (o app não é um PSP, só orquestra a comunicação).
- **Disponibilidade**: cobrança recorrente não pode falhar silenciosamente — precisa de monitoramento de job/cron.
- **Importante juridicamente**: como o app vai cobrar juros ao mês, checar limites legais (juros abusivos, Lei de Usura) — não é aconselhável deixar o usuário configurar qualquer taxa sem um teto sugerido/aviso.

---

## 10. Métricas de sucesso (North Star + apoio)

- **North Star**: nº de cobranças "Cobra Aí" enviadas e marcadas como pagas por semana
- Apoio: grupos ativos, assinaturas cadastradas, taxa de conversão free → premium, retenção D7/D30

---

## 11. Roadmap sugerido

| Fase | Duração estimada | Entregável |
|---|---|---|
| Fase 0 | 1–2 semanas | Validação (landing page + waitlist, testar nome/proposta) |
| Fase 1 — MVP | 6–8 semanas | Cadastro, grupos de despesa, assinaturas, Cobra Aí (WhatsApp + PIX), Flutter web |
| Fase 2 | 4 semanas | Freemium/paywall, notificações, polimento |
| Fase 3 | 2–3 semanas | Build iOS/Android a partir do mesmo código-base, publicar nas lojas |

---

## 12. Identidade visual / Design system

Ver arquivo dedicado **`DESIGN_SYSTEM.md`** (paleta, tipografia, ícones, motion, modo escuro) e a implementação em código **`app_theme.dart`**, ambos nesta mesma pasta.

Resumo: tom de verde-água com contraponto quente (coral) reservado só para cobrança/alerta; tipografia geométrica de personalidade + números tabulares pra valores monetários; elemento de assinatura visual é o "corte de onda" nas bordas dos cards, ligado à metáfora água/fluidez do dinheiro circulando entre pessoas.

---

## 13. Próximos passos imediatos

1. ~~Fechar o nome definitivo~~ → **Fechaí**. Falta checar disponibilidade de domínio/redes/app stores.
2. Prototipar telas principais (Figma) — grupo de despesa, tela de assinatura, tela "Cobra Aí" — aplicando o design system
3. Validar taxa de juros/aviso legal com alguém que entenda de direito do consumidor
4. Estruturar o projeto Flutter (arquitetura de pastas, gerenciamento de estado — Riverpod ou Bloc — e o `app_theme.dart` como tema global do app)

---

## 14. Status de implementação (atualizado)

O MVP já foi implementado em Flutter + Supabase. Estado detalhado e próximos passos em **`IMPLEMENTATION_TODO.md`**; como testar com dados reais em **`TESTING.md`**.

Ajustes ao escopo original decididos durante a construção:
- **Estado: Riverpod** · **Backend: Supabase** (substitui Firebase; login por e-mail, OTP/WhatsApp na fase final).
- **Aba "Cobrar" oficializada como *hub*** que agrega todas as pendências (dívidas de grupo + cotas de assinatura), com atrasos no topo — serve diretamente a North Star (nº de "Cobra Aí").
- **Juros** reposicionados como **ilustrativos** (até 20%, aviso acima de 1%), com **termo de uso** no login — em vez de só um teto rígido.
- **Grupos também têm juros** (não só assinaturas).
- **Cobrança automática recorrente** (jobs em D+3/D+10/D+30…) foi movida para **enhancement pós-deploy** — não bloqueia o lançamento. Segue valendo: baixa de pagamento é **manual** no MVP e conciliação de PIX continua v2 (seção 6).
- **Notificações push** dependem de FCM/APNs (Supabase não faz push nativo) — ficam como enhancement; lembretes sairão da cobrança automática.
