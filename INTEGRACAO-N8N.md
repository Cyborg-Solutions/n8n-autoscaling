# 🔗 Integração com N8N e Redis

Este guia explica como integrar o autoscaler com stacks existentes do N8N e Redis.

## 📋 Pré-requisitos

- Docker Swarm ativo
- Stack do N8N rodando
- Redis configurado e acessível
- Rede Docker compartilhada (CSNet)

## 🏗️ Arquitetura de Integração

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   N8N Main      │    │   Redis         │    │   Autoscaler    │
│   (Webhook)     │◄──►│   (Queue)       │◄──►│   (Monitor)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   N8N Workers   │    │   Bull Queues   │    │  Redis Monitor  │
│   (Escaláveis)  │    │   (DB 2)        │    │   (Métricas)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## ⚙️ Configuração Automática

### Opção 1: Script de Configuração (Recomendado)

#### Linux/macOS (Bash)
```bash
# Tornar o script executável
chmod +x configure-n8n-integration.sh

# Executar configuração automática
./configure-n8n-integration.sh
```

#### Windows (PowerShell)
```powershell
# Executar configuração automática
.\configure-n8n-integration.ps1

# Ou com parâmetros
.\configure-n8n-integration.ps1 -DockerUsername "seu_usuario" -SkipDeploy
```

O script irá:
- ✅ Verificar dependências (Docker, Swarm)
- ✅ Criar/verificar rede CSNet
- ✅ Detectar serviços N8N e Redis existentes
- ✅ Configurar arquivo .env
- ✅ Fazer deploy automático (opcional)

### Opção 2: Configuração Manual

#### 1. Verificar Rede

```bash
# Verificar se a rede CSNet existe
docker network ls | grep CSNet

# Se não existir, criar
docker network create --driver overlay --attachable CSNet
```

#### 2. Identificar Serviços

```bash
# Listar serviços do N8N
docker service ls | grep n8n

# Exemplo de saída:
# n8n_n8n_main     replicated   1/1        n8nio/n8n:latest
# n8n_n8n_worker   replicated   2/2        n8nio/n8n:latest
```

#### 3. Configurar Variáveis

Edite o arquivo `.env`:

```bash
DOCKER_USERNAME=seu_usuario_dockerhub
```

#### 4. Deploy da Stack

```bash
# Deploy integrado
docker stack deploy -c stack-n8n-integration.yaml autoscaler-n8n
```

## 🔧 Configurações Específicas

### Redis

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `REDIS_HOST` | `redis` | Nome do serviço Redis |
| `REDIS_PORT` | `6379` | Porta padrão do Redis |
| `REDIS_PASSWORD` | `` | Sem senha (padrão N8N) |
| `REDIS_DB` | `2` | Database usado pelo N8N |

### N8N Worker

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `N8N_WORKER_SERVICE_NAME` | `n8n_n8n_worker` | Nome do serviço worker |
| `QUEUE_NAME_PREFIX` | `bull` | Prefixo das filas Bull |
| `QUEUE_NAME` | `jobs` | Nome da fila principal |

### Escalabilidade

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `MIN_REPLICAS` | `1` | Mínimo de workers |
| `MAX_REPLICAS` | `10` | Máximo de workers |
| `SCALE_UP_QUEUE_THRESHOLD` | `20` | Jobs para escalar para cima |
| `SCALE_DOWN_QUEUE_THRESHOLD` | `5` | Jobs para escalar para baixo |
| `POLLING_INTERVAL_SECONDS` | `30` | Intervalo de verificação |
| `COOLDOWN_PERIOD_SECONDS` | `300` | Tempo de espera entre escalas |

## 📊 Monitoramento

### Verificar Status

```bash
# Listar todos os serviços
docker service ls

# Verificar réplicas do worker N8N
docker service ps n8n_n8n_worker

# Status do autoscaler
docker service ps autoscaler-n8n_autoscaler
```

### Logs em Tempo Real

```bash
# Logs do autoscaler
docker service logs -f autoscaler-n8n_autoscaler

# Logs do monitor Redis
docker service logs -f autoscaler-n8n_redis-monitor

# Logs do worker N8N
docker service logs -f n8n_n8n_worker
```

### Métricas Importantes

```bash
# Verificar filas no Redis
docker exec -it $(docker ps -q -f name=redis) redis-cli
> SELECT 2
> KEYS bull:*
> LLEN bull:jobs:waiting
> LLEN bull:jobs:active
```

## 🚨 Troubleshooting

### Problema: Autoscaler não encontra o worker

**Sintoma:** Logs mostram "Serviço não encontrado"

**Solução:**
```bash
# Verificar nome exato do serviço
docker service ls | grep worker

# Atualizar variável de ambiente
docker service update --env-add N8N_WORKER_SERVICE_NAME=nome_correto autoscaler-n8n_autoscaler
```

### Problema: Não consegue conectar no Redis

**Sintoma:** Erro de conexão Redis

**Solução:**
```bash
# Verificar se Redis está na mesma rede
docker service inspect redis --format '{{.Spec.TaskTemplate.Networks}}'

# Verificar conectividade
docker exec -it $(docker ps -q -f name=autoscaler) ping redis
```

### Problema: Workers não escalam

**Sintoma:** Filas cheias mas workers não aumentam

**Solução:**
```bash
# Verificar logs do autoscaler
docker service logs autoscaler-n8n_autoscaler | tail -20

# Verificar permissões Docker socket
docker service inspect autoscaler-n8n_autoscaler --format '{{.Spec.TaskTemplate.ContainerSpec.Mounts}}'
```

## 🔄 Atualizações

### Atualizar Imagens

```bash
# Pull das novas imagens
docker service update --image seu_usuario/autoscaler:latest autoscaler-n8n_autoscaler
docker service update --image seu_usuario/redis-monitor:latest autoscaler-n8n_redis-monitor
```

### Modificar Configurações

```bash
# Exemplo: Alterar threshold de escala
docker service update --env-add SCALE_UP_QUEUE_THRESHOLD=30 autoscaler-n8n_autoscaler

# Exemplo: Alterar máximo de réplicas
docker service update --env-add MAX_REPLICAS=15 autoscaler-n8n_autoscaler
```

## 🗑️ Remoção

```bash
# Remover stack do autoscaler
docker stack rm autoscaler-n8n

# Verificar se foi removido
docker service ls | grep autoscaler
```

## 📈 Otimizações

### Para Alto Volume

- Aumentar `MAX_REPLICAS` para 20+
- Reduzir `POLLING_INTERVAL_SECONDS` para 15
- Ajustar `SCALE_UP_QUEUE_THRESHOLD` para 50+

### Para Economia de Recursos

- Manter `MIN_REPLICAS` em 0
- Aumentar `COOLDOWN_PERIOD_SECONDS` para 600
- Ajustar `SCALE_DOWN_QUEUE_THRESHOLD` para 2

### Para Responsividade

- Reduzir `POLLING_INTERVAL_SECONDS` para 10
- Reduzir `COOLDOWN_PERIOD_SECONDS` para 120
- Ajustar `SCALE_UP_QUEUE_THRESHOLD` para 10