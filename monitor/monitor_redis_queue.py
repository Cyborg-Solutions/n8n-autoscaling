import redis
import time
import os

REDIS_HOST = os.getenv('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', None)
QUEUE_NAME_PREFIX = os.getenv('QUEUE_NAME_PREFIX', 'bull') # BullMQ default prefix
QUEUE_NAME = os.getenv('QUEUE_NAME', 'jobs')
POLL_INTERVAL_SECONDS = int(os.getenv('POLL_INTERVAL_SECONDS', 5))

def get_redis_connection():
    """Estabelece uma conexão com o Redis."""
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD, decode_responses=True)
        r.ping()
        print(f"Conectado com sucesso ao Redis em {REDIS_HOST}:{REDIS_PORT}")
        return r
    except redis.exceptions.ConnectionError as e:
        print(f"Erro ao conectar com o Redis: {e}")
        return None

def get_queue_length(r_conn, queue_name_prefix, queue_name):
    """Obtém o comprimento da fila BullMQ especificada."""
    # BullMQ armazena listas para diferentes estados de uma fila.
    # 'wait' (ou a lista principal da fila) é geralmente o que as pessoas querem dizer com "comprimento da fila"
    # Normalmente é nomeada "bull:<queue_name>:wait" ou apenas "bull:<queue_name>" para versões mais antigas
    # ou às vezes apenas <queue_name_prefix>:<queue_name>
    # Também verificaremos 'active', 'delayed', 'completed', 'failed' para dar uma visão mais completa.

    # A lista principal representando jobs pendentes é geralmente <prefix>:<queue_name>:wait
    # No entanto, LLEN em <prefix>:<queue_name> em si frequentemente também dá a contagem de jobs aguardando.
    # Vamos tentar o mais comum para jobs "aguardando".
    # BullMQ v3+ usa <prefix>:<queue_name>:wait para jobs aguardando
    # BullMQ v4+ usa <prefix>:<queue_name>:waiting para jobs aguardando
    # Abordagem mais simples: BullMQ também mantém uma lista nomeada apenas <prefix>:<queue_name>
    # que frequentemente corresponde à lista 'waiting' ou é um bom proxy.
    
    # Para BullMQ, a chave para a lista de jobs aguardando é tipicamente `<prefix>:<queue_name>:wait`
    # ou para versões mais novas `<prefix>:<queue_name>:waiting`.
    # O comando `LLEN <prefix>:<queue_name>` frequentemente dá a contagem de jobs aguardando.
    # Vamos tentar obter o comprimento da lista principal para a fila.
    # Chaves de fila BullMQ são tipicamente prefixadas, ex., "bull:myQueueName:id"
    # A lista real de jobs aguardando é frequentemente "bull:myQueueName:wait" ou "bull:myQueueName:waiting"
    # No entanto, n8n pode usar uma nomenclatura mais simples. O comando `KEYS` mostrou `bull:jobs:active` etc.
    # Isso implica que o nome base da fila é `jobs` e o prefixo é `bull`.
    # A lista de jobs aguardando é tipicamente `bull:<queue_name>:wait`.
    
    # Baseado na saída do `KEYS "bull:*:*"`, `bull:jobs:active` e chaves similares existem.
    # A lista de jobs *aguardando* é o que nos interessa.
    # Isso é tipicamente `bull:<queue_name>:wait` ou `bull:<queue_name>:waiting`.
    # Vamos tentar `LLEN bull:jobs:wait`
    key_to_check = f"{queue_name_prefix}:{queue_name}:wait"
    try:
        length = r_conn.llen(key_to_check)
        if length is None: # Se a chave não existe, llen pode retornar None ou um erro dependendo da versão do cliente
             # Tenta o padrão mais antigo se :wait não existe
            key_to_check_legacy = f"{queue_name_prefix}:{queue_name}"
            length = r_conn.llen(key_to_check_legacy)
            if length is not None:
                print(f"Nota: Usando padrão de chave legado '{key_to_check_legacy}' para comprimento da fila.")
                key_to_check = key_to_check_legacy # update for logging
            else:
                 # Se nenhuma existe, pode ser 0 ou um problema.
                 # Vamos também verificar a chave usada pelo BullMQ v4+
                key_to_check_v4 = f"{queue_name_prefix}:{queue_name}:waiting"
                length = r_conn.llen(key_to_check_v4)
                if length is not None:
                    print(f"Nota: Usando padrão de chave BullMQ v4+ '{key_to_check_v4}' para comprimento da fila.")
                    key_to_check = key_to_check_v4
                else:
                    print(f"Aviso: Chave '{key_to_check}', '{key_to_check_legacy}', ou '{key_to_check_v4}' não encontrada ou não é uma lista. Assumindo comprimento 0.")
                    return 0
        return length
    except redis.exceptions.ResponseError as e:
        # Isso pode acontecer se a chave existe mas não é do tipo lista
        print(f"Erro do Redis ao verificar comprimento de '{key_to_check}': {e}. Assumindo comprimento 0.")
        return 0
    except Exception as e:
        print(f"Erro inesperado ao verificar comprimento de '{key_to_check}': {e}. Assumindo comprimento 0.")
        return 0


if __name__ == "__main__":
    redis_conn = get_redis_connection()
    if redis_conn:
        print(f"Monitorando fila Redis '{QUEUE_NAME_PREFIX}:{QUEUE_NAME}' a cada {POLL_INTERVAL_SECONDS} segundos...")
        print("Pressione Ctrl+C para parar.")
        try:
            while True:
                length = get_queue_length(redis_conn, QUEUE_NAME_PREFIX, QUEUE_NAME)
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Comprimento da fila '{QUEUE_NAME_PREFIX}:{QUEUE_NAME}:wait': {length}")
                time.sleep(POLL_INTERVAL_SECONDS)
        except KeyboardInterrupt:
            print("\nMonitoramento interrompido pelo usuário.")
        finally:
            redis_conn.close()
            print("Conexão Redis fechada.")