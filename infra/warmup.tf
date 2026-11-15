# ---------------------------------------------------------------
# Aquecimento agendado (EventBridge Scheduler)
# Chama a API no horário do restaurante para manter a Lambda inicializada e o
# Aurora acordado. A rota consultada é pública e lê o banco, sem alterar dados.
# Desligado por padrão (enable_warmup = false) durante a Entrega 2.
# ---------------------------------------------------------------
resource "aws_scheduler_schedule" "warmup" {
  count       = var.enable_warmup ? 1 : 0
  name        = "${var.projeto}-api-warmup"
  description = "Mantem a Lambda da API e o Aurora acordados no horario do restaurante"

  schedule_expression          = var.warmup_schedule
  schedule_expression_timezone = var.warmup_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.api_live.arn
    role_arn = aws_iam_role.scheduler[0].arn

    # Evento no mesmo formato enviado pelo API Gateway (HTTP API, payload 2.0)
    input = jsonencode({
      version        = "2.0"
      routeKey       = "$default"
      rawPath        = "/api/usuario/findByUsername"
      rawQueryString = "username=warmup"
      headers        = { "content-type" = "application/json", host = "warmup" }
      requestContext = {
        http      = { method = "GET", path = "/api/usuario/findByUsername", protocol = "HTTP/1.1", sourceIp = "127.0.0.1", userAgent = "eventbridge-warmup" }
        stage     = "$default"
        requestId = "warmup"
      }
      isBase64Encoded = false
    })

    retry_policy {
      maximum_retry_attempts = 0
    }
  }
}
