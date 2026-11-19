# Roteiro de testes — do zero ao destroy

> Siga na ordem. Cada etapa tem **o que fazer**, **o que deve acontecer** e **o que guardar** (evidência para `docs/validacao.md` / `docs/evidencias/`).
> Tempo total: cerca de **3 horas**. Custo: cerca de **US$ 0,30** (o NAT é cobrado por hora). Se precisar parar no meio, rode o `infra-destroy` (etapa 10) e recrie depois.

Notação:
- `<BASTION>`, `<APP>`, `<NAT>`, `<IP_PRIV_APP>`, `<IP_PRIV_DB>` e `<BUCKET>` vêm do resumo da execução do `infra-deploy` (seção **Outputs**) ou do output `ssh_commands`.
- Os comandos `bash` rodam no Git Bash. Para o PowerShell há uma alternativa indicada.

---

## Etapa 0 — Pré-requisitos (uma vez)

| # | O que fazer | Esperado | Evidência |
|---|---|---|---|
| 0.1 | Ativar **MFA** no usuário IAM e na conta root | Console IAM mostra o MFA atribuído | `s8-mfa.png` |
| 0.2 | Billing → **Cost allocation tags** → ativar `projeto` | Status "Active" | — |
| 0.3 | Conferir a AWS CLI: `aws sts get-caller-identity` | Mostra o seu usuário IAM | — |
| 0.4 | Gerar a chave SSH: `ssh-keygen -t ed25519 -C kubeshop-devs-em-crise -f ~/.ssh/kubeshop-grupo` | Arquivos `kubeshop-grupo` e `kubeshop-grupo.pub` | — |

## Etapa 1 — Bootstrap (local)

```bash
cd bootstrap
cp bootstrap.tfvars.example bootstrap.tfvars   # edite o e-mail do alerta
terraform init
terraform apply -var-file=bootstrap.tfvars
```

| Esperado | Evidência |
|---|---|
| `Apply complete!` com os outputs `tf_state_bucket`, `aws_access_key_id` e `aws_secret_access_key` (sensível) | `orcamento.png` (Billing → Budgets, com o alerta `kubeshop-orcamento-mensal`) |
| O e-mail do alerta pode pedir confirmação: confirme | — |

## Etapa 2 — GitHub e primeira execução automática

1. Em **Settings → Secrets and variables → Actions**, cadastrar as Variables `TF_STATE_BUCKET`, `AWS_REGION=us-east-2`, `SSH_ALLOWED_CIDR` (seu IP + `/32`) e os Secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `SSH_PRIVATE_KEY` e `SSH_PUBLIC_KEY`.
2. Em **Settings → Actions → General → Workflow permissions**, marcar **Read and write**.
3. Commit e push na `main`.

| Esperado (aba Actions) | Se falhar |
|---|---|
| **`security`** verde: Gitleaks, Terraform, Trivy/Checkov, ansible-lint | Abra o job; ele mostra o achado ou o arquivo |
| **`app-ci`** verde: testes, build e Trivy das imagens (ainda sem publicar) | Testes: rode `npm test` localmente |

Evidência: artefatos `relatorios-iac` e `relatorio-gitleaks` → `docs/evidencias/relatorios-iac/`.

## Etapa 3 — Publicar as versões da aplicação

Sem tags Git: a cada push na `main` o `app-ci` publica as imagens com a versão do `package.json`.

1. **Versão 1.0.0:** já é a versão atual do `package.json`. Basta o push na `main` (ou Actions → app-ci → Run workflow).
2. **Versão 1.0.1** (para o cenário 2 e o rollback), depois que a 1.0.0 estiver publicada:

```bash
sed -i '0,/"version": "1.0.0"/s//"version": "1.0.1"/' package.json
```

```bash
sed -i '0,/"version": "1.0.0"/s//"version": "1.0.1"/; 0,/"version": "1.0.0"/s//"version": "1.0.1"/' package-lock.json
```

