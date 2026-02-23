#!/bin/bash

# --- CONFIGURATION ---
ALIAS_NAME="tgmtproxy"
BINARY_PATH="/usr/local/bin/tgmtproxy"

# --- COLOURS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- SYSTEM CHECK ---
check_root() {
    if [ "$EUID" -ne 0 ]; then echo -e "${RED}Error: run as sudo!${NC}"; exit 1; fi
}

install_deps() {
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    fi
    if ! command -v qrencode &> /dev/null; then
        apt-get update && apt-get install -y qrencode || yum install -y qrencode
    fi
    cp "$0" "$BINARY_PATH" && chmod +x "$BINARY_PATH"
}

get_ip() {
    local ip
    ip=$(curl -s -4 --max-time 5 https://api.ipify.org || curl -s -4 --max-time 5 https://icanhazip.com || echo "0.0.0.0")
    echo "$ip" | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1
}

# --- DATA PANEL ---
show_config() {
    if ! docker ps | grep -q "mtproto-proxy"; then echo -e "${RED}Прокси не найден!${NC}"; return; fi
    SECRET=$(docker inspect mtproto-proxy --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}')
    IP=$(get_ip)
    PORT=$(docker inspect mtproto-proxy --format='{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}{{end}}' 2>/dev/null)
    PORT=${PORT:-443}
    LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"

    echo -e "\n${GREEN}DATA PANEL${NC}"
    echo -e "IP: $IP | Port: $PORT"
    echo -e "Secret: $SECRET"
    echo -e "Link: ${BLUE}$LINK${NC}"
    qrencode -t ANSIUTF8 "$LINK"
}

# --- INSTALLING ---
menu_install() {
    clear
    echo -e "${CYAN}--- Choose domen for masking (Fake TLS) ---${NC}"
    domains=(
        "google.com" "wikipedia.org" "habr.com" "github.com" 
        "coursera.org" "udemy.com" "medium.com" "stackoverflow.com"
        "bbc.com" "cnn.com" "reuters.com" "nytimes.com"
        "lenta.ru" "rbc.ru" "ria.ru" "kommersant.ru"
        "stepik.org" "duolingo.com" "khanacademy.org" "ted.com"
    )
    
    for i in "${!domains[@]}"; do
        printf "${YELLOW}%2d)${NC} %-20s " "$((i+1))" "${domains[$i]}"
        [[ $(( (i+1) % 2 )) -eq 0 ]] && echo ""
    done
    
    read -p "Your choice [1-20]: " d_idx
    DOMAIN=${domains[$((d_idx-1))]}
    DOMAIN=${DOMAIN:-google.com}

    echo -e "\n${CYAN}--- Choose port ---${NC}"
    echo -e "1) 443 (Recommended)"
    echo -e "2) 8443"
    echo -e "3) My port"
    read -p "Choice (number): " p_choice
    case $p_choice in
        2) PORT=8443 ;;
        3) read -p "Insert your port: " PORT ;;
        *) PORT=443 ;;
    esac

    echo -e "${YELLOW}[*] Setting up proxy...${NC}"
    SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN")
    docker stop mtproto-proxy &>/dev/null && docker rm mtproto-proxy &>/dev/null
    
    docker run -d --name mtproto-proxy --restart always -p "$PORT":"$PORT" \
        nineseconds/mtg:2 simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT" "$SECRET" > /dev/null
    
    clear
    show_config
    read -p "Installing complete. Press Enter..."
}

# --- EXIT ---
show_exit() {
    clear
    show_config
    exit 0
}

# --- SCRIPT START ---
check_root
install_deps

while true; do
    echo -e "\n${MAGENTA}Telegram MTProxy install script manager${NC}"
    echo -e "1) ${GREEN}Install / Update proxy${NC}"
    echo -e "2) Show connection data${NC}"
    echo -e "3) ${RED}Delete proxy${NC}"
    echo -e "0) Exit${NC}"
    read -p "Command (number): " m_idx
    case $m_idx in
        1) menu_install ;;
        2) clear; show_config; read -p "Press Enter..." ;;
        3) docker stop mtproto-proxy && docker rm mtproto-proxy && echo "Deleted" ;;
        0) show_exit ;;
        *) echo "Bad input" ;;
    esac
done
