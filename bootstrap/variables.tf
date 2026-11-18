variable "region" {
  type        = string
  description = "Região AWS onde o projeto é implantado."
  default     = "us-east-2"
}

variable "project" {
  type        = string
  description = "Nome do projeto, usado como prefixo de recursos e na tag 'projeto'."
  default     = "kubeshop"
}

variable "group" {
  type        = string
  description = "Identificação do grupo (tag 'grupo')."
  default     = "devs-em-crise"
}

variable "budget_limit_usd" {
  type        = string
  description = "Limite mensal do alerta de orçamento, em USD."
  default     = "20"
}

variable "budget_emails" {
  type        = list(string)
  description = "E-mails que recebem os alertas de orçamento. Informe em bootstrap.tfvars (não versionado)."
}
