#!/bin/bash

# Script simplificado para build e push sem dependência do jq
# Usa versionamento baseado em timestamp

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

# Gerar versão baseada em timestamp
generate_version() {
    local timestamp=$(date +"%Y%m%d%H%M")
    echo "1.0.${timestamp}"
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

# Verificar se está logado no Docker Hub
if ! docker info | grep -q "Username"; then
    echo -e "${YELLOW}Fazendo login no Docker Hub...${NC}"
    docker login
fi

echo -e "${BLUE}=== Build e Push Simplificado para Docker Hub ===${NC}"
echo -e "${BLUE}Repositórios:${NC}"
echo -e "  - Monitor: ${REPO_MONITOR}"
echo -e "  - Autoscaler: ${REPO_AUTOSCALER}"
echo ""

# Gerar versão única
VERSION=$(generate_version)
echo -e "${GREEN}Versão gerada: ${VERSION}${NC}"
echo ""

# Build do Redis Monitor
echo -e "${YELLOW}=== REDIS MONITOR ===${NC}"
build_and_push "./monitor" "$REPO_MONITOR" "$VERSION"
echo ""

# Build do Autoscaler
echo -e "${YELLOW}=== N8N AUTOSCALER ===${NC}"
build_and_push "./autoscaler" "$REPO_AUTOSCALER" "$VERSION"
echo ""

echo -e "${GREEN}=== BUILD E PUSH CONCLUÍDOS ===${NC}"
echo -e "${GREEN}Versões publicadas:${NC}"
echo -e "  - ${REPO_MONITOR}:${VERSION}"
echo -e "  - ${REPO_AUTOSCALER}:${VERSION}"
echo ""
echo -e "${BLUE}Para usar as novas versões, atualize o stack.yaml:${NC}"
echo -e "  redis-monitor: image: ${REPO_MONITOR}:${VERSION}"
echo -e "  n8n-autoscaler: image: ${REPO_AUTOSCALER}:${VERSION}"

# Salvar informações da versão
cat > version-info.txt << EOF
Última build realizada em: $(date)
Versão: ${VERSION}

Imagens publicadas:
- ${REPO_MONITOR}:${VERSION}
- ${REPO_AUTOSCALER}:${VERSION}

Para atualizar o stack.yaml:
services:
  redis-monitor:
    image: ${REPO_MONITOR}:${VERSION}
  n8n-autoscaler:
    image: ${REPO_AUTOSCALER}:${VERSION}
EOF

echo -e "${BLUE}Informações salvas em version-info.txt${NC}"