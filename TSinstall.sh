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
# Определение архитектуры
# =========================================================

MACHINE="$(uname -m)"

case "${MACHINE}" in
    aarch64)
        ARCH="arm64"
        ;;
    armv7l)
        ARCH="arm7"
        ;;
    armv6l)
        ARCH="arm6"
        ;;
    x86_64)
        ARCH="amd64"
        ;;
    i386|i686)
        ARCH="386"
        ;;
    *)
        echo "ОШИБКА: неизвестная архитектура: ${MACHINE}"
        exit 1
        ;;
esac

echo "Система: ${MACHINE}"
echo "Архитектура: ${ARCH}"
echo ""

# =========================================================
# Получение последнего релиза
# =========================================================

echo "Проверка последней версии TorrServer..."

RELEASE_JSON="/tmp/torrserver_release.json"

rm -f "${RELEASE_JSON}"

wget -q -O "${RELEASE_JSON}" \
    --header="Accept: application/vnd.github+json" \
    --header="User-Agent: Routerich-TorrServer-Installer" \
    "${API_URL}"

if [ $? -ne 0 ] || [ ! -s "${RELEASE_JSON}" ]; then
    echo ""
    echo "ОШИБКА: не удалось получить информацию о последнем релизе."
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
    echo ""
    echo "ОШИБКА: не удалось определить последнюю версию."
    exit 1
fi

echo "Последняя версия: ${RELEASE_TAG}"
echo ""

# =========================================================
# Определение установленной версии
# =========================================================

INSTALLED_VERSION=""

if [ -x "${BINARY}" ]; then
    INSTALLED_VERSION="$(
        "${BINARY}" --version 2>/dev/null |
        head -n 1 |
        tr -d '\r'
    )"
fi

# Если --version вернул что-то вроде:
# TorrServer MatriX.145.UN
# пытаемся вытащить MatriX...
case "${INSTALLED_VERSION}" in
    *MatriX*)
        INSTALLED_VERSION="$(
            echo "${INSTALLED_VERSION}" |
            sed -n 's/.*\(MatriX[^ ]*\).*/\1/p'
        )"
        ;;
esac

echo "Установленная версия: ${INSTALLED_VERSION:-не определена}"
echo ""

# =========================================================
# Если версия уже последняя — ничего не делаем
# =========================================================

if [ -n "${INSTALLED_VERSION}" ] &&
   [ "${INSTALLED_VERSION}" = "${RELEASE_TAG}" ]; then

    echo "======================================"
    echo " TorrServer уже обновлён"
    echo "======================================"
    echo ""
    echo "Установлена последняя версия:"
    echo "${RELEASE_TAG}"
    echo ""
    echo "Переустановка не требуется."
    echo ""

    exit 0
fi

# =========================================================
# Новая версия или версия не определена
# =========================================================

if [ -n "${INSTALLED_VERSION}" ]; then
    echo "Доступна новая версия!"
    echo ""
    echo "Установлена: ${INSTALLED_VERSION}"
    echo "Доступна:    ${RELEASE_TAG}"
else
    echo "Текущая версия не определена."
    echo "Будет выполнена установка версии ${RELEASE_TAG}."
fi

echo ""

# =========================================================
# Подтверждение обновления
# =========================================================

printf "Обновить TorrServer? [Y/N]: "
read ANSWER

case "${ANSWER}" in
    y|Y|д|Д)
        ;;
    *)
        echo ""
        echo "Обновление отменено."
        exit 0
        ;;
esac

echo ""

# =========================================================
# Удаление старой службы / бинарника
# =========================================================

echo "[1/4] Остановка старого TorrServer..."

if [ -x "${INIT_SCRIPT}" ]; then
    "${INIT_SCRIPT}" stop 2>/dev/null
    "${INIT_SCRIPT}" disable 2>/dev/null
fi

killall torrserver 2>/dev/null
killall TorrServer 2>/dev/null

rm -f "${BINARY}"

mkdir -p "${DIR}"

echo "Старый бинарник удалён."
echo ""

# =========================================================
# Скачивание
# =========================================================

echo "[2/4] Скачивание TorrServer..."

ASSET_NAME="TorrServer-linux-${ARCH}"

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"

echo "Файл: ${ASSET_NAME}"
echo "URL:  ${DOWNLOAD_URL}"
echo ""

wget -O "${BINARY}" "${DOWNLOAD_URL}"

if [ $? -ne 0 ]; then
    echo ""
    echo "ОШИБКА: не удалось скачать TorrServer."
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
echo "TorrServer скачан."
echo ""

# =========================================================
# Создание службы
# =========================================================

echo "[3/4] Настройка службы..."

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

"${INIT_SCRIPT}" enable

echo "Служба настроена."
echo ""

# =========================================================
# Запуск
# =========================================================

echo "[4/4] Запуск TorrServer..."

"${INIT_SCRIPT}" start

sleep 3

if "${INIT_SCRIPT}" status | grep -q "running"; then

    echo ""
    echo "======================================"
    echo " TorrServer успешно обновлён!"
    echo "======================================"
    echo ""
    echo "Версия: ${RELEASE_TAG}"
    echo "Архитектура: ${ARCH}"
    echo "Порт: 8090"
    echo ""
    echo "http://192.168.1.1:8090"
    echo ""

else

    echo ""
    echo "======================================"
    echo " ВНИМАНИЕ: TorrServer не запустился"
    echo "======================================"
    echo ""
    echo "Проверь:"
    echo "/etc/init.d/torrserver status"
    echo "logread | grep -i torrserver"
    echo ""

    exit 1
fi

exit 0
