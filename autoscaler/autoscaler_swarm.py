import os
import time
import redis
import docker
import logging
import requests
import json
import socket
import platform
import psutil
from dotenv import load_dotenv

load_dotenv()

# --- Configuração de Logging ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Configuração das Variáveis de Ambiente ---
REDIS_HOST = os.getenv('REDIS_HOST')
REDIS_PORT = int(os.getenv('REDIS_PORT'))
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD')
REDIS_DB = int(os.getenv('REDIS_DB', 0))  # Database Redis (padrão 0)
QUEUE_NAME_PREFIX = os.getenv('QUEUE_NAME_PREFIX')
QUEUE_NAME = os.getenv('QUEUE_NAME')

# Nome do serviço Docker Swarm (não mais projeto Docker Compose)
N8N_WORKER_SERVICE_NAME = os.getenv('N8N_WORKER_SERVICE_NAME')

MIN_REPLICAS = int(os.getenv('MIN_REPLICAS'))
MAX_REPLICAS = int(os.getenv('MAX_REPLICAS'))
SCALE_UP_QUEUE_THRESHOLD = int(os.getenv('SCALE_UP_QUEUE_THRESHOLD'))
SCALE_DOWN_QUEUE_THRESHOLD = int(os.getenv('SCALE_DOWN_QUEUE_THRESHOLD'))

POLLING_INTERVAL_SECONDS = int(os.getenv('POLLING_INTERVAL_SECONDS'))
COOLDOWN_PERIOD_SECONDS = int(os.getenv('COOLDOWN_PERIOD_SECONDS'))

# Configuração de Webhook
WEBHOOK_URL = os.getenv('WEBHOOK_URL')
WEBHOOK_TOKEN = os.getenv('WEBHOOK_TOKEN')

last_scale_time = 0

def get_server_info():
    """Collect comprehensive server information including system specs and resource usage."""
    try:
        # Get basic system information
        hostname = socket.gethostname()
        
        # Get local IP address
        try:
            # Connect to a remote address to determine local IP
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
        except Exception:
            local_ip = "127.0.0.1"
        
        # Get platform information
        system_info = {
            "system": platform.system(),
            "release": platform.release(),
            "version": platform.version(),
            "machine": platform.machine(),
            "processor": platform.processor(),
            "architecture": platform.architecture()[0],
            "python_version": platform.python_version()
        }
        
        # Get CPU information
        cpu_percent = psutil.cpu_percent(interval=1)
        cpu_count = psutil.cpu_count()
        
        # Get memory information
        memory = psutil.virtual_memory()
        memory_total_gb = round(memory.total / (1024**3), 2)
        memory_used_gb = round(memory.used / (1024**3), 2)
        memory_percent = round(memory.percent, 2)
        
        # Get disk information
        disk = psutil.disk_usage('/')
        disk_total_gb = round(disk.total / (1024**3), 2)
        disk_used_gb = round(disk.used / (1024**3), 2)
        disk_percent = round((disk.used / disk.total) * 100, 2)
        
        server_info = {
            "hostname": hostname,
            "local_ip": local_ip,
            "platform": f"{system_info['system']} {system_info['release']} ({system_info['architecture']})",
            "processor": system_info['processor'] or f"{system_info['machine']} processor",
            "python_version": system_info['python_version'],
            "cpu_count": cpu_count,
            "cpu_percent": cpu_percent,
            "memory_total_gb": memory_total_gb,
            "memory_used_gb": memory_used_gb,
            "memory_percent": memory_percent,
            "disk_total_gb": disk_total_gb,
            "disk_used_gb": disk_used_gb,
            "disk_percent": disk_percent
        }
        
        logging.debug(f"Informações do servidor coletadas: {hostname} ({local_ip})")
        return server_info
        
    except Exception as e:
        logging.error(f"Erro ao coletar informações do servidor: {e}")
        return {
            "hostname": "unknown",
            "local_ip": "unknown",
            "platform": "unknown",
            "processor": "unknown",
            "python_version": "unknown",
            "cpu_count": 0,
            "cpu_percent": 0,
            "memory_total_gb": 0,
            "memory_used_gb": 0,
            "memory_percent": 0,
            "disk_total_gb": 0,
            "disk_used_gb": 0,
            "disk_percent": 0
        }

