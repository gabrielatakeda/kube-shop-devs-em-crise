# S4: senhas geradas pelo Terraform e guardadas no SSM Parameter Store
# (SecureString, criptografadas com a CMK do projeto). Nada vai para o repositório.
# O Ansible lê os parâmetros na pipeline (no_log) e grava os arquivos nas VMs
# com permissão restrita. O valor também fica no state, que está em bucket
# privado e criptografado (risco aceito, registrado em docs/seguranca.md).

locals {
  mongo_users = toset(["mongo-root-password", "mongo-app-password", "mongo-backup-password"])
}

resource "random_password" "mongo" {
  for_each = local.mongo_users

  length  = 40
  special = false
}

resource "aws_ssm_parameter" "mongo" {
  for_each = local.mongo_users

  name        = "/${var.project}/${var.environment}/${each.key}"
  description = "Senha do MongoDB (${each.key}) do KubeShop"
  type        = "SecureString"
  value       = random_password.mongo[each.key].result
  key_id      = aws_kms_key.main.arn
}
