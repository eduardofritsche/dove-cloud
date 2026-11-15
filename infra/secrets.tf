# ---------------------------------------------------------------
# Segredo da aplicação (S4)
# Chave de assinatura dos tokens JWT (SECRET_KEY do Spring), gerada pelo
# Terraform. Guardada no Secrets Manager e injetada na Lambda no deploy.
# ---------------------------------------------------------------
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "jwt" {
  name        = "${var.projeto}/api/jwt-secret"
  description = "Chave de assinatura dos tokens JWT da API (SECRET_KEY)"

  # Exclusão imediata no destroy, para permitir recriar o ambiente com o mesmo nome
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = random_password.jwt_secret.result
}
