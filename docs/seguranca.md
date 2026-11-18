# Segurança — KubeShop na AWS (Entrega 2, Parte B)

> Arquitetura implantada: bastion + VM da aplicação (sub-rede pública) + VM do MongoDB (sub-rede privada) em `us-east-2a`, NAT gerenciado, backup em S3. Código em `infra/` (Terraform) e `ansible/`.

## 1. Controles obrigatórios S1–S8

| # | Controle | Como foi aplicado | Onde está | Como verificar (demo) |
|---|---|---|---|---|
| **S1** | Endurecimento do SSH | `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin no`, `AuthenticationMethods publickey`, `MaxAuthTries 3`. Só o bastion tem `AllowTcpForwarding yes`; app e banco têm `no`. O arquivo é validado com `sshd -t` antes de aplicar | `ansible/roles/ssh_hardening/` | `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password ubuntu@<bastion>` → `Permission denied (publickey)` |
| **S2** | Saída restrita | Nenhum SG libera "todo o tráfego". Saída só nas portas necessárias: 80/443 (pacotes, imagens, S3), 53 só para o resolvedor da VPC, 27017 só app→banco, 22 só bastion→app/banco. O SG padrão da VPC fica sem regras | `infra/security.tf` | Console EC2 → Security Groups → regras de saída; `nc -zv 1.1.1.1 25` a partir de uma VM → falha |
| **S3** | HTTPS | Proxy Nginx na VM da aplicação com TLS 1.2/1.3 e certificado autoassinado para o IP público, gerado pelo Ansible. A porta 80 só redireciona (301) para HTTPS. HSTS desligado de propósito (com certificado autoassinado ele travaria o navegador) | `ansible/roles/kubeshop_app/` | `curl -vk https://<ip-app>` e `curl -I http://<ip-app>` → `301` |
| **S4** | Gestão de segredos | As 3 senhas do MongoDB são geradas pelo Terraform (`random_password`) e guardadas no **SSM Parameter Store (SecureString com a CMK)**. O Ansible lê os valores no runner (`no_log`) e grava nas VMs em arquivos `0400`, montados como *secrets* do Compose. Nada no Git; chave SSH e `SSH_*` ficam nos GitHub Secrets; credencial AWS da pipeline é a access key de um usuário IAM dedicado, guardada só nos GitHub Secrets (OIDC bloqueado pela SCP do curso) | `infra/secrets.tf`, `ansible/playbook.yml`, workflows | Console SSM → Parameter Store (tipo SecureString); `gitleaks` sem achados; `grep` no repositório |
| **S5** | Menor privilégio para as instâncias | Só a VM do banco tem identidade (instance profile): `s3:PutObject` e `s3:AbortMultipartUpload` **somente** em `bucket/diario/*`, mais `kms:GenerateDataKey`/`kms:Decrypt` **somente via S3**. Ela não lê, não lista e não apaga backups. Bastion e app **não têm role**. IMDSv2 obrigatório com hop limit 1 (contêineres não alcançam as credenciais) | `infra/iam.tf`, `infra/compute.tf` | Na VM do banco: `aws s3 ls s3://<bucket>/` → `AccessDenied`; o backup funciona |
| **S6** | Criptografia em repouso | **CMK própria** (`aws_kms_key`, rotação anual ligada) declarada em todos os discos EBS (raiz das 3 VMs + disco de dados), no bucket de backup (SSE-KMS + bucket key) e nos parâmetros SSM. O bucket do state usa SSE-S3 e versionamento | `infra/kms.tf`, `compute.tf`, `backup.tf`, `secrets.tf`, `bootstrap/main.tf` | Console EC2 → Volumes → "Encrypted: yes, KMS key: alias/kubeshop-dev"; `ops backup` mostra `aws:kms` |
| **S7** | Análise automatizada | Pipeline `security.yml` em todo push/PR e antes de todo deploy: **Gitleaks** no histórico completo, **Trivy** e **Checkov** na IaC, `terraform fmt/validate`, `ansible-lint`. Falha em achado sem decisão registrada. Imagens da aplicação passam pelo **Trivy** no `app-ci.yml` | `.github/workflows/security.yml`, `app-ci.yml` | Artefatos `relatorios-iac` e `relatorio-gitleaks` da execução → `docs/evidencias/` |
| **S8** | Proteção da conta | MFA no usuário IAM do grupo e na conta root. A pipeline usa um usuário IAM próprio (`kubeshop-github-actions`), sem console e com política de escopo mínimo | Console IAM | Captura em `docs/evidencias/s8-mfa.png` (sem dados sensíveis) |

