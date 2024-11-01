#!/bin/bash

#Password para autenticação no siem.contego.com.br
SIEM_PASSWD='iTszIT;A+8,Z[Q?bf+'
#Grupo de SO
GROUP='Linux'
#Adicione os grupos de clientes neste array. O padrão é caixa alta
CLIENTS=("CONTEGO" "COOBRASTUR" "GEO" "LAB-CONTEGO" "TIROL" "CAP" "POC" "TESTE")

#INPUT SERVIDOR SIEM
read -p "Digite o servidor SIEM: " SIEM_SERVER

# Testar conectividade com o servidor SIEM via ping e testar conectividade via telnet nas portas 1515 e 1514
if ping -c 1 "$SIEM_SERVER" >/dev/null && nc -z -v -w5 "$SIEM_SERVER" 1515 >/dev/null 2>&1 && nc -z -v -w5 "$SIEM_SERVER" 1514 >/dev/null 2>&1; then
    echo -e "\nTeste de conexão ok.\n"
else
    echo -e "O servidor $SIEM_SERVER não está acessível ou não é possível conectar nas portas 1515/1514. Verifique se o nome ou IP está correto.\n"
    read -p "Deseja continuar mesmo assim? (Y/N): " confirm
    [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
fi

#Verifica se o nome do cliente existe no array CLIENTS
max_attempts=3
attempt=0
found=0
while [ $attempt -lt $max_attempts ] && [ $found -eq 0 ]; do
    # INPUT CLIENTE
    echo -e "Para testes, use o grupo LAB-CONTEGO \n"
    read -p "Digite o cliente: " siem_group

    #converte para caixa alta
    SIEM_GROUP=$(echo "$siem_group" | tr '[:lower:]' '[:upper:]')
    
    # Percorrer o array de clientes
    for client in "${CLIENTS[@]}"; do
        if [[ "$SIEM_GROUP" == "$client" ]]; then
            found=1
            break
        fi
    done

    # Verificação se o cliente foi encontrado
    if [ $found -eq 1 ]; then
        echo "Cliente ${SIEM_GROUP} encontrado!"
        break  # Encerra o loop se o cliente foi encontrado
    else
        echo "Cliente ${SIEM_GROUP} não encontrado. Verifique se você digitou corretamente."
    fi
    
    # Incrementa o número de tentativas
    attempt=$((attempt + 1))

done

# Se o cliente não for encontrado após 3 tentativas, encerra o script
if [ $found -eq 0 ]; then
    echo "Você atingiu o número máximo de tentativas. O script será encerrado."
    exit 1
fi

#Adiciona Linux no grupo
SIEM_GROUPS="${GROUP},${SIEM_GROUP}"


#Verifica OS e instala os componentes de SIEM.
OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release)

