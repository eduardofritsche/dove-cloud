# Identidades com menor privilégio (S5). Nenhuma chave de acesso é gravada nos recursos.

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------
# Role das Lambdas (API e teste do NAT)
# Permite apenas criar as ENIs nas sub-redes privadas e gravar logs.
# A Lambda não acessa o Secrets Manager: os valores são injetados no deploy.
# ---------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name               = "${var.projeto}-lambda-exec"
  description        = "Execucao das Lambdas do projeto: ENIs na VPC e logs no CloudWatch"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ---------------------------------------------------------------
# Role do EventBridge Scheduler (aquecimento)
# Pode apenas invocar o alias da Lambda da API.
# ---------------------------------------------------------------
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_alias.api_live.arn]
  }
}

resource "aws_iam_role" "scheduler" {
  count              = var.enable_warmup ? 1 : 0
  name               = "${var.projeto}-scheduler-warmup"
  description        = "Permite ao EventBridge Scheduler invocar apenas a Lambda da API"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  count  = var.enable_warmup ? 1 : 0
  name   = "invoke-api-lambda"
  role   = aws_iam_role.scheduler[0].id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}
