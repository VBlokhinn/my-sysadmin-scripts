#!/usr/bin/env bash
set -euo pipefail

echo "=== 1. Установка необходимых пакетов ==="
sudo apt-get update
sudo apt-get install -y docker.io mdadm lvm2 nginx

echo "=== 2. Сборка и запуск Docker-контейнера ==="
docker build -t my-script .
# Если контейнер уже существует, удаляем его перед созданием
docker rm -f my-app 2>/dev/null || true
docker run -d -p 8080:8080 --name my-app my-script

echo "=== 3. Настройка хранилища (RAID 1 и LVM на loop-устройствах) ==="
sudo mkdir -p /mnt/raid-lab
cd /mnt/raid-lab

# Очищаем старые точки и loop-устройства (на случай повторного запуска)
sudo umount /mnt/raid 2>/dev/null || true
sudo umount /mnt/logs 2>/dev/null || true
sudo vgremove -y -f vg_data 2>/dev/null || true
sudo mdadm --stop /dev/md0 2>/dev/null || true
sudo losetup -D 2>/dev/null || true

# Создаем файлы-диски по 512 МБ
sudo dd if=/dev/zero of=disk1.img bs=1M count=512 status=none
sudo dd if=/dev/zero of=disk2.img bs=1M count=512 status=none
sudo dd if=/dev/zero of=disk3.img bs=1M count=512 status=none

# Подключаем как loop-устройства и получаем их имена автоматически
LOOP1=$(sudo losetup -fP --show disk1.img)
LOOP2=$(sudo losetup -fP --show disk2.img)
LOOP3=$(sudo losetup -fP --show disk3.img)

# Создаем RAID 1
echo y | sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 "$LOOP1" "$LOOP2"
sudo mkfs.ext4 -F /dev/md0
sudo mkdir -p /mnt/raid
sudo mount /dev/md0 /mnt/raid

# Создаем LVM
echo y | sudo pvcreate "$LOOP3"
sudo vgcreate vg_data "$LOOP3"
echo y | sudo lvcreate -L 200M -n lv_logs vg_data
sudo mkfs.ext4 -F /dev/vg_data/lv_logs
sudo mkdir -p /mnt/logs
sudo mount /dev/vg_data/lv_logs /mnt/logs

echo "=== 4. Настройка SSL и Nginx Reverse Proxy ==="
sudo rm -f /etc/nginx/sites-enabled/default

# Генерация самоподписанного TLS-сертификата
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/my-app.key \
  -out /etc/ssl/certs/my-app.crt \
  -subj "/CN=my-app.local"

# Конфигурация Nginx
sudo tee /etc/nginx/sites-available/my-app > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/ssl/certs/my-app.crt;
    ssl_certificate_key /etc/ssl/private/my-app.key;

    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

echo "=== 5. Настройка и запуск systemd-службы ==="
docker stop my-app

sudo tee /etc/systemd/system/my-app.service > /dev/null << 'EOF'
[Unit]
Description=my-app service
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/docker start -a my-app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable my-app
sudo systemctl start my-app

# Задержка 3 секунды, чтобы веб-сервер внутри контейнера успел запуститься
sleep 3

echo "=== 6. Проверка доступности сервиса по HTTPS ==="
curl -kI https://127.0.0.1

echo "Развертывание капстоуна успешно завершено!"