```bash
git commit -am "Versão 1.0.1" && git push origin main
```

| Esperado | Verificação |
|---|---|
| Uma execução do `app-ci` por versão, publicando `kubeshop-api` e `kubeshop-frontend` (`1.0.0` e depois `1.0.1`) | Perfil do GitHub → **Packages** |
| Pacotes **públicos** (Package settings → Change visibility) | `docker pull ghcr.io/gabrielatakeda/kubeshop-api:1.0.0` funciona sem login |

## Etapa 4 — Cenário 1: criação inicial

**Actions → infra-deploy → Run workflow** com `action = plan` e o resto padrão (`dev`, `t3.micro`, `docker_tag = 1.0.0`).

| Esperado | |
|---|---|
| Resumo "Terraform plan" com dezenas de `will be created` e `Plan: N to add, 0 to change, 0 to destroy` | Confira se aparecem bastion, app, db, NAT, bucket e KMS |

Depois rode de novo com **`action = apply`** (10–15 min).

| Job | Esperado |
|---|---|
| Terraform | `Apply complete! Resources: N added` + bloco **Outputs** |
| Ansible | Plays: bastion → app/banco → Docker → MongoDB e backup → Aplicação; `PLAY RECAP` com `failed=0` |
| Verificação externa | `301`, `{"ready":true,"database":true}`, `Versão: 1.0.0`, "SSH direto na VM da aplicação: bloqueado" |

Evidência: link da execução + artefatos `terraform-dev` e `ansible-dev` → `cenario-1-*`.

## Etapa 5 — Testes manuais (D2, D3, D4, ACE-03/04)

### 5.1 Aplicação (D2 / ACE-04)
1. No **celular** (outra rede), abra `https://<APP>` e aceite o certificado.
2. Adicione um produto, confirme o pedido, abra **Meus pedidos** e **recarregue** a página: o pedido continua lá.

```bash
curl -I http://<APP>                       # 301 Moved Permanently → https://
curl -sk https://<APP>/api/health/ready    # {"ready":true,"database":true}
curl -sk https://<APP>/api/info            # {"version":"1.0.0",...}
curl -vk https://<APP> 2>&1 | grep -E "SSL connection|subject"   # TLSv1.3 / CN=<APP>
```

### 5.2 Acesso administrativo (D3 / S1)
```bash
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/kubeshop-grupo
ssh ubuntu@<BASTION>                                   # entra
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password ubuntu@<BASTION>
#   → Permission denied (publickey).
ssh -J ubuntu@<BASTION> ubuntu@<IP_PRIV_APP>           # entra na app
ssh -J ubuntu@<BASTION> ubuntu@<IP_PRIV_DB>            # entra no banco
```

### 5.3 Isolamento e NAT (D4 / ACE-03 / S5)
Dentro da **VM do banco** (`ssh -J …`):
```bash
curl -s https://ifconfig.me          # igual ao output nat_public_ip
ip -brief addr                       # só IP privado 10.20.11.x
sudo docker ps                       # kubeshop-mongodb (healthy)
aws s3 ls s3://<BUCKET>/             # AccessDenied → a VM não lista nem lê backups (S5)
```

Do **seu computador**:
```bash
ssh -o ConnectTimeout=8 ubuntu@<APP>      # timeout → app não aceita SSH da internet
nc -zv -w 5 <APP> 27017                   # falha → MongoDB não exposto
```
No PowerShell: `Test-NetConnection <APP> -Port 22` e `-Port 27017` devem mostrar `TcpTestSucceeded : False`.

Evidência: capturas `d3-ssh.png` e `d4-nat.png`.

## Etapa 6 — Rotinas de operação (ACE-07/08, D6)

Rode em **Actions → ops**, uma de cada vez:

