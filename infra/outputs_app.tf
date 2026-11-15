# Outputs da etapa 3 (aplicação). Complementam o outputs.tf da etapa 2 (R11).

output "app_url" {
  description = "URL da aplicação (HTTPS pelo CloudFront)."
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "ID da distribuição do CloudFront (usado na invalidação de cache após o deploy do front)."
  value       = aws_cloudfront_distribution.main.id
}

output "frontend_bucket" {
  description = "Bucket onde o build do Angular é publicado (aws s3 sync)."
  value       = aws_s3_bucket.frontend.id
}

output "api_gateway_endpoint" {
  description = "Endpoint direto do API Gateway (a aplicação usa o CloudFront; este endereço serve para diagnóstico)."
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "lambda_functions" {
  description = "Nomes das funções Lambda (API e teste do NAT) e versão publicada da API."
  value = {
    api          = aws_lambda_function.api.function_name
    api_version  = aws_lambda_function.api.version
    egress_check = aws_lambda_function.egress_check.function_name
  }
}

output "egress_check_security_group_id" {
  description = "ID do security group da função de teste do NAT."
  value       = aws_security_group.egress_check.id
}

output "jwt_secret_arn" {
  description = "ARN do segredo com a SECRET_KEY do JWT."
  value       = aws_secretsmanager_secret.jwt.arn
}
