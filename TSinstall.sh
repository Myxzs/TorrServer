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
# 1. Удаление старого TorrServer
# =========================================================

echo "[1/5] Удаление старого TorrServer..."

if [ -x "${INIT_SCRIPT}" ]; then
    echo "Остановка службы..."
    "${INIT_SCRIPT}" stop 2>/dev/null
    "${INIT_SCRIPT}" disable 2>/dev/null
fi

killall torrserver 2>/dev/null
killall TorrServer 2>/dev/null

rm -f "${BINARY}"
rm -f "${INIT_SCRIPT}"

mkdir -p "${DIR}"

echo "Старый TorrServer удалён."
echo ""

# =========================================================
# 2. Определение архитектуры
# =========================================================

echo "[2/5] Определение архитектуры..."

MACHINE="$(uname -m)"

echo "Система: ${MACHINE}"

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
        echo ""
        echo "ОШИБКА: неизвестная архитектура: ${MACHINE}"
        exit 1
        ;;
esac

echo "Архитектура TorrServer: ${ARCH}"
echo ""

# =========================================================
# 3. Получение последнего релиза
# =========================================================

echo "[3/5] Получение последнего релиза..."

RELEASE_JSON="/tmp/torrserver_release.json"

rm -f "${RELEASE_JSON}"

wget -q -O "${RELEASE_JSON}" \
    --header="Accept: application/vnd.github+json" \
    --header="User-Agent: Routerich-TorrServer-Installer" \
    "${API_URL}"

if [ ! -s "${RELEASE_JSON}" ]; then
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
    echo "ОШИБКА: не удалось определить последний релиз."
    exit 1
fi

echo "Последний релиз: ${RELEASE_TAG}"
echo ""

# =========================================================
# 4. Скачивание TorrServer
# =========================================================

echo "[4/5] Скачивание TorrServer..."

ASSET_NAME="TorrServer-linux-${ARCH}"

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"

echo "Файл: ${ASSET_NAME}"
echo "URL:  ${DOWNLOAD_URL}"
echo ""

rm -f "${BINARY}"

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

echo ""
echo "Проверка бинарника..."

HEADER="$(hexdump -n 20 -v -e '1/1 "%02x"' "${BINARY}" 2>/dev/null)"

echo "ELF header:"
hexdump -n 20 -v -e '1/1 "%02x "' "${BINARY}" 2>/dev/null

# Проверяем ELF magic: 7f 45 4c 46
case "${HEADER}" in
    7f454c46*)
        ;;
    *)
        echo ""
        echo "ОШИБКА: файл не является ELF-бинарником."
        rm -f "${BINARY}"
        exit 1
        ;;
esac

# =========================================================
# Проверка архитектуры ELF
# =========================================================

if [ "${ARCH}" = "arm64" ]; then

    # ELFCLASS64 находится в 5-м байте ELF-заголовка.
    # Для 64-bit значение = 02.
    ELF_CLASS="$(echo "${HEADER}" | cut -c9-10)"

    # e_machine находится на 18-19 байтах.
    # AArch64 = 0x00b7.
    MACHINE_BYTES="$(echo "${HEADER}" | cut -c37-40)"

    if [ "${ELF_CLASS}" != "02" ]; then
        echo ""
        echo "ОШИБКА: бинарник не является 64-битным."
        echo "ELF class: ${ELF_CLASS}"
        rm -f "${BINARY}"
        exit 1
    fi

    if [ "${MACHINE_BYTES}" != "b700" ]; then
        echo ""
        echo "ОШИБКА: бинарник не является ARM64/AArch64."
        echo "Machine: ${MACHINE_BYTES}"
        rm -f "${BINARY}"
        exit 1
    fi

    echo "ELF: 64-bit"
    echo "Architecture: AArch64 / ARM64"

elif [ "${ARCH}" = "amd64" ]; then

    ELF_CLASS="$(echo "${HEADER}" | cut -c9-10)"
    MACHINE_BYTES="$(echo "${HEADER}" | cut -c37-40)"

    if [ "${ELF_CLASS}" != "02" ]; then
        echo ""
        echo "ОШИБКА: бинарник не является 64-битным."
        rm -f "${BINARY}"
        exit 1
    fi

    if [ "${MACHINE_BYTES}" != "3e00" ]; then
        echo ""
        echo "ОШИБКА: бинарник не является x86_64."
        echo "Machine: ${MACHINE_BYTES}"
        rm -f "${BINARY}"
        exit 1
    fi

    echo "ELF: 64-bit"
    echo "Architecture: x86_64"

fi

chmod +x "${BINARY}"

echo ""
echo "Бинарник корректный."
echo ""

# =========================================================
# 5. Создание init.d службы
# =========================================================

echo "[5/5] Создание службы TorrServer..."

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

echo "Служба создана."

# =========================================================
# Включение автозапуска
# =========================================================

"${INIT_SCRIPT}" enable

echo "Автозапуск включён."

# =========================================================
# Запуск
# =========================================================

echo ""
echo "Запуск TorrServer..."

"${INIT_SCRIPT}" start

sleep 3

# =========================================================
# Проверка
# =========================================================

echo ""
echo "Проверка состояния..."

if "${INIT_SCRIPT}" status | grep -q "running"; then

    echo ""
    echo "======================================"
    echo " TorrServer успешно установлен!"
    echo "======================================"
    echo ""
    echo "Версия: ${RELEASE_TAG}"
    echo "Архитектура: ${ARCH}"
    echo "Каталог: ${DIR}"
    echo "Порт: 8090"
    echo ""
    echo "Открыть:"
    echo "http://192.168.1.1:8090"
    echo ""
    echo "Статус:"
    echo "/etc/init.d/torrserver status"
    echo ""
    echo "Лог:"
    echo "logread | grep -i torrserver"
    echo ""

else

    echo ""
    echo "======================================"
    echo " ВНИМАНИЕ: TorrServer не запустился"
    echo "======================================"
    echo ""
    echo "Проверь:"
    echo ""
    echo "/etc/init.d/torrserver status"
    echo "logread | grep -i torrserver"
    echo ""
    exit 1

fi

exit 0
