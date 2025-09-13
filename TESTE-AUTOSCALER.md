# 🧪 Guia de Testes do Autoscaler

Como testar se o autoscaler está funcionando corretamente.

## 📊 1. Verificar Status dos Serviços

### Verificar se todos os serviços estão rodando:
```bash
# Listar todos os serviços da stack
docker service ls | grep autoscaler-n8n

# Verificar réplicas atuais do N8N Worker
docker service ls | grep n8n_worker

# Status detalhado dos serviços
docker service ps autoscaler-n8n_autoscaler
docker service ps autoscaler-n8n_redis-monitor
```

## 📝 2. Monitorar Logs em Tempo Real

### Logs do Autoscaler:
```bash
# Acompanhar logs do autoscaler
docker service logs -f autoscaler-n8n_autoscaler

# Logs das últimas 50 linhas
docker service logs --tail 50 autoscaler-n8n_autoscaler
```

### Logs do Redis Monitor:
```bash
# Acompanhar logs do monitor
docker service logs -f autoscaler-n8n_redis-monitor
```

### O que procurar nos logs:
- ✅ `"Conectado com sucesso ao daemon Docker"`
- ✅ `"Autoscaler iniciado. Monitorando serviço..."`
- ✅ `"Fila atual: X jobs"`
- ✅ `"Réplicas atuais: X"`

## 🔥 3. Simular Carga para Testar Escalabilidade

### Método 1: Via N8N Interface
1. Acesse o N8N
2. Crie um workflow simples que adicione jobs na fila
3. Execute múltiplas vezes rapidamente
4. Monitore os logs do autoscaler

### Método 2: Via Redis CLI (Simulação Direta)
```bash
# Conectar ao Redis
docker exec -it $(docker ps -q -f name=redis) redis-cli

# Dentro do Redis CLI:
# Selecionar database 2 (onde estão as filas do N8N)
SELECT 2

# Verificar filas existentes
KEYS bull:*

# Adicionar jobs fictícios na fila (simular carga)
LPUSH bull:jobs:waiting '{"id":"test1","data":{"test":true}}'
LPUSH bull:jobs:waiting '{"id":"test2","data":{"test":true}}'
LPUSH bull:jobs:waiting '{"id":"test3","data":{"test":true}}'

# Verificar tamanho da fila
LLEN bull:jobs:waiting

# Adicionar muitos jobs de uma vez (para testar scale up)
for i in {1..25}; do LPUSH bull:jobs:waiting "{\"id\":\"test$i\",\"data\":{\"test\":true}}"; done

# Sair do Redis CLI
exit
```

### Método 3: Script de Teste Automatizado
```bash
# Criar script de teste
cat > test-autoscaler.sh << 'EOF'
#!/bin/bash

echo "🧪 Iniciando teste do autoscaler..."

# Função para adicionar jobs
add_jobs() {
    local count=$1
    echo "📈 Adicionando $count jobs na fila..."
    
    for i in $(seq 1 $count); do
        docker exec $(docker ps -q -f name=redis) redis-cli -n 2 LPUSH bull:jobs:waiting "{\"id\":\"test$i\",\"data\":{\"test\":true}}"
    done
}

# Função para verificar fila
check_queue() {
    local size=$(docker exec $(docker ps -q -f name=redis) redis-cli -n 2 LLEN bull:jobs:waiting)
    echo "📊 Tamanho atual da fila: $size jobs"
    return $size
}

# Função para verificar réplicas
check_replicas() {
    local replicas=$(docker service inspect n8n_n8n_worker --format '{{.Spec.Mode.Replicated.Replicas}}')
    echo "🔄 Réplicas atuais do N8N Worker: $replicas"
}

# Teste 1: Scale Up
echo "\n🚀 TESTE 1: Scale Up"
check_queue
check_replicas
add_jobs 25
check_queue
echo "⏳ Aguardando 60 segundos para o autoscaler reagir..."
sleep 60
check_replicas

# Teste 2: Scale Down (limpar fila)
echo "\n📉 TESTE 2: Scale Down"
echo "🧹 Limpando fila..."
docker exec $(docker ps -q -f name=redis) redis-cli -n 2 DEL bull:jobs:waiting
check_queue
echo "⏳ Aguardando 5 minutos para cooldown e scale down..."
sleep 300
check_replicas

echo "\n✅ Teste concluído! Verifique os logs para mais detalhes."
EOF

# Tornar executável
chmod +x test-autoscaler.sh

# Executar teste
./test-autoscaler.sh
```

