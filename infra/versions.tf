terraform {
  # Versões fixadas para que todo o grupo use as mesmas (seção 7.2).
  # O .terraform.lock.hcl gerado pelo "terraform init" deve ser versionado.
  required_version = "~> 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8.0"
    }
  }
}
