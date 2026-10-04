#!/bin/sh

DIR="/opt/torrserver"
BINARY="${DIR}/torrserver"
INIT_SCRIPT="/etc/init.d/torrserver"

REPO="bylampa/Matrix"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

echo "======================================"
echo " TorrServer installer"
echo " Source: github.com/${REPO}"
echo "======================================"
echo ""

# =========================================================
# 1. Удаляем старый TorrServer
# =========================================================

echo "[1/5] Удаление старого TorrServer..."

if [ -f "${INIT_SCRIPT}" ]; then
    echo "Останавливаем службу..."

    "${INIT_SCRIPT}" stop 2>/dev/null
    "${INIT_SCRIPT}" disable 2>/dev/null

    rm -f "${INIT_SCRIPT}"
fi

killall torrserver 2>/dev/null
killall TorrServer 2>/dev/null

rm -f "${BINARY}"

echo "Старый TorrServer удалён."
echo ""

# =========================================================
# 2. Определяем архитектуру
# =========================================================

echo "[2/5] Определение архитектуры..."

MACHINE="$(uname -m)"

case "${MACHINE}" in
    x86_64)
        ARCH="amd64"
        ;;
    i386|i486|i586|i686)
        ARCH="386"
        ;;
    aarch64)
        ARCH="arm64"
        ;;
    armv7|armv7l)
        ARCH="arm7"
        ;;
    armv6|armv6l)
        ARCH="arm6"
        ;;
    armv5|armv5l)
        ARCH="arm5"
        ;;
    mips64el)
        ARCH="mips64le"
        ;;
    mips64)
        ARCH="mips64"
        ;;
    mipsel)
        ARCH="mipsle"
        ;;
    mips)
        ARCH="mips"
        ;;
    *)
        echo "ОШИБКА: неподдерживаемая архитектура: ${MACHINE}"
        exit 1
        ;;
esac

echo "Система:     ${MACHINE}"
echo "Архитектура: ${ARCH}"
echo ""

# =========================================================
# 3. Получаем последний релиз
# =========================================================

echo "[3/5] Поиск последнего релиза..."

RELEASE_JSON="/tmp/torrserver_release.json"

rm -f "${RELEASE_JSON}"

wget -q -O "${RELEASE_JSON}" \
    --header="Accept: application/vnd.github+json" \
    --header="User-Agent: Routerich-TorrServer-Installer" \
    "${API_URL}"

if [ $? -ne 0 ] || [ ! -s "${RELEASE_JSON}" ]; then
    echo "ОШИБКА: не удалось получить информацию о релизе."
    rm -f "${RELEASE_JSON}"
    exit 1
fi

RELEASE_TAG="$(
    sed -n \
    's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "${RELEASE_JSON}" |
    head -n 1
)"

rm -f "${RELEASE_JSON}"

if [ -z "${RELEASE_TAG}" ]; then
    echo "ОШИБКА: не удалось определить версию релиза."
    exit 1
fi

echo "Последний релиз: ${RELEASE_TAG}"
echo ""

# =========================================================
# 4. Формируем ПРЯМОЙ URL нужного бинарника
# =========================================================

echo "[4/5] Скачивание TorrServer..."

ASSET_NAME="TorrServer-linux-${ARCH}"

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"

echo "Файл: ${ASSET_NAME}"
echo "URL:  ${DOWNLOAD_URL}"
echo ""

mkdir -p "${DIR}"

wget -O "${BINARY}" "${DOWNLOAD_URL}"

if [ $? -ne 0 ]; then
    echo ""
    echo "ОШИБКА: TorrServer не удалось скачать."
    rm -f "${BINARY}"
    exit 1
fi

if [ ! -s "${BINARY}" ]; then
    echo ""
    echo "ОШИБКА: скачанный файл пустой."
    rm -f "${BINARY}"
    exit 1
fi

# =========================================================
# Проверяем ELF и архитектуру
# =========================================================

echo ""
echo "Проверка бинарника..."

MAGIC="$(hexdump -n 20 -v -e '1/1 "%02x "' "${BINARY}" 2>/dev/null)"

echo "ELF header:"
echo "${MAGIC}"

# ELF magic
if ! echo "${MAGIC}" | grep -q "^7f 45 4c 46"; then
    echo ""
    echo "ОШИБКА: скачанный файл не является ELF-бинарником."
    rm -f "${BINARY}"
    exit 1
fi

# Для ARM64:
# ELFCLASS64 = 02
# EM_AARCH64 = 0xb7 (байты b7 00 в little-endian)
if [ "${ARCH}" = "arm64" ]; then

    ELF_CLASS="$(hexdump -n 5 -v -e '1/1 "%02x "' "${BINARY}" 2>/dev/null | awk '{print $5}')"

    MACHINE_BYTES="$(hexdump -s 18 -n 2 -v -e '1/1 "%02x "' "${BINARY}" 2>/dev/null)"

    if [ "${ELF_CLASS}" != "02" ]; then
        echo ""
        echo "ОШИБКА: получен не 64-битный ELF."
        echo "Ожидался ELFCLASS64 (02), получено: ${ELF_CLASS}"
        rm -f "${BINARY}"
        exit 1
    fi

    if [ "${MACHINE_BYTES}" != "b7 00" ]; then
        echo ""
        echo "ОШИБКА: бинарник не является ARM64/AArch64."
        echo "Machine: ${MACHINE_BYTES}"
        rm -f "${BINARY}"
        exit 1
    fi

fi

chmod +x "${BINARY}"

echo ""
echo "Бинарник успешно проверен."
ls -lh "${BINARY}"
echo ""

# =========================================================
# 5. Создаём службу OpenWrt
# =========================================================

echo "[5/5] Создание службы OpenWrt..."

cat > "${INIT_SCRIPT}" << EOF
#!/bin/sh /etc/rc.common

START=95
STOP=10

USE_PROCD=1

start_service() {
    procd_open_instance

    procd_set_param command ${BINARY} \
        -d ${DIR} \
        -p 8090 \
        --logpath /tmp/log/torrserver/torrserver.log

    procd_set_param respawn

    procd_close_instance
}
EOF

chmod +x "${INIT_SCRIPT}"

echo "Включение автозапуска..."
"${INIT_SCRIPT}" enable

echo "Запуск TorrServer..."
"${INIT_SCRIPT}" start

sleep 2

if "${INIT_SCRIPT}" status | grep -q "running"; then
    echo ""
    echo "TorrServer успешно запущен."
else
    echo ""
    echo "ВНИМАНИЕ: TorrServer не запустился."
    echo "Проверь:"
    echo "  ${INIT_SCRIPT} status"
    echo "  logread | grep -i torrserver"
    exit 1
fi

echo ""
echo "======================================"
echo " TorrServer установлен!"
echo "======================================"
echo "Источник:    github.com/${REPO}"
echo "Версия:      ${RELEASE_TAG}"
echo "Архитектура: ${ARCH}"
echo "Бинарник:    ${BINARY}"
echo "Каталог:     ${DIR}"
echo "Порт:        8090"
echo ""
echo "Открыть:"
echo "http://IP-РОУТЕРА:8090"
echo "======================================"

exit 0
