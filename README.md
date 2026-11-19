# KubeShop na AWS — Devs em Crise

Loja virtual didática (catálogo, sacola e histórico de pedidos fictícios) com frontend React/Nginx, API Node.js/Express e MongoDB, implantada na **AWS** com **Terraform**, **Ansible** e **GitHub Actions**.

Este repositório atende a duas entregas:
- **Projeto Integrador · Entrega 2** (Uniamérica Descomplica): implantação, segurança, alta disponibilidade e backup;
- **PM-04 · Projeto Final**: pipeline de CI/CD com Terraform e Ansible. O documento de demanda é o escopo da Zibiska Korp (`escopo.pdf`).

> ⚠️ **Este projeto gera custos na conta AWS do grupo** (≈ US$ 0,09/hora com tudo ligado; o NAT Gateway e os IPs públicos são cobrados por hora mesmo sem tráfego). Configure o alerta de orçamento **antes** do primeiro apply, mantenha o ambiente ligado só durante testes e apresentações e rode o `infra-destroy` ao terminar. Detalhes em [`docs/custos/estimativas.md`](docs/custos/estimativas.md).

## Integrantes e divisão das demonstrações

| Integrante | Responsável por | Demonstrações (Entrega 2) | Cenários (PM-04) |
|---|---|---|---|
| *(nome)* | Terraform, rede, custos | D1 · D4 | Cenário 1 |
| *(nome)* | Ansible, pipelines | D2 · D3 | Cenários 2 e 3 |
| *(nome)* | Segurança, backup, documentação | D5 · D6 · D7 | Validação da demanda |

## Arquitetura

```
Internet ──22 (só CIDR do grupo)──▶ Bastion (EIP) ──22──▶ VM-APP / VM-DB
Internet ──443 (80→301)──────────▶ VM-APP (EIP): proxy TLS → frontend → API ──27017──▶ VM-DB (privada)
VM-DB ──NAT──▶ S3 backup (diario/, 2 dias, SSE-KMS)
```

- **VPC** `10.20.0.0/16` em `us-east-2a`: sub-rede pública (bastion, app, NAT) e privada (MongoDB).
- **3 VMs:** bastion t3.micro (único SSH), aplicação t3.micro (proxy TLS + frontend + API), MongoDB t3.micro com disco EBS de dados dedicado.
- **Segurança:** SSH só por chave via bastion; segredos no SSM (SecureString); CMK própria para discos, backup e segredos; a pipeline autentica com access key de um usuário IAM restrito (OIDC bloqueado pela SCP do curso); scans com Trivy, Checkov e Gitleaks.
- Diagramas: [`docs/diagramas/`](docs/diagramas/). Decisões: [`docs/adr/`](docs/adr/).

| Pasta | Conteúdo |
|---|---|
| `apps/`, `docker/`, `scripts/`, `tests/`, `compose.yaml` | Aplicação original (execução local) |
| `bootstrap/` | Executado uma vez: bucket do state, usuário IAM da pipeline, alerta de orçamento |
| `infra/` | Terraform do ambiente (rede, SGs, VMs, KMS, SSM, IAM, backup) |
| `ansible/` | Configuração das VMs (`playbook.yml`) e rotinas de operação (`ops.yml`) |
| `.github/workflows/` | `app-ci`, `security`, `infra-deploy`, `ops`, `infra-destroy` |
| `docs/` | Segurança, HA, backup, custos, ADRs, errata, manual, validação, evidências |

## Pré-requisitos

- Conta AWS com **MFA** e um usuário IAM administrativo para o bootstrap
- AWS CLI v2 configurada (`aws configure`, região `us-east-2`)
- Terraform ≥ 1.10 (testado com 1.17.0)
- Repositório no GitHub com Actions habilitado
- Par de chaves SSH do grupo:

```bash
ssh-keygen -t ed25519 -C kubeshop-devs-em-crise -f ~/.ssh/kubeshop-grupo
```

## 1. Bootstrap (uma vez, localmente)

Cria o bucket do Terraform state, o usuário IAM da pipeline (com access key) e o alerta de orçamento. São as exceções que a Entrega 2 permite criar fora da pipeline.

```bash
cd bootstrap
```

```bash
cp bootstrap.tfvars.example bootstrap.tfvars
```

Edite `bootstrap.tfvars` (e-mail do alerta) e aplique:

```bash
terraform init
```

```bash
terraform apply "-var-file=bootstrap.tfvars"
```

## 2. Configuração do GitHub

Em **Settings → Secrets and variables → Actions**:

| Tipo | Nome | Valor |
|---|---|---|
| Secret | `AWS_ACCESS_KEY_ID` | Output `aws_access_key_id` do bootstrap |
| Secret | `AWS_SECRET_ACCESS_KEY` | `terraform output -raw aws_secret_access_key` (no diretório `bootstrap`) |
| Variable | `TF_STATE_BUCKET` | Output `tf_state_bucket` do bootstrap |
| Variable | `AWS_REGION` | `us-east-2` |
| Variable | `SSH_ALLOWED_CIDR` | IP público do grupo, ex.: `203.0.113.10/32` (vários separados por vírgula) |
| Secret | `SSH_PRIVATE_KEY` | Conteúdo de `~/.ssh/kubeshop-grupo` |
| Secret | `SSH_PUBLIC_KEY` | Conteúdo de `~/.ssh/kubeshop-grupo.pub` |

