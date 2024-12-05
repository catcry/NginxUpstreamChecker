#!/bin/bash

####################################
#            Variables             #              
####################################
#WORKER_LIST=("localhost" "ccgb.catcry.ir")
WORKER_LIST=("$@")
PORT="7243"
RESOURCE_PATH="/ccHeal/v2"
CHECK_DATE=$(date)
WORKER_LAST_STATUS=()
WORKER_PREVIOUS_STATUS=()
WORKER_CURRENT_STATUS=()
BASE_DIR="/etc/nginx/conf_template"
NGINX_TEMPLATE_CONFIG_FILE="$BASE_DIR/nginx_template.conf"
NGINX_NEW_CONF_FILE="$BASE_DIR/amir2.conf"
NGINX_CONF_DIR="/etc/nginx/conf.d"

AUTH_HEADER="Authorization: Basic YWRtaW46YWRtaW4="

####################################
#            Initialize            #              
####################################
for ((i=0; i<${#WORKER_LIST[@]}; i++)); do
    WORKER_CURRENT_STATUS+=("1")
done
#echo "${WORKER_CURRENT_STATUS[@]}"
####################################
#            Functions             #
####################################
check_worker_stat() {
    local worker_address=$1
    worker_response=$(curl -s -k -X GET "$worker_address" -H 'accept: */*' -H "$AUTH_HEADER")

    worker_status=$(echo $worker_response | jq -r '.status')
    
    if [[ "$worker_status" == "available" ]]; then
        return 1
    else
        return 0
    fi
}

compare_status() {
    local -n previous_status=$1
    local -n current_status=$2

    for ((i=0; i<${#previous_status[@]}; i++)); do
        if [[ ${previous_status[$i]} -ne ${current_status[$i]} ]]; then
            return 1 
        fi
    done

    return 0
}


####################################
#          Business Logic          #
####################################



while true
do
    WORKER_PREVIOUS_STATUS=("${WORKER_CURRENT_STATUS[@]}")
    WORKER_CURRENT_STATUS=()
    CHECK_DATE=$(date)
    for worker in "${WORKER_LIST[@]}"; do
        
        echo $worker
        worker_health_endpoint="https://$worker:$PORT$RESOURCE_PATH"
        check_worker_stat "$worker_health_endpoint"
        status=$?
        WORKER_CURRENT_STATUS+=("$status")
                
    done
    echo "${WORKER_CURRENT_STATUS[@]}"

    compare_status  WORKER_PREVIOUS_STATUS WORKER_CURRENT_STATUS
    status_changed=$?
    echo $status_changed

    if [[ $status_changed -eq 0 ]]; then
        echo "$CHECK_DATE | Workers' status did not change."
        sleep 30
        continue
    fi
    echo "$CHECK_DATE | Workers' status changed. Reconfiguring NGINX ..."

    cp "$NGINX_TEMPLATE_CONFIG_FILE" "$NGINX_NEW_CONF_FILE"

    for ((i=0; i<${#WORKER_CURRENT_STATUS[@]}; i++)); do
        if [[ ${WORKER_CURRENT_STATUS[$i]} -eq 0 ]]; then
            # If the worker is unavailable, update the Nginx config file
            worker="${WORKER_LIST[$i]}"
            

            # Add a comment to the unavailable upstream server line
            sudo sed -i "/upstream.*{/,/}/s/\(\s*server\s*$worker.*\)/# \1/" "$NGINX_NEW_CONF_FILE"

            echo "Marked worker $worker as unavailable in Nginx config."
        fi
    done

    cp "$NGINX_NEW_CONF_FILE" "$NGINX_CONF_DIR"
    sudo systemctl reload nginx
    echo "NGNIX service reloaded."

    sleep 30
done
