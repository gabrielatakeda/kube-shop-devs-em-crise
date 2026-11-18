# Credenciais vêm do ambiente (perfil da AWS CLI localmente, access key do usuário IAM na pipeline).
provider "aws" {
  region = var.region

  # R10: tags em todos os recursos que as suportam.
  default_tags {
    tags = {
      projeto  = var.project
      grupo    = var.group
      ambiente = var.environment
      gerido   = "terraform"
    }
  }
}
