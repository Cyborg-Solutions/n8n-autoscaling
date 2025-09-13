#!/bin/bash

# 🧪 Comandos de Teste do Autoscaler - Versão Corrigida
# Para usar em ambiente de produção

echo "🔍 Verificando containers Redis disponíveis..."

# Método 1: Encontrar container Redis corretamente
REDIS_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i redis | head -1)
echo "📦 Container Redis encontrado: $REDIS_CONTAINER"

if [ -z "$REDIS_CONTAINER" ]; then
    echo "❌ Nenhum container Redis encontrado!"
    echo "📋 Containers disponíveis:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    exit 1
fi

# Método 2: Testar conexão Redis primeiro
echo "🔗 Testando conexão com Redis..."
docker exec "$REDIS_CONTAINER" redis-cli ping

if [ $? -ne 0 ]; then
    echo "❌ Falha na conexão com Redis!"
    exit 1
fi

echo "✅ Redis conectado com sucesso!"

# Método 3: Verificar database e filas existentes
echo "📊 Verificando filas existentes..."
docker exec "$REDIS_CONTAINER" redis-cli -n 2 KEYS "bull:*"

# Método 4: Função para adicionar jobs de forma segura
add_test_jobs() {
    local count=$1
    echo "📈 Adicionando $count jobs de teste na fila..."
    
    for i in $(seq 1 $count); do
        docker exec "$REDIS_CONTAINER" redis-cli -n 2 LPUSH "bull:jobs:waiting" "{\"id\":\"test$i\",\"data\":{\"test\":true},\"timestamp\":\"$(date -Iseconds)\"}"
        if [ $((i % 5)) -eq 0 ]; then
            echo "  ✓ $i jobs adicionados..."
        fi
    done
    
    echo "✅ $count jobs adicionados com sucesso!"
}

# Método 5: Função para verificar tamanho da fila
check_queue_size() {
    local size=$(docker exec "$REDIS_CONTAINER" redis-cli -n 2 LLEN "bull:jobs:waiting")
    echo "📊 Tamanho atual da fila: $size jobs"
    return $size
}

# Método 6: Função para verificar réplicas do N8N
check_n8n_replicas() {
    echo "🔄 Verificando réplicas do N8N Worker..."
    docker service ls | grep n8n_worker
    
    # Tentar diferentes nomes de serviço
    local service_name=""
    if docker service ls | grep -q "n8n_n8n_worker"; then
        service_name="n8n_n8n_worker"
    elif docker service ls | grep -q "n8n_worker"; then
        service_name="n8n_worker"
    elif docker service ls | grep -q "n8n-worker"; then
        service_name="n8n-worker"
    fi
    
    if [ -n "$service_name" ]; then
        local replicas=$(docker service inspect "$service_name" --format '{{.Spec.Mode.Replicated.Replicas}}' 2>/dev/null)
        echo "📈 Réplicas configuradas: $replicas"
        
        local running=$(docker service ps "$service_name" --filter "desired-state=running" --format "{{.Name}}" | wc -l)
        echo "🏃 Réplicas rodando: $running"
    else
        echo "⚠️  Serviço N8N Worker não encontrado!"
    fi
}

# Método 7: Função para monitorar logs do autoscaler
check_autoscaler_logs() {
    echo "📝 Últimos logs do autoscaler:"
    
    # Tentar diferentes nomes de serviço do autoscaler
    if docker service ls | grep -q "autoscaler-n8n_autoscaler"; then
        docker service logs --tail 10 autoscaler-n8n_autoscaler
    elif docker service ls | grep -q "autoscaler_autoscaler"; then
        docker service logs --tail 10 autoscaler_autoscaler
    elif docker service ls | grep -q "autoscaler"; then
        docker service logs --tail 10 autoscaler
    else
        echo "⚠️  Serviço autoscaler não encontrado!"
        echo "📋 Serviços disponíveis:"
        docker service ls
    fi
}

# Executar testes
echo "\n🚀 INICIANDO TESTES DO AUTOSCALER"
echo "================================="

# Verificar estado inicial
echo "\n📊 ESTADO INICIAL:"
check_queue_size
check_n8n_replicas

# Adicionar jobs para testar scale up
echo "\n📈 TESTE DE SCALE UP:"
add_test_jobs 25
check_queue_size

echo "\n⏳ Aguardando 60 segundos para o autoscaler reagir..."
echo "💡 Dica: Abra outro terminal e execute: docker service logs -f autoscaler-n8n_autoscaler"
sleep 60

echo "\n📊 ESTADO APÓS 60 SEGUNDOS:"
check_queue_size
check_n8n_replicas
check_autoscaler_logs

echo "\n✅ Teste concluído!"
echo "📝 Para continuar monitorando:"
echo "   - Logs: docker service logs -f autoscaler-n8n_autoscaler"
echo "   - Réplicas: watch -n 5 'docker service ls | grep n8n_worker'"
echo "   - Fila: docker exec $REDIS_CONTAINER redis-cli -n 2 LLEN bull:jobs:waiting"