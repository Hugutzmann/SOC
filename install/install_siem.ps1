#Script desenvolvido pela equipe interna de Engenharia Contego Security
#Este script instala o produto de SIEM bem como suas dependencias
#O uso do mesmo é RESTRITO aos colaboradores da equipe técnica Contego Security
#Criado e mantido por Hugo Gutzmann Puga 
#last modified 02/10/2024

# Verifica a versão do Windows para compatibilidade
#$osVersion = (Get-WmiObject -Class Win32_OperatingSystem).Version
#if ($osVersion -lt "6.3") {
#    Write-Host "A versão do Windows Server é inferior a 2012 R2. Não é possível instalar o script."
#    exit
#}

###CLIENTE SIEM
#array CLIENTES
$allowedClients = @("CAP", "CONTEGO", "COOBRASTUR", "GEO", "LAB-CONTEGO", "TIROL")
#Confere input - max attempt = 3
function Get-ValidClient {
    $attempts = 0
    do {
        $CLIENTE = Read-Host "Digite o nome do cliente (ex: LAB-CONTEGO, PROD-CONTEGO, DEV-CONTEGO)"
        $CLIENTE = $CLIENTE.ToUpper()

        # Verifica se a entrada do usuário está no array de clientes permitidos
        if ($allowedClients -contains $CLIENTE) {
            Write-Host "Cliente válido: $CLIENTE"
            return $CLIENTE
        } else {
            Write-Host "Erro: Cliente inválido. Tente novamente." -ForegroundColor Red
            $attempts++
        }
    } while ($attempts -lt 3)

    Write-Host "Número máximo de tentativas atingido. O script será encerrado." -ForegroundColor Red
    exit
}

# Solicita e valida a entrada do cliente
$CLIENTE = Get-ValidClient
$GROUP = "Windows"
$GROUPS = "$CLIENTE,$GROUP"
$SIEM_PASSWD = "iTszIT;A+8,Z[Q?bf+"

###SERVIDOR SIEM
# Define o valor padrão para SIEM_SERVER
$SIEM_SERVER = "siem.contego.com.br"
$inputServer = Read-Host "Digite o endereço do servidor SIEM (pressione Enter para manter padrão: $SIEM_SERVER)"
#null keeps default or get new value 
if (![string]::IsNullOrWhiteSpace($inputServer)) {
    $SIEM_SERVER = $inputServer
}
#Exibe valor
Write-Host "Servidor SIEM: $SIEM_SERVER"

###TESTA CONECTIVIDADE SERVIDOR SIEM
$pingResult = Test-Connection -ComputerName $SIEM_SERVER -Count 1 -Quiet

if ($pingResult) {
    Write-Host "Conexão com $SIEM_SERVER bem-sucedida." -ForegroundColor Green
    
    # Testa as portas 1515 e 1514
    $port1515 = Test-NetConnection -ComputerName $SIEM_SERVER -Port 1515
    $port1514 = Test-NetConnection -ComputerName $SIEM_SERVER -Port 1514
###Os comentarios forçam o resultado postivo dos testes para seguir com script. Caso desejar que o script continue se a conexao falhar, descomente as linhas do if e $proceed (linhas 69,70,71,73,77,78,79,81)
    if ($port1515.TcpTestSucceeded -and $port1514.TcpTestSucceeded) {
        Write-Host "Conexão bem-sucedida nas portas 1515 e 1514." -ForegroundColor Green
    } else {
        Write-Host "Falha ao conectar nas portas 1515 ou 1514." -ForegroundColor Red
#        $proceed = Read-Host "Deseja continuar o script mesmo assim? (Y/N)"
#        if ($proceed.ToUpper() -ne "Y") {
#            Write-Host "Encerrando o script." -ForegroundColor Red
            exit
#        }
    }
} else {
    Write-Host "Falha ao conectar ao servidor SIEM $SIEM_SERVER." -ForegroundColor Red
#    $proceed = Read-Host "Deseja continuar o script mesmo assim? (Y/N)"
#   if ($proceed.ToUpper() -ne "Y") {
#        Write-Host "Encerrando o script." -ForegroundColor Red
        exit
#    }
}

