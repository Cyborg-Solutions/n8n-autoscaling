# 🔧 Troubleshooting - N8N Autoscaler

Guia para resolução dos problemas mais comuns do autoscaler.

## 🔧 Problemas Comuns e Soluções

### 1. Problemas com Traefik e Resolução de Nomes

**Erro:** `Failed to resolve 'docker-api-proxy'` ou `Name does not resolve`

**Causa:** Conflito entre Traefik e acesso direto ao Docker socket, ou serviços não encontrados na rede.

**Soluções:**

#### Opção 1: Usar Stack Específica para Traefik
```bash
# Use a stack otimizada para Traefik
docker stack deploy -c stack-n8n-integration-traefik.yaml autoscaler-n8n

# Verificar se todos os serviços estão rodando
docker service ls | grep autoscaler-n8n
```

#### Opção 2: Verificar Conectividade de Rede
```bash
# Verificar se a rede CSNet existe e está ativa
docker network ls | grep CSNet

# Verificar serviços na rede
docker network inspect CSNet

# Testar conectividade entre serviços
docker exec -it $(docker ps -q -f name=autoscaler) ping docker-socket-proxy
```

#### Opção 3: Recriar a Rede CSNet
```bash
# Remover stack temporariamente
docker stack rm autoscaler-n8n

# Recriar a rede
docker network rm CSNet
docker network create --driver overlay --attachable CSNet

# Redeploy da stack
docker stack deploy -c stack-n8n-integration-traefik.yaml autoscaler-n8n
```

## 🚨 Erro: Permission denied no Docker Socket

### Sintoma
```
ERROR - CRÍTICO: Falha ao conectar ao Redis ou Docker: Error while fetching server API version: ('Connection aborted.', PermissionError(13, 'Permission denied'))
```

### Causa
O container do autoscaler não tem permissões para acessar o Docker socket (`/var/run/docker.sock`).

### Soluções

#### Solução 1: Verificar Montagem do Volume (Mais Comum)

```bash
# Verificar se o volume está montado corretamente
docker service inspect autoscaler-n8n_autoscaler --format '{{.Spec.TaskTemplate.ContainerSpec.Mounts}}'

# Deve mostrar algo como:
# [{bind  /var/run/docker.sock /var/run/docker.sock   true rprivate}]
```

Se não aparecer a montagem:

```bash
# Atualizar o serviço com a montagem correta
docker service update --mount-add type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock,readonly autoscaler-n8n_autoscaler
```

#### Solução 2: Verificar Permissões do Docker Socket

```bash
# Verificar permissões do socket
ls -la /var/run/docker.sock

# Deve mostrar algo como:
# srw-rw---- 1 root docker 0 Jan 1 12:00 /var/run/docker.sock
```

Se as permissões estiverem incorretas:

```bash
# Corrigir permissões (cuidado em produção)
sudo chmod 666 /var/run/docker.sock

# Ou adicionar usuário ao grupo docker
sudo usermod -aG docker $USER
```

#### Solução 3: Recriar o Serviço

```bash
# Remover stack atual
docker stack rm autoscaler-n8n

# Aguardar remoção completa
docker service ls | grep autoscaler

# Fazer deploy novamente
docker stack deploy -c stack-n8n-integration.yaml autoscaler-n8n
```

#### Solução 4: Verificar Constraints de Placement

O serviço deve rodar apenas em nodes manager:

```bash
# Verificar nodes disponíveis
docker node ls

# Verificar se o constraint está correto
docker service inspect autoscaler-n8n_autoscaler --format '{{.Spec.TaskTemplate.Placement.Constraints}}'

# Deve mostrar: [node.role == manager]
```

#### Solução 5: Usar Docker Socket Proxy (Recomendado para Produção)

Para maior segurança, use um proxy do Docker socket:

```yaml
# Adicionar ao stack-n8n-integration.yaml
  docker-socket-proxy:
    image: tecnativa/docker-socket-proxy:latest
    networks:
      - CSNet
    environment:
      - CONTAINERS=1
      - SERVICES=1
      - SWARM=1
      - NODES=1
      - NETWORKS=1
      - TASKS=1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
```

E atualizar o autoscaler para usar o proxy:

