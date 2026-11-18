# Ubuntu 24.04 LTS (Canonical). Usada só quando ami_id não é informado.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
}

# R8: somente a chave pública é informada ao Terraform.
resource "aws_key_pair" "group" {
  key_name   = "${local.name}-chave-grupo"
  public_key = var.ssh_public_key
}

# ---------------------------------------------------------------- Bastion
# Único ponto de entrada SSH (R6/R7). Sub-rede pública, IP fixo, sem role IAM,
# sem Docker e sem dados: se comprometido, não expõe aplicação nem backups.
resource "aws_instance" "bastion" {
  #checkov:skip=CKV_AWS_126:Monitoramento detalhado (1 min) e cobrado por metrica; o basico (5 min) basta para o escopo.
  #checkov:skip=CKV2_AWS_41:O bastion nao acessa APIs da AWS; sem role e o menor privilegio possivel (S5).
  ami                         = local.ami_id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.group.key_name
  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.bastion_root_volume_size_gb
    encrypted             = true
    kms_key_id            = aws_kms_key.main.arn
    delete_on_termination = true
    tags                  = { Name = "${var.instance_name}-bastion-root" }
  }

  tags = { Name = "${var.instance_name}-bastion", funcao = "bastion" }

  lifecycle {
    ignore_changes = [ami]
  }
}

# R6: IP público estático no recurso de acesso administrativo.
resource "aws_eip" "bastion" {
  domain = "vpc"
  tags   = { Name = "${local.name}-eip-bastion" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

# ---------------------------------------------------------------- VM da aplicação
# Sub-rede pública, IP fixo (EIP) para a loja em HTTPS. SSH somente via bastion.
resource "aws_instance" "app" {
  #checkov:skip=CKV_AWS_126:Monitoramento detalhado (1 min) e cobrado por metrica; o basico (5 min) basta para o escopo.
  #checkov:skip=CKV2_AWS_41:A VM da aplicacao nao acessa APIs da AWS; sem role e o menor privilegio possivel (S5).
  ami                         = local.ami_id
  instance_type               = var.app_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = aws_key_pair.group.key_name
  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  # S6: criptografia declarada explicitamente.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    kms_key_id            = aws_kms_key.main.arn
    delete_on_termination = true
    tags                  = { Name = "${var.instance_name}-app-root" }
  }

  tags = { Name = "${var.instance_name}-app", funcao = "aplicacao" }

  # Nova AMI publicada pela Canonical não deve recriar a VM (plan limpo).
  lifecycle {
    ignore_changes = [ami]
  }
}

# IP público estático da loja (URL da aplicação).
resource "aws_eip" "app" {
  domain = "vpc"
  tags   = { Name = "${local.name}-eip-app" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}

# ---------------------------------------------------------------- VM do banco
# R5: sub-rede privada, sem IP público.
resource "aws_instance" "db" {
  #checkov:skip=CKV_AWS_126:Monitoramento detalhado (1 min) e cobrado por metrica; o basico (5 min) basta para o escopo.
  ami                         = local.ami_id
  instance_type               = var.db_instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.db.id]
  key_name                    = aws_key_pair.group.key_name
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.db.name
  ebs_optimized               = true
  monitoring                  = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    kms_key_id            = aws_kms_key.main.arn
    delete_on_termination = true
    tags                  = { Name = "${var.instance_name}-db-root" }
  }

  tags = { Name = "${var.instance_name}-db", funcao = "banco" }

  lifecycle {
    ignore_changes = [ami]
  }

  # A rota pelo NAT precisa existir para a VM baixar pacotes no Ansible.
  depends_on = [aws_route.private_nat]
}

# Disco de dados dedicado ao MongoDB: sobrevive à troca de tipo ou à recriação
# da VM (escopo ACE-05 / PM-04 Cenário 2).
resource "aws_ebs_volume" "db_data" {
  availability_zone = var.availability_zone
  size              = var.db_data_volume_size_gb
  type              = "gp3"
  encrypted         = true
  kms_key_id        = aws_kms_key.main.arn

  tags = { Name = "${var.instance_name}-db-dados", backup = "mongodump-diario" }
}

resource "aws_volume_attachment" "db_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.db_data.id
  instance_id = aws_instance.db.id
}
