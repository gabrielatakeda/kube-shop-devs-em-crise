# Plano de backup — KubeShop (Entrega 2, Parte D)

> **Alta disponibilidade não substitui backup.** Se alguém apagar a coleção `orders`, a réplica do banco apaga junto. O Terraform recria a infraestrutura, mas não recria os pedidos.

Este documento tem duas políticas:

| Política | Papel | Situação |
|---|---|---|
| **Conservadora (GFS)** | O que recomendamos para operar o KubeShop de verdade | Apenas planejada, com custo de 12 meses (B3, B7) |
| **Mínima** | Exercitar os mecanismos com custo próximo de zero | **Configurada por Terraform e Ansible** e demonstrada (B6) |

---

## B1. Inventário

| Ativo | Precisa de backup? | Mecanismo / justificativa |
|---|---|---|
| **Banco `kubeshop` (coleção `orders`)** | **Sim** | Único dado que não se recria: o histórico de pedidos. Dump lógico (`mongodump`) |
| Usuários do MongoDB (`kubeshop`, `backup`) | Não | Recriados pelo `init.js` e pelo Ansible a partir das senhas do SSM |
| Senhas (SSM Parameter Store) | Não, separadamente | Geradas pelo Terraform e guardadas no state (bucket versionado). Recriar o ambiente gera senhas novas; o dump não depende delas |
| **Terraform state** | **Sim** | Bucket próprio com **versionamento** (versões antigas mantidas 30 dias) e criptografia. Sem ele, o Terraform perde o controle dos recursos |
| Catálogo de produtos | Não | Definido no código da API (`catalog.js`), não está no banco |
| Código, Terraform, Ansible, pipelines | Não | No Git (GitHub); o histórico é o backup |
| Imagens Docker da aplicação | Não | Versionadas no GHCR e reconstruíveis pelo `app-ci.yml` a partir da tag Git |
| Discos das VMs (sistema) | Não | Reproduzíveis: Terraform + Ansible recriam tudo em cerca de 10 min |
| Disco de dados do MongoDB (EBS) | Não, como disco | O conteúdo já é coberto pelo dump lógico, que é consistente. O snapshot seria só *crash-consistent* |
| Arquivos enviados por usuários | Não se aplica | O KubeShop não tem upload |
| Logs | Não | Diagnóstico de curto prazo; rotacionados (3 × 10 MB por contêiner) |

## B2. RPO e RTO

| Meta | Valor | Justificativa |
|---|---|---|
| **RPO** (perda máxima de dados) | **24 horas** | Pedidos fictícios de um marketplace em fase de lançamento, com baixo volume. Perder até um dia de pedidos é tolerável e mantém o custo do backup diário próximo de zero. Para pedidos reais seria preciso reduzir (dump de hora em hora ou *point-in-time* com oplog) |
| **RTO** (tempo para voltar) | **1 hora** | Recriar a infraestrutura pela pipeline leva cerca de 10–15 min (com o NAT); restaurar um dump de MB leva segundos; sobra margem para diagnóstico. Na proposta de HA, uma falha de instância não aciona restauração |

## B3. Política conservadora (GFS)

Mecanismo: **dump lógico** (`mongodump --archive --gzip`, consistente do ponto de vista do banco) gravado em S3, **um prefixo por geração**, com **regra de ciclo de vida por prefixo**.

| Geração | Frequência | Promoção | Retenção | Classe de armazenamento |
|---|---|---|---|---|
| **Son** (`diario/`) | Diária, 03:15 UTC (00:15 em Brasília, menor movimento) | — | **7 dias** | S3 Standard (restauração imediata e frequente) |
| **Father** (`semanal/`) | Semanal | A cópia **de domingo** é copiada (`s3 cp` dentro do bucket) para `semanal/` | **5 semanas** | S3 Standard-IA (mínimo de 30 dias cobrados, compatível com 35 dias de retenção) |
| **Grandfather** (`mensal/`) | Mensal | A cópia do **último dia do mês** é copiada para `mensal/` | **12 meses** | S3 Glacier Instant Retrieval (mínimo de 90 dias, compatível; leitura em milissegundos) |

Complementos da política conservadora:
- **Replicação entre regiões** (`us-east-2` → `us-east-1`) dos três prefixos, contra perda de região ou exclusão acidental do bucket.
- **Versionamento + S3 Object Lock (modo *governance*)** nos prefixos `semanal/` e `mensal/`, contra exclusão maliciosa.
- **Restore-test semanal** automático (`ops.yml` → `restore-test`) com alerta em caso de falha.
- Um disco cuja captura faça sentido não é necessário: o dump lógico evita o problema de consistência do snapshot (*crash-consistent*).

