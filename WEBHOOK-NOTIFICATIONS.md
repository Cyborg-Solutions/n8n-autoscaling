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

### 4. Integração com PHP

#### Webhook Simples com PHP

```php
<?php
// webhook-autoscaler.php

// Verificar método HTTP
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Método não permitido']);
    exit;
}

// Verificar Content-Type
if (!isset($_SERVER['CONTENT_TYPE']) || $_SERVER['CONTENT_TYPE'] !== 'application/json') {
    http_response_code(400);
    echo json_encode(['error' => 'Content-Type deve ser application/json']);
    exit;
}

// Verificar token de autenticação
$headers = getallheaders();
if (!isset($headers['Authorization'])) {
    http_response_code(401);
    echo json_encode(['error' => 'Token de autorização necessário']);
    exit;
}

$token = str_replace('Bearer ', '', $headers['Authorization']);
if ($token !== $_ENV['WEBHOOK_TOKEN']) {
    http_response_code(401);
    echo json_encode(['error' => 'Token inválido']);
    exit;
}

// Ler payload JSON
$input = file_get_contents('php://input');
$data = json_decode($input, true);

if (json_last_error() !== JSON_ERROR_NONE) {
    http_response_code(400);
    echo json_encode(['error' => 'JSON inválido']);
    exit;
}

// Processar dados do webhook
$action = $data['action'];
$serviceName = $data['service_name'];
$oldReplicas = $data['old_replicas'];
$newReplicas = $data['new_replicas'];
$queueLength = $data['queue_length'];
$timestamp = $data['timestamp'];

// Log da notificação
error_log("🔄 Escalonamento detectado: {$action} - {$serviceName} ({$oldReplicas} → {$newReplicas})");

// Aqui você pode:
// - Salvar no banco de dados
// - Enviar email
// - Fazer POST para outro endpoint
// - Atualizar cache/dashboard

// Resposta de sucesso
http_response_code(200);
echo json_encode(['status' => 'received', 'timestamp' => time()]);
?>
```

#### PHP com Reenvio para Outro Endpoint

