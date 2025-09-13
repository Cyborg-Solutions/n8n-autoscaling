import os
import time
import redis
import docker
import logging
from dotenv import load_dotenv

load_dotenv()

# --- Configuração de Logging ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Configuração das Variáveis de Ambiente ---
REDIS_HOST = os.getenv('REDIS_HOST')
REDIS_PORT = int(os.getenv('REDIS_PORT'))
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD')
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

last_scale_time = 0

def get_redis_connection():
    """Establishes a connection to Redis."""
    logging.info(f"Conectando ao Redis em {REDIS_HOST}:{REDIS_PORT}")
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD, decode_responses=True)

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
                    last_scale_time = current_time
                    scaled = True
            elif queue_len < SCALE_DOWN_QUEUE_THRESHOLD and current_reps > MIN_REPLICAS:
                new_replicas = max(current_reps - 1, MIN_REPLICAS)
                logging.info(f"Condição atendida para ESCALAR PARA BAIXO. Fila: {queue_len} < {SCALE_DOWN_QUEUE_THRESHOLD}. Réplicas: {current_reps} > {MIN_REPLICAS}.")
                if scale_service_swarm(docker_cl, N8N_WORKER_SERVICE_NAME, new_replicas):
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