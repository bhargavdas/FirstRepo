#!/bin/bash -x

detect_ss_usb()
{
    RC=0
    #connect usb storage device using Acroname
    sshpass -p $1 ssh $2@$3 -y python $4 control $5 && sleep 4

    #check if usb ss device detected 
    lsusb -t | grep "Mass Storage" | grep 5000M
    RC=$?
}

usage()
{
    echo "Example:"
    echo " $0 <host password> <host username> <host ip addr> <location of Acromame script location in host> <Channel of device conencted to Acroname>"
    exit 3
}

#main
RC=0
if [ $# -ne 5 ]; then 
    usage
fi

#disconnect all usb devices
sshpass -p $1 ssh $2@$3 -y python $4 disable && sleep 4

detect_ss_usb $1 $2 $3 $4 $5 || exit $RC

#disconnect all usb devices after test
sshpass -p $1 ssh $2@$3 -y python $4 disable && sleep 4

if [ $RC -eq 0 ]; then
    tst_resm TPASS "Test PASS"
else
    tst_resm TFAIL "Test FAIL"
fi