#!/usr/bin/env bash

RED_FONT_PREFIX="\033[31m"
GREEN_FONT_PREFIX="\033[32m"
YELLOW_FONT_PREFIX="\033[1;33m"
LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
ARIA2_CONF=${1:-aria2.conf}
DOWNLOADER="curl -fsSL --connect-timeout 3 --max-time 3 --retry 2"
NL=$'\n'

DATE_TIME() {
    date +"%m/%d %H:%M:%S"
}

GET_TRACKERS() {
    TRACKER=""
    if [[ -z "${CUSTOM_TRACKER_URL}" ]]; then
        echo && echo -e "$(DATE_TIME) ${INFO} Get BT trackers..."
        TRACKER=$(
            ${DOWNLOADER} https://trackerslist.com/all_aria2.txt ||
            ${DOWNLOADER} https://cdn.statically.io/gh/XIU2/TrackersListCollection/master/all_aria2.txt ||
            ${DOWNLOADER} https://trackers.p3terx.com/all_aria2.txt
        )
    else
        echo && echo -e "$(DATE_TIME) ${INFO} Get BT trackers from url(s):${CUSTOM_TRACKER_URL} ..."
        URLS=$(echo "${CUSTOM_TRACKER_URL}" | tr "," "\n")
        TRACKER=""
        for URL in ${URLS}; do
            TRACKER_DATA="$(${DOWNLOADER} "${URL}")" || continue
            TRACKER+="$(
                echo "${TRACKER_DATA}" \
                | tr "," "\n" \
                | awk '/^(udp|http|https):\/\/[^/:]+(:[0-9]+)?(\/|$)/' \
                | sort -u \
                | paste -sd ","
            ),"
        done
        TRACKER="$(echo "${TRACKER}" | sed 's/,$//')"
    fi

    [[ -z "${TRACKER}" ]] && {
        echo
        echo -e "$(DATE_TIME) ${ERROR} Unable to get trackers, network failure or invalid links." && exit 1
    }
}

# [...] 其他函数保持不变

if [ "$1" = "cat" ]; then
    GET_TRACKERS
    ECHO_TRACKERS
elif [ "$1" = "RPC" ]; then
    RPC_ADDRESS="$2/jsonrpc"
    RPC_SECRET="$3"
    GET_TRACKERS
    ECHO_TRACKERS
    ADD_TRACKERS_REMOTE_RPC
elif [ "$2" = "RPC" ]; then
    GET_TRACKERS
    ECHO_TRACKERS
    ADD_TRACKERS
    echo
    ADD_TRACKERS_LOCAL_RPC
else
    GET_TRACKERS
    ECHO_TRACKERS
    ADD_TRACKERS
fi

exit 0
