# Credenciais NÃO ficam no código: use um perfil do AWS CLI (export AWS_PROFILE=dove)
# ou variáveis de ambiente (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY).
provider "aws" {
  region = var.aws_region

  # Tags aplicadas a todos os recursos que as suportam (R10)
  default_tags {
    tags = {
      projeto        = var.projeto
      grupo          = var.grupo
      ambiente       = var.ambiente
      gerenciado-por = "terraform"
    }
  }
}
