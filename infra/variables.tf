# ---------------------------------------------------------------- Identificação
variable "region" {
  type        = string
  description = "Região AWS da implantação."
  default     = "us-east-2"
}

variable "availability_zone" {
  type        = string
  description = "Zona de disponibilidade das sub-redes (arquitetura implantada usa uma zona; a proposta de HA usa duas)."
  default     = "us-east-2a"
}

variable "project" {
  type        = string
  description = "Nome do projeto: prefixo dos recursos e tag 'projeto'."
  default     = "kubeshop"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project))
    error_message = "Use de 3 a 20 caracteres: letras minúsculas, números e hífen."
  }
}

variable "group" {
  type        = string
  description = "Identificação do grupo (tag 'grupo')."
  default     = "devs-em-crise"
}

variable "environment" {
  type        = string
  description = "Ambiente de destino (parâmetro 'environment' da pipeline)."
  default     = "dev"

  validation {
    condition     = contains(["dev", "homolog", "prod"], var.environment)
    error_message = "environment deve ser dev, homolog ou prod."
  }
}

variable "instance_name" {
  type        = string
  description = "Prefixo do nome das VMs (parâmetro 'instance_name'). Gera <nome>-app e <nome>-db."
  default     = "kubeshop"
}

# ---------------------------------------------------------------- Rede (R1, R2)
variable "vpc_cidr" {
  type        = string
  description = "CIDR da VPC definido na Entrega 1."
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr deve ser um CIDR IPv4 válido."
  }
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR da sub-rede pública (bastion, VM da aplicação e NAT)."
  default     = "10.20.1.0/24"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR da sub-rede privada (VM do MongoDB)."
  default     = "10.20.11.0/24"
}

# ---------------------------------------------------------------- Acesso (R7, R8)
variable "ssh_allowed_cidrs" {
  type        = list(string)
  description = "CIDRs autorizados a acessar o bastion por SSH (ex.: IP do grupo /32). Única entrada SSH da arquitetura."

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0 && alltrue([for c in var.ssh_allowed_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "Informe ao menos um CIDR válido. 0.0.0.0/0 não é aceito para SSH."
  }
}

variable "ssh_public_key" {
  type        = string
  description = "Chave pública SSH do grupo. A chave privada nunca entra no repositório."

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ", var.ssh_public_key))
    error_message = "Informe uma chave pública OpenSSH (ssh-ed25519, ssh-rsa ou ecdsa)."
  }
}

# ---------------------------------------------------------------- Computação (R9)
variable "app_instance_type" {
  type        = string
  description = "Tipo da VM da aplicação (parâmetro 'instance_type' da pipeline)."
  default     = "t3.micro"
}

variable "db_instance_type" {
  type        = string
  description = "Tipo da VM do MongoDB."
  default     = "t3.micro"
}

variable "bastion_instance_type" {
  type        = string
  description = "Tipo da VM bastion (apenas SSH; não roda aplicação)."
  default     = "t3.nano"
}

variable "bastion_root_volume_size_gb" {
  type        = number
  description = "Tamanho do disco do sistema do bastion, em GB."
  default     = 8
}

variable "ami_id" {
  type        = string
  description = "AMI fixa das VMs. Vazio = Ubuntu 24.04 LTS mais recente no primeiro apply (alterações posteriores da AMI são ignoradas)."
  default     = ""
}

variable "root_volume_size_gb" {
  type        = number
  description = "Tamanho do disco do sistema das VMs, em GB."
  default     = 20
}

variable "db_data_volume_size_gb" {
  type        = number
  description = "Tamanho do disco de dados dedicado ao MongoDB, em GB."
  default     = 10
}

# ---------------------------------------------------------------- Backup (Parte D)
variable "backup_retention_days" {
  type        = number
  description = "Dias até a expiração das cópias da geração diária (política mínima: no máximo 2)."
  default     = 2

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 2
    error_message = "A política mínima exige retenção de 1 a 2 dias."
  }
}

variable "backup_force_destroy" {
  type        = bool
  description = "Permite que o destroy apague o bucket de backup mesmo com objetos (encerramento do trabalho)."
  default     = true
}