```php
<?php
// webhook-autoscaler-relay.php

require_once 'vendor/autoload.php'; // Se usar Composer

// ... código de autenticação anterior ...

// Processar dados do webhook
$webhookData = json_decode(file_get_contents('php://input'), true);

// Preparar payload customizado para reenvio
$relayPayload = [
    'event_type' => 'n8n_autoscaler',
    'action' => $webhookData['action'],
    'details' => [
        'service' => $webhookData['service_name'],
        'scaling' => [
            'from' => $webhookData['old_replicas'],
            'to' => $webhookData['new_replicas']
        ],
        'queue_size' => $webhookData['queue_length'],
        'occurred_at' => date('Y-m-d H:i:s', $webhookData['timestamp'])
    ],
    'metadata' => [
        'source' => 'n8n-autoscaler',
        'environment' => $_ENV['ENVIRONMENT'] ?? 'production',
        'processed_at' => date('Y-m-d H:i:s')
    ]
];

// Função para enviar POST
function sendWebhookNotification($url, $payload, $token = null) {
    $ch = curl_init();
    
    $headers = [
        'Content-Type: application/json',
        'User-Agent: N8N-Autoscaler-Webhook/1.0'
    ];
    
    if ($token) {
        $headers[] = "Authorization: Bearer {$token}";
    }
    
    curl_setopt_array($ch, [
        CURLOPT_URL => $url,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 10,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS => 3
    ]);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);
    
    return [
        'success' => $httpCode >= 200 && $httpCode < 300,
        'http_code' => $httpCode,
        'response' => $response,
        'error' => $error
    ];
}

// Enviar para múltiplos endpoints
$endpoints = [
    [
        'name' => 'Slack Webhook',
        'url' => $_ENV['SLACK_WEBHOOK_URL'],
        'token' => null // Slack usa URL com token embutido
    ],
    [
        'name' => 'Sistema de Monitoramento',
        'url' => $_ENV['MONITORING_WEBHOOK_URL'],
        'token' => $_ENV['MONITORING_TOKEN']
    ],
    [
        'name' => 'Dashboard Interno',
        'url' => $_ENV['DASHBOARD_WEBHOOK_URL'],
        'token' => $_ENV['DASHBOARD_TOKEN']
    ]
];

$results = [];

foreach ($endpoints as $endpoint) {
    if (empty($endpoint['url'])) {
        continue; // Pular endpoints não configurados
    }
    
    $result = sendWebhookNotification(
        $endpoint['url'],
        $relayPayload,
        $endpoint['token']
    );
    
    $results[$endpoint['name']] = $result;
    
    // Log do resultado
    if ($result['success']) {
        error_log("✅ Webhook enviado com sucesso para {$endpoint['name']}");
    } else {
        error_log("❌ Erro ao enviar webhook para {$endpoint['name']}: {$result['error']} (HTTP {$result['http_code']})");
    }
}

// Salvar no banco de dados (opcional)
try {
    $pdo = new PDO(
        "mysql:host={$_ENV['DB_HOST']};dbname={$_ENV['DB_NAME']}",
        $_ENV['DB_USER'],
        $_ENV['DB_PASS']
    );
    
    $stmt = $pdo->prepare("
        INSERT INTO autoscaler_events 
        (action, service_name, old_replicas, new_replicas, queue_length, occurred_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, NOW())
    ");
    
    $stmt->execute([
        $webhookData['action'],
        $webhookData['service_name'],
        $webhookData['old_replicas'],
        $webhookData['new_replicas'],
        $webhookData['queue_length'],
        date('Y-m-d H:i:s', $webhookData['timestamp'])
    ]);
    
    error_log("💾 Evento salvo no banco de dados");
    
} catch (PDOException $e) {
    error_log("❌ Erro ao salvar no banco: " . $e->getMessage());
}

// Resposta de sucesso
http_response_code(200);
echo json_encode([
    'status' => 'processed',
    'webhook_results' => $results,
    'timestamp' => time()
]);
?>
```

#### Configuração do Servidor Web (Apache/Nginx)

**Apache (.htaccess):**
```apache
RewriteEngine On
RewriteCond %{REQUEST_METHOD} !^POST$
RewriteRule ^webhook/autoscaler$ - [R=405,L]

# Redirecionar para o script PHP
RewriteRule ^webhook/autoscaler$ webhook-autoscaler.php [L]
```

**Nginx:**
```nginx
location /webhook/autoscaler {
    if ($request_method !~ ^(POST)$) {
        return 405;
    }
    
    try_files $uri /webhook-autoscaler.php;
    
    fastcgi_pass php-fpm;
    fastcgi_param SCRIPT_FILENAME $document_root/webhook-autoscaler.php;
    include fastcgi_params;
}
```

#### Variáveis de Ambiente PHP

Crie um arquivo `.env` para configuração:

```bash
# Autenticação
WEBHOOK_TOKEN=seu-token-secreto-aqui

# Banco de dados
DB_HOST=localhost
DB_NAME=monitoring
DB_USER=webhook_user
DB_PASS=senha_segura

# Endpoints para reenvio
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX
MONITORING_WEBHOOK_URL=https://monitoring.empresa.com/api/webhooks/autoscaler
MONITORING_TOKEN=token-do-sistema-monitoramento
DASHBOARD_WEBHOOK_URL=https://dashboard.empresa.com/api/events
DASHBOARD_TOKEN=token-do-dashboard

# Ambiente
ENVIRONMENT=production
```

#### Schema do Banco de Dados (MySQL)

```sql
CREATE TABLE autoscaler_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    action VARCHAR(20) NOT NULL,
    service_name VARCHAR(100) NOT NULL,
    old_replicas INT NOT NULL,
    new_replicas INT NOT NULL,
    queue_length INT NOT NULL,
    occurred_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL,
    INDEX idx_action (action),
    INDEX idx_service (service_name),
    INDEX idx_occurred_at (occurred_at)
);
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