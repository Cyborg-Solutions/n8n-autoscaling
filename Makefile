# Makefile para build e deploy automático
# Uso: make build-all DOCKER_USER=seu-usuario

# Configurações padrão
DOCKER_USER ?= cyborgsolutionstech
REPO_MONITOR = $(DOCKER_USER)/n8n-redis-monitor
REPO_AUTOSCALER = $(DOCKER_USER)/n8n-autoscaler

# Cores para output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
NC = \033[0m

.PHONY: help build-monitor build-autoscaler build-all push-monitor push-autoscaler push-all clean login check-docker

# Target padrão
help:
	@echo "$(BLUE)=== N8N Autoscaling Stack - Build Commands ===$(NC)"
	@echo ""
	@echo "$(YELLOW)Comandos disponíveis:$(NC)"
	@echo "  make build-all DOCKER_USER=seu-usuario    - Build de todas as imagens"
	@echo "  make push-all DOCKER_USER=seu-usuario     - Push de todas as imagens"
	@echo "  make build-monitor                        - Build apenas do Redis Monitor"
	@echo "  make build-autoscaler                     - Build apenas do Autoscaler"
	@echo "  make push-monitor                         - Push apenas do Redis Monitor"
	@echo "  make push-autoscaler                      - Push apenas do Autoscaler"
	@echo "  make login                                - Login no Docker Hub"
	@echo "  make clean                                - Limpar imagens locais"
	@echo ""
	@echo "$(YELLOW)Exemplo de uso:$(NC)"
	@echo "  make build-all DOCKER_USER=meuusuario"
	@echo "  make push-all DOCKER_USER=meuusuario"
	@echo ""
	@echo "$(YELLOW)Variáveis:$(NC)"
	@echo "  DOCKER_USER - Seu usuário do Docker Hub (obrigatório)"

check-docker:
	@echo "$(BLUE)Verificando Docker...$(NC)"
	@docker info > /dev/null 2>&1 || (echo "$(RED)Docker não está rodando$(NC)" && exit 1)
	@echo "$(GREEN)Docker OK$(NC)"

login: check-docker
	@echo "$(BLUE)Fazendo login no Docker Hub...$(NC)"
	@docker login

# Build targets
build-monitor: check-docker
	@echo "$(BLUE)Building Redis Monitor...$(NC)"
	@docker build -t $(REPO_MONITOR):latest ./monitor
	@echo "$(GREEN)Redis Monitor build concluído$(NC)"

build-autoscaler: check-docker
	@echo "$(BLUE)Building N8N Autoscaler...$(NC)"
	@docker build -t $(REPO_AUTOSCALER):latest ./autoscaler
	@echo "$(GREEN)N8N Autoscaler build concluído$(NC)"

build-all: build-monitor build-autoscaler
	@echo "$(GREEN)Todos os builds concluídos!$(NC)"

# Push targets
push-monitor: build-monitor
	@echo "$(BLUE)Fazendo push do Redis Monitor...$(NC)"
	@docker push $(REPO_MONITOR):latest
	@echo "$(GREEN)Redis Monitor push concluído$(NC)"

push-autoscaler: build-autoscaler
	@echo "$(BLUE)Fazendo push do N8N Autoscaler...$(NC)"
	@docker push $(REPO_AUTOSCALER):latest
	@echo "$(GREEN)N8N Autoscaler push concluído$(NC)"

push-all: push-monitor push-autoscaler
	@echo "$(GREEN)=== TODOS OS PUSHES CONCLUÍDOS ===$(NC)"
	@echo "$(GREEN)Imagens disponíveis:$(NC)"
	@echo "  - $(REPO_MONITOR):latest"
	@echo "  - $(REPO_AUTOSCALER):latest"
	@echo ""
	@echo "$(BLUE)Para usar no stack.yaml:$(NC)"
	@echo "services:"
	@echo "  redis-monitor:"
	@echo "    image: $(REPO_MONITOR):latest"
	@echo "  n8n-autoscaler:"
	@echo "    image: $(REPO_AUTOSCALER):latest"

# Versioned builds (com incremento automático)
build-versioned:
	@echo "$(BLUE)Executando build com versionamento automático...$(NC)"
	@if [ "$(OS)" = "Windows_NT" ]; then \
		powershell -ExecutionPolicy Bypass -File ./build-and-push.ps1 -DockerUsername $(DOCKER_USER); \
	else \
		./build-and-push.sh; \
	fi

# Deploy da stack
deploy: check-docker
	@echo "$(BLUE)Fazendo deploy da stack...$(NC)"
	@docker stack deploy -c stack.yaml n8n-monitor
	@echo "$(GREEN)Stack deployada com sucesso!$(NC)"
	@echo "$(BLUE)Verificando serviços:$(NC)"
	@docker service ls | grep n8n-monitor

# Remover stack
undeploy:
	@echo "$(BLUE)Removendo stack...$(NC)"
	@docker stack rm n8n-monitor
	@echo "$(GREEN)Stack removida$(NC)"

# Logs dos serviços
logs-monitor:
	@docker service logs -f n8n-monitor_redis-monitor

logs-autoscaler:
	@docker service logs -f n8n-monitor_n8n-autoscaler

logs-all:
	@echo "$(BLUE)Logs do Redis Monitor:$(NC)"
	@docker service logs --tail 20 n8n-monitor_redis-monitor
	@echo ""
	@echo "$(BLUE)Logs do N8N Autoscaler:$(NC)"
	@docker service logs --tail 20 n8n-monitor_n8n-autoscaler

# Limpeza
clean:
	@echo "$(BLUE)Limpando imagens locais...$(NC)"
	@docker image prune -f
	@docker rmi $(REPO_MONITOR):latest $(REPO_AUTOSCALER):latest 2>/dev/null || true
	@echo "$(GREEN)Limpeza concluída$(NC)"

# Status dos serviços
status:
	@echo "$(BLUE)Status dos serviços:$(NC)"
	@docker service ls | grep n8n-monitor || echo "$(YELLOW)Nenhum serviço encontrado$(NC)"
	@echo ""
	@echo "$(BLUE)Detalhes dos serviços:$(NC)"
	@docker service ps n8n-monitor_redis-monitor 2>/dev/null || echo "$(YELLOW)Redis Monitor não encontrado$(NC)"
	@docker service ps n8n-monitor_n8n-autoscaler 2>/dev/null || echo "$(YELLOW)N8N Autoscaler não encontrado$(NC)"