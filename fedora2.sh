#!/bin/bash

# Script de configuração para Fedora 42 RDS fcosta
# Executa apenas conexões RDS em tela cheia
# Usuário: fcosta
#Versão 2.1 20/8/25
#Por José Luiz

set -e

echo "=== Configuração Fedora 42 RDS fcosta ==="
echo "Iniciando configuração do sistema..."

# Atualizar sistema
echo "Atualizando sistema base..."
sudo dnf update -y

# Instalar pacotes necessários para RDS/RDP
echo "Instalando pacotes necessários..."
sudo dnf install -y \
    freerdp \
    xorg-x11-server-Xorg \
    xorg-x11-xinit \
    xorg-x11-drv-evdev \
    xorg-x11-drv-fbdev \
    xorg-x11-drv-vesa \
    xorg-x11-utils \
    xorg-x11-xauth \
    openbox \
    NetworkManager \
    openssh-server \
    chrony \
    xterm \
    unclutter-xfixes \
    mesa-dri-drivers --skip-unavailable
    
# Remover pacotes desnecessários
echo "Removendo pacotes desnecessários..."
sudo dnf remove -y \
    firefox \
    thunderbird \
    libreoffice-* \
    gnome-* \
    evolution-* \
    rhythmbox \
    totem \
    cheese \
    nautilus \
    gedit \
    calculator \
    2>/dev/null || true

# Configurar autologin do usuário fcosta
echo "Configurando autologin para usuário fcosta..."
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin fcosta --noclear %I $TERM
EOF

# Criar arquivo RDP com configurações da empresa
echo "Criando arquivo de configuração RDP..."
sudo mkdir -p /home/fcosta/.config
sudo tee /home/fcosta/empresa.rdp > /dev/null << 'EOF'
redirectclipboard:i:1
redirectprinters:i:1
redirectcomports:i:0
redirectsmartcards:i:1
devicestoredirect:s:*
drivestoredirect:s:*
redirectdrives:i:1
session bpp:i:32
prompt for credentials on client:i:1
span monitors:i:1
use multimon:i:1
remoteapplicationmode:i:1
server port:i:3389
allow font smoothing:i:1
promptcredentialonce:i:0
videoplaybackmode:i:1
audiocapturemode:i:1
gatewayusagemethod:i:0
gatewayprofileusagemethod:i:1
gatewaycredentialssource:i:0
full address:s:192.168.0.102
#alternate shell:s:||SFC_RDS
#remoteapplicationprogram:s:||SFC_RDS
#remoteapplicationname:s:SFC_RDS
remoteapplicationcmdline:s:
workspace id:s:192.168.0.102
use redirection server name:i:1
#loadbalanceinfo:s:tsv://MS Terminal Services Plugin.1.RemoteApp_RDSHO
EOF

# Criar script de inicialização do X11 para fcosta
echo "Configurando inicialização X11..."
sudo tee /home/fcosta/.xinitrc > /dev/null << 'EOF'
#!/bin/bash

# Log de debug
exec > /home/fcosta/xinitrc.log 2>&1
echo "=== Iniciando .xinitrc ==="
echo "Data: $(date)"
echo "Display: $DISPLAY"
echo "Usuário: $(whoami)"

# Aguardar rede estar disponível
echo "Aguardando conectividade de rede..."
for i in {1..30}; do
    if ping -c 1 192.168.0.102 >/dev/null 2>&1; then
        echo "Conectividade OK após $i tentativas"
        break
    fi
    echo "Tentativa $i/30 - aguardando rede..."
    sleep 2
done

# Configurações do X11
echo "Configurando X11..."
xset s off
xset -dpms
xset s noblank

# Esconder cursor após inatividade
unclutter -idle 3 -root &

# Configurar áudio
echo "Configurando áudio..."
pulseaudio --start --log-target=syslog 2>/dev/null || true
sleep 2

# Iniciar gerenciador de janelas
echo "Iniciando Openbox..."
openbox --config-file /home/fcosta/.config/openbox/rc.xml &
OPENBOX_PID=$!
sleep 3

# Testar se Openbox iniciou
if ! kill -0 $OPENBOX_PID 2>/dev/null; then
    echo "ERRO: Openbox não iniciou corretamente"
    xterm -e "echo 'Erro no Openbox. Pressione Enter para tentar novamente'; read" &
    wait
    exit 1
fi

echo "Openbox iniciado com PID: $OPENBOX_PID"

