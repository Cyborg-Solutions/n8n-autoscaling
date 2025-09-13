# Notificações Webhook do Autoscaler

O autoscaler do N8N agora suporta notificações webhook que são enviadas sempre que ocorre um evento de escalonamento (scale up ou scale down).

## Configuração

### Variáveis de Ambiente

Para habilitar as notificações webhook, configure as seguintes variáveis de ambiente:

```bash
# URL do endpoint que receberá as notificações
WEBHOOK_URL=https://seu-endpoint.com/webhook/autoscaler

# Token de autenticação (enviado no header Authorization: Bearer)
WEBHOOK_TOKEN=seu-token-secreto-aqui
```

### No Docker Stack

No arquivo `stack-n8n-traefik.yaml`, as variáveis já estão configuradas:

```yaml
environment:
  # ... outras variáveis ...
  # Configuração de Webhook (opcional)
  - WEBHOOK_URL=https://seu-endpoint.com/webhook/autoscaler
  - WEBHOOK_TOKEN=seu-token-secreto
```

## Formato da Notificação

Quando um evento de escalonamento ocorre, o autoscaler envia um POST request para a URL configurada com o seguinte payload JSON:

```json
{
  "action": "scale_up",           // "scale_up" ou "scale_down"
  "service_name": "n8n_n8n_worker", // Nome do serviço escalado
  "old_replicas": 2,              // Número anterior de réplicas
  "new_replicas": 3,              // Novo número de réplicas
  "queue_length": 25,             // Tamanho atual da fila
  "timestamp": 1704067200.123     // Timestamp Unix da operação
}
```

### Headers HTTP

```
Content-Type: application/json
Authorization: Bearer seu-token-secreto
```

## Exemplos de Uso

### 1. Webhook Simples com Node.js/Express

```javascript
const express = require('express');
const app = express();

app.use(express.json());

// Middleware de autenticação
app.use('/webhook/autoscaler', (req, res, next) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (token !== process.env.WEBHOOK_TOKEN) {
    return res.status(401).json({ error: 'Token inválido' });
  }
  next();
});

// Endpoint do webhook
app.post('/webhook/autoscaler', (req, res) => {
  const { action, service_name, old_replicas, new_replicas, queue_length } = req.body;
  
  console.log(`🔄 Escalonamento detectado:`);
  console.log(`   Ação: ${action}`);
  console.log(`   Serviço: ${service_name}`);
  console.log(`   Réplicas: ${old_replicas} → ${new_replicas}`);
  console.log(`   Fila: ${queue_length} jobs`);
  
  // Aqui você pode:
  // - Enviar notificação para Slack/Discord
  // - Salvar no banco de dados
  // - Enviar email
  // - Atualizar dashboard
  
  res.status(200).json({ status: 'received' });
});

app.listen(3000);
```

### 2. Integração com Slack

```javascript
const { WebClient } = require('@slack/web-api');
const slack = new WebClient(process.env.SLACK_TOKEN);

app.post('/webhook/autoscaler', async (req, res) => {
  const { action, service_name, old_replicas, new_replicas, queue_length } = req.body;
  
  const emoji = action === 'scale_up' ? '📈' : '📉';
  const color = action === 'scale_up' ? 'good' : 'warning';
  
  await slack.chat.postMessage({
    channel: '#infrastructure',
    attachments: [{
      color: color,
      title: `${emoji} Autoscaler - ${action.replace('_', ' ').toUpperCase()}`,
      fields: [
        { title: 'Serviço', value: service_name, short: true },
        { title: 'Réplicas', value: `${old_replicas} → ${new_replicas}`, short: true },
        { title: 'Fila', value: `${queue_length} jobs`, short: true },
        { title: 'Timestamp', value: new Date().toLocaleString(), short: true }
      ]
    }]
  });
  
  res.status(200).json({ status: 'received' });
});
```

### 3. Salvando em Banco de Dados

```javascript
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

app.post('/webhook/autoscaler', async (req, res) => {
  const { action, service_name, old_replicas, new_replicas, queue_length, timestamp } = req.body;
  
  try {
    await prisma.scalingEvent.create({
      data: {
        action,
        serviceName: service_name,
        oldReplicas: old_replicas,
        newReplicas: new_replicas,
        queueLength: queue_length,
        timestamp: new Date(timestamp * 1000)
      }
    });
    
    console.log('Evento de escalonamento salvo no banco de dados');
    res.status(200).json({ status: 'saved' });
  } catch (error) {
    console.error('Erro ao salvar evento:', error);
    res.status(500).json({ error: 'Erro interno' });
  }
});
```

## Configuração Opcional

As notificações webhook são **opcionais**. Se as variáveis `WEBHOOK_URL` e `WEBHOOK_TOKEN` não estiverem configuradas, o autoscaler funcionará normalmente sem enviar notificações.

## Tratamento de Erros

O autoscaler possui tratamento robusto de erros para webhooks:

- **Timeout**: 10 segundos
- **Retry**: Não há retry automático (para evitar spam)
- **Logs**: Erros são logados mas não interrompem o funcionamento do autoscaler
- **Status codes**: Apenas 200 é considerado sucesso

## Segurança

1. **Sempre use HTTPS** para a URL do webhook
2. **Valide o token** no seu endpoint
3. **Use tokens seguros** (pelo menos 32 caracteres aleatórios)
4. **Implemente rate limiting** no seu endpoint se necessário
5. **Monitore logs** para detectar tentativas de acesso não autorizado

## Troubleshooting

### Webhook não está sendo chamado

1. Verifique se `WEBHOOK_URL` e `WEBHOOK_TOKEN` estão configurados
2. Verifique os logs do autoscaler para erros de conexão
3. Teste a conectividade de rede do container do autoscaler

### Recebendo 401/403

1. Verifique se o token está correto
2. Verifique se o header `Authorization` está sendo validado corretamente

### Timeout

1. Verifique se o endpoint responde em menos de 10 segundos
2. Otimize o processamento no seu webhook
3. Considere processamento assíncrono para operações demoradas

## Exemplo de Teste

Para testar o webhook localmente:

```bash
# Use ngrok para expor seu servidor local
ngrok http 3000

# Configure o WEBHOOK_URL com a URL do ngrok
WEBHOOK_URL=https://abc123.ngrok.io/webhook/autoscaler
WEBHOOK_TOKEN=test-token-123

# Execute o autoscaler e force um escalonamento
./test-commands-fixed.sh
```