## B4. Armazenamento

- **Fora da instância:** as cópias vão direto para o S3 em streaming (`mongodump | aws s3 cp -`); nada fica no disco da VM.
- **Outra zona:** o S3 Standard guarda dados em pelo menos 3 AZs da região. Na política conservadora também vai para **outra região** (replicação).
- **Criptografia (S6):** SSE-KMS com a CMK do projeto (`alias/kubeshop-<env>`), bucket key ligada, TLS obrigatório (a bucket policy nega `aws:SecureTransport = false`).
- **Acesso restrito (S5):** a VM do banco só tem `s3:PutObject` em `diario/*`. Ela **não lê, não lista e não apaga**. A leitura (restore-test) é feita pelo usuário IAM da pipeline, fora das VMs. Acesso público bloqueado (`public access block` + `BucketOwnerEnforced`).

## B5. Responsabilidade compartilhada

| Ativo | A AWS garante | Responsabilidade do grupo |
|---|---|---|
| Objetos no S3 | Durabilidade de 11 noves, réplicas em várias AZs, criptografia com a chave escolhida | Gerar as cópias, definir retenção, testar a restauração, proteger o acesso (IAM, bucket policy), não perder a CMK |
| Disco EBS de dados | Replicação dentro da AZ, criptografia | Backup lógico do conteúdo; o EBS **não** protege contra exclusão lógica nem contra perda da AZ |
| MongoDB em VM (não gerenciado) | Nada além da VM | Instalação, atualização, usuários, backup, restauração |
| Terraform state | Durabilidade do S3 | Versionamento, lock, criptografia, não expor o state |
| Chave KMS | Disponibilidade e rotação automática | Não agendar exclusão por engano; sem a chave, as cópias ficam ilegíveis |

## B6. Política mínima configurada

| Requisito (seção 6.3) | Implementação | Onde |
|---|---|---|
| Mecanismo | **Opção A:** dump lógico do MongoDB em object storage | `ansible/roles/backup/` |
| Geração | Só **Son**, prefixo `diario/` | `infra/backup.tf` |
| Configuração por código | Bucket, criptografia, bloqueio público, bucket policy e lifecycle no **Terraform**; script e cron no **Ansible** | `infra/backup.tf`, `ansible/roles/backup/` |
| Retenção | Expiração em **`backup_retention_days = 2`** (a validação do Terraform recusa valores acima de 2) | `infra/variables.tf` |
| Criptografia | SSE-KMS com a CMK; a pipeline confere `ServerSideEncryption = aws:kms` em cada backup | `infra/backup.tf`, `ops.yml` |
| Identidade | Instance profile só com `PutObject` em `diario/*` (S5) | `infra/iam.tf` |
| Agenda | Cron diário 03:15 UTC (`flock` evita execuções paralelas); execução sob demanda: `ops.yml → backup` | `ansible/roles/backup/` |
| Usuário do banco | `backup` com o papel nativo `backup` (somente o necessário para o dump) | `ansible/roles/kubeshop_db/files/ensure-backup-user.js` |
| Cópia existente | `ops.yml → backup` mostra objeto, tamanho, criptografia e data de expiração; `ops.yml → restore-test` restaura num MongoDB descartável | Artefatos da pipeline → `docs/evidencias/` |

**Expiração assíncrona:** a AWS processa as regras de ciclo de vida uma vez por dia (por volta de 00:00 UTC) e a remoção pode atrasar. O cabeçalho `x-amz-expiration` do objeto mostra a data prevista, e a cobrança para na data de expiração, mesmo que a remoção física aconteça depois (documentação do S3 Lifecycle).

### O que a política mínima **não** protege (em comparação com a GFS)
- Um erro descoberto **depois de 2 dias** (por exemplo, pedidos apagados na sexta e percebidos na segunda) não pode ser desfeito.
- Não há cópia semanal nem mensal: não dá para voltar ao estado do mês anterior.
- Não há cópia em **outra região**: se o bucket ou a região forem perdidos, os backups também se perdem.
- Não há **Object Lock**: uma credencial administrativa comprometida pode apagar o bucket.
- O destroy (`backup_force_destroy = true`) **apaga as cópias** junto com o ambiente.

