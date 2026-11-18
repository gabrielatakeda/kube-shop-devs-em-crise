# R11 e dados consumidos pelo Ansible (inventário gerado pela pipeline).

output "bastion_public_ip" {
  description = "IP público fixo do bastion (recurso de acesso administrativo, R6)."
  value       = aws_eip.bastion.public_ip
}

output "app_public_ip" {
  description = "IP público fixo da VM da aplicação (acesso à loja)."
  value       = aws_eip.app.public_ip
}

output "nat_public_ip" {
  description = "IP público do NAT gateway (saída da sub-rede privada)."
  value       = aws_eip.nat.public_ip
}

output "bastion_private_ip" {
  description = "IP privado do bastion."
  value       = aws_instance.bastion.private_ip
}

output "app_private_ip" {
  description = "IP privado da VM da aplicação."
  value       = aws_instance.app.private_ip
}

output "db_private_ip" {
  description = "IP privado da VM do MongoDB."
  value       = aws_instance.db.private_ip
}

output "app_url" {
  description = "URL HTTPS da loja."
  value       = "https://${aws_eip.app.public_ip}"
}

output "backup_bucket" {
  description = "Bucket da política mínima de backup."
  value       = aws_s3_bucket.backup.bucket
}

output "db_data_volume_id" {
  description = "ID do volume EBS de dados do MongoDB (usado pelo Ansible para montar o disco)."
  value       = aws_ebs_volume.db_data.id
}

output "ssm_parameter_prefix" {
  description = "Prefixo dos segredos no SSM Parameter Store."
  value       = "/${var.project}/${var.environment}"
}

output "bastion_security_group_id" {
  description = "SG do bastion (a pipeline abre e fecha nele a regra SSH temporária do runner)."
  value       = aws_security_group.bastion.id
}

output "ssh_commands" {
  description = "Comandos de acesso administrativo (D3)."
  value = {
    bastion = "ssh ubuntu@${aws_eip.bastion.public_ip}"
    app     = "ssh -J ubuntu@${aws_eip.bastion.public_ip} ubuntu@${aws_instance.app.private_ip}"
    db      = "ssh -J ubuntu@${aws_eip.bastion.public_ip} ubuntu@${aws_instance.db.private_ip}"
  }
}

output "environment" {
  description = "Ambiente implantado."
  value       = var.environment
}
