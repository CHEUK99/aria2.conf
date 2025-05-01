#!/bin/bash

# 配置文件路径 (与aria2.conf一致)
ARIA2_CONF="/path/to/your/aria2.conf"
RPC_URL="http://localhost:6800/jsonrpc"
RPC_SECRET="CHEUK"

# Tracker源列表 (多源冗余)
TRACKER_SOURCES=(
    "https://trackerslist.com/all_aria2.txt"
    "https://cdn.staticaly.com/gh/XIU2/TrackersListCollection/master/all_aria2.txt"
    "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt"
    "http://tinytorrent.net/best-trackers.txt"
    "https://newtrackon.com/api/live"
)

# 获取最新Tracker列表
fetch_trackers() {
    local final_trackers=""
    
    for source in "${TRACKER_SOURCES[@]}"; do
        echo "尝试从 $source 获取Tracker..."
        if trackers=$(curl -fsSL --connect-timeout 10 "$source" 2>/dev/null); then
            # 统一格式化处理
            formatted=$(echo "$trackers" | \
                tr ',' '\n' | \
                grep -E '^(udp|http|https)://[^/:]+(:[0-9]+)?' | \
                sort -u | \
                paste -sd ',')
            
            [ -n "$formatted" ] && final_trackers+="${formatted},"
            echo "获取成功，共 $(echo "$formatted" | tr -cd ',' | wc -c) 个Tracker"
        fi
    done

    # 去重并移除末尾逗号
    echo "${final_trackers}" | \
        tr ',' '\n' | \
        sort -u | \
        paste -sd ',' | \
        sed 's/,$//'
}

# 更新配置文件
update_config() {
    local trackers="$1"
    
    # 备份原配置
    cp "$ARIA2_CONF" "${ARIA2_CONF}.bak"
    
    # 更新Tracker配置
    if grep -q "bt-tracker=" "$ARIA2_CONF"; then
        sed -i "s|^bt-tracker=.*|bt-tracker=${trackers}|" "$ARIA2_CONF"
    else
        echo "bt-tracker=${trackers}" >> "$ARIA2_CONF"
    fi
    
    echo "配置文件已更新"
}

# 通过RPC热更新
rpc_update() {
    local trackers="$1"
    local payload
    
    if [ -n "$RPC_SECRET" ]; then
        payload='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"tracker-update","params":["token:'$RPC_SECRET'",{"bt-tracker":"'$trackers'"}]}'
    else
        payload='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"tracker-update","params":[{"bt-tracker":"'$trackers'"}]}'
    fi
    
    curl -fsS "$RPC_URL" -d "$payload" -H "Content-Type: application/json" && \
    echo "RPC更新成功" || \
    echo "RPC更新失败"
}

# 主流程
trackers=$(fetch_trackers)
if [ -n "$trackers" ]; then
    echo "最终获取 $(echo "$trackers" | tr -cd ',' | wc -c) 个有效Tracker"
    update_config "$trackers"
    rpc_update "$trackers"
else
    echo "无法获取有效Tracker列表"
    exit 1
fi