## B7. Custos

### Política mínima no período do trabalho
Dumps de poucos KB a poucos MB, no máximo 2 cópias retidas → armazenamento e requisições na ordem de **US$ 0,00**. O custo do KMS (US$ 1/mês proporcional) é compartilhado com os discos e já está em `docs/custos/estimativas.md`.

### Política conservadora GFS em 12 meses

**Premissas:** banco com 100 MB no mês 1, crescendo 20 MB/mês; dump comprimido com 30% do tamanho do banco; o tamanho de todas as cópias retidas é aproximado pelo dump do mês (estimativa conservadora); 30 dumps diários + 4 cópias semanais + 1 mensal gravados por mês; replicação idêntica em us-east-1. Preços unitários em `docs/custos/estimativas.md` (confirmar na calculadora). Planilha: `docs/custos/gfs-12-meses.csv`.

| Mês | Banco (MB) | Dump (MB) | Cópias S+F+G | Volume em backup (GB, por região) | Armazenamento | Requisições | Replicação (2ª região + transferência) | **Total do mês** |
|---|---|---|---|---|---|---|---|---|
| 1 | 100 | 30 | 7+4+1 = 12 | 0.35 | $0.006 | $0.000 | $0.017 | **$0.023** |
| 2 | 120 | 36 | 7+5+2 = 14 | 0.49 | $0.008 | $0.000 | $0.021 | **$0.029** |
| 3 | 140 | 42 | 7+5+3 = 15 | 0.62 | $0.010 | $0.000 | $0.024 | **$0.034** |
| 4 | 160 | 48 | 7+5+4 = 16 | 0.75 | $0.011 | $0.000 | $0.028 | **$0.039** |
| 5 | 180 | 54 | 7+5+5 = 17 | 0.90 | $0.013 | $0.000 | $0.032 | **$0.045** |
| 6 | 200 | 60 | 7+5+6 = 18 | 1.05 | $0.015 | $0.000 | $0.035 | **$0.050** |
| 7 | 220 | 66 | 7+5+7 = 19 | 1.22 | $0.016 | $0.000 | $0.039 | **$0.055** |
| 8 | 240 | 72 | 7+5+8 = 20 | 1.41 | $0.018 | $0.000 | $0.043 | **$0.061** |
| 9 | 260 | 78 | 7+5+9 = 21 | 1.60 | $0.020 | $0.000 | $0.047 | **$0.067** |
| 10 | 280 | 84 | 7+5+10 = 22 | 1.80 | $0.022 | $0.000 | $0.051 | **$0.072** |
| 11 | 300 | 90 | 7+5+11 = 23 | 2.02 | $0.024 | $0.000 | $0.054 | **$0.078** |
| 12 | 320 | 96 | 7+5+12 = 24 | 2.25 | $0.025 | $0.000 | $0.058 | **$0.084** |
| **Ano** | | | | | | | | **$0.64** |

O custo cresce todo mês porque a geração Grandfather acumula uma cópia por mês até chegar a 12, e o tamanho do banco aumenta.

**Itens considerados além do armazenamento:** PUTs por classe (desprezíveis) e transferência entre regiões da replicação. As classes IA e Glacier IR cobram duração mínima (30 e 90 dias) e tamanho mínimo de objeto (128 KB). As retenções escolhidas (35 dias e 12 meses) respeitam os mínimos, e os dumps passam de 128 KB. Também cobram **leitura** (Standard-IA US$ 0,01/GB e Glacier IR US$ 0,03/GB), que só ocorre numa restauração.

**Qual parâmetro mais influencia o custo anual?** A **frequência da geração Son combinada com a replicação entre regiões**. No mês 12, a transferência para a segunda região dos 35 objetos gravados (30 diários + 4 semanais + 1 mensal) custa cerca de US$ 0,033 (US$ 0,01/GB de Ohio para N. Virginia). Isso é mais que todo o armazenamento local: Son US$ 0,015, Father US$ 0,006 e Grandfather US$ 0,005.
- **Reduzir a frequência para semanal** cortaria cerca de 75% desse custo, mas o RPO iria de 24 h para até 7 dias.
- **Desligar a replicação** cortaria cerca de 70% do total, mas sem proteção contra a perda da região ou a exclusão do bucket.

Na escala do KubeShop, todo o backup custa cerca de **US$ 0,64 por ano**. O que domina o custo da arquitetura é o NAT Gateway, não o backup.
