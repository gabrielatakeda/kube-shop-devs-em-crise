# Estimativas de custo — KubeShop na AWS

> **Premissas gerais:** região **us-east-2 (Ohio)**, moeda USD, mês de **730 h**, preços sob demanda.
> **Fontes (18/11/2026):** preços unitários conferidos na **AWS Price List API** (`aws pricing get-products`, a mesma base da calculadora) e arquitetura implantada montada na **AWS Pricing Calculator** (https://calculator.aws). Créditos e faixas gratuitas aparecem separados e **não** foram descontados.

## 0. Estimativa na AWS Pricing Calculator (arquitetura implantada)

> **Atualizar (18/11):** o apply mostrou que a conta está no plano Free Tier e recusa t3.nano. O bastion passou a t3.micro (+US$ 3,79/mês). A estimativa salva abaixo ainda usa t3.nano: editar a linha do bastion na calculadora e gerar um novo link e PDF.

| Serviço (calculadora) | Configuração | Mensal |
|---|---|---|
| Amazon EC2 | Bastion t3.nano, On-Demand 100%, EBS gp3 8 GB | US$ 4,44 |
| Amazon EC2 | VM aplicação t3.micro, On-Demand 100%, EBS gp3 20 GB | US$ 9,19 |
| Amazon EC2 | VM MongoDB t3.micro, On-Demand 100%, EBS gp3 30 GB (20 sistema + 10 dados) | US$ 9,99 |
| Amazon VPC | 3 IPv4 públicos em uso + 1 NAT Gateway em 1 AZ, 5 GB processados* | US$ 44,03 |
| AWS KMS | 1 CMK + 10.000 requisições simétricas | US$ 1,03 |
| **Total** | | **US$ 68,68/mês · US$ 824,16 em 12 meses** |

\* A calculadora exige preencher o bloco "Regional NAT Gateway" quando o NAT é selecionado. O NAT foi lançado como **1 NAT regional ativo em 1 AZ** (mesmo preço: US$ 0,045/h por AZ + US$ 0,045/GB) e "Number of NAT Gateways" = 0, para não contar em dobro. S3 (backup mínimo e state) ficou de fora por ser ≈ US$ 0,00.

> **Estimativa oficial "KubeShop - arquitetura implantada (us-east-2)"**, gerada em 18/11/2026 (o link expira em 1 ano):
> - Link: https://calculator.aws/#/estimate?id=4b640792ac51c5798c2c887331dab986b2c6f771
> - PDF: [`calculadora-arquitetura-implantada.pdf`](calculadora-arquitetura-implantada.pdf)

## 1. Preços unitários usados

| Item | Preço oficial (Price List API, us-east-2) |
|---|---|
| EC2 t3.nano / t3.micro / t3.small (Linux, sob demanda) | US$ 0,0052 / 0,0104 / 0,0208 por hora |
| NAT Gateway | US$ 0,045 por hora + US$ 0,045 por GB processado |
| Endereço IPv4 público (EIP, inclusive o do NAT e os do ALB) | US$ 0,005 por hora cada |
| EBS gp3 | US$ 0,08 por GB-mês (3.000 IOPS e 125 MB/s inclusos) |
| KMS: chave gerenciada pelo cliente | US$ 1,00 por mês (proporcional por hora) + requisições (desprezíveis com bucket key) |
| S3 Standard / Standard-IA / Glacier Instant Retrieval | US$ 0,023 / 0,0125 / 0,004 por GB-mês |
| S3 PUT (Standard / IA / Glacier IR) | US$ 0,005 / 0,01 / 0,02 por 1.000 |
| Transferência entre regiões (replicação S3, Ohio → N. Virginia) | US$ 0,01 por GB |
| Application Load Balancer | US$ 0,0225 por hora + US$ 0,008 por LCU-hora |
| SSM Parameter Store (parâmetros padrão) | sem custo |
| Transferência de saída para a internet | 100 GB/mês gratuitos na conta (faixa gratuita, separada) |

## 2. Arquitetura implantada (operação contínua)

| Recurso | Quantidade | Custo mensal |
|---|---|---|
| Bastion t3.micro (t3.nano não é elegível no plano Free Tier da conta) | 1 | US$ 7,59 |
| VM da aplicação t3.micro | 1 | US$ 7,59 |
| VM do MongoDB t3.micro | 1 | US$ 7,59 |
| NAT Gateway (hora) | 1 | US$ 32,85 |
| NAT: dados processados (premissa: 5 GB/mês de atualizações e imagens) | 5 GB | US$ 0,23 |
| IPv4 públicos (bastion, aplicação, NAT) | 3 | US$ 10,95 |
| EBS gp3 (8 bastion + 20 app + 20 banco + 10 dados) | 58 GB | US$ 4,64 |
| KMS CMK | 1 | US$ 1,00 |
| S3: backup mínimo + state | < 0,1 GB | ≈ US$ 0,00 |
| **Total mensal** | | **≈ US$ 72,43** (calculadora com bastion t3.nano: US$ 68,68; com t3.micro: ≈ US$ 72,47) |

**O que mais pesa:** o NAT Gateway (48% do total) e os IPv4 públicos (16%). O bastion dedicado acrescenta cerca de US$ 7,45 (VM + IP), mais US$ 0,64 de disco.

## 3. Custo do período do trabalho

Custo por hora com tudo ligado: **≈ US$ 0,094**. O ambiente fica ligado só durante testes e apresentações (destroy depois de cada sessão, recriação pela pipeline).

| Período | Horas (premissa) | Custo |
|---|---|---|
| Testes da Entrega 2 (19–22/11) | 20 h | US$ 1,87 |
| Apresentação da Entrega 2 (23/11) | 6 h | US$ 0,56 |
| Testes e apresentação da PM-04 (dez/2026) | 14 h | US$ 1,31 |
| **Total previsto** | **40 h** | **≈ US$ 3,75** |

Cobranças que podem continuar depois do destroy: chave KMS em exclusão pendente (7 dias) e bucket do Terraform state (KB, ≈ US$ 0,00). O custo **real** do painel de faturamento entra na seção 6 depois da apresentação.

## 4. Proposta de alta disponibilidade × implantada

Detalhes da proposta em `docs/alta-disponibilidade.md`.

| Recurso (HA, 2 AZs) | Custo mensal |
|---|---|
| ALB (hora + 1 LCU médio) | US$ 22,27 |
| 2 VMs da aplicação t3.micro (Auto Scaling, mínimo 2) | US$ 15,18 |
| 3 nós MongoDB t3.micro (replica set em 3 AZs) | US$ 22,78 |
| 2 NAT Gateways (um por AZ) + 10 GB processados | US$ 66,15 |
| IPv4 públicos: 2 NAT + 2 do ALB (bastion substituído por Session Manager; sem EIP na app) | US$ 14,60 |
| EBS gp3 (2 × 20 app + 3 × 30 banco) | US$ 10,40 |
| KMS CMK + VPC flow logs (estimado) | US$ 2,00 |
| **Total mensal da proposta** | **≈ US$ 153,38** |

| Versão | Custo mensal estimado | Variação |
|---|---|---|
| Arquitetura implantada | ≈ US$ 68,64 | — |
| Proposta de alta disponibilidade | ≈ US$ 153,38 | **+123%** |

> Se o cenário A da Entrega 1 tiver outro valor, substitua a linha "Arquitetura implantada" por ele e recalcule a variação.

**O que mais contribui para o aumento:** o segundo NAT Gateway (+US$ 33), o ALB (+US$ 22) e os dois nós extras do MongoDB (+US$ 15).

## 5. Backup

- **Política mínima configurada** (dumps de KB, expiração em 2 dias): ≈ **US$ 0,00** no período do trabalho.
- **Política conservadora GFS (12 meses):** tabela em `docs/backup.md`, seção B7, e dados brutos em `gfs-12-meses.csv` (≈ **US$ 0,64 no ano** com replicação entre regiões).

## 6. Custo real (preencher após a apresentação)

| Período | Painel de faturamento (Cost Explorer) | Estimado | Diferença |
|---|---|---|---|
| 18/11 a 24/11/2026 | US$ ____ | US$ 2,43 | |
| Comparação com o cenário B da Entrega 1 | US$ ____ | | |

Anexar captura do Cost Explorer filtrado pela tag `projeto = kubeshop` em `docs/evidencias/`. Para o filtro funcionar, ative `projeto` como **cost allocation tag** em Billing → Cost allocation tags **antes** do primeiro apply: a AWS só agrupa custos a partir da ativação, e ela leva até 24 h para valer.
