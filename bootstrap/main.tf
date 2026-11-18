# Bootstrap: executado UMA vez, localmente, com as credenciais do grupo.
# Cria apenas o que a Entrega 2 permite fora da pipeline:
#   - bucket do remote state
#   - credencial de acesso da pipeline (usuário IAM + access key; OIDC bloqueado pela SCP do curso)
#   - alerta de orçamento
# O state deste diretório é local (bootstrap/terraform.tfstate, ignorado pelo Git).

terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      projeto = var.project
      grupo   = var.group
      gerido  = "terraform-bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

# ---------------------------------------------------------------- Remote state
resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versões antigas do state expiram em 30 dias (custo próximo de zero).
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expira-versoes-antigas"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ---------------------------------------------------------------- Usuário da pipeline
# A SCP da organização do curso bloqueia provedores OIDC (iam:*OpenIDConnectProvider),
# então a pipeline usa um usuário IAM dedicado, com access key guardada nos
# GitHub Secrets (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY).
resource "aws_iam_user" "github_actions" {
  name = "${var.project}-github-actions"
}

resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}

data "aws_iam_policy_document" "github_permissions" {
  # Rede e computação do projeto.
  statement {
    sid       = "Ec2Vpc"
    actions   = ["ec2:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # State e bucket de backup do projeto.
  statement {
    sid     = "S3Projeto"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.project}-*",
      "arn:aws:s3:::${var.project}-*/*",
    ]
  }

  # Segredos da aplicação.
  statement {
    sid       = "SsmParametros"
    actions   = ["ssm:*Parameter*", "ssm:AddTagsToResource", "ssm:ListTagsForResource", "ssm:RemoveTagsFromResource"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/*"]
  }
  statement {
    sid       = "SsmDescribe"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  # Identidade da VM de banco (role + instance profile com prefixo do projeto).
  statement {
    sid = "IamInstanceRole"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile", "iam:ListInstanceProfilesForRole", "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project}-*",
    ]
  }

  # CMK do projeto (criação, uso pelo EBS/S3/SSM e exclusão agendada no destroy).
  # kms:CreateKey não aceita restrição por recurso; o uso é limitado à região.
  statement {
    sid = "KmsProjeto"
    actions = [
      "kms:CreateKey", "kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy",
      "kms:GetKeyRotationStatus", "kms:EnableKeyRotation", "kms:ListResourceTags",
      "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion",
      "kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias", "kms:ListAliases",
      "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*",
      "kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # Leitura usada por data sources e pelo provider.
  statement {
    sid       = "Leitura"
    actions   = ["sts:GetCallerIdentity", "iam:ListRoles"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "github_permissions" {
  name   = "${var.project}-pipeline"
  user   = aws_iam_user.github_actions.name
  policy = data.aws_iam_policy_document.github_permissions.json
}

# ---------------------------------------------------------------- Orçamento
resource "aws_budgets_budget" "mensal" {
  name         = "${var.project}-orcamento-mensal"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_emails
  }
}