## 📈 4. Comandos de Monitoramento

### Verificar Réplicas em Tempo Real:
```bash
# Monitorar mudanças nas réplicas
watch -n 5 'docker service ls | grep n8n_worker'

# Verificar tasks do serviço N8N Worker
watch -n 5 'docker service ps n8n_n8n_worker'
```

### Verificar Uso de Recursos:
```bash
# CPU e Memória dos containers
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Recursos específicos do autoscaler
docker stats $(docker ps -q -f name=autoscaler)
```

### Verificar Conectividade Redis:
```bash
# Testar conexão Redis
docker exec $(docker ps -q -f name=autoscaler) ping redis

# Verificar se consegue acessar Redis
docker exec $(docker ps -q -f name=redis) redis-cli ping
```

## 🎯 5. Cenários de Teste

### Cenário 1: Scale Up Básico
1. **Estado inicial:** 1 réplica do N8N Worker
2. **Ação:** Adicionar 25+ jobs na fila
3. **Resultado esperado:** Aumento para 2-3 réplicas em ~60 segundos
4. **Verificação:** `docker service ls | grep n8n_worker`

### Cenário 2: Scale Down
1. **Estado inicial:** Múltiplas réplicas rodando
2. **Ação:** Limpar fila ou aguardar processamento
3. **Resultado esperado:** Redução para MIN_REPLICAS após cooldown (5 min)
4. **Verificação:** Logs mostram "Scaling down"

### Cenário 3: Limite Máximo
1. **Estado inicial:** Qualquer número de réplicas
2. **Ação:** Adicionar 100+ jobs na fila
3. **Resultado esperado:** Não passar de MAX_REPLICAS (10)
4. **Verificação:** Logs mostram "Maximum replicas reached"

## 🚨 6. Indicadores de Problemas

### ❌ Sinais de que NÃO está funcionando:
- Logs param de aparecer
- Erro "Failed to connect to Redis"
- Erro "Service not found"
- Réplicas não mudam mesmo com fila cheia
- Timeout errors

### ✅ Sinais de que ESTÁ funcionando:
- Logs regulares a cada 30 segundos
- "Fila atual: X jobs" aparece nos logs
- Réplicas aumentam quando fila > 20 jobs
- Réplicas diminuem quando fila < 5 jobs
- "Scaling up/down" aparece nos logs

## 📋 7. Checklist de Verificação

- [ ] Todos os serviços estão rodando (autoscaler, redis-monitor, docker-api-proxy)
- [ ] Logs do autoscaler mostram conexão com Redis e Docker
- [ ] Consegue ver tamanho da fila nos logs
- [ ] Réplicas aumentam com carga alta (>20 jobs)
- [ ] Réplicas diminuem com carga baixa (<5 jobs)
- [ ] Respeita limites MIN_REPLICAS e MAX_REPLICAS
- [ ] Cooldown funciona (não escala muito rápido)

## 🔧 8. Troubleshooting Rápido

```bash
# Se não estiver funcionando, execute:

# 1. Verificar se serviços estão saudáveis
docker service ps autoscaler-n8n_autoscaler --no-trunc

# 2. Reiniciar autoscaler
docker service update --force autoscaler-n8n_autoscaler

# 3. Verificar variáveis de ambiente
docker service inspect autoscaler-n8n_autoscaler --format '{{.Spec.TaskTemplate.ContainerSpec.Env}}'

# 4. Testar conectividade manual
docker exec -it $(docker ps -q -f name=autoscaler) ping redis
docker exec -it $(docker ps -q -f name=autoscaler) ping docker-api-proxy
```

---

**💡 Dica:** Mantenha os logs abertos em um terminal separado enquanto executa os testes para ver as reações em tempo real!