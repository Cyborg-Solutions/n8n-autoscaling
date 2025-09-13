import os
import time
import redis
import docker
import subprocess
import logging
import requests
import json
import socket
import platform
import psutil
from dotenv import load_dotenv

load_dotenv()

# --- Logging Setup ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Configuration from Environment Variables ---
REDIS_HOST = os.getenv('REDIS_HOST')
REDIS_PORT = int(os.getenv('REDIS_PORT'))
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD') # Added for completeness
QUEUE_NAME_PREFIX = os.getenv('QUEUE_NAME_PREFIX')
QUEUE_NAME = os.getenv('QUEUE_NAME')

N8N_WORKER_SERVICE_NAME = os.getenv('N8N_WORKER_SERVICE_NAME')
COMPOSE_PROJECT_NAME = os.getenv('COMPOSE_PROJECT_NAME') # e.g., "n8n-workers"
COMPOSE_FILE_PATH = os.getenv('COMPOSE_FILE_PATH') # Path inside this container

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
    """Collects server information for webhook notifications."""
    try:
        # Basic server information
        hostname = socket.gethostname()
        
        # Try to get local IP address
        try:
            # Connect to a remote address to determine local IP
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
        except Exception:
            local_ip = "unknown"
        
        # System information
        system_info = {
            "hostname": hostname,
            "local_ip": local_ip,
            "platform": platform.platform(),
            "architecture": platform.architecture()[0],
            "processor": platform.processor() or "unknown",
            "python_version": platform.python_version()
        }
        
        # Resource information
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            system_info.update({
                "cpu_percent": round(cpu_percent, 2),
                "memory_total_gb": round(memory.total / (1024**3), 2),
                "memory_used_gb": round(memory.used / (1024**3), 2),
                "memory_percent": round(memory.percent, 2),
                "disk_total_gb": round(disk.total / (1024**3), 2),
                "disk_used_gb": round(disk.used / (1024**3), 2),
                "disk_percent": round((disk.used / disk.total) * 100, 2)
            })
        except Exception as e:
            logging.warning(f"Erro ao coletar informações de recursos: {e}")
            system_info.update({
                "cpu_percent": "unknown",
                "memory_total_gb": "unknown",
                "memory_used_gb": "unknown",
                "memory_percent": "unknown",
                "disk_total_gb": "unknown",
                "disk_used_gb": "unknown",
                "disk_percent": "unknown"
            })
        
        return system_info
        
    except Exception as e:
        logging.error(f"Erro ao coletar informações do servidor: {e}")
        return {
            "hostname": "unknown",
            "local_ip": "unknown",
            "platform": "unknown",
            "architecture": "unknown",
            "processor": "unknown",
            "python_version": "unknown",
            "cpu_percent": "unknown",
            "memory_total_gb": "unknown",
            "memory_used_gb": "unknown",
            "memory_percent": "unknown",
            "disk_total_gb": "unknown",
            "disk_used_gb": "unknown",
            "disk_percent": "unknown"
        }

def send_webhook_notification(action, service_name, old_replicas, new_replicas, queue_length):
    """Sends a webhook notification when scaling occurs with server information."""
    if not WEBHOOK_URL or not WEBHOOK_TOKEN:
        logging.debug("Webhook não configurado. Pulando notificação.")
        return
    
    try:
        # Get server information
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
            "Content-Type": "application/json",
            "Authorization": f"Bearer {WEBHOOK_TOKEN}"
        }
        
        response = requests.post(
            WEBHOOK_URL,
            data=json.dumps(payload),
            headers=headers,
            timeout=10
        )
        
        if response.status_code == 200:
            logging.info(f"Notificação webhook enviada com sucesso para {action}: {old_replicas} -> {new_replicas} réplicas")
            logging.info(f"Servidor: {server_info['hostname']} ({server_info['local_ip']})")
        else:
            logging.warning(f"Webhook retornou status {response.status_code}: {response.text}")
            
    except requests.exceptions.RequestException as e:
        logging.error(f"Erro ao enviar notificação webhook: {e}")
    except Exception as e:
        logging.error(f"Erro inesperado ao enviar webhook: {e}")

