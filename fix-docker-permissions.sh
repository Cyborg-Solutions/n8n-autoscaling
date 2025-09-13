#!/bin/bash

# Script de Correção Rápida - Permissões Docker Socket
# Resolve o erro: PermissionError(13, 'Permission denied') no Docker socket

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Correção de Permissões Docker Socket${NC}"
echo "============================================"
echo ""

# Verificar se está rodando como root ou com sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Este script precisa de privilégios de administrador${NC}"
    echo -e "${YELLOW}💡 Execute: sudo $0${NC}"
    exit 1
fi

echo -e "${YELLOW}🔍 Diagnosticando problema...${NC}"

# Verificar se o Docker está rodando
if ! systemctl is-active --quiet docker; then
    echo -e "${RED}❌ Docker não está rodando${NC}"
    echo -e "${YELLOW}🚀 Iniciando Docker...${NC}"
    systemctl start docker
    sleep 3
fi

echo -e "${GREEN}✅ Docker está rodando${NC}"

# Verificar permissões atuais do socket
echo -e "${YELLOW}📋 Permissões atuais do Docker socket:${NC}"
ls -la /var/run/docker.sock

# Verificar se o grupo docker existe
if ! getent group docker > /dev/null 2>&1; then
    echo -e "${YELLOW}📝 Criando grupo docker...${NC}"
    groupadd docker
fi

# Corrigir permissões do socket
echo -e "${YELLOW}🔧 Corrigindo permissões do Docker socket...${NC}"
chown root:docker /var/run/docker.sock
chmod 660 /var/run/docker.sock

echo -e "${GREEN}✅ Permissões corrigidas${NC}"

# Verificar permissões após correção
echo -e "${YELLOW}📋 Novas permissões:${NC}"
ls -la /var/run/docker.sock

# Verificar se o serviço autoscaler existe
echo -e "${YELLOW}🔍 Verificando serviço autoscaler...${NC}"
if docker service ls | grep -q "autoscaler-n8n_autoscaler"; then
    echo -e "${GREEN}✅ Serviço encontrado${NC}"
    
    # Verificar montagem do volume
    echo -e "${YELLOW}📋 Verificando montagem do Docker socket...${NC}"
    MOUNT_INFO=$(docker service inspect autoscaler-n8n_autoscaler --format '{{.Spec.TaskTemplate.ContainerSpec.Mounts}}' 2>/dev/null || echo "")
    
    if [[ $MOUNT_INFO == *"/var/run/docker.sock"* ]]; then
        echo -e "${GREEN}✅ Docker socket está montado corretamente${NC}"
    else
        echo -e "${RED}❌ Docker socket não está montado${NC}"
        echo -e "${YELLOW}🔧 Adicionando montagem do Docker socket...${NC}"
        
        docker service update \
            --mount-add type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock,readonly=true \
            autoscaler-n8n_autoscaler
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Montagem adicionada com sucesso${NC}"
        else
            echo -e "${RED}❌ Erro ao adicionar montagem${NC}"
        fi
    fi
    
    # Reiniciar o serviço para aplicar as mudanças
    echo -e "${YELLOW}🔄 Reiniciando serviço autoscaler...${NC}"
    docker service update --force autoscaler-n8n_autoscaler
    
    echo -e "${YELLOW}⏳ Aguardando reinicialização...${NC}"
    sleep 10
    
    # Verificar status após reinicialização
    echo -e "${YELLOW}📊 Status do serviço:${NC}"
    docker service ps autoscaler-n8n_autoscaler --no-trunc
    
else
    echo -e "${RED}❌ Serviço autoscaler-n8n_autoscaler não encontrado${NC}"
    echo -e "${YELLOW}💡 Execute o deploy primeiro:${NC}"
    echo "docker stack deploy -c stack-n8n-integration.yaml autoscaler-n8n"
fi

echo ""
echo -e "${BLUE}📋 Comandos para verificar se funcionou:${NC}"
echo "1. Ver logs: docker service logs -f autoscaler-n8n_autoscaler"
echo "2. Status: docker service ps autoscaler-n8n_autoscaler"
echo "3. Teste: docker exec -it \$(docker ps -q -f name=autoscaler) docker version"

echo ""
echo -e "${GREEN}🎉 Correção concluída!${NC}"
echo -e "${YELLOW}📝 Se o problema persistir, verifique o TROUBLESHOOTING.md${NC}"