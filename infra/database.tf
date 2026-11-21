# ---------------------------------------------------------------
# Senha do banco (S4)
# Gerada pelo Terraform e guardada no Secrets Manager. Não aparece no código
# nem em .tfvars; fica apenas no state, que não vai para o Git.
# ---------------------------------------------------------------
resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_master" {
  name        = "${var.projeto}/aurora/master"
  description = "Credenciais do usuário administrador do Aurora (usadas no deploy da Lambda e pela Data API)"

  # Exclusão imediata no destroy, para permitir recriar o ambiente com o mesmo nome
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_master" {
  secret_id = aws_secretsmanager_secret.db_master.id
  secret_string = jsonencode({
    engine   = "postgres"
    username = var.db_master_username
    password = random_password.db_master.result
    dbname   = var.db_name
    host     = aws_rds_cluster.main.endpoint
    port     = 5432
  })
}

# ---------------------------------------------------------------
# Subnet group e parâmetros
# ---------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.projeto}-db-subnet-group"
  description = "priv-a e priv-b: o Aurora exige sub-redes em pelo menos duas zonas"
  subnet_ids  = [aws_subnet.priv_a.id, aws_subnet.priv_b.id]

  tags = { Name = "${var.projeto}-db-subnet-group" }
}

resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${var.projeto}-aurora-pg17"
  family      = "aurora-postgresql17"
  description = "Encerra sessoes ociosas para permitir a pausa automatica do Aurora"

  # Conexões ociosas da Lambda impediriam a pausa (ADR-003). Valores em milissegundos.
  parameter {
    name  = "idle_session_timeout"
    value = "300000"
  }

  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "300000"
  }
}

# ---------------------------------------------------------------
# Aurora PostgreSQL Serverless v2 (ADR-003)
# O Free plan da AWS não permite Aurora MySQL; o único motor Aurora liberado é o PostgreSQL.
# ---------------------------------------------------------------
resource "aws_rds_cluster" "main" {
  cluster_identifier = "${var.projeto}-aurora"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = var.aurora_engine_version

  database_name   = var.db_name
  master_username = var.db_master_username
  master_password = random_password.db_master.result

  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  # Criptografia em repouso declarada explicitamente; os backups herdam (S6)
  storage_encrypted = true

  # Política mínima de backup (Parte D, seção 6.3)
  backup_retention_period = var.db_backup_retention_days
  preferred_backup_window = var.db_backup_window
  copy_tags_to_snapshot   = true

  # RDS Data API: acesso administrativo ao banco por IAM, sem porta aberta (ADR-001)
  enable_http_endpoint = true

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
    # A AWS descarta a pausa quando a capacidade mínima é maior que 0; enviar o valor
    # nesse caso deixaria o plan sempre com alteração pendente (0 -> 300)
    seconds_until_auto_pause = var.aurora_min_capacity == 0 ? var.aurora_seconds_until_auto_pause : null
  }

  # Ambiente acadêmico: permite o destroy completo, sem snapshot final retido
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = { Name = "${var.projeto}-aurora" }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.projeto}-aurora-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  # Writer único em priv-a (sa-east-1a); a réplica em priv-b fica para a proposta de HA
  availability_zone   = var.az_a
  publicly_accessible = false

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = { Name = "${var.projeto}-aurora-writer" }
}
