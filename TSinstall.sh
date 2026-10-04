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

# На случай, если процесс запущен не через procd
killall torrserver 2>/dev/null
killall TorrServer 2>/dev/null

# Удаляем старый бинарник
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
# 3. Получаем последний релиз bylampa/Matrix
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

# Получаем tag_name
RELEASE_TAG="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${RELEASE_JSON}" | head -n 1)"

if [ -z "${RELEASE_TAG}" ]; then
    echo "ОШИБКА: не удалось определить версию релиза."
    rm -f "${RELEASE_JSON}"
    exit 1
fi

echo "Последний релиз: ${RELEASE_TAG}"
echo ""

# =========================================================
# 4. Ищем нужный бинарник и скачиваем его
# =========================================================

echo "[4/5] Поиск TorrServer для ${ARCH}..."

ASSET_NAME="TorrServer-linux-${ARCH}"

# Ищем download URL именно нужного asset
DOWNLOAD_URL="$(
    sed 's/[{},]/\n/g' "${RELEASE_JSON}" |
    grep -B 15 -A 15 "\"name\"[[:space:]]*:[[:space:]]*\"${ASSET_NAME}\"" |
    sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n 1
)"

rm -f "${RELEASE_JSON}"

if [ -z "${DOWNLOAD_URL}" ]; then
    echo "ОШИБКА: в релизе ${RELEASE_TAG} не найден:"
    echo "${ASSET_NAME}"
    exit 1
fi

echo "Файл: ${ASSET_NAME}"
echo "URL:   ${DOWNLOAD_URL}"
echo ""

mkdir -p "${DIR}"

echo "Скачивание..."

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

chmod +x "${BINARY}"

echo ""
echo "TorrServer успешно скачан:"
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
