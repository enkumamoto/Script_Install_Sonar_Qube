#!/bin/bash

# Script de instalação do SonarQube para Amazon Linux
# Execute como root ou com sudo

set -e

echo "=== Iniciando instalação do SonarQube no Amazon Linux ==="

# Atualizar sistema
echo "Atualizando o sistema..."
yum update -y

# Instalar Java 17 (requisito do SonarQube)
echo "Instalando Java 17..."
yum install -y java-17-amazon-corretto-devel

# Verificar instalação do Java
java -version

# Configurar variáveis de ambiente Java
echo "Configurando JAVA_HOME..."
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto' >> /etc/environment
echo 'export PATH=$PATH:$JAVA_HOME/bin' >> /etc/environment
source /etc/environment

# Instalar PostgreSQL (banco de dados recomendado)
echo "Instalando PostgreSQL..."
yum install -y postgresql15-server postgresql15

# Inicializar e iniciar PostgreSQL
echo "Configurando PostgreSQL..."
postgresql-setup --initdb
systemctl enable postgresql
systemctl start postgresql

# Configurar usuário e banco de dados para SonarQube
echo "Criando banco de dados para SonarQube..."
sudo -u postgres psql -c "CREATE USER sonarqube WITH PASSWORD 'sonarqube';"
sudo -u postgres psql -c "CREATE DATABASE sonarqube OWNER sonarqube;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonarqube;"

# Configurar autenticação PostgreSQL
echo "Configurando autenticação PostgreSQL..."
PG_VERSION=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP '\d+\.\d+' | head -1)
PG_CONFIG_DIR="/var/lib/pgsql/data"

# Backup do arquivo original
cp ${PG_CONFIG_DIR}/pg_hba.conf ${PG_CONFIG_DIR}/pg_hba.conf.backup

# Adicionar configuração para SonarQube
echo "local   sonarqube   sonarqube   md5" >> ${PG_CONFIG_DIR}/pg_hba.conf
echo "host    sonarqube   sonarqube   127.0.0.1/32   md5" >> ${PG_CONFIG_DIR}/pg_hba.conf

# Reiniciar PostgreSQL
systemctl restart postgresql

# Criar usuário do sistema para SonarQube
echo "Criando usuário sonarqube..."
useradd sonarqube
usermod -aG wheel sonarqube

# Configurar limites do sistema
echo "Configurando limites do sistema..."
cat >> /etc/security/limits.conf << EOF
sonarqube   -   nofile   131072
sonarqube   -   nproc    8192
EOF

# Configurar parâmetros do kernel
echo "Configurando parâmetros do kernel..."
cat >> /etc/sysctl.conf << EOF
vm.max_map_count=524288
fs.file-max=131072
EOF

# Aplicar configurações
sysctl -p

# Baixar SonarQube
echo "Baixando SonarQube..."
cd /opt
SONARQUBE_VERSION="10.4.1.88267"
wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip

# Instalar unzip se necessário
yum install -y unzip

# Extrair SonarQube
echo "Extraindo SonarQube..."
unzip sonarqube-${SONARQUBE_VERSION}.zip
mv sonarqube-${SONARQUBE_VERSION} sonarqube
rm sonarqube-${SONARQUBE_VERSION}.zip

# Configurar propriedades do SonarQube
echo "Configurando SonarQube..."
cat > /opt/sonarqube/conf/sonar.properties << EOF
# Configuração do banco de dados
sonar.jdbc.username=sonarqube
sonar.jdbc.password=sonarqube
sonar.jdbc.url=jdbc:postgresql://localhost:5432/sonarqube

# Configuração de rede
sonar.web.host=0.0.0.0
sonar.web.port=9000

# Configuração de logs
sonar.log.level=INFO
sonar.path.logs=logs

# Configuração de dados
sonar.path.data=data
sonar.path.temp=temp
EOF

# Alterar proprietário dos arquivos
echo "Configurando permissões..."
chown -R sonarqube:sonarqube /opt/sonarqube
chmod +x /opt/sonarqube/bin/linux-x86-64/sonar.sh

# Criar serviço systemd
echo "Criando serviço systemd..."
cat > /etc/systemd/system/sonarqube.service << EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonarqube
Group=sonarqube
Restart=always
LimitNOFILE=131072
LimitNPROC=8192

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd e iniciar serviço
echo "Iniciando serviço SonarQube..."
systemctl daemon-reload
systemctl enable sonarqube
systemctl start sonarqube

# Configurar firewall se estiver ativo
if systemctl is-active --quiet firewalld; then
    echo "Configurando firewall..."
    firewall-cmd --permanent --add-port=9000/tcp
    firewall-cmd --reload
fi

# Aguardar inicialização
echo "Aguardando inicialização do SonarQube..."
sleep 30

# Verificar status
echo "Verificando status do serviço..."
systemctl status sonarqube

echo ""
echo "=== Instalação concluída! ==="
echo ""
echo "SonarQube está sendo executado em: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000"
echo ""
echo "Credenciais padrão:"
echo "  Usuário: admin"
echo "  Senha: admin"
echo ""
echo "IMPORTANTE: Altere a senha padrão no primeiro acesso!"
echo ""
echo "Para verificar logs: journalctl -u sonarqube -f"
echo "Para verificar status: systemctl status sonarqube"
echo "Para parar: systemctl stop sonarqube"
echo "Para iniciar: systemctl start sonarqube"
echo ""
echo "Certifique-se de que a porta 9000 está aberta no Security Group da instância EC2."
