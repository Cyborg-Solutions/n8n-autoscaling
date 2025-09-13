#!/bin/bash

# 🧪 Comandos de Teste do Autoscaler - VERSÃO CORRIGIDA
# Problema identificado: autoscaler monitora 'bull:jobs:wait' mas jobs eram adicionados em 'bull:jobs:waiting'

echo "🔍 DIAGNÓSTICO DO PROBLEMA ENCONTRADO:"
echo "❌ Autoscaler monitora: bull:jobs:wait"
echo "❌ Jobs eram adicionados em: bull:jobs:waiting"
echo "✅ CORREÇÃO: Adicionar jobs na fila correta!"
echo "==========================================\n"

# Encontrar container Redis correto
REDIS_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i redis | grep -v monitor | head -1)

# Se não encontrar, tentar por imagem
if [ -z "$REDIS_CONTAINER" ]; then
    REDIS_CONTAINER=$(docker ps --format "{{.Names}}" --filter "ancestor=redis" | head -1)
fi

echo "📦 Container Redis encontrado: $REDIS_CONTAINER"

if [ -z "$REDIS_CONTAINER" ]; then
    echo "❌ Nenhum container Redis encontrado!"
    echo "📋 Containers disponíveis:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    exit 1
fi

# Testar conexão Redis com métodos alternativos
echo "🔗 Testando conexão com Redis..."

# Método 1: Tentar redis-cli
if docker exec "$REDIS_CONTAINER" redis-cli ping > /dev/null 2>&1; then
    echo "✅ Redis conectado via redis-cli"
elif docker exec "$REDIS_CONTAINER" /usr/local/bin/redis-cli ping > /dev/null 2>&1; then
    echo "✅ Redis conectado via /usr/local/bin/redis-cli"
elif docker exec "$REDIS_CONTAINER" sh -c "echo 'PING' | nc localhost 6379" 2>/dev/null | grep -q "PONG"; then
    echo "✅ Redis conectado via netcat"
else
    echo "❌ Falha na conexão com Redis!"
    echo "📋 Tentando listar processos no container:"
    docker exec "$REDIS_CONTAINER" ps aux 2>/dev/null || echo "Não foi possível listar processos"
    exit 1
fi

echo "✅ Redis conectado com sucesso!\n"

# Verificar filas existentes
echo "📊 Verificando filas existentes..."
if docker exec "$REDIS_CONTAINER" redis-cli -n 2 KEYS "bull:jobs:*" 2>/dev/null | sort; then
    echo ""
elif docker exec "$REDIS_CONTAINER" /usr/local/bin/redis-cli -n 2 KEYS "bull:jobs:*" 2>/dev/null | sort; then
    echo ""
else
    echo "⚠️  Não foi possível listar filas (redis-cli não disponível)"
fi
echo ""

# Function to check queue size with fallback methods
check_queue_size() {
    local size
    
    # Tentar redis-cli primeiro
    if size=$(docker exec "$REDIS_CONTAINER" redis-cli -n 2 LLEN "bull:jobs:wait" 2>/dev/null); then
        echo "📊 Tamanho atual da fila (bull:jobs:wait): $size jobs"
        return $size
    elif size=$(docker exec "$REDIS_CONTAINER" /usr/local/bin/redis-cli -n 2 LLEN "bull:jobs:wait" 2>/dev/null); then
        echo "📊 Tamanho atual da fila (bull:jobs:wait): $size jobs"
        return $size
    else
        echo "⚠️  Não foi possível verificar tamanho da fila (redis-cli não disponível)"
        return 0
    fi
}

# Função para verificar réplicas
check_replicas() {
    echo "🔄 Verificando réplicas do N8N Worker..."
    docker service ls | grep n8n_worker
    local replicas=$(docker service ls --format "{{.Replicas}}" --filter "name=n8n_n8n_worker")
    echo "📈 Réplicas configuradas: $replicas"
}

