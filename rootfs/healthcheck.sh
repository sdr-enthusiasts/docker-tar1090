#!/command/with-contenv bash
set -e

EXITCODE=0

if [ -f "/run/readsb/aircraft.json" ]; then

    # get latest timestamp of readsb json update
    TIMESTAMP_LAST_READSB_UPDATE=$(jq '.now' < /run/readsb/aircraft.json)

    # get current timestamp
    TIMESTAMP_NOW=$(date +"%s.%N")

    # makse sure readsb has updated json in past 60 seconds
    TIMEDELTA=$(echo "$TIMESTAMP_NOW - $TIMESTAMP_LAST_READSB_UPDATE" | bc)
    if [ "$(echo "$TIMEDELTA" \< 60 | bc)" -ne 1 ]; then
        echo "readsb last updated: ${TIMESTAMP_LAST_READSB_UPDATE}, now: ${TIMESTAMP_NOW}, delta: ${TIMEDELTA}. UNHEALTHY"
        EXITCODE=1
    else
        echo "readsb last updated: ${TIMESTAMP_LAST_READSB_UPDATE}, now: ${TIMESTAMP_NOW}, delta: ${TIMEDELTA}. HEALTHY"
    fi

else

    echo "ERROR: Cannot find /run/readsb/aircraft.json!"
    EXITCODE=1

fi

# death count for nginx
# shellcheck disable=SC2126
NGINX_DEATHS=$(s6-svdt /run/service/nginx | grep -v "exitcode 0" | wc -l)
if [ "$NGINX_DEATHS" -ge 1 ]; then
    echo "nginx deaths: $NGINX_DEATHS. UNHEALTHY"
    EXITCODE=1
else
    echo "nginx deaths: $NGINX_DEATHS. HEALTHY"
fi
s6-svdt-clear /run/service/nginx

# death count for readsb
# shellcheck disable=SC2126
READSB_DEATHS=$(s6-svdt /run/service/readsb | grep -v "exitcode 0" | wc -l)
if [ "$READSB_DEATHS" -ge 1 ]; then
    echo "readsb deaths: $READSB_DEATHS. UNHEALTHY"
    EXITCODE=1
else
    echo "readsb deaths: $READSB_DEATHS. HEALTHY"
fi
s6-svdt-clear /run/service/readsb

# death count for tar1090
# shellcheck disable=SC2126
TAR1090_DEATHS=$(s6-svdt /run/service/tar1090 | grep -v "exitcode 0" | wc -l)
if [ "$TAR1090_DEATHS" -ge 1 ]; then
    echo "tar1090 deaths: $TAR1090_DEATHS. UNHEALTHY"
    EXITCODE=1
else
    echo "tar1090 deaths: $TAR1090_DEATHS. HEALTHY"
fi
s6-svdt-clear /run/service/tar1090

exit $EXITCODE
