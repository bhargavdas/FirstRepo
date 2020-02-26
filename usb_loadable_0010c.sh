#!/bin/bash -x

# Function:     setup
#
# Description:  - Check if required commands exits
#               - Export global variables
#               - Check if required config files exits
#               - Create temporary files and directories
# Return        - zero on success
setup()
{
    export TST_TOTAL=1
    export TCID="setup"
    export TST_COUNT=0
    RC=1
    if [ -e $LTPROOT ]
    then
        export LTPSET=0
    else   
        export LTPSET=1
        return $RC   
    fi
       
    trap "cleanup" 0 2
           
    platform=$(platfm.sh) || platfm=$?
                      
    if [ $platfm -eq 7 ] || [ $platfm -eq 84 ] || [ $platfm -eq 85 ]; then
       phy=phy_generic
    elif [ $platfm -eq 82 ]; then
       urls=`uname -r`
       ver_gte $urls 4.19
       if [ $? -eq 0 ]; then
           phy="phy_fsl_imx8mq_usb"
       else
           phy="dwc3_of_simple" #just a place hold
       fi
    elif [ $platfm -eq 81 ] || [ $platfm -eq 83 ]; then
        # QXP platform, ChipIdea and CDN(USB3.0) are both
        # included.
        phy="phy_mxs_usb phy_generic"
    else
       phy=phy_mxs_usb
    fi
    if [ $platfm -eq 79 ]; then
        md="standby mem"
    else
        md="mem"
    fi
    if [ $platfm -eq 82 ]; then 
        core_driver="dwc3"
    elif [ $platfm -eq 81 ] || [ $platfm -eq 83 ]; then
        core_driver="ci_hdrc_imx cdns3"
    else
        core_driver="ci_hdrc_imx"
    fi
    modprobe -a $phy && modprobe -a $core_driver
    sleep 5
    
    RC=0
    return $RC
}

# Function:     cleanup
# Description   -.
cleanup()
{
    #disk_node=$(check_usb_device "disk" "no")
    #delete duplicated device node
    disk_node=`echo "$disk_node" | sort | uniq`
    if [ -n "$disk_node" ]; then
        umount_partition $disk_node
    fi
    modprobe -a -r $core_driver && modprobe -a -r $phy
}


usb_loadable()
{
    RC=0   
    TCID="LOADABLE0014c"
    echo "--------------------------------------------------"
    echo "Reminder: This case need use special kernel and dtb"
    echo "--------------------------------------------------"
    sleep 10
    echo "=============================="
    echo "=     start $TCID      ="
           
    modprobe -a $phy && modprobe -a $core_driver
    sleep 5

    sshpass -p $1 ssh $2@$3 python $4 disable && sleep 4   
    i=1
    while [ $i -lt 6 ]
    do
        sshpass -p $1 ssh $2@$3 python $4 disable && sleep 4
        echo "testing $i times usb mouse plugin/plugout"
        de_init_cnt=$(ls -l /sys/class/input/ | grep -m 1 usb | wc -l)
        sleep 6
        sshpass -p $1 ssh $2@$3 python $4 control $5 && sleep 4
        init_cnt=$(ls -l /sys/class/input/ | grep -m 1 usb | wc -l)
        if [ $de_init_cnt -lt $init_cnt ];then
            echo "usb mouse plugin/plugout normal"
        else
            echo "usb mouse plugin/plugout fail"
            RC=2
            return $RC
        fi
        i=`expr $i + 1`
        RC=0
    done

    modprobe -a -r $core_driver; modprobe -a -r $phy
    sleep 5
    sshpass -p $1 ssh $2@$3 python $4 disable && sleep 4
    return $RC

}

usage()
{
    echo "Example:"
    echo " $0 <host password> <host username> <host ip addr> <location of Acromame script location in host> <Channel of device conencted to Acroname>"
    exit 3
}

#main
export TST_TOTAL=1
RC=0
if [ $# -ne 5 ]; then 
    usage
fi

setup || exit $RC

for loop in $(seq 1 $6);do
    echo "Checking usb connect and disconnect $loop time(s)"
    usb_loadable $1 $2 $3 $4 $5 || exit $RC
done
if [ $RC -eq 0 ]; then
    tst_resm TPASS "Test PASS"
else
    tst_resm TFAIL "Test FAIL"
fi