```yaml
  autoscaler:
    # ... outras configurações
    environment:
      # ... outras variáveis
      - DOCKER_HOST=tcp://docker-socket-proxy:2375
    # Remover volumes do docker.sock
    # volumes:
    #   - /var/run/docker.sock:/var/run/docker.sock:ro
```

## 🔍 Erro: Não consegue conectar ao Redis

### Sintoma
```
ERROR - Falha ao conectar ao Redis: ConnectionError
```

### Soluções

#### Verificar Conectividade

```bash
# Testar conectividade do container
docker exec -it $(docker ps -q -f name=autoscaler) ping redis

# Testar conexão Redis
docker exec -it $(docker ps -q -f name=autoscaler) nc -zv redis 6379
```

#### Verificar Configurações de Rede

```bash
# Verificar se ambos estão na mesma rede
docker service inspect redis --format '{{.Spec.TaskTemplate.Networks}}'
docker service inspect autoscaler-n8n_autoscaler --format '{{.Spec.TaskTemplate.Networks}}'
```

#### Verificar Variáveis de Ambiente

```bash
# Verificar configurações do Redis
docker service inspect autoscaler-n8n_autoscaler --format '{{.Spec.TaskTemplate.ContainerSpec.Env}}'
```

## ⚙️ Erro: Worker N8N não escala

### Sintoma
Filas cheias mas workers não aumentam.

### Soluções

#### Verificar Nome do Serviço

```bash
# Listar serviços N8N
docker service ls | grep n8n

# Verificar nome configurado
docker service inspect autoscaler-n8n_autoscaler --format '{{.Spec.TaskTemplate.ContainerSpec.Env}}' | grep N8N_WORKER

# Atualizar se necessário
docker service update --env-add N8N_WORKER_SERVICE_NAME=nome_correto autoscaler-n8n_autoscaler
```

#### Verificar Thresholds

```bash
# Ver configurações atuais
docker service logs autoscaler-n8n_autoscaler | grep -i threshold

# Ajustar se necessário
docker service update --env-add SCALE_UP_QUEUE_THRESHOLD=10 autoscaler-n8n_autoscaler
```

#### Verificar Cooldown

```bash
# Verificar se está em período de cooldown
docker service logs autoscaler-n8n_autoscaler | grep -i cooldown

# Reduzir cooldown se necessário
docker service update --env-add COOLDOWN_PERIOD_SECONDS=120 autoscaler-n8n_autoscaler
```

## 📊 Comandos de Diagnóstico

### Verificar Status Geral

```bash
# Status de todos os serviços
docker service ls

# Status específico do autoscaler
docker service ps autoscaler-n8n_autoscaler

# Logs em tempo real
docker service logs -f autoscaler-n8n_autoscaler
```

### Verificar Filas Redis

```bash
# Conectar ao Redis
docker exec -it $(docker ps -q -f name=redis) redis-cli

# Selecionar database correto
SELECT 2

# Verificar filas
KEYS bull:*
LLEN bull:jobs:waiting
LLEN bull:jobs:active
LLEN bull:jobs:completed
LLEN bull:jobs:failed
```

### Verificar Recursos

```bash
# Uso de recursos dos containers
docker stats --no-stream

# Recursos disponíveis no Swarm
docker node ls
docker node inspect $(docker node ls -q) --format '{{.Description.Resources}}'
```

## 🔄 Reinicialização Completa

Se nada funcionar, reinicialização completa:

```bash
# 1. Remover stack
docker stack rm autoscaler-n8n

# 2. Aguardar remoção
watch docker service ls

# 3. Limpar volumes órfãos (opcional)
docker volume prune -f

# 4. Verificar rede
docker network ls | grep CSNet

# 5. Recriar se necessário
docker network rm CSNet
docker network create --driver overlay --attachable CSNet

# 6. Deploy novamente
docker stack deploy -c stack-n8n-integration.yaml autoscaler-n8n

# 7. Verificar logs
docker service logs -f autoscaler-n8n_autoscaler
```

## 📞 Suporte

Se o problema persistir:

1. Colete os logs: `docker service logs autoscaler-n8n_autoscaler > logs.txt`
2. Colete informações do ambiente: `docker info > docker-info.txt`
3. Colete configurações: `docker service inspect autoscaler-n8n_autoscaler > service-config.json`
4. Entre em contato com o suporte da Cyborg Solutions