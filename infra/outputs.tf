# Outputs de rede e banco (R11). A URL da aplicação e os demais outputs estão em outputs_app.tf.

output "vpc_id" {
  description = "ID da VPC do projeto."
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "IDs das sub-redes pública e privadas."
  value = {
    pub_a  = aws_subnet.pub_a.id
    priv_a = aws_subnet.priv_a.id
    priv_b = aws_subnet.priv_b.id
  }
}

output "nat_public_ip" {
  description = "IP público (Elastic IP) do NAT Gateway; null quando enable_nat = false."
  value       = try(aws_eip.nat[0].public_ip, null)
}

output "security_group_ids" {
  description = "IDs dos security groups da Lambda e do banco."
  value = {
    lambda = aws_security_group.lambda.id
    db     = aws_security_group.db.id
  }
}

output "aurora_endpoint" {
  description = "Endpoint privado do writer do Aurora (usado no DB_URL da Lambda)."
  value       = aws_rds_cluster.main.endpoint
}

output "aurora_cluster_arn" {
  description = "ARN do cluster Aurora (usado na Data API e no Query Editor)."
  value       = aws_rds_cluster.main.arn
}

output "db_secret_arn" {
  description = "ARN do segredo com as credenciais do banco (usado na Data API e no Query Editor)."
  value       = aws_secretsmanager_secret.db_master.arn
}
