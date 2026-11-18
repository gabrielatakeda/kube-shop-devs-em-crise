# R7 / S2: grupos de segurança com regras como recursos separados.
# Não usar blocos ingress/egress inline: a pipeline adiciona e remove uma regra
# SSH temporária (IP do runner) no SG do bastion, e regras inline fariam o
# Terraform enxergar essa regra como divergência (plan com alterações).
#
# Fluxo administrativo: grupo/pipeline --22--> bastion --22--> app e banco.
# Somente o bastion aceita SSH vindo da internet, e apenas dos CIDRs autorizados.

locals {
  # Resolver DNS da Amazon (base da VPC + 2).
  vpc_dns_cidr = "${cidrhost(var.vpc_cidr, 2)}/32"
}

# ================================================================= SG do bastion
resource "aws_security_group" "bastion" {
  name        = "${local.name}-sg-bastion"
  description = "Bastion: SSH somente dos CIDRs autorizados; salto para app e banco"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-sg-bastion" }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.bastion.id
  description       = "SSH administrativo do grupo"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_app_ssh" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "Salto SSH para a VM da aplicacao"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_db_ssh" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "Salto SSH para a VM do banco"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.db.id
}

# ACEITO (AVD-AWS-0104): repositorios apt nao tem faixa de IP fixa;
# a saida e limitada as portas 80/443 (controle S2). Ver docs/seguranca.md.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "bastion_https_out" {
  security_group_id = aws_security_group.bastion.id
  description       = "Atualizacoes do SO"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ACEITO (AVD-AWS-0104): repositorios apt nao tem faixa de IP fixa;
# a saida e limitada as portas 80/443 (controle S2). Ver docs/seguranca.md.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "bastion_http_out" {
  security_group_id = aws_security_group.bastion.id
  description       = "Repositorios apt (HTTP)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "bastion_dns_udp" {
  security_group_id = aws_security_group.bastion.id
  description       = "DNS da VPC"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = local.vpc_dns_cidr
}

resource "aws_vpc_security_group_egress_rule" "bastion_dns_tcp" {
  security_group_id = aws_security_group.bastion.id
  description       = "DNS da VPC"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = local.vpc_dns_cidr
}

# ================================================================= SG da aplicação
resource "aws_security_group" "app" {
  name        = "${local.name}-sg-app"
  description = "VM da aplicacao: HTTPS publico; SSH somente a partir do bastion"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-sg-app" }
}

resource "aws_vpc_security_group_ingress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS da loja"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_http_redirect" {
  #checkov:skip=CKV_AWS_260:Porta 80 aberta apenas para redirecionar a HTTPS (S3); nenhum conteudo e servido em HTTP.
  security_group_id = aws_security_group.app.id
  description       = "HTTP apenas para redirecionar a HTTPS"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh_from_bastion" {
  #checkov:skip=CKV_AWS_24:Falso positivo - a origem e o SG do bastion (referenced_security_group_id), nao 0.0.0.0/0.
  security_group_id            = aws_security_group.app.id
  description                  = "SSH somente a partir do bastion"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion.id
}

# ACEITO (AVD-AWS-0104): apt, Docker Hub, GHCR e S3 nao tem faixa de IP fixa;
# a saida e limitada as portas 80/443 (controle S2). Ver docs/seguranca.md.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "Pacotes do SO, Docker e imagens do GHCR"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ACEITO (AVD-AWS-0104): apt, Docker Hub, GHCR e S3 nao tem faixa de IP fixa;
# a saida e limitada as portas 80/443 (controle S2). Ver docs/seguranca.md.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "app_http_out" {
  security_group_id = aws_security_group.app.id
  description       = "Repositorios apt (HTTP)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_dns_udp" {
  security_group_id = aws_security_group.app.id
  description       = "DNS da VPC"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = local.vpc_dns_cidr
}

resource "aws_vpc_security_group_egress_rule" "app_dns_tcp" {
  security_group_id = aws_security_group.app.id
  description       = "DNS da VPC"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = local.vpc_dns_cidr
}

resource "aws_vpc_security_group_egress_rule" "app_to_db_mongo" {
  security_group_id            = aws_security_group.app.id
  description                  = "API para o MongoDB"
  ip_protocol                  = "tcp"
  from_port                    = 27017
  to_port                      = 27017
  referenced_security_group_id = aws_security_group.db.id
}

# ================================================================= SG do banco
resource "aws_security_group" "db" {
  name        = "${local.name}-sg-db"
  description = "VM do MongoDB: 27017 somente da aplicacao; SSH somente do bastion"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-sg-db" }
}

resource "aws_vpc_security_group_ingress_rule" "db_mongo_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MongoDB somente da API"
  ip_protocol                  = "tcp"
  from_port                    = 27017
  to_port                      = 27017
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "db_ssh_from_bastion" {
  #checkov:skip=CKV_AWS_24:Falso positivo - a origem e o SG do bastion (referenced_security_group_id), nao 0.0.0.0/0.
  security_group_id            = aws_security_group.db.id
  description                  = "SSH somente a partir do bastion"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion.id
}

# ACEITO (AVD-AWS-0104): apt, Docker Hub, GHCR e S3 nao tem faixa de IP fixa;
# a saida e limitada as portas 80/443 (controle S2). Ver docs/seguranca.md.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "db_https_out" {
  security_group_id = aws_security_group.db.id
  description       = "Pacotes, imagem do MongoDB e envio de backup ao S3 (via NAT)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ACEITO (AVD-AWS-0104): apt, Docker Hub, GHCR e S3 nao tem faixa de IP fixa;
# a saida e limitada as portas 80/443 (controle S2). Ver docs/seguranca.md.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "db_http_out" {
  security_group_id = aws_security_group.db.id
  description       = "Repositorios apt (HTTP) via NAT"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "db_dns_udp" {
  security_group_id = aws_security_group.db.id
  description       = "DNS da VPC"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = local.vpc_dns_cidr
}

resource "aws_vpc_security_group_egress_rule" "db_dns_tcp" {
  security_group_id = aws_security_group.db.id
  description       = "DNS da VPC"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = local.vpc_dns_cidr
}
