# Alta disponibilidade — proposta (Entrega 2, Parte C)

> **Somente projetada, não implantada.** Diagramas: `docs/diagramas/arquitetura.drawio` + `.png` (implantada) e `docs/diagramas/arquitetura-ha.drawio` + `.png` (proposta). Ao editar um `.drawio`, exporte de novo o PNG (draw.io → Arquivo → Exportar como → PNG).
> Decisão registrada em `docs/adr/ADR-XXX-alta-disponibilidade.md`.

## Ponto de partida (arquitetura implantada)

Uma AZ (`us-east-2a`), um NAT, um bastion, uma VM da aplicação (proxy + frontend + API) com IP público e uma VM do MongoDB na sub-rede privada. Qualquer falha de instância ou da AZ derruba a loja.

## H1. Duas ou mais zonas e novo plano de endereçamento

A VPC continua `10.20.0.0/16`. A aplicação passa para sub-redes privadas atrás de um balanceador, e o banco ganha uma terceira AZ para ter maioria no replica set.

| Sub-rede | AZ a (`us-east-2a`) | AZ b (`us-east-2b`) | AZ c (`us-east-2c`) | Conteúdo |
|---|---|---|---|---|
| Pública | 10.20.1.0/24 *(existente)* | **10.20.2.0/24** | — | ALB, NAT Gateways |
| Privada · aplicação | **10.20.21.0/24** | **10.20.22.0/24** | — | Instâncias do Auto Scaling Group |
| Privada · dados | 10.20.11.0/24 *(existente)* | **10.20.12.0/24** | **10.20.13.0/24** | Nós do MongoDB |

## H2. Balanceador e Auto Scaling

- **Application Load Balancer** público nas duas sub-redes públicas, ouvindo em 443 (certificado do **ACM**, que é gratuito e exige um domínio próprio) e redirecionando 80 → 443.
- **Auto Scaling Group** com *launch template* (mesma AMI e o mesmo Ansible via user data/SSM): **mínimo 2, desejado 2, máximo 4**, distribuído nas duas AZs.
- **Health check do target group:** `GET /api/health/ready` (o endpoint já existe e testa a conexão com o MongoDB), intervalo de 15 s, 2 sucessos para saudável e 3 falhas para não saudável. Instâncias reprovadas são substituídas.
- O proxy TLS deixa de existir na VM: o TLS termina no ALB e as instâncias recebem HTTP só do SG do ALB.

## H3. Estratégia de NAT

**Um NAT Gateway por AZ** (`a` e `b`), cada sub-rede privada com rota para o NAT da própria AZ.
- **Consequência:** +US$ 33/mês (é o item que mais encarece a proposta), mas a perda de uma AZ não corta a saída da outra. Com NAT compartilhado, a queda da AZ do NAT impediria as instâncias da outra AZ de baixar pacotes e imagens e de enviar backup ao S3. A loja continuaria respondendo, mas o Auto Scaling não conseguiria criar instâncias novas.
- Complemento sem custo: **VPC Gateway Endpoint do S3**. O backup deixa de passar pelo NAT, o que reduz o custo por GB e a dependência do NAT.
- AZ `c` (só banco): rota para o NAT da AZ `a`. **Aceito:** o nó da AZ c só precisa de saída para atualizações.

## H4. Banco de dados

**Replica set MongoDB com 3 nós**, um em cada AZ de dados (`a`, `b`, `c`): 1 primário + 2 secundários, com eleição automática.
- A API conecta pela *connection string* do replica set (`mongodb://n1,n2,n3/kubeshop?replicaSet=rs0`), com `writeConcern: majority`. O código já usa `MONGO_HOST`/`MONGODB_URI`, então basta configurar.
- Três nós são necessários para ter maioria (2 de 3) se uma AZ cair. Com só dois nós, a perda de um impede a eleição.
- **Alternativa avaliada:** Amazon DocumentDB (compatível com a API do MongoDB, gerenciado e Multi-AZ). Foi descartada pelo custo mínimo maior (instâncias `db.t3.medium` ou acima) e pela compatibilidade parcial com o MongoDB 8. Fica registrada como evolução se a operação manual pesar.
- O backup continua lógico (`mongodump`), agora a partir de um **secundário** (`--readPreference=secondary`), sem carga no primário.

## H5. Estado da aplicação fora da instância

O KubeShop já é *stateless* na camada de aplicação, e não precisa de mudança de código:

| Estado | Onde fica hoje | Na proposta |
|---|---|---|
| Sessão de usuário | Não existe (sem login, por escopo) | — |
| Sacola de compras | **Memória do navegador** até a confirmação | Igual: qualquer instância atende qualquer requisição |
| Pedidos | MongoDB | Replica set (H4) |
| Catálogo | Código da API | Igual (vem na imagem) |
| Arquivos enviados | Não existem (sem upload) | Se surgirem: S3 |
| Segredos | Arquivos gravados pelo Ansible a partir do SSM | Lidos do SSM no boot pela role da instância |

Não é preciso *sticky session* no ALB.