Também é preciso:
- Em **Settings → Actions → General → Workflow permissions**, marcar **Read and write permissions** (publicação no GHCR).
- Depois da primeira publicação, deixar os pacotes `kubeshop-api` e `kubeshop-frontend` **públicos** (Packages → Package settings).

## 3. Publicar a aplicação

A cada push na `main`, o `app-ci` testa, constrói, passa o Trivy e publica as imagens `ghcr.io/<owner>/kubeshop-{api,frontend}` com a **versão do `package.json`** (ex.: `1.0.0`) e com `sha-<commit>`. Também pode ser disparado manualmente em Actions → app-ci → Run workflow.

Para lançar uma nova versão, altere o campo `"version"` do `package.json` e do `package-lock.json` (as duas primeiras ocorrências) e faça push. Tags Git **não** são usadas para publicar: a tag `entrega-2` marca apenas a versão final entregue.

## 4. Criar ou atualizar o ambiente (apply)

**Actions → infra-deploy → Run workflow**:

| Parâmetro | Exemplo | Efeito |
|---|---|---|
| `action` | `plan` / `apply` | Só mostrar o plano, ou aplicar Terraform + Ansible |
| `environment` | `dev` | Ambiente (state separado) |
| `instance_name` | `kubeshop` | Nome das VMs |
| `app_instance_type` / `db_instance_type` | `t3.micro` | Tamanho das VMs (troca no lugar, dados preservados) |
| `docker_image` / `docker_tag` | vazio / `1.0.0` | Versão da aplicação |
| `update_os` | `false` | Atualizar o SO |
| `extra_packages` | `curl,htop` | Pacotes adicionais |
| `ssh_allowed_cidr` | vazio | Sobrescreve `SSH_ALLOWED_CIDR` nesta execução |

O fluxo é: verificações de segurança → `terraform plan`/`apply` → Ansible via bastion → verificação externa.

**Procedimento de instalação da aplicação (R12):** é executado pelo Ansible, nesta ordem:
1. Pacotes e atualizações (`os_updates`)
2. SSH endurecido (`ssh_hardening`)
3. Docker (`docker`)
4. MongoDB no disco de dados, com senhas do SSM (`kubeshop_db`)
5. Backup + cron (`backup`)
6. Certificado TLS, proxy, frontend e API (`kubeshop_app`)
7. Health checks e smoke test (`verify`)

Para reproduzir manualmente, rode o mesmo playbook a partir de uma máquina com Ansible, com as credenciais AWS e a chave do grupo carregadas:

```bash
bash ansible/inventory/gerar-inventario.sh tf-outputs.json us-east-2
```

```bash
cd ansible && ansible-playbook playbook.yml -e docker_tag=1.0.0
```

Os comandos de acesso SSH aparecem no output `ssh_commands`.

## 5. Operação

**Actions → ops**: `health`, `logs`, `restart`, `backup`, `restore-test` e `reset-demo` (este exige confirmação). Guia completo: [`docs/manual-operacao.md`](docs/manual-operacao.md).

## 6. Destruir o ambiente (destroy)

**Actions → infra-destroy**, com `confirm = DESTRUIR-dev`. Remove todos os recursos do ambiente, inclusive o bucket de backup. Depois confere na AWS se sobrou algo e gera o artefato `inventario-pos-destroy.md`. Executar em até 24 h após a apresentação e publicar a evidência em `docs/evidencias/`.

## Verificações de segurança locais

```bash
terraform -chdir=infra fmt -check && terraform -chdir=infra validate
```

```bash
trivy config infra/
```

```bash
checkov -d infra --framework terraform
```

```bash
gitleaks git .
```

## Executar a aplicação localmente (desenvolvimento)

Requer Docker com Compose v2.20+.

```bash
sh scripts/setup.sh
```

No Windows, use `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup.ps1`. O script gera `.env` e as senhas em `.secrets/`; ajuste `BIND_ADDRESS=127.0.0.1` no `.env` e suba os serviços:

```bash
docker compose up -d --build --wait --wait-timeout 240
```

Acesse http://localhost:8080. Teste funcional:

```bash
docker compose exec -T api node /app/scripts/smoke.mjs
```

Para encerrar sem apagar os pedidos:

```bash
docker compose down
```

Validação original da aplicação: [`VALIDATION.md`](VALIDATION.md).

## Documentação

| Documento | Conteúdo |
|---|---|
| [`docs/demanda.md`](docs/demanda.md) | Análise do escopo e requisitos → infraestrutura (PM-04) |
| [`docs/seguranca.md`](docs/seguranca.md) | S1–S8, achados dos scans, análise de ameaças |
| [`docs/alta-disponibilidade.md`](docs/alta-disponibilidade.md) | Proposta H1–H7 e custo |
| [`docs/backup.md`](docs/backup.md) | B1–B7, GFS por 12 meses, política mínima |
| [`docs/custos/`](docs/custos/) | Estimativas, período do trabalho, custo real |
| [`docs/adr/`](docs/adr/) | Decisões de arquitetura |
| [`docs/errata.md`](docs/errata.md) | Divergências em relação à Entrega 1 |
| [`docs/roteiro-de-testes.md`](docs/roteiro-de-testes.md) | Passo a passo para testar tudo, do bootstrap ao destroy |
| [`docs/validacao.md`](docs/validacao.md) | Critérios de aceite, cenários e roteiro D1–D7 |
| [`IA.md`](IA.md) | Uso de IA |
