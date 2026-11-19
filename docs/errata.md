# Errata — divergências entre o projeto da Entrega 1 e o que foi implantado

> **Revisar com o documento da Entrega 1.** As linhas abaixo registram as decisões tomadas na implantação. Para cada uma, confirmar se a Entrega 1 previa outra coisa; se não houver divergência, remover a linha. Quando uma decisão da Entrega 1 mudar, o ADR original recebe status **"substituída"** e o novo ADR é citado aqui pelo número.

| # | Item | Previsto na Entrega 1 | Implantado | Motivo | ADR |
|---|---|---|---|---|---|
| 1 | Aplicação | *(preencher)* | KubeShop (escopo da Zibiska Korp), usado também como documento de demanda da PM-04 | Uma única aplicação atende as duas disciplinas | *(novo ADR, se a E1 usava outra aplicação)* |
| 2 | Região | *(preencher)* | `us-east-2` (Ohio) | Custo menor que São Paulo (NAT, EC2, IPv4) | *(ADR de provedor/região da E1)* |
| 3 | Acesso administrativo | *(preencher)* | **Bastion dedicado** t3.micro; app e banco só aceitam SSH do bastion | Separar a superfície exposta da aplicação do caminho de administração | ADR-XXX-bastion-dedicado |
| 4 | Criptografia | *(preencher)* | **CMK própria** para EBS, S3 e SSM | Corrigir o achado alto AVD-AWS-0132 (S6/S7) | — (registrado em `docs/seguranca.md`) |
| 5 | HTTPS | *(preencher)* | Proxy Nginx extra com certificado autoassinado; 80 → 301 | Sem domínio próprio; a imagem do frontend fica inalterada | — |
| 6 | Disco do banco | *(preencher)* | **Volume EBS de dados separado** (10 GB) montado em `/data/mongo` | Os pedidos sobrevivem à troca de tipo ou à recriação da VM (ACE-05, Cenário 2 da PM-04) | — |
| 7 | Credenciais da pipeline | *(preencher)* | Usuário IAM dedicado com access key em GitHub Secrets (OIDC bloqueado pela SCP do curso) + regra SSH temporária no bastion | Nenhuma chave AWS no repositório; política com escopo mínimo; R7 preservado | ADR-XXX-pipeline-credencial-ssh-temporario |
| 8 | Backup | *(preencher)* | Dump lógico → S3 (opção A), retenção de 2 dias | Consistência do dump; VM só com escrita | ADR-XXX-backup |
| 9 | Tipos de instância | *(preencher)* | Bastion, app e banco t3.micro (variáveis) | Conta no plano Free Tier da AWS só aceita tipos elegíveis (t3.nano foi recusado no apply com InvalidParameterCombination); MongoDB limitado a 0,25 GB de cache | — |
| 10 | CIDRs | *(preencher)* | VPC 10.20.0.0/16; pública 10.20.1.0/24; privada 10.20.11.0/24 | Ajustar para os CIDRs da Entrega 1 em `infra/variables.tf`, se diferentes | — |

## Incidentes de segurança

Nenhuma credencial, chave privada ou state foi commitado até a tag `entrega-2` (Gitleaks no histórico completo, sem achados). Se ocorrer: revogar imediatamente, registrar aqui com data, commit e ação tomada.
