#!/bin/bash

# Atualiza o sistema
apt update && apt upgrade -y

# Instala o Bacula (incluindo console)
apt install -y bacula-director-sqlite3 bacula-sd bacula-fd bacula-console sqlite3

# Define o banco de dados SQLite
DB_FILE="/var/lib/bacula/bacula.db"
BACULA_DIR_CONF="/etc/bacula/bacula-dir.conf"
BACULA_SD_CONF="/etc/bacula/bacula-sd.conf"
BACULA_FD_CONF="/etc/bacula/bacula-fd.conf"

# Cria e configura o banco de dados
echo "Configurando banco de dados SQLite..."
mkdir -p /var/lib/bacula
sqlite3 $DB_FILE <<EOF
CREATE TABLE Job (
    JobId INTEGER PRIMARY KEY,
    Name TEXT,
    Type TEXT,
    Level TEXT,
    ClientId INTEGER,
    JobStatus TEXT
);
EOF
chown bacula:bacula $DB_FILE
chmod 600 $DB_FILE

# Configuração do Bacula Director
cat > $BACULA_DIR_CONF <<EOF
Director {
  Name = bacula-dir
  DIRport = 9101
  QueryFile = "/etc/bacula/scripts/query.sql"
  WorkingDirectory = "/var/lib/bacula"
  PidDirectory = "/run/bacula"
  Maximum Concurrent Jobs = 10
  Password = "senhadiretor"
  Messages = Daemon
}

JobDefs {
  Name = "BackupPadrao"
  Type = Backup
  Level = Incremental
  Client = bacula-fd
  FileSet = "ArquivosPadrao"
  Schedule = "Diario"
  Storage = File
  Messages = Standard
  Pool = Default
  Priority = 10
}

Job {
  Name = "BackupServidor"
  JobDefs = "BackupPadrao"
}

FileSet {
  Name = "ArquivosPadrao"
  Include {
    Options {
      compression=GZIP
    }
    File = "/etc"
    File = "/home"
  }
}

Schedule {
  Name = "Diario"
  Run = Full 1st sun at 00:05
  Run = Incremental mon-sat at 00:05
}

Client {
  Name = bacula-fd
  Address = 127.0.0.1
  FDPort = 9102
  Catalog = MyCatalog
  Password = "senhacliente"
  FileRetention = 30 days
  JobRetention = 6 months
}

Storage {
  Name = File
  Address = 127.0.0.1
  SDPort = 9103
  Password = "senhastorage"
  Device = FileStorage
  MediaType = File
}

Pool {
  Name = Default
  Pool Type = Backup
  Recycle = yes
  AutoPrune = yes
  Volume Retention = 365 days
}

Catalog {
  Name = MyCatalog
  dbname = "$DB_FILE"
}
EOF

# Configuração do Storage Daemon
cat > $BACULA_SD_CONF <<EOF
Storage {
  Name = bacula-sd
  SDPort = 9103
  WorkingDirectory = "/var/lib/bacula"
  PidDirectory = "/run/bacula"
  Maximum Concurrent Jobs = 10
}

Device {
  Name = FileStorage
  MediaType = File
  ArchiveDevice = /var/backups/bacula
  LabelMedia = yes
  Random Access = yes
  AutomaticMount = yes
  RemovableMedia = no
  AlwaysOpen = no
}

Messages {
  Name = Standard
  director = bacula-dir = all
}
EOF

# Configuração do File Daemon
cat > $BACULA_FD_CONF <<EOF
FileDaemon {
  Name = bacula-fd
  FDport = 9102
  WorkingDirectory = "/var/lib/bacula"
  PidDirectory = "/run/bacula"
}

Messages {
  Name = Standard
  director = bacula-dir = all, !skipped, !restored
}
EOF

# Criando diretório de backup
mkdir -p /var/backups/bacula
chown -R bacula:bacula /var/backups/bacula

# Reiniciando e ativando os serviços do Bacula
for service in bacula-director bacula-sd bacula-fd; do
    systemctl restart $service
    systemctl enable $service
done

# Instalação do Bacula Web
echo "Instalando Bacula Web..."
apt install -y apache2 php php-cli php-sqlite3 libapache2-mod-php unzip
cd /var/www/html
wget https://github.com/bacula-web/bacula-web/releases/download/8.6.0/bacula-web-8.6.0.zip
unzip bacula-web-8.6.0.zip
mv bacula-web-8.6.0 bacula-web
chown -R www-data:www-data /var/www/html/bacula-web

# Configuração do Apache para Bacula Web
cat > /etc/apache2/sites-available/bacula-web.conf <<EOF
<VirtualHost *:80>
    DocumentRoot /var/www/html/bacula-web
    <Directory /var/www/html/bacula-web>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2ensite bacula-web
systemctl reload apache2

# Instalação do Webmin
echo "Instalando Webmin..."
wget -qO - http://www.webmin.com/jcameron-key.asc | apt-key add -
echo "deb http://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list
apt update
apt install -y webmin

# Reiniciando serviços
systemctl restart apache2
systemctl restart webmin

echo "✅ Instalação concluída!"
echo "🌐 Acesse a interface gráfica do Bacula Web em: http://SEU_IP/bacula-web"
echo "🔐 Acesse o Webmin em: https://SEU_IP:10000"
echo "🖥 Para acessar o Bacula Console, use: bconsole"
