# Relatório de validação

> Preencher durante os testes reais, seguindo `docs/roteiro-de-testes.md`. Cada linha precisa de uma **evidência verificável**: link da execução da pipeline (Actions → run) e/ou arquivo em `docs/evidencias/`. A página inicial acessível, sozinha, não comprova a integração.

## Critérios de aceite do escopo KubeShop

| Critério | Como demonstrar | Execução / evidência | Resultado |
|---|---|---|---|
| ACE-01 Reprodução | `infra-deploy` `apply` em ambiente vazio | run: | ☐ |
| ACE-02 Duas VMs | Output do Terraform + console EC2: `kubeshop-app`, `kubeshop-db` (+ `kubeshop-bastion`) | | ☐ |
| ACE-03 Isolamento | `readiness.database = true`; de fora: `nc -zv <ip-app> 27017` falha; VM-DB sem IP público; SG-DB só aceita a app | | ☐ |
| ACE-04 Aplicação | Em outro dispositivo: loja via HTTPS, catálogo, pedido criado, recarregar e ver o pedido em "Meus pedidos" | | ☐ |
| ACE-05 Persistência | Pedido preservado após `ops restart` **e** após `infra-deploy` com `app_instance_type` t3.micro → t3.small | | ☐ |
| ACE-06 CI/CD | `app-ci` publicando `1.0.0` e `1.0.1`; `infra-deploy` com `docker_tag=1.0.1` (atualização) e `1.0.0` (rollback) | | ☐ |
| ACE-07 Recuperação | `ops backup` + `ops restore-test` (contagem de pedidos restaurados) | | ☐ |
| ACE-08 Administração | Logs das pipelines; `ops health/logs/restart`; manual; Gitleaks limpo; nenhum segredo nos logs | | ☐ |
| ACE-09 Custos | `docs/custos/estimativas.md` | | ☐ |
| ACE-10 Transferência | `docs/manual-operacao.md` + demonstração conduzida pelos integrantes | | ☐ |

## Cenários da PM-04

| Cenário | Parâmetros | O que mostrar | Execução | Resultado |
|---|---|---|---|---|
| 1 · Criação inicial | `apply`, `dev`, `t3.micro`, `docker_tag=1.0.0` | Plano criando os recursos; Ansible instalando pacotes, Docker e contêineres; verificação externa verde | | ☐ |
| 2 · Atualização | `app_instance_type=t3.small`, `docker_tag=1.0.1`, `update_os=true`, `extra_packages=htop` | Plano com `~ instance_type` (sem `-/+`); Ansible com `changed` no Docker e pacotes; `/api/info = 1.0.1`; pedido antigo ainda presente | | ☐ |
| 3 · Reexecução | Mesmos parâmetros do cenário 2 | `No changes.` no Terraform e `changed=0` no PLAY RECAP | | ☐ |

## Roteiro da Entrega 2

| Demo | O que mostrar | Responsável | Evidência |
|---|---|---|---|
| D1 | `terraform plan` sem mudanças pendentes + `terraform output` | | |
| D2 | `https://<ip-app>`, pedido fictício | | |
| D3 | `ssh` no bastion, `ssh -J` para app e banco, recusa de senha | | |
| D4 | Na VM-DB, `curl -s https://ifconfig.me` = `nat_public_ip`; VM-DB sem IP público; SSH só do CIDR | | |
| D5 | SSM (segredos fora do código); relatório com a CMK (corrigido) e saída 80/443 (aceito) | | |
| D6 | `ops backup`: mecanismo, retenção (lifecycle), `aws:kms`, cópia existente; custo GFS | | |
| D7 | `arquitetura-ha.png` + análise de custo | | |