# Função para conexão RDS com logs detalhados
conectar_rds() {
    echo "=== Tentativa de conexão RDS ==="
    echo "Data: $(date)"
    echo "Servidor: 192.168.0.102"
    echo "Porta: 3389"
    
    # Testar conectividade antes de tentar conectar
    echo "Testando conectividade..."
    if ! nc -z 192.168.0.102 3389 2>/dev/null; then
        echo "ERRO: Não foi possível conectar na porta 3389 do servidor 192.168.0.102"
        return 1
    fi
    echo "Porta 3389 acessível"
    
    # Tentar conexão com parâmetros simplificados primeiro
    echo "Iniciando conexão FreeRDP..."
    xfreerdp /v:192.168.0.102:3389 \
              /u:userServer \
              /p:"pwdServer" \
              /f \
              /bpp:32 \
              /clipboard \
              /cert:ignore \
              /sec:tls \
              /timeout:60000 \
              /log-level:INFO \
              +auto-reconnect \
              /auto-reconnect-max-retries:5
    
    local exit_code=$?
    echo "FreeRDP finalizado com código: $exit_code"
    return $exit_code
}

# Loop principal de conexão
tentativa=1
while true; do
    echo "=== Tentativa $tentativa de conexão ==="
    
    if conectar_rds; then
        echo "Conexão finalizada normalmente"
    else
        echo "Conexão falhou ou foi interrompida"
    fi
    
    echo "Aguardando 10 segundos antes de reconectar..."
    sleep 10
    ((tentativa++))
done
EOF

# Configurar .bashrc para iniciar X automaticamente
echo "Configurando .bashrc para auto-inicialização..."
sudo tee /home/fcosta/.bashrc > /dev/null << 'EOF'
# .bashrc para fcosta RDS

# Verificar se está em TTY1 e iniciar X automaticamente
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
    echo "Iniciando modo fcosta RDS..."
    exec startx
fi
EOF

# Configurar Openbox para modo fcosta
echo "Configurando Openbox..."
sudo mkdir -p /home/fcosta/.config/openbox
sudo tee /home/fcosta/.config/openbox/rc.xml > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>200</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Primary</monitor>
    <primaryMonitor>1</primaryMonitor>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>yes</animateIconify>
    <font place="ActiveWindow">
      <name>sans</name>
      <size>8</size>
      <weight>bold</weight>
      <slant>normal</slant>
    </font>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names>
      <name>Desktop 1</name>
    </names>
    <popupTime>875</popupTime>
  </desktops>
  <resize>
    <drawContents>yes</drawContents>
    <popupShow>Nonpixel</popupShow>
    <popupPosition>Center</popupPosition>
    <popupFixedPosition>
      <x>10</x>
      <y>10</y>
    </popupFixedPosition>
  </resize>
  <keyboard>
    <!-- Desabilitar todas as combinações de teclas -->
  </keyboard>
  <mouse>
    <dragThreshold>1</dragThreshold>
    <doubleClickTime>500</doubleClickTime>
    <screenEdgeWarpTime>0</screenEdgeWarpTime>
    <screenEdgeWarpMouse>false</screenEdgeWarpMouse>
  </mouse>
  <applications>
    <application class="*">
      <decor>no</decor>
      <maximized>true</maximized>
    </application>
  </applications>
</openbox_config>
EOF

# Configurar permissões
echo "Configurando permissões..."
sudo chown -R fcosta:fcosta /home/fcosta/
sudo chmod +x /home/fcosta/.xinitrc

# Desabilitar serviços desnecessários
echo "Desabilitando serviços desnecessários..."
sudo systemctl disable \
    bluetooth.service \
    avahi-daemon.service \
    ModemManager.service \
    2>/dev/null || true

# Habilitar serviços necessários
echo "Habilitando serviços necessários..."
sudo systemctl enable \
    NetworkManager.service \
    sshd.service \
    cups.service
    chronyd.service

# Configurar firewall para permitir apenas RDS
echo "Configurando firewall..."
sudo firewall-cmd --permanent --remove-service=dhcpv6-client 2>/dev/null || true
sudo firewall-cmd --permanent --add-port=3389/tcp  # RDS
sudo firewall-cmd --permanent --add-service=ssh    # SSH para administração
sudo firewall-cmd --reload

# Configurar sudoers para usuário fcosta (apenas comandos específicos)
echo "Configurando sudoers..."
sudo tee /etc/sudoers.d/fcosta > /dev/null << 'EOF'
fcosta ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot, /bin/systemctl restart NetworkManager
EOF

# Configurar GRUB para boot silencioso e rápido
echo "Configurando GRUB..."
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
sudo sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="quiet splash rd.systemd.show_status=false rd.udev.log_level=3"/' /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

# Criar script de reconexão manual (para troubleshooting)
echo "Criando script de reconexão manual..."
sudo tee /home/fcosta/reconectar.sh > /dev/null << 'EOF'
#!/bin/bash

echo "=== Script de Reconexão RDS ==="
echo "Data: $(date)"

