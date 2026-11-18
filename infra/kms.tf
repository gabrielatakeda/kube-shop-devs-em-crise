# S6: chave KMS gerenciada pelo grupo (CMK) para todos os dados em repouso:
# discos EBS, bucket de backup e senhas no SSM Parameter Store.
# Corrige os achados AVD-AWS-0132 / AVD-AWS-0027 (Trivy) e CKV_AWS_145 /
# CKV_AWS_189 / CKV_AWS_337 (Checkov). Custo: US$ 1/mês, proporcional por hora.
# No destroy, a chave entra em "exclusão pendente" pelo período mínimo de 7 dias.

data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Politica padrao de chave KMS; "*" em key policy se refere apenas a propria chave.
  #checkov:skip=CKV_AWS_111:Politica padrao de chave KMS; "*" em key policy se refere apenas a propria chave.
  #checkov:skip=CKV_AWS_356:Politica padrao de chave KMS; "*" em key policy se refere apenas a propria chave.
  # Política padrão: a conta controla a chave e delega o uso às políticas IAM
  # (role da pipeline e role da VM do banco).
  statement {
    sid       = "AdministracaoPelaConta"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "main" {
  description             = "KubeShop ${var.environment}: EBS, backup S3 e segredos SSM"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json

  tags = { Name = "${local.name}-cmk" }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}
