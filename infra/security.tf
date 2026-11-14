# Matriz de regras da seção 5.5. A AWS não aceita "name" começando com "sg-",
# por isso os nomes sg-lambda e sg-db ficam na tag Name (exibida no console).
# As regras são recursos separados para que um security group possa referenciar
# o outro sem criar dependência circular.

# ---------------------------------------------------------------
# sg-lambda: ENIs da Lambda da API
# Sem regras de entrada: a Lambda é invocada pelo serviço Lambda, não por IP.
# Saída apenas para o banco na porta 5432 (PostgreSQL).
# ---------------------------------------------------------------
resource "aws_security_group" "lambda" {
  name        = "${var.projeto}-lambda"
  description = "ENIs da Lambda da API: sem entrada; saida apenas para o banco"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "sg-lambda" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_db" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "PostgreSQL apenas para o Aurora (S2)"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.db.id
}

# ---------------------------------------------------------------
# sg-db: Aurora
# Sem regras de saída: o banco nunca inicia conexões.
# ---------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.projeto}-db"
  description = "Aurora: entrada PostgreSQL apenas a partir do sg-lambda"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "sg-db" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_lambda" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL apenas a partir da Lambda da API"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.lambda.id
}
