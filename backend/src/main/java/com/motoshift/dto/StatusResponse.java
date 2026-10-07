package com.motoshift.dto;

/**
 * O que o {@code GET /api/status} responde (SCRUM-48).
 *
 * @param ok           sempre {@code true}: se a resposta chegou, o servidor está no ar
 * @param horaServidor o "agora" do servidor, com o deslocamento do fuso
 *                     ("2026-10-07T19:30:05-03:00") — é por onde se confere,
 *                     depois de um deploy, que ele está na hora de Brasília
 * @param fuso         o fuso padrão da JVM ("America/Sao_Paulo")
 * @param versao       o commit publicado, ou a versão do pom quando a
 *                     hospedagem não informa o commit
 */
public record StatusResponse(boolean ok, String horaServidor, String fuso, String versao) {
}
