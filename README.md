## 🏗️ Build e Publicação

### Opção 1: Script Automático (Recomendado)

**Windows (PowerShell):**
```powershell
# Altere 'seu-usuario-dockerhub' no arquivo build-and-push.ps1
.\build-and-push.ps1 -DockerUsername "seu-usuario-dockerhub"
```

**Linux/Mac (Bash com jq):**
```bash
# Requer jq instalado: sudo apt-get install jq
# Altere 'seu-usuario-dockerhub' no arquivo build-and-push.sh
chmod +x build-and-push.sh
./build-and-push.sh
```

**Linux/Mac (Bash simplificado - sem jq):**
```bash
# Não requer jq, usa versionamento por timestamp
# Altere 'seu-usuario-dockerhub' no arquivo build-simple.sh
chmod +x build-simple.sh
./build-simple.sh
```

### Opção 2: Makefile

```bash
# Build e push de todas as imagens
make build-all DOCKER_USER=seu-usuario-dockerhub
make push-all DOCKER_USER=seu-usuario-dockerhub

# Ou build com versionamento automático
make build-versioned DOCKER_USER=seu-usuario-dockerhub
```

### Opção 3: Manual

```bash
# Login no Docker Hub
docker login

# Build das imagens
docker build -t seu-usuario/n8n-redis-monitor:latest ./monitor
docker build -t seu-usuario/n8n-autoscaler:latest ./autoscaler

# Push para Docker Hub
docker push seu-usuario/n8n-redis-monitor:latest
docker push seu-usuario/n8n-autoscaler:latest
```

## 🚀 Deploy

> 📖 **Para integração com N8N existente:** Consulte o [Guia de Integração N8N](INTEGRACAO-N8N.md)

### Configuração das Variáveis de Ambiente

Antes do deploy, configure as variáveis no arquivo `.env`:

```bash
# Copie o arquivo de exemplo
cp .env.example .env

# Edite as configurações
nano .env
```

### Deploy no Docker Swarm

#### Opção 1: Stack Standalone (Padrão)

```bash
# Deploy da stack completa
docker stack deploy -c stack.yaml autoscaler

# Verificar status dos serviços
docker service ls

# Ver logs do autoscaler
docker service logs -f autoscaler_autoscaler

# Ver logs do redis-monitor
docker service logs -f autoscaler_redis-monitor
```

#### Opção 2: Integração com Stack N8N Existente

Se você já possui um stack do N8N rodando com Redis, use o arquivo de integração:

```bash
# Deploy integrado com N8N existente
docker stack deploy -c stack-n8n-integration.yaml autoscaler-n8n

# Verificar se os serviços estão na mesma rede
docker network ls | grep CSNet

# Ver logs do autoscaler integrado
docker service logs -f autoscaler-n8n_autoscaler
```

**Configurações importantes para integração:**
- Redis DB: `2` (mesmo usado pelo N8N)
- Rede: `CSNet` (rede externa do N8N)
- Worker Service: `n8n_n8n_worker` (nome do serviço worker do N8N)
- Sem senha no Redis (conforme configuração do N8N)

**Configuração automática:**
```bash
# Script de configuração automática para N8N
chmod +x configure-n8n-integration.sh
./configure-n8n-integration.sh
```

> 📚 **Documentação completa:** [INTEGRACAO-N8N.md](INTEGRACAO-N8N.md)  
> 🔧 **Resolução de problemas:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md)