## 2. Tratamento dos achados (S7)

Ferramentas: Trivy 0.67.2 (`trivy config infra/`) e Checkov 3.2.495 (`checkov -d infra --framework terraform`). Resultado atual: **Trivy 0 achados abertos; Checkov 183 aprovadas, 0 falhas, 17 aceitas com justificativa**. Cada achado aceito está anotado **no próprio recurso** (`#trivy:ignore:<ID>` com comentário "ACEITO", ou `#checkov:skip=<ID>:<justificativa>`). O relatório da pipeline lista esses aceites automaticamente.

### 2.1 Corrigidos

| Achado | Severidade | Recurso | Decisão | Justificativa / correção |
|---|---|---|---|---|
| AVD-AWS-0132: bucket sem chave gerenciada pelo cliente | **Alta** | `aws_s3_bucket_server_side_encryption_configuration.backup` | **Corrigido** | Criada a CMK `aws_kms_key.main`; bucket em SSE-KMS (S6) |
| AVD-AWS-0027 / CKV_AWS_189: EBS sem CMK | Baixa | `aws_ebs_volume.db_data` (e discos raiz) | **Corrigido** | `kms_key_id = aws_kms_key.main.arn` em todos os volumes |
| CKV_AWS_145: S3 sem KMS por padrão | Média | `aws_s3_bucket.backup` | **Corrigido** | Mesmo ajuste da AVD-AWS-0132 |
| CKV_AWS_337: SSM sem CMK | Média | `aws_ssm_parameter.mongo[*]` | **Corrigido** | `key_id = aws_kms_key.main.arn` |
| SSH aberto ao mundo (verificação preventiva) | Crítica | `sg-bastion` | **Corrigido no projeto** | SSH só dos `ssh_allowed_cidrs`; validação no Terraform recusa `0.0.0.0/0` (R7) |
| IMDSv1 / EBS sem criptografia (verificações preventivas) | Alta | instâncias | **Corrigido no projeto** | `http_tokens = "required"`, `encrypted = true` (passam nas verificações AVD-AWS-0028 / CKV_AWS_8) |

### 2.2 Aceitos

| Achado | Severidade | Recurso | Decisão | Justificativa |
|---|---|---|---|---|
| AVD-AWS-0104: saída irrestrita (80/443 para 0.0.0.0/0) | **Crítica** | `bastion_*_out`, `app_*_out`, `db_*_out` | **Aceito** | Repositórios apt, Docker Hub, GHCR e S3 não têm faixas de IP estáveis. A saída já está limitada a duas portas (S2). Risco residual: exfiltração por HTTPS a partir de uma VM comprometida. Mitigação futura: proxy de saída ou VPC endpoints (S3 gateway endpoint é gratuito) |
| CKV_AWS_260: porta 80 aberta à internet | Média | `app_http_redirect` | **Aceito** | Necessária só para redirecionar a HTTPS; nenhum conteúdo é servido em HTTP (S3) |
| CKV_AWS_24: SSH a partir de 0.0.0.0/0 | Alta | `app_ssh_from_bastion`, `db_ssh_from_bastion` | **Falso positivo** | A origem é o SG do bastion (`referenced_security_group_id`), não a internet |
| CKV_AWS_300: lifecycle sem limite para uploads incompletos | Média | `aws_s3_bucket_lifecycle_configuration.backup` | **Falso positivo** | A regra define `abort_incomplete_multipart_upload` (1 dia) |
| CKV_AWS_109 / 111 / 356: política com `*` | Alta | `data.aws_iam_policy_document.kms` | **Falso positivo** | É a política padrão de chave KMS; em key policy, `*` se refere à própria chave |
| AVD-AWS-0090 / CKV_AWS_21: bucket sem versionamento | Média | `aws_s3_bucket.backup` | **Aceito** | O versionamento manteria cópias depois da expiração de 2 dias, contrariando a política mínima (seção 6.3). Previsto na política GFS |
| CKV_AWS_144: sem replicação entre regiões | Média | `aws_s3_bucket.backup` | **Aceito** | Dobra o custo; previsto apenas na política conservadora (`docs/backup.md`) |
| AVD-AWS-0089 / CKV_AWS_18: bucket sem log de acesso | Baixa | `aws_s3_bucket.backup` | **Aceito** | Exige outro bucket e gera custo por requisição; o acesso ao bucket já é só escrita (VM) e leitura pela pipeline |
| CKV2_AWS_62: sem notificação de eventos | Baixa | `aws_s3_bucket.backup` | **Aceito** | Não há consumidor de eventos nesta arquitetura |
| AVD-AWS-0178 / CKV2_AWS_11: VPC sem flow logs | Média | `aws_vpc.main` | **Aceito** | Custo de ingestão e armazenamento; previsto na proposta de HA |
| CKV_AWS_126: sem monitoramento detalhado | Baixa | 3 instâncias | **Aceito** | Cobrado por métrica; o básico (5 min) basta para o escopo |
| CKV2_AWS_41: instância sem role IAM | Baixa | bastion, app | **Aceito** | Elas não acessam APIs da AWS; não ter role é o menor privilégio possível (S5) |

