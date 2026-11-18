# Parte D: política mínima configurada (geração "Son" do GFS).
# Mecanismo: dump lógico do MongoDB gravado no S3 (opção A da seção 6.3).
# - Prefixo diario/ com expiração em backup_retention_days (<= 2 dias).
# - Criptografia com a CMK do projeto (S6), bloqueio de acesso público e TLS obrigatório.

data "aws_caller_identity" "current" {}

# ACEITOS: ver justificativas abaixo e docs/seguranca.md.
#trivy:ignore:AVD-AWS-0089
#trivy:ignore:AVD-AWS-0090
resource "aws_s3_bucket" "backup" {
  #checkov:skip=CKV_AWS_18:Log de acesso exige outro bucket e gera custo por requisicao; incompativel com a politica minima.
  #checkov:skip=CKV_AWS_21:Versionamento manteria copias apos a expiracao de 2 dias, contrariando a politica minima (secao 6.3).
  #checkov:skip=CKV_AWS_144:Replicacao entre regioes dobra o custo; prevista apenas na politica conservadora GFS (docs/backup.md).
  #checkov:skip=CKV2_AWS_62:Notificacoes de eventos nao tem consumidor nesta arquitetura.
  bucket        = "${local.name}-backup-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.backup_force_destroy

  tags = { Name = "${local.name}-backup" }
}

resource "aws_s3_bucket_ownership_controls" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    # Bucket key reduz as chamadas (e o custo) ao KMS.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  #checkov:skip=CKV_AWS_300:Falso positivo - a regra define abort_incomplete_multipart_upload (1 dia).
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "geracao-diaria-son"
    status = "Enabled"
    filter {
      prefix = "diario/"
    }
    expiration {
      days = var.backup_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "backup_bucket" {
  statement {
    sid       = "NegaTransporteSemTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backup.arn, "${aws_s3_bucket.backup.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id
  policy = data.aws_iam_policy_document.backup_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.backup]
}
