# ADR-XXX: Estratégia de alta disponibilidade (proposta)

> Renumerar seguindo a sequência dos ADRs da Entrega 1.

- **Status:** proposta (projetada, não implantada)
- **Data:** 18/11/2026
- **Relacionados:** `docs/alta-disponibilidade.md`, `docs/diagramas/arquitetura-ha.drawio`, `docs/custos/estimativas.md`

## Contexto

A arquitetura implantada usa uma AZ, uma VM da aplicação, uma VM do MongoDB, um NAT e um bastion: cada um é ponto único de falha. A Entrega 2 pede uma proposta que elimine ou aceite explicitamente esses pontos, com estratégia de NAT e de banco, estado fora da instância e análise de custo. A aplicação já é *stateless* (sacola no navegador, sem login nem upload), e o único estado é o MongoDB.

## Decisão (Y-statement)

No contexto de evoluir o KubeShop para tolerar a falha de uma instância ou de uma zona, diante da exigência de eliminar os pontos únicos de falha com custo justificável, decidimos por:
- **ALB + Auto Scaling Group** (mínimo 2 instâncias em 2 AZs, health check em `/api/health/ready`);
- **um NAT Gateway por AZ**;
- **replica set do MongoDB com 3 nós em 3 AZs**;
- **Session Manager no lugar do bastion**;
- **S3 Gateway Endpoint** para o backup.

Descartamos:
- **NAT compartilhado:** perder a AZ do NAT impediria o Auto Scaling de criar instâncias na outra AZ;
- **replica set com 2 nós:** sem maioria após uma falha;
- **Amazon DocumentDB:** custo mínimo maior e compatibilidade parcial com o MongoDB 8.

Com isso, a loja continua no ar se uma AZ inteira cair, com *failover* automático do banco. **Aceitamos que:**
- o custo mensal sobe cerca de 123% (de ≈ US$ 69 para ≈ US$ 153);
- a operação passa a incluir um replica set;
- a região continua sendo um ponto único de falha, mitigado só pela réplica dos backups em `us-east-1`;
- **para o perfil atual** (marketplace em lançamento, pedidos fictícios, sem SLA) **a proposta não se paga**, e só deve ser implantada quando houver vendas reais.

## Consequências

- A VM da aplicação deixa de ter IP público; o TLS passa para o ALB (ACM exige domínio próprio).
- A connection string da API passa a apontar para o replica set (`replicaSet=rs0`, `writeConcern=majority`), sem mudança de código.
- A pipeline troca SSH por **SSM Run Command** ou por um novo *launch template* com substituição gradual das instâncias.
- O backup passa a ser feito a partir de um **secundário**, sem carga no primário.
- Passo intermediário possível: 2 instâncias + ALB, NAT compartilhado e replica set 2 nós + árbitro (≈ US$ 110/mês).