**Gitleaks:** histórico completo sem achados (relatório `relatorio-gitleaks`).

## 3. Análise de ameaças

| # | Ameaça | Ativo afetado | Controle aplicado | Risco residual |
|---|---|---|---|---|
| 1 | Força bruta ou varredura no SSH do bastion | Bastion e, a partir dele, app e banco | SSH só dos CIDRs do grupo (R7), só por chave (S1), `MaxAuthTries 3`; app e banco não aceitam SSH da internet (a pipeline verifica que a porta 22 da app está fechada) | Roubo da chave privada de um integrante que esteja numa rede autorizada |
| 2 | Criação em massa de pedidos falsos via `POST /api/orders` (sem login, por desenho do escopo) | MongoDB (disco de dados) e disponibilidade da loja | `limit_req` de 10 req/s por IP (burst 20) no proxy; corpo limitado a 32 KB no proxy e 16 KB na API; validação de itens na API; disco de dados separado do sistema | Ataque distribuído a partir de muitos IPs; não há WAF |
| 3 | Leitura do histórico de pedidos de todos via `GET /api/orders` | Dados dos pedidos | **Aceito**: comportamento do escopo (pedidos fictícios, histórico compartilhado, sem login); a API retorna no máximo 100 pedidos e não guarda dado pessoal | Exposição dos pedidos fictícios |
| 4 | Acesso direto ao MongoDB pela internet ou por outra VM | Banco `kubeshop` | VM em sub-rede privada sem IP público (R5); porta 27017 publicada só no IP privado; SG do banco aceita 27017 **somente do SG da app**; autenticação obrigatória; usuário da app só com `readWrite` em `kubeshop` | Comprometimento da própria VM da aplicação (ameaça 5) |
| 5 | Invasor explora a aplicação e usa a VM da app para chegar ao banco | VM do banco | A app não é ponto de salto (`AllowTcpForwarding no`), o SG do banco não aceita SSH da app, nenhuma chave privada está nas VMs; contêineres sem root, com FS somente leitura, `cap_drop: ALL`, `no-new-privileges` | Com a senha da app (lida pelo contêiner da API), o invasor consegue ler e alterar pedidos |
| 6 | Invasor na VM do banco tenta apagar ou ler os backups | Cópias no S3 | Role com **apenas** `PutObject` em `diario/*`; sem `GetObject`, `ListBucket` ou `DeleteObject`; a restauração é feita pela pipeline, não pela VM | Ele consegue enviar arquivos falsos para `diario/` (detectável no restore-test); não há Object Lock |
| 7 | Vazamento de senha ou chave pelo repositório ou pelos logs da pipeline | SSM, MongoDB, AWS | Gitleaks no histórico em toda execução; `no_log` nas tasks com segredo; GitHub mascara secrets; access key da pipeline só nos GitHub Secrets e rotacionável pelo bootstrap; `.gitignore` cobre `*.tfvars`, `*.tfstate`, chaves | As senhas também estão no state do Terraform (bucket privado, criptografado e versionado). **Aceito** |
| 8 | Pipeline do GitHub usada por terceiros para alterar a conta | Conta AWS | Access key só nos GitHub Secrets do repositório; permissões limitadas a EC2/VPC na região, S3/SSM/IAM com prefixo `kubeshop-`; regra SSH da pipeline temporária e sempre revogada | Integrante com acesso de escrita ao repositório pode executar as pipelines; se a access key vazar, vale até ser rotacionada (`terraform apply -replace=aws_iam_access_key.github_actions`) |

## 4. Verificações rápidas (seção 4.2 da Entrega 2)

```bash
trivy config infra/
checkov -d infra --framework terraform
gitleaks git .
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password ubuntu@<IP_BASTION>
curl -vk https://<IP_APP>
```
