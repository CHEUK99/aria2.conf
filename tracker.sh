#!/usr/bin/env bash
#
# 修复版 Tracker 更新脚本
# 修复问题：
# 1. TRACKER变量未初始化导致拼接问题
# 2. 自定义URL处理逻辑错误
# 3. 多源下载失败处理不完善
# 4. 输出格式不规范
#

RED_FONT_PREFIX="\033[31m"
GREEN_FONT_PREFIX="\033[32m"
YELLOW_FONT_PREFIX="\033[1;33m"
LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
ARIA2_CONF="${1:-aria2.conf}"
DOWNLOADER="curl -fsSL --connect-timeout 5 --max-time 10 --retry 2"
NL=$'\n'

DATE_TIME() {
    date +"%Y-%m-%d %H:%M:%S"
}

GET_TRACKERS() {
    local TRACKER=""
    
    if [[ -z "${CUSTOM_TRACKER_URL}" ]]; then
        echo -e "$(DATE_TIME) ${INFO} 获取默认Tracker列表..."
        TRACKER=$(
            ${DOWNLOADER} "https://trackerslist.com/all_aria2.txt" || \
            ${DOWNLOADER} "https://cdn.statically.io/gh/XIU2/TrackersListCollection/master/all_aria2.txt" || \
            ${DOWNLOADER} "https://trackers.p3terx.com/all_aria2.txt" || \
            ${DOWNLOADER} "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt"
        )
    else
        echo -e "$(DATE_TIME) ${INFO} 从自定义URL获取Tracker..."
        TRACKER=""
        IFS=',' read -ra URLS <<< "${CUSTOM_TRACKER_URL}"
        
        for URL in "${URLS[@]}"; do
            echo -e "$(DATE_TIME) ${INFO} 正在下载: ${URL}"
            DATA="$(${DOWNLOADER} "${URL}" 2>/dev/null)"
            
            if [[ -n "${DATA}" ]]; then
                # 统一处理各种分隔符格式
                FORMATTED=$(echo "${DATA}" | \
                    tr ',' '\n' | \
                    grep -E '^(udp|http|https)://[^/:]+(:[0-9]+)?' | \
                    sort -u | \
                    paste -sd ',')
                
                [[ -n "${FORMATTED}" ]] && TRACKER+="${FORMATTED},"
            fi
        done
        
        TRACKER="${TRACKER%,}"
    fi

    [[ -z "${TRACKER}" ]] && {
        echo -e "$(DATE_TIME) ${ERROR} 无法获取Tracker列表"
        exit 1
    }

    # 最终去重处理
    echo "${TRACKER}" | awk -F, '{for(i=1;i<=NF;i++) if(!a[$i]++) printf("%s%s",$i,(i==NF)?ORS:OFS)}' | tr ' ' ','
}

ECHO_TRACKERS() {
    echo -e "\n${GREEN_FONT_PREFIX}========== 有效Tracker列表 ==========${FONT_COLOR_SUFFIX}"
    echo "${1}" | tr "," "\n"
    echo -e "${GREEN_FONT_PREFIX}===================================${FONT_COLOR_SUFFIX}"
    echo -e "${INFO} 总数: $(echo "${1}" | tr -cd ',' | wc -c)个\n"
}

ADD_TRACKERS() {
    local CONFIG_FILE="${1}"
    local TRACKERS="${2}"
    
    echo -e "$(DATE_TIME) ${INFO} 更新配置文件: ${CONFIG_FILE}"
    
    [[ ! -f "${CONFIG_FILE}" ]] && {
        echo -e "$(DATE_TIME) ${ERROR} 配置文件不存在"
        return 1
    }

    # 创建备份
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak" 2>/dev/null
    
    # 更新配置
    if grep -q "bt-tracker=" "${CONFIG_FILE}"; then
        sed -i "s|^bt-tracker=.*|bt-tracker=${TRACKERS}|" "${CONFIG_FILE}"
    else
        echo "bt-tracker=${TRACKERS}" >> "${CONFIG_FILE}"
    fi
    
    [[ $? -eq 0 ]] && echo -e "$(DATE_TIME) ${INFO} 更新成功" || \
    echo -e "$(DATE_TIME) ${ERROR} 更新失败"
}

ADD_TRACKERS_RPC() {
    local RPC_URL="${1}"
    local SECRET="${2}"
    local TRACKERS="${3}"
    
    local PAYLOAD
    if [[ -n "${SECRET}" ]]; then
        PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"tracker-update","params":["token:'${SECRET}'",{"bt-tracker":"'${TRACKERS}'"}]}'
    else
        PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"tracker-update","params":[{"bt-tracker":"'${TRACKERS}'"}]}'
    fi

    echo -e "$(DATE_TIME) ${INFO} 通过RPC更新..."
    RESPONSE=$(curl -fsS --connect-timeout 5 "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d "${PAYLOAD}" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "${RESPONSE}" | grep -q '"result":"OK"'; then
        echo -e "$(DATE_TIME) ${INFO} RPC更新成功"
        return 0
    else
        echo -e "$(DATE_TIME) ${ERROR} RPC更新失败"
        [[ -n "${RESPONSE}" ]] && echo -e "${RESPONSE}"
        return 1
    fi
}

# 主程序
main() {
    # 检查依赖
    if ! command -v curl &>/dev/null; then
        echo -e "$(DATE_TIME) ${ERROR} 需要curl但未安装"
        exit 1
    fi

    # 获取Tracker
    TRACKERS=$(GET_TRACKERS)
    [[ -z "${TRACKERS}" ]] && exit 1
    
    # 显示Tracker
    ECHO_TRACKERS "${TRACKERS}"

    # 执行操作
    case "$1" in
        "cat")
            # 仅显示
            ;;
        "RPC")
            # 远程RPC
            [[ $# -lt 2 ]] && {
                echo -e "$(DATE_TIME) ${ERROR} 用法: $0 RPC <地址> [密码]"
                exit 1
            }
            ADD_TRACKERS_RPC "$2/jsonrpc" "$3" "${TRACKERS}"
            ;;
        *)
            # 更新配置文件
            ADD_TRACKERS "${ARIA2_CONF}" "${TRACKERS}"
            
            # 本地RPC
            if [[ "$2" == "RPC" ]]; then
                PORT=$(grep -oP '^rpc-listen-port=\K\d+' "${ARIA2_CONF}" 2>/dev/null)
                SECRET=$(grep -oP '^rpc-secret=\K[^ ]+' "${ARIA2_CONF}" 2>/dev/null)
                
                [[ -n "${PORT}" ]] && \
                ADD_TRACKERS_RPC "http://localhost:${PORT}/jsonrpc" "${SECRET}" "${TRACKERS}" || \
                echo -e "$(DATE_TIME) ${ERROR} 获取RPC端口失败"
            fi
            ;;
    esac
}

main "$@"