def get_redis_connection():
    """Establishes a connection to Redis."""
    logging.info(f"Connecting to Redis at {REDIS_HOST}:{REDIS_PORT}")
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD, decode_responses=True)

def get_queue_length(r_conn):
    """Gets the length of the specified BullMQ waiting queue."""
    key_to_check = f"{QUEUE_NAME_PREFIX}:{QUEUE_NAME}:wait"
    length = None
    try:
        length = r_conn.llen(key_to_check)
        if length is not None:
            return length
        
        # Try BullMQ v4+ pattern
        key_to_check_v4 = f"{QUEUE_NAME_PREFIX}:{QUEUE_NAME}:waiting"
        length = r_conn.llen(key_to_check_v4)
        if length is not None:
            logging.info(f"Using BullMQ v4+ key pattern '{key_to_check_v4}' for queue length.")
            return length

        # Try legacy pattern (sometimes just the queue name for older Bull versions or simple lists)
        key_to_check_legacy = f"{QUEUE_NAME_PREFIX}:{QUEUE_NAME}"
        length = r_conn.llen(key_to_check_legacy)
        if length is not None:
            logging.info(f"Using legacy key pattern '{key_to_check_legacy}' for queue length.")
            return length
        
        logging.warning(f"Queue key patterns ('{key_to_check}', '{key_to_check_v4}', '{key_to_check_legacy}') not found or not a list. Assuming length 0.")
        return 0
    except redis.exceptions.ResponseError as e:
        logging.error(f"Redis error when checking length of queue keys: {e}. Assuming length 0.")
        return 0
    except Exception as e:
        logging.error(f"Unexpected error checking queue length: {e}. Assuming length 0.")
        return 0


def get_current_replicas(docker_client, service_name, project_name):
    """Gets the current number of running containers for a Docker Compose service."""
    if not project_name:
        logging.warning("COMPOSE_PROJECT_NAME is not set. Cannot accurately determine current replicas.")
        # As a fallback, we might try to count containers based on service name label alone,
        # but this is unreliable if multiple projects use the same service name.
        # For now, return a high number to prevent unintended scaling if project name is missing.
        return MAX_REPLICAS + 1 # Prevents scaling if project name is missing

    try:
        filters = {
            "label": [
                f"com.docker.compose.service={service_name}",
                f"com.docker.compose.project={project_name}"
            ],
            "status": "running"
        }
        service_containers = docker_client.containers.list(filters=filters, all=True) # all=True to catch restarting ones too
        
        # Further filter by status in Python if 'status' filter is not precise enough
        running_count = 0
        for container in service_containers:
            if container.status == 'running':
                 running_count +=1
        logging.info(f"Found {running_count} running containers for service '{service_name}' in project '{project_name}'.")
        return running_count
    except Exception as e:
        logging.error(f"Error getting current replicas for {service_name} in {project_name}: {e}")
        return MAX_REPLICAS + 1 # Return a safe value to prevent scaling on error


def scale_service(service_name, replicas, compose_file, project_name):
    """Scales a Docker Compose service using docker-compose CLI."""
    if not project_name:
        logging.error("COMPOSE_PROJECT_NAME is not set. Cannot execute docker-compose scale.")
        return False

    command = [
        "docker",
        "compose",
        "-f", compose_file,
        "--project-name", project_name,
        "--project-directory", "/app",
        "up",
        "-d",
        "--no-deps",
        "--scale", f"{service_name}={replicas}",
        service_name
    ]
    logging.info(f"Executing scaling command: {' '.join(command)}")
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        logging.info(f"Scale command stdout: {result.stdout.strip()}")
        if result.stderr.strip():
             logging.warning(f"Scale command stderr: {result.stderr.strip()}")
        return True
    except subprocess.CalledProcessError as e:
        logging.error(f"Error scaling service {service_name} to {replicas}:")
        logging.error(f"  Command: {' '.join(e.cmd)}")
        logging.error(f"  Return Code: {e.returncode}")
        logging.error(f"  Stdout: {e.stdout.strip()}")
        logging.error(f"  Stderr: {e.stderr.strip()}")
        return False
    except FileNotFoundError:
        logging.error("docker-compose command not found. Ensure it's installed in the autoscaler container and in PATH.")
        return False

