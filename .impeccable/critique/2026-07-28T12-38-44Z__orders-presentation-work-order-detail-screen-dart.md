---
timestamp: 2026-07-28T12-38-44Z
slug: orders-presentation-work-order-detail-screen-dart
---
{
  "target": "lib/features/work_orders/presentation/work_order_detail_screen.dart",
  "command": "critique",
  "degraded": false,
  "deterministic_coverage": "none — detector nao suporta .dart; cobertura zero no alvo",
  "browser_evidence": "indisponivel e nao aplicavel (Flutter CanvasKit pinta em <canvas>)",
  "design_specificity": "category-interchangeable",
  "health_score": { "total": 16, "max": 40, "band": "poor" },
  "heuristics": { "visibility": 2, "match_real_world": 3, "user_control": 1, "consistency": 2, "error_prevention": 1, "recognition": 2, "flexibility": 1, "minimalist": 1, "error_recovery": 1, "help": 1 },
  "cognitive_load": { "failures": 7, "checks": 8, "level": "alto" },
  "issues": [
    { "id": "P0-1", "title": "Gerar cobranca em OS nao iniciada, sem checagem de status nem de permissao", "where": "work_order_detail_screen.dart:519-523; 0013_financials_minimum.sql:125-155" },
    { "id": "P0-2", "title": "Barra ignora o status e o banco aceita qualquer transicao (opened -> done)", "where": "work_order_detail_screen.dart:474-523; 0008_work_orders.sql:271-337" },
    { "id": "P1-1", "title": "Tres acoes primarias simultaneas violam o Principio 3 do PRODUCT.md", "where": "work_order_detail_screen.dart:474,513,519" },
    { "id": "P1-2", "title": "Botoes do tecnico (40px) menores que os que ele nao deve tocar (58px)", "where": "app_theme.dart:246-261" },
    { "id": "P1-3", "title": "_mapError descarta a mensagem especifica do banco", "where": "work_order_repository.dart:752-765" }
  ]
}
