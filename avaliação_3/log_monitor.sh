#!/bin/bash

# Cores para destacar mensagens
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # Sem cor

# Arquivo de configuração
CONFIG_FILE="log_monitor.conf"

# Função para exibir ajuda
show_help() {
    echo -e "${GREEN}Uso do script:${NC}"
    echo -e "  ./log_monitor.sh"
    echo -e "\n${YELLOW}Descrição:${NC}"
    echo -e "  Este script permite monitorar logs locais e remotos em tempo real, com filtros por palavras-chave e destaque de eventos importantes."
    echo -e "  Use o menu interativo para selecionar opções."
}

# Função para carregar configurações
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        echo -e "${YELLOW}Arquivo de configuração não encontrado. Criando um novo...${NC}"
        echo -e "# Lista de arquivos de log a serem monitorados" > "$CONFIG_FILE"
        echo -e "log_files=(" >> "$CONFIG_FILE"
        echo -e "    \"/var/log/syslog\"" >> "$CONFIG_FILE"
        echo -e "    \"/var/log/auth.log\"" >> "$CONFIG_FILE"
        echo -e ")" >> "$CONFIG_FILE"
        echo -e "\n# Palavras-chave para filtro" >> "$CONFIG_FILE"
        echo -e "keywords=(\"error\" \"warning\" \"failed\")" >> "$CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
}

# Função para validar arquivos de log
validate_log_files() {
    local log_files=("${!1}")
    for file in "${log_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo -e "${RED}Erro: Arquivo de log não encontrado: $file${NC}"
            return 1
        fi
    done
    return 0
}

# Função para validar endereço remoto
validate_remote_host() {
    local remote_host="$1"
    if [[ ! "$remote_host" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}Erro: Endereço remoto inválido. Use o formato 'user@host'.${NC}"
        return 1
    fi
    return 0
}

# Função para testar conexão SSH
test_ssh_connection() {
    local remote_host="$1"
    echo -e "${YELLOW}Testando conexão com $remote_host...${NC}"
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote_host" echo > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Erro: Não foi possível conectar ao servidor remoto.${NC}"
        return 1
    fi
    echo -e "${GREEN}Conexão SSH bem-sucedida.${NC}"
    return 0
}

# Função para monitorar logs
monitor_logs() {
    local log_files=("${!1}")
    local keywords=("${!2}")
    local regex_filter=""
    local output_file=""

    echo -e "${GREEN}Iniciando monitoramento de logs...${NC}"
    echo -e "${BLUE}Arquivos de log: ${log_files[*]}${NC}"
    echo -e "${BLUE}Palavras-chave: ${keywords[*]}${NC}"

    # Perguntar ao usuário se deseja salvar os logs filtrados
    read -p "Deseja salvar os logs filtrados em um arquivo? (s/n): " save_logs
    if [[ "$save_logs" == "s" ]]; then
        read -p "Digite o nome do arquivo de saída: " output_file
        echo -e "${YELLOW}Os logs filtrados serão salvos em: $output_file${NC}"
    fi

    # Construir regex para filtro
    for keyword in "${keywords[@]}"; do
        regex_filter+="$keyword|"
    done
    regex_filter="${regex_filter%|}"  # Remover o último |

    # Monitorar logs em tempo real
    if [[ -n "$output_file" ]]; then
        tail -f "${log_files[@]}" | grep --line-buffered -E --color=always "$regex_filter" | tee "$output_file"
    else
        tail -f "${log_files[@]}" | grep --line-buffered -E --color=always "$regex_filter"
    fi
}

# Função para monitorar logs remotos via SSH
monitor_remote_logs() {
    echo -e "${GREEN}Conectar a um servidor remoto para monitorar logs.${NC}"
    read -p "Digite o endereço do servidor remoto (user@host): " remote_host

    # Validar endereço remoto
    validate_remote_host "$remote_host" || return 1

    # Testar conexão SSH
    test_ssh_connection "$remote_host" || return 1

    echo -e "${YELLOW}Arquivos de log disponíveis no servidor remoto:${NC}"
    echo -e "1. /var/log/syslog"
    echo -e "2. /var/log/auth.log"
    echo -e "3. /var/log/nginx/access.log"
    echo -e "4. /var/log/nginx/error.log"
    echo -e "5. Personalizado (digite o caminho completo)"
    read -p "Selecione os arquivos de log (separados por espaço): " log_choices

    log_files=()
    for choice in $log_choices; do
        case $choice in
            1) log_files+=("/var/log/syslog") ;;
            2) log_files+=("/var/log/auth.log") ;;
            3) log_files+=("/var/log/nginx/access.log") ;;
            4) log_files+=("/var/log/nginx/error.log") ;;
            5)
                read -p "Digite o caminho completo do arquivo de log: " custom_log
                log_files+=("$custom_log")
                ;;
            *) echo -e "${RED}Opção inválida: $choice${NC}" ;;
        esac
    done

    if [[ ${#log_files[@]} -eq 0 ]]; then
        echo -e "${RED}Nenhum arquivo de log selecionado.${NC}"
        return
    fi

    echo -e "${YELLOW}Palavras-chave para filtro (separadas por espaço):${NC}"
    read -p "Padrão: error warning failed: " keywords_input
    keywords=(${keywords_input:-"error" "warning" "failed"})

    echo -e "${GREEN}Conectando ao servidor remoto: $remote_host${NC}"
    ssh "$remote_host" "tail -f ${log_files[*]}" | grep --line-buffered -E --color=always "${keywords[*]}"
}

# Função para editar configuração
edit_config() {
    echo -e "${YELLOW}Editando arquivo de configuração...${NC}"
    nano "$CONFIG_FILE"
    echo -e "${GREEN}Configuração atualizada.${NC}"
}

# Função para exibir o menu interativo
show_menu() {
    while true; do
        echo -e "\n${BLUE}==== Menu de Monitoramento de Logs ====${NC}"
        echo -e "1. Monitorar logs locais"
        echo -e "2. Monitorar logs remotos"
        echo -e "3. Editar configuração"
        echo -e "4. Exibir ajuda"
        echo -e "5. Sair"
        read -p "Escolha uma opção (1-5): " choice

        case $choice in
            1)
                load_config
                if validate_log_files log_files[@]; then
                    monitor_logs log_files[@] keywords[@]
                fi
                ;;
            2)
                monitor_remote_logs
                ;;
            3)
                edit_config
                ;;
            4)
                show_help
                ;;
            5)
                echo -e "${GREEN}Saindo...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Opção inválida. Tente novamente.${NC}"
                ;;
        esac
    done
}

# Iniciar o menu interativo
show_menu
