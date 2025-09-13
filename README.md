## 🏗️ Build e Publicação

### Opção 1: Script Automático (Recomendado)

**Windows (PowerShell):**
```powershell
# Altere 'seu-usuario-dockerhub' no arquivo build-and-push.ps1
.\build-and-push.ps1 -DockerUsername "seu-usuario-dockerhub"
```

**Linux/Mac (Bash):**
```bash
# Altere 'seu-usuario-dockerhub' no arquivo build-and-push.sh
chmod +x build-and-push.sh
./build-and-push.sh
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

```bash
# Deploy da stack
docker stack deploy -c stack.yaml n8n-monitor

# Verificar serviços
docker service ls

# Logs dos serviços
docker service logs n8n-monitor_redis-monitor
docker service logs n8n-monitor_n8n-autoscaler
```