#!/usr/bin/env python3
"""
Script de teste para verificar a funcionalidade de verificação de recursos
do autoscaler Docker Swarm.

Este script demonstra como as funções de verificação de recursos funcionam
sem executar o autoscaler completo.
"""

import docker
import logging
import sys
import os

# Configurar logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def test_swarm_connection():
    """Test Docker Swarm connection."""
    try:
        client = docker.from_env()
        client.ping()
        
        # Verificar se está em modo Swarm
        info = client.info()
        if 'Swarm' not in info or info['Swarm']['LocalNodeState'] != 'active':
            logging.error("Docker não está em modo Swarm ou nó não está ativo")
            return None
            
        logging.info("Conexão com Docker Swarm estabelecida com sucesso")
        return client
    except Exception as e:
        logging.error(f"Erro ao conectar com Docker: {e}")
        return None

def test_resource_functions(client, service_name):
    """Test resource checking functions."""
    try:
        # Importar as funções do autoscaler
        sys.path.append(os.path.join(os.path.dirname(__file__), 'autoscaler'))
        from autoscaler_swarm import get_swarm_resources, get_service_resource_limits, check_resources_for_scaling
        
        logging.info("=== Testando Verificação de Recursos ===")
        
        # Testar obtenção de recursos do Swarm
        logging.info("1. Obtendo recursos do Swarm...")
        swarm_resources = get_swarm_resources(client)
        if swarm_resources:
            logging.info(f"   CPU Total: {swarm_resources['total_cpu_cores']:.2f} cores")
            logging.info(f"   Memória Total: {swarm_resources['total_memory_gb']:.2f} GB")
            logging.info(f"   CPU Disponível: {swarm_resources['available_cpu_cores']:.2f} cores")
            logging.info(f"   Memória Disponível: {swarm_resources['available_memory_gb']:.2f} GB")
        else:
            logging.warning("   Não foi possível obter recursos do Swarm")
        
        # Testar obtenção de limites do serviço
        logging.info(f"\n2. Obtendo limites do serviço '{service_name}'...")
        service_limits = get_service_resource_limits(client, service_name)
        if service_limits:
            cpu_limit = service_limits['cpu_limit_cores']
            memory_limit = service_limits['memory_limit_gb']
            logging.info(f"   Limite de CPU: {cpu_limit if cpu_limit else 'Não definido'} cores")
            logging.info(f"   Limite de Memória: {memory_limit if memory_limit else 'Não definido'} GB")
        else:
            logging.warning("   Não foi possível obter limites do serviço")
        
        # Testar verificação para escalonamento
        logging.info("\n3. Testando verificação para escalonamento...")
        for additional_replicas in [1, 2, 5]:
            logging.info(f"\n   Testando {additional_replicas} réplica(s) adicional(is):")
            can_scale = check_resources_for_scaling(client, service_name, additional_replicas)
            result = "PERMITIDO" if can_scale else "BLOQUEADO"
            logging.info(f"   Resultado: {result}")
        
        logging.info("\n=== Teste Concluído ===")
        
    except ImportError as e:
        logging.error(f"Erro ao importar funções do autoscaler: {e}")
    except Exception as e:
        logging.error(f"Erro durante o teste: {e}")

def main():
    """Main test function."""
    service_name = os.getenv('N8N_WORKER_SERVICE_NAME', 'n8n-worker')
    
    logging.info(f"Iniciando teste de verificação de recursos para o serviço: {service_name}")
    
    # Testar conexão
    client = test_swarm_connection()
    if not client:
        logging.error("Não foi possível estabelecer conexão com Docker Swarm")
        return 1
    
    # Verificar se o serviço existe
    try:
        service = client.services.get(service_name)
        logging.info(f"Serviço '{service_name}' encontrado")
    except docker.errors.NotFound:
        logging.error(f"Serviço '{service_name}' não encontrado no Swarm")
        logging.info("Certifique-se de que o serviço está rodando e o nome está correto")
        return 1
    except Exception as e:
        logging.error(f"Erro ao verificar serviço: {e}")
        return 1
    
    # Executar testes
    test_resource_functions(client, service_name)
    
    return 0

if __name__ == "__main__":
    exit(main())