echo -e "Sistema Operacional identificado como ${OS}\n"
echo -e "O script irá instalar o agente de SIEM, Sysmon, Auditd, PacketBeat e Suricata.\n"
read -p "Deseja continuar? (Y/N): " confirm
[[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1

# Ubuntu
if [[ $OS == *"Ubuntu"* ]]; then
    #SIEM Ubuntu
    wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.7.0-1_amd64.deb && sudo WAZUH_MANAGER='siem.contego.com.br' WAZUH_REGISTRATION_PASSWORD=${SIEM_PASSWD} WAZUH_AGENT_GROUP=${SIEM_GROUPS} dpkg -i ./wazuh-agent_4.7.0-1_amd64.deb
    sudo systemctl daemon-reload
    sudo systemctl start wazuh-agent
    #Sysmon
    wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    sudo apt-get update
    sudo apt-get install sysmonforlinux -y
    #PacketBeat
    sudo apt-get install libpcap0.8 -y
    wget -q https://artifacts.elastic.co/downloads/beats/packetbeat/packetbeat-7.17.23-amd64.deb -O packetbeat-7.17.23-amd64.deb
    sudo dpkg -i packetbeat-7.17.23-amd64.deb
    #Auditd
    apt-get install auditd audispd-plugins -y
    #Suricata
    sudo apt-get install software-properties-common
    sudo add-apt-repository ppa:oisf/suricata-stable
    sudo apt update
    sudo apt install suricata jq


# Debian 11
elif [[ $OS == *"Debian"* ]]; then
    #SIEM Ubuntu
    wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.7.0-1_amd64.deb && sudo WAZUH_MANAGER='siem.contego.com.br' WAZUH_REGISTRATION_PASSWORD=${SIEM_PASSWD} WAZUH_AGENT_GROUP=${SIEM_GROUPS} dpkg -i ./wazuh-agent_4.7.0-1_amd64.deb
    sudo systemctl daemon-reload
    sudo systemctl start wazuh-agent
    #Sysmon
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.asc.gpg
    sudo mv microsoft.asc.gpg /etc/apt/trusted.gpg.d/
    wget -q https://packages.microsoft.com/config/debian/11/prod.list
    sudo mv prod.list /etc/apt/sources.list.d/microsoft-prod.list
    sudo chown root:root /etc/apt/trusted.gpg.d/microsoft.asc.gpg
    sudo chown root:root /etc/apt/sources.list.d/microsoft-prod.list
    sudo apt-get update
    sudo apt-get install apt-transport-https -y
    sudo apt-get update
    sudo apt-get install sysmonforlinux -y
    #PacketBeat
    sudo apt-get install libpcap0.8 -y
    wget -q https://artifacts.elastic.co/downloads/beats/packetbeat/packetbeat-7.17.23-amd64.deb -O packetbeat-7.17.23-amd64.deb
    sudo dpkg -i packetbeat-7.17.23-amd64.deb
    #Auditd
    apt-get install auditd audispd-plugins -y
    #Suricata
    echo "deb http://http.debian.net/debian buster-backports main" > /etc/apt/sources.list.d/backports.list
    apt-get update
    apt-get install suricata -t buster-backports

# CentOS
elif [[ $OS == *"CentOS"* ]]; then
    #SIEM RPM
    curl -o wazuh-agent-4.7.0-1.x86_64.rpm https://packages.wazuh.com/4.x/yum/wazuh-agent-4.7.0-1.x86_64.rpm && sudo WAZUH_MANAGER='siem.contego.com.br' WAZUH_REGISTRATION_PASSWORD=${SIEM_PASSWD} WAZUH_AGENT_GROUP=${SIEM_GROUPS} rpm -ihv wazuh-agent-4.7.0-1.x86_64.rpm
    sudo systemctl daemon-reload
    sudo systemctl start wazuh-agent
    #Sysmon
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo wget -q -O /etc/yum.repos.d/microsoft-prod.repo https://packages.microsoft.com/config/rhel/8/prod.repo
    sudo yum install sysmonforlinux
    #PacketBeat
    sudo yum install libpcap -y
    curl -L -O https://artifacts.elastic.co/downloads/beats/packetbeat/packetbeat-7.17.23-x86_64.rpm
    sudo rpm -vi packetbeat-7.17.23-x86_64.rpm
    #Auditd
    yum install audit audit-libs -y
    #Suricata
    # Habilitar o repositório EPEL e plugins core
    sudo yum install epel-release yum-utils
    sudo yum-config-manager --add-repo https://copr.fedorainfracloud.org/coprs/g/oisf/suricata-7.0/repo/epel-7/group_oisf-suricata-7.0-epel-7.repo
    # Instalar o Suricata
    sudo yum install suricata

# RHEL
elif [[ $OS == *"Red Hat"* || $OS == *"Oracle"*  ]]; then
    #SIEM RPM
    curl -o wazuh-agent-4.7.0-1.x86_64.rpm https://packages.wazuh.com/4.x/yum/wazuh-agent-4.7.0-1.x86_64.rpm && sudo WAZUH_MANAGER='siem.contego.com.br' WAZUH_REGISTRATION_PASSWORD=${SIEM_PASSWD} WAZUH_AGENT_GROUP=${SIEM_GROUPS} rpm -ihv wazuh-agent-4.7.0-1.x86_64.rpm
    sudo systemctl daemon-reload
    sudo systemctl start wazuh-agent
    #Sysmon
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo wget -q -O /etc/yum.repos.d/microsoft-prod.repo https://packages.microsoft.com/config/rhel/8/prod.repo
    sudo yum install sysmonforlinux
    #PacketBeat
    sudo yum install libpcap -y
    curl -L -O https://artifacts.elastic.co/downloads/beats/packetbeat/packetbeat-7.17.23-x86_64.rpm
    sudo rpm -vi packetbeat-7.17.23-x86_64.rpm
    #Auditd
    sudo yum install audit audit-libs -y
    #Suricata
    sudo dnf install epel-release dnf-plugins-core
    sudo dnf copr enable @oisf/suricata-7.0
    sudo dnf install suricata

else
    echo "\n ${OS} não suportado. Por favor contate o responsável"
    exit 1
fi

# Install Sysmon
sudo sysmon -i

#Configuração Sysmon
sudo wget -O /opt/sysmon/config-custom.xml https://raw.githubusercontent.com/ContegoSecurity/SOC/main/sysmon/linux/sysmon-custom.xml
sudo sysmon -c /opt/sysmon/config-custom.xml

#Configura Wazuh-agent
sudo systemctl enable wazuh-agent

#Configuração Suricata
sudo suricata-update
################
#Configurar linha af-packet - substituir interface default pelo nome da interface a ser monitorada
#arrumando isso, script 100%
################
sudo systemctl restart suricata
sudo systemctl enable suricata

#Configuração PacketBeat
sudo wget -O /etc/packetbeat/packetbeat.yml https://raw.githubusercontent.com/ContegoSecurity/SOC/main/Packetbeat/packetbeat.yml
sudo systemctl enable packetbeat
sudo systemctl start packetbeat
#Configuração Auditd
sudo wget -O /etc/audit/rules.d/audit.rules https://raw.githubusercontent.com/ContegoSecurity/SOC/main/Auditd/auditd.conf
sudo auditctl -R /etc/audit/rules.d/audit.rules

#Configura logrotate para rotar logs do suricata. Adicionar novos para qualquer necessidade.
cat <<EOF > /etc/logrotate.d/siem_contego
/var/log/suricata/*.log {
        dayly
        rotate 2
        notifempty
        sharedscripts
        postrotate
                /usr/bin/systemctl reload suricata > /dev/null 2>/dev/null || true
        endscript
}
EOF
#reinicia logrotate
systemctl restart logrotate
echo "\n Script finalizado. Por favor acesse /etc/suricata/suricata.yaml e atualize a linha af-packet para o nome da interface de rede do host a ser monitorado."
