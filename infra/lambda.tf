# Sufixo aleatório para nomes de bucket, que precisam ser únicos em toda a AWS
resource "random_id" "suffix" {
  byte_length = 4
}

# ---------------------------------------------------------------
# Bucket de artefatos
# O pacote da API tem ~50 MB, no limite do upload direto da Lambda; por isso
# ele é enviado ao S3 e a Lambda é criada a partir do objeto.
# ---------------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.projeto}-artifacts-${random_id.suffix.hex}"
  force_destroy = true

  tags = { Name = "${var.projeto}-artifacts" }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Criptografia em repouso declarada explicitamente (S6)
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "api_zip" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "api/dove-lambda.zip"
  source = "${path.module}/${var.api_zip_path}"
  # source_hash (e não etag): o upload de arquivos grandes é multipart, e a ETag do S3
  # não é o MD5 do arquivo, o que deixaria o plan sempre com alteração pendente
  source_hash = filemd5("${path.module}/${var.api_zip_path}")

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.artifacts]
}

# ---------------------------------------------------------------
# Logs (criados antes das funções para controlar a retenção)
# ---------------------------------------------------------------
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${var.projeto}-api"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "egress_check" {
  name              = "/aws/lambda/${var.projeto}-egress-check"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------
# Lambda da API (Spring Boot)
# ---------------------------------------------------------------
resource "aws_lambda_function" "api" {
  function_name = "${var.projeto}-api"
  description   = "API REST do Dove Restaurante (Spring Boot via aws-serverless-java-container)"
  role          = aws_iam_role.lambda.arn

  runtime     = "java17"
  handler     = "com.Restaurante.Dove.StreamLambdaHandler::handleRequest"
  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_s

  s3_bucket        = aws_s3_bucket.artifacts.id
  s3_key           = aws_s3_object.api_zip.key
  source_code_hash = filebase64sha256("${path.module}/${var.api_zip_path}")

  # Cada deploy publica uma versão; o SnapStart só vale para versões publicadas
  publish = true

  dynamic "snap_start" {
    for_each = var.enable_snapstart ? [1] : []
    content {
      apply_on = "PublishedVersions"
    }
  }

  # ENIs nas sub-redes privadas; a saída é controlada pelo sg-lambda (somente 5432)
  vpc_config {
    subnet_ids         = [aws_subnet.priv_a.id, aws_subnet.priv_b.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  # Valores injetados no deploy: a Lambda não depende de saída para a internet
  environment {
    variables = {
      SPRING_PROFILES_ACTIVE = "prod"
      # Timeouts longos (em segundos): o Aurora pausado leva ~15 s ou mais para acordar,
      # e a conexão não pode desistir antes disso (inclusive na criação do snapshot do SnapStart)
      DB_URL = "jdbc:postgresql://${aws_rds_cluster.main.endpoint}:5432/${var.db_name}?connectTimeout=30&socketTimeout=60&loginTimeout=60"
      # Tempo máximo, em ms, que o pool espera por uma conexão
      SPRING_DATASOURCE_HIKARI_CONNECTIONTIMEOUT = "90000"
      DB_USERNAME                                = var.db_master_username
      DB_PASSWORD                                = random_password.db_master.result
      SECRET_KEY                                 = random_password.jwt_secret.result
      # Compilação rápida da JVM: reduz o tempo de inicialização em funções curtas
      JAVA_TOOL_OPTIONS = "-XX:+TieredCompilation -XX:TieredStopAtLevel=1"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.api,
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_rds_cluster_instance.writer,
  ]

  tags = { Name = "${var.projeto}-api" }
}

# Alias estável usado pelo API Gateway e pelo aquecimento; aponta para a última versão publicada
resource "aws_lambda_alias" "api_live" {
  name             = "live"
  description      = "Versao em uso pela API"
  function_name    = aws_lambda_function.api.function_name
  function_version = aws_lambda_function.api.version
}

# ---------------------------------------------------------------
# Lambda de teste do NAT (fluxo 3 / demonstração D4)
# Consulta https://ifconfig.me a partir da sub-rede privada. Com o NAT ligado,
# retorna o Elastic IP do NAT; com o NAT desligado, a chamada esgota o tempo.
# ---------------------------------------------------------------
data "archive_file" "egress_check" {
  type        = "zip"
  output_path = "${path.module}/build/egress-check.zip"

  source {
    filename = "index.py"
    content  = <<-PY
      import urllib.request


      def handler(event, context):
          try:
              with urllib.request.urlopen("https://ifconfig.me/ip", timeout=5) as resp:
                  ip = resp.read().decode().strip()
              return {"saida_pela_internet": True, "ip_de_origem": ip}
          except Exception as erro:
              return {"saida_pela_internet": False, "erro": str(erro)}
    PY
  }
}

resource "aws_lambda_function" "egress_check" {
  function_name = "${var.projeto}-egress-check"
  description   = "Teste do fluxo 3: mostra o IP de saida da sub-rede privada (deve ser o IP do NAT)"
  role          = aws_iam_role.lambda.arn

  runtime     = "python3.12"
  handler     = "index.handler"
  memory_size = 128
  timeout     = 10

  filename         = data.archive_file.egress_check.output_path
  source_code_hash = data.archive_file.egress_check.output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.priv_a.id, aws_subnet.priv_b.id]
    security_group_ids = [aws_security_group.egress_check.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.egress_check,
    aws_iam_role_policy_attachment.lambda_vpc,
  ]

  tags = { Name = "${var.projeto}-egress-check" }
}

# Security group próprio da função de teste: única regra de saída para a internet (HTTPS)
resource "aws_security_group" "egress_check" {
  name        = "${var.projeto}-egress-check"
  description = "Funcao de teste do NAT: saida HTTPS para a internet"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "sg-egress-check" }
}

resource "aws_vpc_security_group_egress_rule" "egress_check_https" {
  security_group_id = aws_security_group.egress_check.id
  description       = "HTTPS para a internet via NAT (teste do fluxo 3)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