def send_webhook_notification(action, service_name, old_replicas, new_replicas, queue_length):
    """Sends a webhook notification when scaling occurs."""
    if not WEBHOOK_URL:
        logging.debug("Webhook não configurado. Pulando notificação.")
        return
    
    try:
        # Collect server information
        server_info = get_server_info()
        
        payload = {
            "action": action,  # "scale_up" ou "scale_down"
            "service_name": service_name,
            "old_replicas": old_replicas,
            "new_replicas": new_replicas,
            "queue_length": queue_length,
            "timestamp": time.time(),
            "server_info": server_info
        }
        
        headers = {
            "Content-Type": "application/json"
        }
        
        # Add authorization header if token is provided
        if WEBHOOK_TOKEN:
            headers["Authorization"] = f"Bearer {WEBHOOK_TOKEN}"
        
        response = requests.post(
            WEBHOOK_URL,
            data=json.dumps(payload),
            headers=headers,
            timeout=10
        )
        
        if response.status_code == 200:
            logging.info(f"Notificação webhook enviada com sucesso para {action}: {old_replicas} -> {new_replicas} réplicas")
        else:
            logging.warning(f"Webhook retornou status {response.status_code}: {response.text}")
            
    except requests.exceptions.RequestException as e:
        logging.error(f"Erro ao enviar notificação webhook: {e}")
    except Exception as e:
        logging.error(f"Erro inesperado ao enviar webhook: {e}")

def get_redis_connection():
    """Establishes a connection to Redis."""
    logging.info(f"Conectando ao Redis em {REDIS_HOST}:{REDIS_PORT} (database {REDIS_DB})")
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD, db=REDIS_DB, decode_responses=True)

def get_queue_length(r_conn):
    """Gets the length of the specified BullMQ waiting queue."""
    key_to_check = f"{QUEUE_NAME_PREFIX}:{QUEUE_NAME}:wait"
    length = None
    try:
        length = r_conn.llen(key_to_check)
        if length is not None:
            return length
        
        # Tentar padrão BullMQ v4+
        key_to_check_v4 = f"{QUEUE_NAME_PREFIX}:{QUEUE_NAME}:waiting"
        length = r_conn.llen(key_to_check_v4)
        if length is not None:
            logging.info(f"Usando padrão de chave BullMQ v4+ '{key_to_check_v4}' para comprimento da fila.")
            return length

        # Tentar padrão legado
        key_to_check_legacy = f"{QUEUE_NAME_PREFIX}:{QUEUE_NAME}"
        length = r_conn.llen(key_to_check_legacy)
        if length is not None:
            logging.info(f"Usando padrão de chave legado '{key_to_check_legacy}' para comprimento da fila.")
            return length
        
        logging.warning(f"Padrões de chave da fila ('{key_to_check}', '{key_to_check_v4}', '{key_to_check_legacy}') não encontrados ou não são listas. Assumindo comprimento 0.")
        return 0
    except redis.exceptions.ResponseError as e:
        logging.error(f"Erro do Redis ao verificar comprimento das chaves da fila: {e}. Assumindo comprimento 0.")
        return 0
    except Exception as e:
        logging.error(f"Erro inesperado ao verificar comprimento da fila: {e}. Assumindo comprimento 0.")
        return 0

def get_current_replicas_swarm(docker_client, service_name):
    """Gets the current number of replicas for a Docker Swarm service."""
    try:
        service = docker_client.services.get(service_name)
        current_replicas = service.attrs['Spec']['Mode']['Replicated']['Replicas']
        logging.info(f"Serviço '{service_name}' possui {current_replicas} réplicas configuradas.")
        return current_replicas
    except docker.errors.NotFound:
        logging.error(f"Serviço '{service_name}' não encontrado no Docker Swarm.")
        return 0
    except KeyError as e:
        logging.error(f"Erro ao acessar configuração de réplicas do serviço '{service_name}': {e}")
        return 0
    except Exception as e:
        logging.error(f"Erro inesperado ao obter réplicas do serviço '{service_name}': {e}")
        return 0

def get_running_tasks_count(docker_client, service_name):
    """Gets the actual number of running tasks for a Docker Swarm service."""
    try:
        service = docker_client.services.get(service_name)
        tasks = service.tasks()
        
        running_count = 0
        for task in tasks:
            if task['Status']['State'] == 'running':
                running_count += 1
        
        logging.info(f"Serviço '{service_name}' possui {running_count} tarefas em execução.")
        return running_count
    except docker.errors.NotFound:
        logging.error(f"Serviço '{service_name}' não encontrado no Docker Swarm.")
        return 0
    except Exception as e:
        logging.error(f"Erro ao obter tarefas em execução do serviço '{service_name}': {e}")
        return 0

def scale_service_swarm(docker_client, service_name, replicas):
    """Scales a Docker Swarm service to the specified number of replicas."""
    try:
        service = docker_client.services.get(service_name)
        
        # Atualizar o serviço com o novo número de réplicas
        service.update(
            mode={'Replicated': {'Replicas': replicas}}
        )
        
        logging.info(f"Serviço '{service_name}' escalado para {replicas} réplicas com sucesso.")
        return True
        
    except docker.errors.NotFound:
        logging.error(f"Serviço '{service_name}' não encontrado no Docker Swarm.")
        return False
    except docker.errors.APIError as e:
        logging.error(f"Erro da API Docker ao escalar serviço '{service_name}' para {replicas} réplicas: {e}")
        return False
    except Exception as e:
        logging.error(f"Erro inesperado ao escalar serviço '{service_name}' para {replicas} réplicas: {e}")
        return False

