#!/bin/bash

# 🔍 Script de Debug do Redis e Filas N8N
# Para identificar por que a fila está sempre vazia

echo "🔍 DIAGNÓSTICO COMPLETO DO REDIS E FILAS"
echo "========================================"

# Função para encontrar container Redis
find_redis_container() {
    echo "📦 Procurando container Redis..."
    
    # Tentar diferentes padrões de nome
    local redis_names=("redis" "n8n_redis" "n8n-redis" "redis-server")
    
    for name in "${redis_names[@]}"; do
        local container=$(docker ps --format "{{.Names}}" | grep -i "$name" | head -1)
        if [ -n "$container" ]; then
            echo "✅ Container Redis encontrado: $container"
            echo "$container"
            return 0
        fi
    done
    
    echo "❌ Nenhum container Redis encontrado!"
    echo "📋 Containers disponíveis:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    return 1
}

# Função para testar conectividade Redis
test_redis_connection() {
    local container=$1
    echo "\n🔗 Testando conectividade Redis..."
    
    if docker exec "$container" redis-cli ping > /dev/null 2>&1; then
        echo "✅ Redis respondendo ao PING"
        return 0
    else
        echo "❌ Redis não está respondendo!"
        return 1
    fi
}

# Função para explorar databases Redis
explore_redis_databases() {
    local container=$1
    echo "\n📊 Explorando databases Redis..."
    
    for db in {0..15}; do
        local keys=$(docker exec "$container" redis-cli -n $db DBSIZE 2>/dev/null)
        if [ "$keys" != "0" ] && [ -n "$keys" ]; then
            echo "📁 Database $db: $keys chaves"
            echo "   Chaves existentes:"
            docker exec "$container" redis-cli -n $db KEYS "*" | head -10
            if [ "$keys" -gt 10 ]; then
                echo "   ... e mais $((keys - 10)) chaves"
            fi
        fi
    done
}

# Função para verificar filas Bull específicas
check_bull_queues() {
    local container=$1
    echo "\n🎯 Verificando filas Bull no database 2..."
    
    # Verificar se database 2 existe e tem dados
    local db2_size=$(docker exec "$container" redis-cli -n 2 DBSIZE)
    echo "📊 Database 2 tem $db2_size chaves"
    
    if [ "$db2_size" -gt 0 ]; then
        echo "\n🔍 Chaves existentes no database 2:"
        docker exec "$container" redis-cli -n 2 KEYS "*" | sort
        
        echo "\n🎯 Filas Bull encontradas:"
        docker exec "$container" redis-cli -n 2 KEYS "bull:*" | sort
        
        # Verificar tamanhos das filas
        local bull_keys=$(docker exec "$container" redis-cli -n 2 KEYS "bull:*")
        if [ -n "$bull_keys" ]; then
            echo "\n📏 Tamanhos das filas:"
            while IFS= read -r key; do
                if [[ "$key" == *":waiting" ]] || [[ "$key" == *":active" ]] || [[ "$key" == *":completed" ]] || [[ "$key" == *":failed" ]]; then
                    local size=$(docker exec "$container" redis-cli -n 2 LLEN "$key" 2>/dev/null)
                    if [ -n "$size" ]; then
                        echo "   $key: $size items"
                    fi
                fi
            done <<< "$bull_keys"
        fi
    else
        echo "⚠️  Database 2 está vazio - pode ser o problema!"
    fi
}

# Função para criar fila de teste
create_test_queue() {
    local container=$1
    echo "\n🧪 Criando fila de teste..."
    
    # Tentar diferentes nomes de fila que o N8N pode usar
    local queue_names=("bull:jobs:waiting" "bull:default:waiting" "bull:n8n:waiting" "bull:workflow:waiting")
    
    for queue_name in "${queue_names[@]}"; do
        echo "📝 Testando fila: $queue_name"
        
        # Adicionar job de teste
        docker exec "$container" redis-cli -n 2 LPUSH "$queue_name" "{\"id\":\"test-$(date +%s)\",\"data\":{\"test\":true,\"timestamp\":\"$(date -Iseconds)\"}}"
        
        # Verificar se foi adicionado
        local size=$(docker exec "$container" redis-cli -n 2 LLEN "$queue_name")
        echo "   ✅ Fila $queue_name agora tem $size items"
        
        # Aguardar um pouco e verificar se o autoscaler detectou
        sleep 5
        
        # Verificar novamente
        local new_size=$(docker exec "$container" redis-cli -n 2 LLEN "$queue_name")
        if [ "$new_size" != "$size" ]; then
            echo "   🔄 Fila processada! Tamanho mudou de $size para $new_size"
        else
            echo "   ⏳ Fila ainda com $new_size items (aguardando processamento)"
        fi
    done
}

# Função para verificar configuração do autoscaler
check_autoscaler_config() {
    echo "\n⚙️  Verificando configuração do autoscaler..."
    
    # Verificar variáveis de ambiente do autoscaler
    local autoscaler_service="autoscaler-n8n_autoscaler"
    
    if docker service ls | grep -q "$autoscaler_service"; then
        echo "📋 Variáveis de ambiente do autoscaler:"
        docker service inspect "$autoscaler_service" --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' | grep -E "REDIS|QUEUE"
    else
        echo "❌ Serviço autoscaler não encontrado!"
        echo "📋 Serviços disponíveis:"
        docker service ls | grep -i autoscaler
    fi
}

# Função principal
main() {
    # Encontrar container Redis
    local redis_container
    redis_container=$(find_redis_container)
    
    if [ $? -ne 0 ]; then
        echo "❌ Não foi possível encontrar o container Redis. Abortando."
        exit 1
    fi
    
    # Testar conectividade
    if ! test_redis_connection "$redis_container"; then
        echo "❌ Redis não está acessível. Abortando."
        exit 1
    fi
    
    # Explorar databases
    explore_redis_databases "$redis_container"
    
    # Verificar filas Bull
    check_bull_queues "$redis_container"
    
    # Verificar configuração do autoscaler
    check_autoscaler_config
    
    # Criar filas de teste
    create_test_queue "$redis_container"
    
    echo "\n✅ DIAGNÓSTICO CONCLUÍDO!"
    echo "\n💡 PRÓXIMOS PASSOS:"
    echo "1. Verifique os logs do autoscaler: docker service logs -f autoscaler-n8n_autoscaler"
    echo "2. Monitore as filas: watch -n 5 'docker exec $redis_container redis-cli -n 2 KEYS \"bull:*\"'"
    echo "3. Se ainda não funcionar, verifique se o N8N está configurado para usar o database 2 do Redis"
}

# Executar diagnóstico
main