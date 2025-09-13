#!/bin/bash

# 🧪 Comandos de Teste do Autoscaler - VERSÃO CORRIGIDA
# Problema identificado: autoscaler monitora 'bull:jobs:wait' mas jobs eram adicionados em 'bull:jobs:waiting'

echo "🔍 DIAGNÓSTICO DO PROBLEMA ENCONTRADO:"
echo "❌ Autoscaler monitora: bull:jobs:wait"
echo "❌ Jobs eram adicionados em: bull:jobs:waiting"
echo "✅ CORREÇÃO: Adicionar jobs na fila correta!"
echo "==========================================\n"

# Encontrar container Redis
REDIS_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i redis | head -1)
echo "📦 Container Redis encontrado: $REDIS_CONTAINER"

if [ -z "$REDIS_CONTAINER" ]; then
    echo "❌ Nenhum container Redis encontrado!"
    exit 1
fi

# Testar conexão Redis
echo "🔗 Testando conexão com Redis..."
docker exec "$REDIS_CONTAINER" redis-cli ping

if [ $? -ne 0 ]; then
    echo "❌ Falha na conexão com Redis!"
    exit 1
fi

echo "✅ Redis conectado com sucesso!\n"

# Verificar filas existentes
echo "📊 Verificando filas existentes..."
docker exec "$REDIS_CONTAINER" redis-cli -n 2 KEYS "bull:jobs:*" | sort
echo ""

# Função para verificar tamanho da fila correta
check_queue_size() {
    local size=$(docker exec "$REDIS_CONTAINER" redis-cli -n 2 LLEN "bull:jobs:wait")
    echo "📊 Tamanho atual da fila (bull:jobs:wait): $size jobs"
    return $size
}

# Função para verificar réplicas
check_replicas() {
    echo "🔄 Verificando réplicas do N8N Worker..."
    docker service ls | grep n8n_worker
    local replicas=$(docker service ls --format "{{.Replicas}}" --filter "name=n8n_n8n_worker")
    echo "📈 Réplicas configuradas: $replicas"
}

# Função para adicionar jobs na fila CORRETA
add_test_jobs_correct() {
    local count=$1
    echo "📈 Adicionando $count jobs de teste na fila CORRETA (bull:jobs:wait)..."
    
    for i in $(seq 1 $count); do
        # Adicionar na fila que o autoscaler está monitorando
        docker exec "$REDIS_CONTAINER" redis-cli -n 2 LPUSH "bull:jobs:wait" "{\"id\":\"test-job-$i\",\"data\":{\"test\":true,\"timestamp\":\"$(date -Iseconds)\",\"job_number\":$i}}"
        
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
current_size=$(docker exec "$REDIS_CONTAINER" redis-cli -n 2 LLEN "bull:jobs:wait")
if [ "$current_size" -gt 20 ]; then
    echo "🔄 Fila ainda tem $current_size jobs. Aguardando mais 30 segundos..."
    sleep 30
    echo "\n📊 VERIFICAÇÃO FINAL:"
    check_queue_size
    check_replicas
    show_autoscaler_logs
fi

echo "\n✅ Teste corrigido concluído!"
echo "📝 Para continuar monitorando:"
echo "   - Logs: docker service logs -f autoscaler-n8n_autoscaler"
echo "   - Réplicas: watch -n 5 'docker service ls | grep n8n_worker'"
echo "   - Fila CORRETA: docker exec $REDIS_CONTAINER redis-cli -n 2 LLEN bull:jobs:wait"
echo "\n🎯 DIFERENÇA IMPORTANTE:"
echo "   ❌ Antes: bull:jobs:waiting (fila errada)"
echo "   ✅ Agora: bull:jobs:wait (fila que o autoscaler monitora)"