def main():
    global last_scale_time
    
    if not COMPOSE_PROJECT_NAME:
        logging.error("CRITICAL: COMPOSE_PROJECT_NAME environment variable is not set. Autoscaler cannot function correctly.")
        logging.error("Please set COMPOSE_PROJECT_NAME to the name of your Docker Compose project (usually the directory name).")
        return # Exit if critical env var is missing

    try:
        r_conn = get_redis_connection()
        docker_cl = docker.from_env()
        # Test Docker connection
        docker_cl.ping()
        logging.info("Successfully connected to Docker daemon.")
    except Exception as e:
        logging.error(f"CRITICAL: Failed to connect to Redis or Docker: {e}")
        return

    logging.info(f"Autoscaler started. Monitoring n8n worker service '{N8N_WORKER_SERVICE_NAME}' in project '{COMPOSE_PROJECT_NAME}'.")
    logging.info(f"  Min Replicas: {MIN_REPLICAS}, Max Replicas: {MAX_REPLICAS}")
    logging.info(f"  Scale Up Queue Threshold: >{SCALE_UP_QUEUE_THRESHOLD}")
    logging.info(f"  Scale Down Queue Threshold: <{SCALE_DOWN_QUEUE_THRESHOLD}")
    logging.info(f"  Polling Interval: {POLLING_INTERVAL_SECONDS}s, Cooldown: {COOLDOWN_PERIOD_SECONDS}s")

    while True:
        try:
            current_time = time.time()
            if (current_time - last_scale_time) < COOLDOWN_PERIOD_SECONDS:
                logging.info(f"In cooldown period. Next check in {COOLDOWN_PERIOD_SECONDS - (current_time - last_scale_time):.0f}s.")
                time.sleep(POLLING_INTERVAL_SECONDS) # Still sleep for polling interval
                continue

            queue_len = get_queue_length(r_conn)
            current_reps = get_current_replicas(docker_cl, N8N_WORKER_SERVICE_NAME, COMPOSE_PROJECT_NAME)

            logging.info(f"Queue Length: {queue_len}, Current Replicas: {current_reps}")

            scaled = False
            if queue_len > SCALE_UP_QUEUE_THRESHOLD and current_reps < MAX_REPLICAS:
                new_replicas = min(current_reps + 1, MAX_REPLICAS) # Scale one by one for now
                logging.info(f"Condition met for SCALE UP. Queue: {queue_len} > {SCALE_UP_QUEUE_THRESHOLD}. Replicas: {current_reps} < {MAX_REPLICAS}.")
                if scale_service(N8N_WORKER_SERVICE_NAME, new_replicas, COMPOSE_FILE_PATH, COMPOSE_PROJECT_NAME):
                    last_scale_time = current_time
                    scaled = True
                    send_webhook_notification("scale_up", N8N_WORKER_SERVICE_NAME, current_reps, new_replicas, queue_len)
            elif queue_len < SCALE_DOWN_QUEUE_THRESHOLD and current_reps > MIN_REPLICAS:
                new_replicas = max(current_reps - 1, MIN_REPLICAS) # Scale one by one
                logging.info(f"Condition met for SCALE DOWN. Queue: {queue_len} < {SCALE_DOWN_QUEUE_THRESHOLD}. Replicas: {current_reps} > {MIN_REPLICAS}.")
                if scale_service(N8N_WORKER_SERVICE_NAME, new_replicas, COMPOSE_FILE_PATH, COMPOSE_PROJECT_NAME):
                    last_scale_time = current_time
                    scaled = True
                    send_webhook_notification("scale_down", N8N_WORKER_SERVICE_NAME, current_reps, new_replicas, queue_len)
            
            if not scaled:
                logging.info("No scaling action needed.")

        except redis.exceptions.ConnectionError as e:
            logging.error(f"Redis connection error: {e}. Retrying connection...")
            time.sleep(5) # Wait before retrying Redis connection
            try:
                r_conn = get_redis_connection()
            except Exception as recon_e:
                logging.error(f"Failed to reconnect to Redis: {recon_e}")
        except Exception as e:
            logging.error(f"Error in autoscaler main loop: {e}", exc_info=True)

        time.sleep(POLLING_INTERVAL_SECONDS)

if __name__ == "__main__":
    main()