# Matar processos FreeRDP existentes
echo "Finalizando conexões RDS existentes..."
pkill -f xfreerdp
pkill -f freerdp
sleep 3

# Verificar se X11 está rodando
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

echo "Display configurado: $DISPLAY"

# Testar conectividade
echo "Testando conectividade com o servidor..."
if ping -c 3 192.168.0.102; then
    echo "Ping OK"
else
    echo "AVISO: Ping falhou - verificar conectividade de rede"
fi

# Testar porta RDS
echo "Testando porta RDS (3389)..."
if nc -z 192.168.0.102 3389; then
    echo "Porta 3389 acessível"
else
    echo "ERRO: Porta 3389 não acessível"
    exit 1
fi

# Tentar conexão simplificada primeiro
echo "Iniciando conexão RDS simplificada..."
xfreerdp /v:192.168.0.102:3389 \
          /f \
          /bpp:32 \
          /cert:ignore \
          /sec:tls \
          /log-level:INFO \
          +auto-reconnect

echo "Conexão finalizada com código: $?"
EOF

# Criar script de diagnóstico
echo "Criando script de diagnóstico..."
sudo tee /home/fcosta/diagnostico.sh > /dev/null << 'EOF'
#!/bin/bash

echo "=== DIAGNÓSTICO RDS fcosta ==="
echo "Data: $(date)"
echo "Usuário: $(whoami)"
echo ""

echo "=== SISTEMA ==="
echo "Versão do Fedora:"
cat /etc/fedora-release
echo ""
echo "Uptime:"
uptime
echo ""

echo "=== REDE ==="
echo "Interfaces de rede:"
ip addr show
echo ""
echo "Teste de conectividade:"
ping -c 3 8.8.8.8
echo ""
echo "Teste servidor RDS:"
ping -c 3 192.168.0.102
echo ""
echo "Teste porta RDS:"
nc -zv 192.168.0.102 3389
echo ""

echo "=== X11 ==="
echo "Display atual: $DISPLAY"
echo "Processos X:"
ps aux | grep -E "(Xorg|xinit|openbox)" | grep -v grep
echo ""
echo "Variáveis X11:"
env | grep -E "(DISPLAY|XAUTHORITY|XDG)"
echo ""

echo "=== FREERDP ==="
echo "Versão FreeRDP:"
xfreerdp --version 2>/dev/null || xfreerdp --version 2>/dev/null || echo "FreeRDP não encontrado"
echo ""
echo "Processos RDP:"
ps aux | grep -E "(freerdp|xfreerdp)" | grep -v grep
echo ""

echo "=== ÁUDIO ==="
echo "Dispositivos de áudio:"
pactl list short sinks 2>/dev/null || echo "PulseAudio não disponível"
echo ""

echo "=== LOGS ==="
echo "Últimas linhas do log X11:"
tail -20 /home/fcosta/xinitrc.log 2>/dev/null || echo "Log não encontrado"
echo ""

echo "=== CONECTIVIDADE DETALHADA ==="
echo "Tabela de roteamento:"
ip route
echo ""
echo "DNS:"
cat /etc/resolv.conf
echo ""

echo "=== FIM DO DIAGNÓSTICO ==="
EOF

# Configurar rotação de logs para economizar espaço
echo "Configurando rotação de logs..."
sudo tee /etc/logrotate.d/rds-fcosta > /dev/null << 'EOF'
/var/log/messages {
    weekly
    rotate 2
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
}
EOF

# Configurar resolução de DNS personalizada (se necessário)
echo "Configurando DNS..."
sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null << 'EOF'
[main]
dns=default
EOF

# Mensagem de finalização
echo ""
echo "=== Configuração concluída! ==="
echo ""
echo "Configurações aplicadas:"
echo "- Sistema configurado para autologin do usuário 'fcosta'"
echo "- X11 inicializa automaticamente em tela cheia"
echo "- Conexão RDS automática para: 192.168.0.102"
echo "- Aplicação: SFC_RDS"
echo "- Reconexão automática em caso de desconexão"
echo "- Serviços desnecessários desabilitados"
echo "- Firewall configurado para RDS e SSH"
echo ""
echo "Comandos úteis:"
echo "- Reiniciar: sudo reboot"
echo "- Desligar: sudo shutdown -h now"
echo "- Reconectar manualmente: /home/fcosta/reconectar.sh"
echo "- Diagnóstico completo: /home/fcosta/diagnostico.sh"
echo "- Ver log do X11: tail -f /home/fcosta/xinitrc.log"
echo "- Reiniciar rede: sudo systemctl restart NetworkManager"
echo "- Testar RDS manual: xfreerdp /v:192.168.0.102 /cert:ignore"
echo ""
echo "IMPORTANTE: Reinicie o sistema para aplicar todas as configurações!"
echo "Comando: sudo reboot"
