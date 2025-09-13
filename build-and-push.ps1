# Script PowerShell para build e push automático para Docker Hub
# Incrementa automaticamente a versão baseada na última tag

param(
    [string]$DockerUsername = "cyborgsolutionstech"  # Altere para seu usuário
)

# Configurações
$RepoMonitor = "$DockerUsername/n8n-redis-monitor"
$RepoAutoscaler = "$DockerUsername/n8n-autoscaler"

# Função para escrever mensagens coloridas
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Função para obter a próxima versão
function Get-NextVersion {
    param([string]$Repo)
    
    Write-ColorOutput "Verificando última versão de $Repo..." "Blue"
    
    try {
        # Obter tags do repositório
        $response = Invoke-RestMethod -Uri "https://registry.hub.docker.com/v2/repositories/$Repo/tags/?page_size=100"
        $tags = $response.results | Where-Object { $_.name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.name } | Select-Object -Last 1
        
        if (-not $tags) {
            Write-ColorOutput "Nenhuma versão encontrada. Iniciando com 1.0.0" "Yellow"
            return "1.0.0"
        }
        
        $lastVersion = $tags.name
        Write-ColorOutput "Última versão encontrada: $lastVersion" "Green"
        
        # Incrementar patch version
        $versionParts = $lastVersion.Split('.')
        $major = [int]$versionParts[0]
        $minor = [int]$versionParts[1]
        $patch = [int]$versionParts[2] + 1
        
        $newVersion = "$major.$minor.$patch"
        Write-ColorOutput "Nova versão: $newVersion" "Green"
        return $newVersion
    }
    catch {
        Write-ColorOutput "Erro ao verificar versões. Usando 1.0.0" "Yellow"
        return "1.0.0"
    }
}

# Função para build e push
function Build-AndPush {
    param(
        [string]$Context,
        [string]$Repo,
        [string]$Version
    )
    
    Write-ColorOutput "Building $Repo`:$Version..." "Blue"
    
    # Build da imagem
    $buildResult = docker build -t "$Repo`:$Version" -t "$Repo`:latest" $Context
    
    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "Build concluído com sucesso!" "Green"
        
        # Push das imagens
        Write-ColorOutput "Fazendo push para Docker Hub..." "Blue"
        docker push "$Repo`:$Version"
        docker push "$Repo`:latest"
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "Push concluído com sucesso!" "Green"
            Write-ColorOutput "Imagem disponível: $Repo`:$Version" "Green"
            return $true
        }
        else {
            Write-ColorOutput "Erro no push da imagem" "Red"
            return $false
        }
    }
    else {
        Write-ColorOutput "Erro no build da imagem" "Red"
        return $false
    }
}

# Verificar se Docker está rodando
try {
    docker info | Out-Null
}
catch {
    Write-ColorOutput "Docker não está rodando ou não está instalado" "Red"
    exit 1
}

# Verificar se está logado no Docker Hub
$dockerInfo = docker info 2>$null
if (-not ($dockerInfo -match "Username")) {
    Write-ColorOutput "Fazendo login no Docker Hub..." "Yellow"
    docker login
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "Falha no login do Docker Hub" "Red"
        exit 1
    }
}

Write-ColorOutput "=== Build e Push Automático para Docker Hub ===" "Blue"
Write-ColorOutput "Repositórios:" "Blue"
Write-ColorOutput "  - Monitor: $RepoMonitor" "White"
Write-ColorOutput "  - Autoscaler: $RepoAutoscaler" "White"
Write-ColorOutput ""

# Build do Redis Monitor
Write-ColorOutput "=== REDIS MONITOR ===" "Yellow"
$MonitorVersion = Get-NextVersion $RepoMonitor
$monitorSuccess = Build-AndPush "./monitor" $RepoMonitor $MonitorVersion
Write-ColorOutput ""

if (-not $monitorSuccess) {
    Write-ColorOutput "Falha no build/push do Redis Monitor" "Red"
    exit 1
}

# Build do Autoscaler
Write-ColorOutput "=== N8N AUTOSCALER ===" "Yellow"
$AutoscalerVersion = Get-NextVersion $RepoAutoscaler
$autoscalerSuccess = Build-AndPush "./autoscaler" $RepoAutoscaler $AutoscalerVersion
Write-ColorOutput ""

if (-not $autoscalerSuccess) {
    Write-ColorOutput "Falha no build/push do N8N Autoscaler" "Red"
    exit 1
}

Write-ColorOutput "=== BUILD E PUSH CONCLUÍDOS ===" "Green"
Write-ColorOutput "Versões publicadas:" "Green"
Write-ColorOutput "  - $RepoMonitor`:$MonitorVersion" "White"
Write-ColorOutput "  - $RepoAutoscaler`:$AutoscalerVersion" "White"
Write-ColorOutput ""
Write-ColorOutput "Para usar as novas versões, atualize o stack.yaml:" "Blue"
Write-ColorOutput "  redis-monitor: image: $RepoMonitor`:$MonitorVersion" "White"
Write-ColorOutput "  n8n-autoscaler: image: $RepoAutoscaler`:$AutoscalerVersion" "White"

# Criar arquivo com as versões para referência
$versionInfo = @"
Últimas versões publicadas em $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'):

Redis Monitor: $RepoMonitor:$MonitorVersion
N8N Autoscaler: $RepoAutoscaler:$AutoscalerVersion

Para atualizar o stack.yaml:
services:
  redis-monitor:
    image: $RepoMonitor:$MonitorVersion
  n8n-autoscaler:
    image: $RepoAutoscaler:$AutoscalerVersion
"@

$versionInfo | Out-File -FilePath "./last-versions.txt" -Encoding UTF8
Write-ColorOutput "Informações das versões salvas em last-versions.txt" "Blue"