| `operation` | Esperado | Evidência |
|---|---|---|
| `health` | 4 contêineres `(healthy)`, readiness `true`, versão `1.0.0` | Link da execução |
| `logs` (`service = all`) | Artefato com `kubeshop-app-kubeshop-api.log`, etc. **Abra e confira que não há senha nenhuma** | Artefato |
| `backup` | Resumo: objeto em `diario/`, `aws:kms`, `expira:` com data em até 2 dias | `backup-objeto.json`, `backup-lifecycle.json` |
| `restore-test` | Resumo com `"colecoes":["orders"]` e a quantidade de pedidos feitos na etapa 5 | `restore-resultado.json` |
| `restart` (`service = api`) | API reiniciada e saudável; o pedido continua no site (**ACE-05**, primeira parte) | Link |

## Etapa 7 — Cenário 2: atualização

**infra-deploy** com `action = apply` e:
`app_instance_type = t3.small`, `docker_tag = 1.0.1`, `update_os = true`, `extra_packages = htop`.

| Onde | Esperado |
|---|---|
| Plano | `aws_instance.app will be updated in-place` com `~ instance_type = "t3.micro" -> "t3.small"` (**sem** `-/+`, a VM não é recriada) |
| Ansible | `changed` em "Aplica atualizações do SO", "Instala pacotes adicionais" e "Sobe/atualiza proxy, frontend e API" |
| Verificação | `Versão em execução: 1.0.1` |
| Navegador | O pedido da etapa 5 **continua lá** (ACE-05, segunda parte) |

## Etapa 8 — Cenário 3: reexecução sem alterações (+ D1)

Rode **exatamente os mesmos parâmetros** da etapa 7.

| Esperado | Se não for |
|---|---|
| Terraform: **`No changes. Your infrastructure matches the configuration.`** | Veja qual recurso mudou no plano (causa comum: CIDR diferente em `ssh_allowed_cidr`) |
| Ansible: `PLAY RECAP` com **`changed=0`** em todos os hosts | Anote a task que mudou e reporte para ajuste |

Para o **D1** na apresentação: `infra-deploy` com `action = plan` e os parâmetros em uso → `No changes`; os outputs aparecem no resumo.

## Etapa 9 — Rollback e preparação da demonstração

| Ação | Esperado |
|---|---|
| infra-deploy com `docker_tag = 1.0.0` (e os demais parâmetros iguais) | `Versão em execução: 1.0.0`; pedidos preservados (**ACE-06**) |
| ops `reset-demo` com `confirm = LIMPAR-dev` | Backup feito antes, `{"removidos": N, "restantes": 0}`; "Meus pedidos" vazio |
| ops `reset-demo` com confirmação errada | Falha imediata: "Digite confirm = LIMPAR-dev" (proteção funcionando) |

## Etapa 10 — Destroy e recriação

**Actions → infra-destroy** com `confirm = DESTRUIR-dev`.

| Esperado | Evidência |
|---|---|
| `Destroy complete!` e o inventário com todas as linhas **OK**; a KMS aparece como `PendingDeletion` | `inventario-pos-destroy.md` |
| Console EC2 (us-east-2): sem instâncias, NAT `Deleted`, nenhum Elastic IP, nenhum volume | Captura |

Depois, para validar a reprodutibilidade, rode o **Cenário 1 de novo** (`apply`, `1.0.0`): tudo deve subir do zero sem ajuste manual. Destrua de novo se não for apresentar em seguida.

---

## Checklist final

- [ ] 0–3 configuração e publicação
- [ ] 4 Cenário 1
- [ ] 5 testes manuais (D2, D3, D4)
- [ ] 6 ops: health, logs, backup, restore-test, restart
- [ ] 7 Cenário 2 · 8 Cenário 3 / D1
- [ ] 9 rollback e reset-demo
- [ ] 10 destroy (inventário OK) e recriação
- [ ] `docs/validacao.md` preenchido com os links das execuções
- [ ] Vídeo de contingência gravado durante as etapas 4–6

Se algo falhar, veja "Diagnóstico de falhas comuns" em `docs/manual-operacao.md` e guarde o log da execução: falhas corrigidas também entram na errata.