# Function to add jobs to correct queue with fallback methods
add_test_jobs_correct() {
    local count=$1
    echo "📈 Adicionando $count jobs de teste na fila CORRETA (bull:jobs:wait)..."
    
    # Verificar qual método de redis-cli funciona
    local redis_cmd="redis-cli"
    if ! docker exec "$REDIS_CONTAINER" redis-cli ping > /dev/null 2>&1; then
        if docker exec "$REDIS_CONTAINER" /usr/local/bin/redis-cli ping > /dev/null 2>&1; then
            redis_cmd="/usr/local/bin/redis-cli"
        else
            echo "❌ redis-cli não disponível no container. Não é possível adicionar jobs."
            return 1
        fi
    fi
    
    for i in $(seq 1 $count); do
        # Adicionar na fila que o autoscaler está monitorando
        docker exec "$REDIS_CONTAINER" $redis_cmd -n 2 LPUSH "bull:jobs:wait" "{\"id\":\"test-job-$i\",\"data\":{\"test\":true,\"timestamp\":\"$(date -Iseconds)\",\"job_number\":$i}}"
        
        if [ $((i % 5)) -eq 0 ]; then
            echo "  ✓ $i jobs adicionados..."
        fi
    done
    
    echo "✅ $count jobs adicionados na fila CORRETA!"
}

# Função para mostrar logs do autoscaler
show_autoscaler_logs() {
    echo "📝 Últimos logs do autoscaler:"
    docker service logs --tail 10 autoscaler-n8n_autoscaler
}

# INÍCIO DOS TESTES
echo "🚀 INICIANDO TESTES CORRIGIDOS DO AUTOSCALER"
echo "============================================\n"

# Estado inicial
echo "📊 ESTADO INICIAL:"
check_queue_size
check_replicas
echo ""

# Teste de Scale Up
echo "📈 TESTE DE SCALE UP (CORRIGIDO):"
add_test_jobs_correct 25
check_queue_size
echo ""

# Aguardar reação do autoscaler
echo "⏳ Aguardando 60 segundos para o autoscaler reagir..."
echo "💡 Dica: Abra outro terminal e execute: docker service logs -f autoscaler-n8n_autoscaler"
echo "💡 Agora os jobs estão na fila CORRETA que o autoscaler monitora!"
sleep 60
echo ""

# Verificar resultado
echo "📊 ESTADO APÓS 60 SEGUNDOS:"
check_queue_size
check_replicas
show_autoscaler_logs
echo ""

# Teste adicional se ainda não escalou
if current_size=$(docker exec "$REDIS_CONTAINER" redis-cli -n 2 LLEN "bull:jobs:wait" 2>/dev/null) || current_size=$(docker exec "$REDIS_CONTAINER" /usr/local/bin/redis-cli -n 2 LLEN "bull:jobs:wait" 2>/dev/null); then
    if [ "$current_size" -gt 20 ]; then
        echo "🔄 Fila ainda tem $current_size jobs. Aguardando mais 30 segundos..."
        sleep 30
        echo "\n📊 VERIFICAÇÃO FINAL:"
        check_queue_size
        check_replicas
        show_autoscaler_logs
    fi
else
    echo "⚠️  Não foi possível verificar tamanho final da fila"
fi

echo "\n✅ Teste corrigido concluído!"
echo "📝 Para continuar monitorando:"
echo "   - Logs: docker service logs -f autoscaler-n8n_autoscaler"
echo "   - Réplicas: watch -n 5 'docker service ls | grep n8n_worker'"
echo "   - Fila CORRETA: docker exec $REDIS_CONTAINER redis-cli -n 2 LLEN bull:jobs:wait"
echo "   - Alternativo: docker exec $REDIS_CONTAINER /usr/local/bin/redis-cli -n 2 LLEN bull:jobs:wait"
echo "\n🎯 DIFERENÇA IMPORTANTE:"
echo "   ❌ Antes: bull:jobs:waiting (fila errada)"
echo "   ✅ Agora: bull:jobs:wait (fila que o autoscaler monitora)"