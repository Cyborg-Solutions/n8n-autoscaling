#!/bin/bash

# Script para build e push automático para Docker Hub
# Incrementa automaticamente a versão baseada na última tag

set -e

# Configurações
DOCKER_USERNAME="cyborgsolutionstech"  # Altere para seu usuário
REPO_MONITOR="${DOCKER_USERNAME}/n8n-redis-monitor"
REPO_AUTOSCALER="${DOCKER_USERNAME}/n8n-autoscaler"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para obter a próxima versão
get_next_version() {
    local repo=$1
    echo -e "${BLUE}Verificando última versão de ${repo}...${NC}"
    
    # Obter tags do repositório
    local tags=$(curl -s "https://registry.hub.docker.com/v2/repositories/${repo}/tags/?page_size=100" | jq -r '.results[].name' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    
    if [ -z "$tags" ]; then
        echo -e "${YELLOW}Nenhuma versão encontrada. Iniciando com 1.0.0${NC}"
        echo "1.0.0"
    else
        echo -e "${GREEN}Última versão encontrada: ${tags}${NC}"
        # Incrementar patch version
        local major=$(echo $tags | cut -d. -f1)
        local minor=$(echo $tags | cut -d. -f2)
        local patch=$(echo $tags | cut -d. -f3)
        local new_patch=$((patch + 1))
        local new_version="${major}.${minor}.${new_patch}"
        echo -e "${GREEN}Nova versão: ${new_version}${NC}"
        echo "$new_version"
    fi
}

# Função para build e push
build_and_push() {
    local context=$1
    local repo=$2
    local version=$3
    
    echo -e "${BLUE}Building ${repo}:${version}...${NC}"
    
    # Build da imagem
    docker build -t "${repo}:${version}" -t "${repo}:latest" "${context}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Build concluído com sucesso!${NC}"
        
        # Push das imagens
        echo -e "${BLUE}Fazendo push para Docker Hub...${NC}"
        docker push "${repo}:${version}"
        docker push "${repo}:latest"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Push concluído com sucesso!${NC}"
            echo -e "${GREEN}Imagem disponível: ${repo}:${version}${NC}"
        else
            echo -e "${RED}Erro no push da imagem${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Erro no build da imagem${NC}"
        exit 1
    fi
}

# Verificar se jq está instalado
if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq não está instalado. Instale com: sudo apt-get install jq${NC}"
    exit 1
fi

# Verificar se está logado no Docker Hub
if ! docker info | grep -q "Username"; then
    echo -e "${YELLOW}Fazendo login no Docker Hub...${NC}"
    docker login
fi

echo -e "${BLUE}=== Build e Push Automático para Docker Hub ===${NC}"
echo -e "${BLUE}Repositórios:${NC}"
echo -e "  - Monitor: ${REPO_MONITOR}"
echo -e "  - Autoscaler: ${REPO_AUTOSCALER}"
echo ""

# Build do Redis Monitor
echo -e "${YELLOW}=== REDIS MONITOR ===${NC}"
MONITOR_VERSION=$(get_next_version "$REPO_MONITOR")
build_and_push "./monitor" "$REPO_MONITOR" "$MONITOR_VERSION"
echo ""

# Build do Autoscaler
echo -e "${YELLOW}=== N8N AUTOSCALER ===${NC}"
AUTOSCALER_VERSION=$(get_next_version "$REPO_AUTOSCALER")
build_and_push "./autoscaler" "$REPO_AUTOSCALER" "$AUTOSCALER_VERSION"
echo ""

echo -e "${GREEN}=== BUILD E PUSH CONCLUÍDOS ===${NC}"
echo -e "${GREEN}Versões publicadas:${NC}"
echo -e "  - ${REPO_MONITOR}:${MONITOR_VERSION}"
echo -e "  - ${REPO_AUTOSCALER}:${AUTOSCALER_VERSION}"
echo ""
echo -e "${BLUE}Para usar as novas versões, atualize o stack.yaml:${NC}"
echo -e "  redis-monitor: image: ${REPO_MONITOR}:${MONITOR_VERSION}"
echo -e "  n8n-autoscaler: image: ${REPO_AUTOSCALER}:${AUTOSCALER_VERSION}"