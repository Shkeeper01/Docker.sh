#!/bin/bash
# Скрипт для автоматической установки Docker Engine + Docker Compose (plugin v2)
# Подходит для ряда OS (Debian/Ubuntu/Astra)
# Тестирование проводил для Desktop систем - и для тестов.



set -euo pipefail

# Проверка root
if [[ "${UID}" -ne 0 ]]; then
    echo 'Must execute with sudo or root' >&2
    exit 1
fi

# Определяем пользователя, для которого добавляем в группу docker
# (если скрипт запущен через sudo, $USER будет root — берём SUDO_USER)
TARGET_USER="${SUDO_USER:-${USER}}"

#  Определяем дистрибутив и кодовое имя
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO="${ID}"
    CODENAME="${VERSION_CODENAME}"
else
    echo "Cannot detect OS. /etc/os-release not found." >&2
    exit 1
fi

if [[ "${DISTRO}" != "ubuntu" && "${DISTRO}" != "debian" ]]; then
    echo "Unsupported distro: ${DISTRO}. Only ubuntu/debian are supported." >&2
    exit 1
fi

echo ">>> Detected: ${DISTRO} ${CODENAME}"

# Обновление индексов пакетов
echo ">>> Updating package index..."
apt-get update -y

# Опциональный upgrade
read -rp "Run full system upgrade? [y/N]: " DO_UPGRADE
if [[ "${DO_UPGRADE,,}" == "y" ]]; then
    apt-get upgrade -y
fi

#  Установка зависимостей
echo ">>> Installing prerequisites..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Удаляем старые/конфликтующие пакеты, если есть
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y "$pkg" 2>/dev/null || true
done

# Добавляем GPG-ключ Docker (современный способ, без apt-key)
echo ">>> Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Добавляем репозиторий Docker
echo ">>> Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/${DISTRO} ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y

# Установка Docker Engine и Compose plugin v2
echo ">>> Installing Docker Engine + Compose plugin..."
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Включаем и запускаем сервис
systemctl enable --now docker

# Добавляем пользователя в группу docker
if id -nG "${TARGET_USER}" | grep -qw docker; then
    echo ">>> User ${TARGET_USER} already in docker group."
else
    echo ">>> Adding ${TARGET_USER} to docker group..."
    usermod -aG docker "${TARGET_USER}"
    NEEDS_RELOGIN=1
fi

# Проверка
echo
echo ">>> Installed versions:"
docker --version
docker compose version

echo
echo "==================================================="
echo " Docker installed successfully!"
if [[ "${NEEDS_RELOGIN:-0}" -eq 1 ]]; then
    echo " NOTE: Log out and back in (or run 'newgrp docker')"
    echo "       so ${TARGET_USER} can use docker without sudo."
fi
echo "==================================================="

exit 0
