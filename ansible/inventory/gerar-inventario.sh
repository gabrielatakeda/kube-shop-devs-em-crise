#!/usr/bin/env bash
# Gera ansible/inventory/hosts.yml a partir dos outputs do Terraform.
# Uso: ./gerar-inventario.sh <arquivo terraform output -json> [regiao]
# O bastion é o único host acessado direto pela internet. A VM da aplicação e a
# VM do banco são acessadas pelos IPs privados, saltando pelo bastion.
set -euo pipefail

OUTPUTS_JSON="${1:?informe o arquivo gerado por: terraform output -json}"
REGION="${2:-${AWS_REGION:-us-east-2}}"
DEST="$(cd "$(dirname "$0")" && pwd)/hosts.yml"

out() { jq -er ".${1}.value" "$OUTPUTS_JSON"; }

BASTION_IP="$(out bastion_public_ip)"
JUMP="-o ProxyCommand=\"ssh -W %h:%p -o StrictHostKeyChecking=accept-new -o BatchMode=yes ubuntu@${BASTION_IP}\""

cat > "$DEST" <<EOF
# Gerado por gerar-inventario.sh. Não versionar.
all:
  vars:
    ansible_user: ubuntu
    aws_region: ${REGION}
    kubeshop_env: $(out environment)
    bastion_public_ip: ${BASTION_IP}
    app_public_ip: $(out app_public_ip)
    app_private_ip: $(out app_private_ip)
    db_private_ip: $(out db_private_ip)
    backup_bucket: $(out backup_bucket)
    db_data_volume_id: $(out db_data_volume_id)
    ssm_parameter_prefix: $(out ssm_parameter_prefix)
  children:
    bastion:
      hosts:
        kubeshop-bastion:
          ansible_host: ${BASTION_IP}
    app:
      hosts:
        kubeshop-app:
          ansible_host: $(out app_private_ip)
          ansible_ssh_common_args: >-
            ${JUMP}
    db:
      hosts:
        kubeshop-db:
          ansible_host: $(out db_private_ip)
          ansible_ssh_common_args: >-
            ${JUMP}
EOF

echo "Inventário gerado em ${DEST}"
