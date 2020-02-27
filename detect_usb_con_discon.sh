#!/bin/bash

check_usb(){
    #check "/sys/bus/usb/devices" contents
    declare -a pre_conn
    pre_conn=(`ls /sys/bus/usb/devices`)
    #print content of "/sys/bus/usb/devices" dir
    ls /sys/bus/usb/devices
    pre_conn_num=${#pre_conn[@]}

    #connect usb storage device using Acroname
    sshpass -p $1 ssh $2@$3 -y python $4 control $5 && sleep 4

    declare -a post_conn
    post_conn=(`ls /sys/bus/usb/devices`)
    post_conn_num=${#post_conn[@]}

    if [ $pre_conn_num -eq $post_conn_num ]; then 
        echo "usb device not connected"
        RC=1
        exit 1
    else
        echo "usb device connected"
        RC=0
    fi

    #print content of "/sys/bus/usb/devices" dir after connecting usb device
    ls /sys/bus/usb/devices

    #disconnect usb device
    sshpass -p $1 ssh $2@$3 -y python $4 disable && sleep 4

    dis_conn=(`ls /sys/bus/usb/devices`)
    dis_conn_num=${#dis_conn[@]}
    if [ $pre_conn_num -ne $dis_conn_num ]; then 
        echo "usb device not disconnected"
        RC=2
        exit 2
    else
        echo "usb device disconnected successfully"
        RC=0
    fi

    #print content of "/sys/bus/usb/devices" dir after disconnecting usb device
    ls /sys/bus/usb/devices
}

usage()
{
    echo "Example:"
    echo " $0 <host password> <host username> <host ip addr> <location of Acromame script location in host> <Channel of device conencted to Acroname> <no of loops>"
    exit 3
}

#main
RC=0
if [ $# -ne 6 ]; then 
    usage
fi

#disconnect all usb devices
sshpass -p $1 ssh $2@$3 -y python $4 disable && sleep 4

for loop in $(seq 1 $6);do
    echo "Checking usb connect and disconnect $loop time(s)"
    check_usb $1 $2 $3 $4 $5 || exit $RC
done
if [ $RC -eq 0 ]; then
    tst_resm TPASS "Test PASS"
else
    tst_resm TFAIL "Test FAIL"
fi

