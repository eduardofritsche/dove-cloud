# ---------------------------------------------------------------
# Identificação e região
# ---------------------------------------------------------------
variable "aws_region" {
  type        = string
  description = "Região da AWS onde a infraestrutura é criada."
  default     = "sa-east-1"
}

variable "projeto" {
  type        = string
  description = "Nome do projeto, usado na tag 'projeto' e no prefixo dos recursos."
  default     = "dove"
}

variable "grupo" {
  type        = string
  description = "Identificação do grupo, usada na tag 'grupo'."
}

variable "ambiente" {
  type        = string
  description = "Nome do ambiente, usado na tag 'ambiente'."
  default     = "entrega2"
}

# ---------------------------------------------------------------
# Rede (plano de endereçamento da seção 5.3)
# ---------------------------------------------------------------
variable "vpc_cidr" {
  type        = string
  description = "Bloco CIDR da VPC."
  default     = "10.20.0.0/16"
}

variable "az_a" {
  type        = string
  description = "Zona de disponibilidade principal (sub-redes pub-a e priv-a, writer do Aurora)."
  default     = "sa-east-1a"
}

variable "az_b" {
  type        = string
  description = "Segunda zona de disponibilidade (sub-rede priv-b, exigida pelo DB subnet group)."
  default     = "sa-east-1b"
}

variable "pub_a_cidr" {
  type        = string
  description = "CIDR da sub-rede pública pub-a (NAT Gateway)."
  default     = "10.20.1.0/24"
}

variable "priv_a_cidr" {
  type        = string
  description = "CIDR da sub-rede privada priv-a (ENIs da Lambda e writer do Aurora)."
  default     = "10.20.10.0/24"
}

variable "priv_b_cidr" {
  type        = string
  description = "CIDR da sub-rede privada priv-b (ENIs da Lambda e DB subnet group)."
  default     = "10.20.11.0/24"
}

variable "enable_nat" {
  type        = bool
  description = "Cria o NAT Gateway, o Elastic IP e a rota 0.0.0.0/0 da sub-rede privada (ADR-002). Deve ser true na apresentação."
  default     = false
}

# ---------------------------------------------------------------
# Banco de dados (ADR-003)
# ---------------------------------------------------------------
variable "aurora_engine_version" {
  type        = string
  description = "Versão do Aurora MySQL. A 3.08 ou superior permite pausar em 0 ACU; a 3.07 ou superior suporta a Data API."
  default     = "8.0.mysql_aurora.3.10.6"
}

variable "aurora_min_capacity" {
  type        = number
  description = "Capacidade mínima do Aurora Serverless v2, em ACU. 0 permite a pausa automática; use 0.5 no dia da apresentação."
  default     = 0

  validation {
    condition     = var.aurora_min_capacity >= 0 && var.aurora_min_capacity <= var.aurora_max_capacity
    error_message = "A capacidade mínima deve ser maior ou igual a 0 e menor ou igual à máxima."
  }
}

variable "aurora_max_capacity" {
  type        = number
  description = "Capacidade máxima do Aurora Serverless v2, em ACU."
  default     = 2
}

variable "aurora_seconds_until_auto_pause" {
  type        = number
  description = "Segundos sem conexões até o Aurora pausar (vale só quando a capacidade mínima é 0)."
  default     = 300

  validation {
    condition     = var.aurora_seconds_until_auto_pause >= 300 && var.aurora_seconds_until_auto_pause <= 86400
    error_message = "O valor deve estar entre 300 e 86400 segundos."
  }
}

variable "db_name" {
  type        = string
  description = "Nome do banco de dados criado no cluster."
  default     = "dove"
}

variable "db_master_username" {
  type        = string
  description = "Usuário administrador do banco. A senha é gerada pelo Terraform e guardada no Secrets Manager."
  default     = "doveadmin"
}

variable "db_backup_retention_days" {
  type        = number
  description = "Dias de retenção do backup automático do Aurora (política mínima, seção 6.3: no máximo 2)."
  default     = 1

  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 2
    error_message = "A política mínima exige retenção de 1 a 2 dias."
  }
}

variable "db_backup_window" {
  type        = string
  description = "Janela diária do backup automático, em UTC (06:00-07:00 UTC = 03:00-04:00 em Brasília)."
  default     = "06:00-07:00"
}