## H6. Pontos únicos de falha

> **Conferir com a seção 5.10 da Entrega 1** e manter a numeração de lá. A lista abaixo cobre a arquitetura implantada.

| # | Ponto único de falha (implantada) | Na proposta | Decisão |
|---|---|---|---|
| 1 | Uma única AZ | 2 AZs (aplicação e NAT) e 3 AZs (banco) | **Eliminado** |
| 2 | Uma VM da aplicação | ASG com mínimo de 2 atrás do ALB | **Eliminado** |
| 3 | Uma VM do MongoDB | Replica set de 3 nós | **Eliminado** |
| 4 | Um NAT Gateway | Um por AZ | **Eliminado** (AZ c aceita compartilhar) |
| 5 | IP público fixo da aplicação (EIP) | ALB gerenciado (vários nós) + DNS | **Eliminado** |
| 6 | Bastion único | Substituído por **AWS Systems Manager Session Manager** (sem porta 22 de entrada, auditado no CloudTrail) | **Eliminado** |
| 7 | Região `us-east-2` | Continua em uma região; os backups são replicados para `us-east-1` (política GFS) | **Aceito:** multi-região multiplicaria o custo para um marketplace em lançamento. RTO de restauração em outra região: horas |
| 8 | Chave KMS única | Chave multi-região só se a operação for multi-região | **Aceito:** a KMS é um serviço regional altamente disponível |
| 9 | Pipeline (GitHub Actions) | Fora do caminho de atendimento; falha impede deploy, não o funcionamento | **Aceito** |

## H7. Fluxos redesenhados

> Ajustar a numeração para coincidir com os fluxos da Entrega 1.

| Fluxo | Arquitetura implantada | Proposta HA |
|---|---|---|
| **F1:** visitante acessa a loja | Navegador → EIP da VM-APP :443 → proxy → frontend | Navegador → DNS → **ALB :443** (ACM) → instância saudável do ASG (AZ a ou b) :8080 → frontend |
| **F2:** frontend encaminha `/api` (catálogo e pedidos) | Nginx do frontend → `api:3000` na mesma VM | Igual, dentro de cada instância |
| **F3:** API grava e consulta pedidos | API → VM-DB `10.20.11.x:27017` | API → **primário do replica set** (driver descobre o primário; *failover* automático) |
| **F4:** replicação de dados | — | Primário → secundários (AZ b, c) pela rede privada, porta 27017 entre os nós do SG do banco |
| **F5:** acesso administrativo | Grupo → **bastion** :22 → `ssh -J` → app / banco | Grupo → **Session Manager** (HTTPS para a API da AWS) → qualquer instância, sem porta 22 |
| **F6:** pipeline (deploy) | GitHub Actions (access key) → API AWS (Terraform) + SSH temporário no bastion → Ansible | Credencial da pipeline → Terraform; configuração por **SSM Run Command** ou novo *launch template* (troca gradual de instâncias no ASG) |
| **F7:** backup | VM-DB → NAT → S3 `diario/` | Secundário → **S3 Gateway Endpoint** → S3 (`diario/`, `semanal/`, `mensal/`) → replicação para `us-east-1` |
| **F8:** atualizações do SO e imagens | VMs → NAT (AZ a) → internet | Instâncias → NAT **da própria AZ** → internet |

## Custo da alta disponibilidade

| Versão | Custo mensal estimado | Variação |
|---|---|---|
| Arquitetura implantada (substituir pelo cenário A da Entrega 1, se for diferente) | ≈ US$ 68,64 | — |
| Proposta de alta disponibilidade | ≈ US$ 153,38 | **+123%** |

**Itens que mais contribuem para o aumento** (detalhes em `docs/custos/estimativas.md`):
- **Segundo NAT Gateway:** +US$ 33
- **ALB:** +US$ 22
- **Dois nós extras do MongoDB:** +US$ 15
- **Segunda instância da aplicação:** +US$ 7,6

Em parte, isso é compensado pela remoção do bastion e do EIP da app (−US$ 11).

### Esse custo se justifica?

**Para o perfil de uso atual, não.** O KubeShop é a base de um marketplace **em lançamento**, com produtos e pedidos fictícios, sem pagamentos reais e sem SLA acordado com a Zibiska Korp. Uma indisponibilidade de 1 hora (RTO do backup) não gera perda financeira real, e a pipeline recria o ambiente em cerca de 15 minutos. Pagar mais que o dobro por mês para proteger contra a falha de uma AZ não se paga nessa fase.

**Passa a se justificar quando houver vendas reais.** Se uma hora de loja fora do ar custar mais que cerca de US$ 85 por mês, ou se houver SLA contratado, a proposta vale a pena. Um passo intermediário mais barato seria:
- 2 instâncias da aplicação em 2 AZs com ALB;
- NAT compartilhado;
- replica set com 2 nós + árbitro;

o que fica perto de US$ 110/mês.

> Revisar esta resposta com o perfil de uso descrito na seção 5.1 da Entrega 1.
