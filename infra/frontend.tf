# ---------------------------------------------------------------
# Bucket do frontend (Angular): privado, lido apenas pelo CloudFront (OAC)
# ---------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.projeto}-frontend-${random_id.suffix.hex}"
  force_destroy = true # permite o destroy mesmo com os arquivos do build no bucket

  tags = { Name = "${var.projeto}-frontend" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Criptografia em repouso declarada explicitamente (S6)
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Somente esta distribuição do CloudFront pode ler os arquivos
data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.projeto}-frontend-oac"
  description                       = "Acesso do CloudFront ao bucket do frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------------------------
# Rotas do Angular: URLs sem extensão de arquivo (ex.: /cardapio) viram /index.html.
# Aplicada apenas ao comportamento padrão, para não afetar os erros da API.
# ---------------------------------------------------------------
resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${var.projeto}-spa-rewrite"
  comment = "Reescreve rotas do Angular para /index.html"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-JS
    function handler(event) {
      var request = event.request;
      if (request.uri.indexOf('.') === -1) {
        request.uri = '/index.html';
      }
      return request;
    }
  JS
}

# ---------------------------------------------------------------
# Políticas de cache e de requisição
# ---------------------------------------------------------------
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# API sem cache. O cabeçalho Authorization precisa estar na política de cache para
# o CloudFront repassá-lo em GET; o TTL máximo de 1 s é exigido para isso.
resource "aws_cloudfront_cache_policy" "api" {
  name        = "${var.projeto}-api-sem-cache"
  comment     = "API: sem cache, repassando Authorization e query strings"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization"]
      }
    }

    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

# ---------------------------------------------------------------
# CloudFront: entrada única com HTTPS (S3)
#   /*      -> S3 (Angular)
#   /api/*  -> API Gateway -> Lambda
# ---------------------------------------------------------------
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  comment             = "Dove Restaurante: frontend e API"
  default_root_object = "index.html"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All" # inclui os pontos de presença da América do Sul

  origin {
    origin_id                = "s3-frontend"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id   = "api-gateway"
    domain_name = replace(aws_apigatewayv2_api.main.api_endpoint, "https://", "")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api-gateway"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = aws_cloudfront_cache_policy.api.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    compress                 = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Certificado válido da própria AWS para *.cloudfront.net (sem domínio próprio)
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "${var.projeto}-cloudfront" }
}
