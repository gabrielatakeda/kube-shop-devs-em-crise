# S5: identidade da VM do banco com permissão mínima.
# Ela só consegue GRAVAR objetos no prefixo da geração diária do bucket de backup.
# Não lê, não lista e não apaga: um invasor na VM não destrói os backups.
# Nenhuma chave de acesso é gravada na instância.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "db" {
  name               = "${local.name}-db-backup"
  description        = "VM do MongoDB: envia dumps para o prefixo diario/ do bucket de backup"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "db_backup" {
  statement {
    sid       = "GravaSomenteGeracaoDiaria"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.backup.arn}/diario/*"]
  }

  # SSE-KMS: gerar a chave de dados do objeto. Decrypt é exigido pelo S3 para
  # concluir uploads multipart criptografados; sem s3:GetObject a VM continua
  # sem conseguir ler os backups. Restrito ao uso via S3 nesta região.
  statement {
    sid       = "UsaCmkSomenteViaS3"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.main.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "db_backup" {
  name   = "grava-backup-diario"
  role   = aws_iam_role.db.id
  policy = data.aws_iam_policy_document.db_backup.json
}

resource "aws_iam_instance_profile" "db" {
  name = "${local.name}-db"
  role = aws_iam_role.db.name
}