def main():
    global last_scale_time
    
    if not N8N_WORKER_SERVICE_NAME:
        logging.error("CRÍTICO: Variável de ambiente N8N_WORKER_SERVICE_NAME não está definida. O autoscaler não pode funcionar corretamente.")
        logging.error("Por favor, defina N8N_WORKER_SERVICE_NAME com o nome do serviço Docker Swarm.")
        return

    try:
        r_conn = get_redis_connection()
        docker_cl = docker.from_env()
        # Testar conexão Docker
        docker_cl.ping()
        logging.info("Conectado com sucesso ao daemon Docker.")
    except Exception as e:
        logging.error(f"CRÍTICO: Falha ao conectar ao Redis ou Docker: {e}")
        return

    logging.info(f"Autoscaler iniciado. Monitorando serviço n8n worker '{N8N_WORKER_SERVICE_NAME}' no Docker Swarm.")
    logging.info(f"  Réplicas Mínimas: {MIN_REPLICAS}, Réplicas Máximas: {MAX_REPLICAS}")
    logging.info(f"  Limite para Escalar Para Cima: >{SCALE_UP_QUEUE_THRESHOLD}")
    logging.info(f"  Limite para Escalar Para Baixo: <{SCALE_DOWN_QUEUE_THRESHOLD}")
    logging.info(f"  Intervalo de Polling: {POLLING_INTERVAL_SECONDS}s, Cooldown: {COOLDOWN_PERIOD_SECONDS}s")

    while True:
        try:
            current_time = time.time()
            if (current_time - last_scale_time) < COOLDOWN_PERIOD_SECONDS:
                remaining_cooldown = COOLDOWN_PERIOD_SECONDS - (current_time - last_scale_time)
                logging.info(f"Em período de cooldown. Próxima verificação em {remaining_cooldown:.0f}s.")
                time.sleep(POLLING_INTERVAL_SECONDS)
                continue

            queue_len = get_queue_length(r_conn)
            current_reps = get_current_replicas_swarm(docker_cl, N8N_WORKER_SERVICE_NAME)
            running_tasks = get_running_tasks_count(docker_cl, N8N_WORKER_SERVICE_NAME)

            logging.info(f"Comprimento da Fila: {queue_len}, Réplicas Configuradas: {current_reps}, Tarefas Executando: {running_tasks}")

            scaled = False
            if queue_len > SCALE_UP_QUEUE_THRESHOLD and current_reps < MAX_REPLICAS:
                new_replicas = min(current_reps + 1, MAX_REPLICAS)
                logging.info(f"Condição atendida para ESCALAR PARA CIMA. Fila: {queue_len} > {SCALE_UP_QUEUE_THRESHOLD}. Réplicas: {current_reps} < {MAX_REPLICAS}.")
                if scale_service_swarm(docker_cl, N8N_WORKER_SERVICE_NAME, new_replicas):
                    send_webhook_notification("scale_up", N8N_WORKER_SERVICE_NAME, current_reps, new_replicas, queue_len)
                    last_scale_time = current_time
                    scaled = True
            elif queue_len < SCALE_DOWN_QUEUE_THRESHOLD and current_reps > MIN_REPLICAS:
                new_replicas = max(current_reps - 1, MIN_REPLICAS)
                logging.info(f"Condição atendida para ESCALAR PARA BAIXO. Fila: {queue_len} < {SCALE_DOWN_QUEUE_THRESHOLD}. Réplicas: {current_reps} > {MIN_REPLICAS}.")
                if scale_service_swarm(docker_cl, N8N_WORKER_SERVICE_NAME, new_replicas):
                    send_webhook_notification("scale_down", N8N_WORKER_SERVICE_NAME, current_reps, new_replicas, queue_len)
                    last_scale_time = current_time
                    scaled = True
            
            if not scaled:
                logging.info("Nenhuma ação de escalonamento necessária.")

        except redis.exceptions.ConnectionError as e:
            logging.error(f"Erro de conexão Redis: {e}. Tentando reconectar...")
            time.sleep(5)
            try:
                r_conn = get_redis_connection()
            except Exception as recon_e:
                logging.error(f"Falha ao reconectar ao Redis: {recon_e}")
        except Exception as e:
            logging.error(f"Erro no loop principal do autoscaler: {e}", exc_info=True)

        time.sleep(POLLING_INTERVAL_SECONDS)

if __name__ == "__main__":
    main()