################ INICIO DO INSTALL
###WAZUH-AGENT
#instala wazuh-agent
Invoke-WebRequest -Uri https://packages.wazuh.com/4.x/windows/wazuh-agent-4.7.0-1.msi -OutFile ${env.tmp}\wazuh-agent.msi
msiexec.exe /i ${env.tmp}\wazuh-agent.msi /q WAZUH_MANAGER=${SIEM_SERVER} WAZUH_REGISTRATION_PASSWORD=${SIEM_PASSWD} WAZUH_AGENT_GROUP=${GROUPS}
Start-Sleep -Seconds 5
NET START Wazuh
###SYSMON
#define download do sysmon, arquivo de configuração e paths
$sysinternals_repo = 'download.sysinternals.com'
$sysinternals_downloadlink = 'https://download.sysinternals.com/files/Sysmon.zip'
$sysinternals_folder = 'C:\Program Files\sysinternals'
$sysinternals_zip = 'SysinternalsSuite.zip'
$sysmonconfig_downloadlink = 'https://raw.githubusercontent.com/ContegoSecurity/SOC/main/sysmon/windows/sysmon-custom.xml'
$sysmonconfig_file = 'sysmonconfig-export.xml'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#Confere se o sysmon já está instalado.
if (Test-Path -Path $sysinternals_folder) {
    Write-Host ('Pasta Sysinternals já existe, pulando instalação do Sysmon') -ForegroundColor Red
} else {
    #se não tiver instalado, testa conexão com o link de download e arquivo de conf
    $OutPath = $env:TMP
    $output = $sysinternals_zip
    New-Item -Path "C:\Program Files" -Name "sysinternals" -ItemType "directory"
    $X = 0
    do {
        Write-Output "Esperando pela rede"
        Start-Sleep -s 5
        $X += 1
    } until(($connectreult = Test-NetConnection $sysinternals_repo -Port 443 | ? { $_.TcpTestSucceeded }) -or $X -eq 3)

    if ($connectreult.TcpTestSucceeded -eq $true) {
        Try {
            Write-Host ('Baixando e copiando ferramentas Sysinternals para C:\Program Files\sysinternals...')
            Invoke-WebRequest -Uri $sysinternals_downloadlink -OutFile $OutPath\$output
            Expand-Archive -path $OutPath\$output -destinationpath $sysinternals_folder
            Start-Sleep -s 10
            Invoke-WebRequest -Uri $sysmonconfig_downloadlink -OutFile $OutPath\$sysmonconfig_file
        } Catch {
            Write-Host "Falha ao baixar Sysinternals" -ForegroundColor Red
        }
    } else {
        Write-Host "Falha na conexão com $sysinternals_repo" -ForegroundColor Red
    }
###Instala Sysmon
$sysmonPath = "$sysinternals_folder\Sysmon64.exe"
    if (Test-Path -Path $sysmonPath) {
        & $sysmonPath -accepteula -i $OutPath\$sysmonconfig_file
    } else {
    Write-Host "Erro: Sysmon não encontrado!"
    }
}
### NPCAP - Dependencia Suricata
# Definir URLs de download
$npcapUrl = "https://npcap.com/dist/npcap-1.80.exe"
$suricataUrl = "https://www.openinfosecfoundation.org/download/windows/Suricata-7.0.6-1-64bit.msi"
$rulesUrl = "https://rules.emergingthreats.net/open/suricata-7.0.6/emerging.rules.zip"
# Definir diretórios
$suricataRoot = "C:\Program Files\Suricata"
$rulesDir = "$suricataRoot\rules"
$tempDir = "$env:TEMP\SuricataInstall"
# Criar diretório temporário para download
if (-Not (Test-Path $tempDir)) {
    New-Item -Path $tempDir -ItemType Directory
}
# Função para download de arquivos
function Download-File($url, $outputPath) {
    Write-Host "Baixando $url..."
    Invoke-WebRequest -Uri $url -OutFile $outputPath
}
# Baixar Npcap
$npcapInstaller = "$tempDir\npcap-1.80.exe"
Download-File $npcapUrl $npcapInstaller
# Instalar Npcap
Write-Host "Instalando Npcap..."
Start-Process -FilePath $npcapInstaller -Wait

### Suricata
#baixa suricata.msi
$suricataInstaller = "$tempDir\Suricata-7.0.6.msi"
Download-File $suricataUrl $suricataInstaller
# Instala Suricata
Write-Host "Instalando Suricata..."
Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$suricataInstaller`" /quiet" -Wait

# Baixar regras Emerging Threats
$rulesArchive = "$tempDir\emerging.rules.zip"
Download-File $rulesUrl $rulesArchive

# Primeiro, verificar se a pasta de regras existe, se não, criar.
if (-Not (Test-Path $rulesDir)) {
    New-Item -Path $rulesDir -ItemType Directory
} else {
    # Se a pasta já existe, apaga para evitar conflitos e sobrescritas
    Write-Host "Limpando o diretório de regras existente..."
    Get-ChildItem -Path $rulesDir -Recurse | Remove-Item -Force -Recurse
}

#Descompactar o arquivo de regras .zip
Expand-Archive -Path $rulesArchive -DestinationPath $rulesDir

# Solicitar ao usuário o IP local que será monitorado
$localIP = Read-Host "Digite o IP local que deseja monitorar (ex: 10.0.0.1)"

# Validar se o IP é válido (formato IPv4 básico)
if (-Not ($localIP -match '^(\d{1,3}\.){3}\d{1,3}$')) {
    Write-Host "IP inválido. O formato correto é: 10.0.0.1"
    exit
}

# Iniciar Suricata como serviço
$suricataExe = "$suricataRoot\suricata.exe"
$suricataConfig = "$suricataRoot\suricata.yaml"
$suricataCmd = "$suricataExe -c $suricataConfig -i $localIP --service-install"

Write-Host "Iniciando Suricata como serviço com o IP $localIP..."
# Iniciar o serviço Suricata usando Start-Process
Start-Process -FilePath "$suricataRoot\suricata.exe" -ArgumentList "-c", "$suricataRoot\suricata.yaml", "-i", $localIP, "--service-install" -Wait
NET START suricata
Set-Service -Name Suricata -StartupType Automatic
Start-Sleep -Seconds 5
Write-Host "Instalação concluída!"
