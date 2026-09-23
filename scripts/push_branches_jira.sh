#!/usr/bin/env bash
# Publica as branches por ticket para o Jira ligar cada card ao GitHub.
# As branches ja existem localmente; este script so faz o push.
set -e
git push origin \
  SCRUM-10-login-email-senha \
  SCRUM-11-painel-indicadores \
  SCRUM-12-cadastro-validacao-documento \
  SCRUM-13-publicar-turno-antecedencia \
  SCRUM-14-aceitar-turno-disponivel \
  SCRUM-15-carteira-saldo-saque-pix \
  SCRUM-16-agenda-visual-cancelamento \
  SCRUM-17-avaliacao-mutua \
  SCRUM-18-filtro-periodo-e-raio \
  SCRUM-19-vencimento-de-turnos \
  SCRUM-20-notificacoes-in-app \
  feat/scrum-19-20-vencimento-notificacoes
echo "Pronto. Confira o painel Development de cada card no Jira."
