#!/bin/bash

# Are we using systemd or rc (ie init) scripts?
systemctl --version 2> /dev/null
if [[ $? -eq 0 ]]
then
    USE_SYSTEMD=1
else
    USE_SYSTEMD=0
fi

function enableService {
    local SERVICE=$1
    if [[ $USE_SYSTEMD = 1 ]]
    then
        systemctl enable $SERVICE
    else
        chkconfig $SERVICE on
    fi
}

function disableService {
    local SERVICE=$1
    if [[ $USE_SYSTEMD = 1 ]]
    then
        systemctl disable $SERVICE
    else
        chkconfig $SERVICE off
    fi
}

function startService {
    local SERVICE=$1
    if [[ $USE_SYSTEMD = 1 ]]
    then
        systemctl start $SERVICE
    else
        service $SERVICE start
    fi
}

function stopService {
    local SERVICE=$1
    if [[ $USE_SYSTEMD = 1 ]]
    then
        systemctl stop $SERVICE
    else
        service $SERVICE stop
    fi
}

function restartService {
    local SERVICE=$1
    if [[ $USE_SYSTEMD = 1 ]]
    then
        systemctl restart $SERVICE
    else
        service $SERVICE restart
    fi
}
