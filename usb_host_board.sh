#!/bin/bash -x
#Copyright (C) 2016 Freescale Semiconductor, Inc. All Rights Reserved.
#The code contained herein is licensed under the GNU General Public
#License. You may obtain a copy of the GNU General Public License
#Version 2 or later at the following locations:
#
#http://www.opensource.org/licenses/gpl-license.html
#http://www.gnu.org/copyleft/gpl.html
###################################################################################################
#
#    @file      usb_host_board.sh
#
#    @brief     1.shell script to test the usb cases which the board as host category
#               2.usb devices can be simulated by TWR-K64, which virtual port id /dev/ttyACM
#                 So when we run below cases, need switch TWR-K64 to approicate usb device.
#                  &: command_cdc + CDC
#                  #: command_cdc + HID
#                  $: command_cdc + Audio_Generator
#                  @: command_cdc + Audio_Speaker
#                  ^: command_cdc + VIDEO
#               3.Usb devices detach and attach can be simulated.
#                  (1)In i.mx side, the de-init will be recognized as detach event and init will be recognized as attach event
#                  (2)only input number(0-9) to k64 console.
#                     for example:if you put 5, the duration is 5*10 Secs
#
#    @Attation  you can also use this script to test the usb device node in your board
#               like
#               Devnode=$(usb_host_board.sh check_usb_device <category>)
#               category is  camera | disk | microphone | loudspeaker | mouse | keyboard
#
#    @Return    9  : Device not found
#               11 : Device was found but not support
#               22 : Device was found but run error
###################################################################################################
#
#Revision History:
#                            Modification     Tracking
#Author                          Date          Number    Description of Changes
#-------------------------   ------------    ----------  -------------------------------------------
#ZhenXin/--------             06/18/2014     N/A          Initial version
#Andy Tian/--------           07/16/2015     N/A          Update usb phy name for 7D
#Yonglei Han/--------         03/31/2016     N/A          Add new feature
#Yonglei Han/--------         11/14/2016     N/A          Use real usb-disk to test
#Yang Zhang/--------          12/14/2016     N/A          Enhance scripts in LOADABLE case
#Andy Tian/--------           02/15/2017     N/A          Add script for TGE-LV-USB-HOST-DVFS-0001
###################################################################################################

ver_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }
ver_gte() { [ "$1" = "$2" ] || ver_gt $1 $2; }

# Function:     setup
#
# Description:  - Check if required commands exits
#               - Export global variables
#               - Check if required config files exits
#               - Create temporary files and directories
# Return        - zero on success
setup()
{
    export TST_TOTAL=8
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
    tf_env=$(cat /proc/cmdline | grep "TF=")

    if [ -n "$tf_env" ];then
        usb_dir="/sys/bus/usb/devices"
        #k64_port=$(ls ${usb_dir}/*/tty/ | head -n 1)
        k64_port=$(find /sys -name ttyACM* | head -n 1)
        if [ -n "$k64_port" ]; then
            k64_port=`basename $k64_port`
        else
            RC=1
        fi
    fi

    RC=0
    return $RC
}

# Function:     cleanup
# Description   -.
cleanup()
{
    disk_node=$(check_usb_device "disk" "no")
    #delete duplicated device node
    disk_node=`echo "$disk_node" | sort | uniq`
    if [ -n "$disk_node" ]; then
        umount_partition $disk_node
    fi
    modprobe -a -r $core_driver && modprobe -a -r $phy
}

# Function:     check_video_node
# Description   get the video devnum
check_video_node()
{
    for devnode in $(ls /dev/video* | awk -F "/dev/" '{print $2}')
    do
        if [ ! -z  $(echo $1 | grep -w $devnode) ]; then
            echo $devnode
        fi
    done
}


# Function:     create_a_partition
# Description   create a partition for disk
create_a_partition()
{
    umount_partition $1
    disk_device=$1
    fdisk /dev/$disk_device <<EOF
    n
    p




    w
EOF

    sleep 3
    umount_partition $1
    partition=$(cat /proc/partitions | grep ${disk_device}[1-9] | head -n 1 | awk '{print $NF}')
    if [ ! -z "$partition" ]; then
        umount /dev/$partition
        umount /dev/$partition
        umount /dev/$partition
        mkfs.vfat /dev/$partition
    else
        echo "fdisk failed, try to use the whole disk"
        umount /dev/$disk_device
        partition=${disk_device}
    fi
}

# Function:     umount_partition
# Description  umount_partition sda  --- umount all mounted partition for sda
#              umount_partition sda 1 --- umount sda1
umount_partition()
{
    cd ~
    disk_device=$1
    if [ -z "$2" ]; then
        i=1
        while [ $i -lt 5 ]; do
            #umount return value
            rv=0
            while [ $rv -eq 0 ]; do
                #try to umount partiton
                umount /dev/${disk_device}${i}
                rv=$?
            done
            let i=i+1
        done
    else
        #the partition No. is given
        rv=0
        while [ $rv -eq 0 ]; do
            umount /dev/${disk_device}${2}
            rv=$?
        done
    fi
    cd -
}

# Function:     del_partition
# Description   del whole partition for disk
del_partition()
{
    umount_partition $1
    disk_device=$1
    fdisk /dev/$disk_device <<EOF
    d

    d

    d

    d


    w
EOF
    sleep 3
    umount_partition $1
}

# Function:     check_disk_node
# Description   get the disk devnum
check_disk_node()
{
    for devnode in $(ls /dev/sd[a-z] | awk -F "/dev/" '{print $2}')
    do
        for u_node in "$@"; do
            #get the first target speed USB Disk node
            if [ ! -z $(echo $u_node | grep $devnode) ]; then
                #check the speed
                usb_host=`echo $u_node | awk -F "[1-9]-[1-9]" '{print $1}'`
                usb_speed=`cat $usb_host/speed`
                if [ "$usb_speed" -eq "$SPEED" ]; then
                    echo $devnode
                    return 0
                fi
            fi
        done
    done
}

# Function:     check_mouse_node
# Description   get the mouse devnum
check_mouse_node()
{
    for devnode in $(ls /dev/input/event* | awk -F "/dev/input/" '{print $2}')
    do
        if [ ! -z $(echo $1 | grep $devnode) ]; then
            echo $devnode
        fi
    done
}

# Function:     get_soundcard_configure
# Description   get the configure information for soundcard
#               like "cap_format,cap_rate,cap_channel"
#               will be use in caller case
get_soundcard_configure()
{
    #get the dev num
    soundcard_num=$(echo $1 | sed 's/card//g')

    #get record  or play format
    if [ "$2" = "microphone"  ]; then
        capture_line_head=$(cat /proc/asound/$1/stream0 | grep -n "Capture" | awk -F ":" '{print $1}')
        capture_line_end=$(cat /proc/asound/$1/stream0 | wc -l)
    elif [ "$2" = "loudspeaker" ]; then
        capture_line_head=$(cat /proc/asound/$1/stream0 | grep -n "Playback" | awk -F ":" '{print $1}')
        capture_line_end=$(cat /proc/asound/$1/stream0 | grep -n "Capture" | awk -F ":" '{print $1}')
        if [ -z "$capture_line_end" ]; then
            capture_line_end=$(cat /proc/asound/$1/stream0 | wc -l)
        fi
    else
        #echo get error parament
        exit 1
    fi

    # check the devnum was support or not
    if [ "$2" = "microphone" ]; then
        cap_endpoint_flag=$(cat /proc/asound/$1/stream0 | sed -n "${capture_line_head},${capture_line_end}p" | grep "Endpoint" | grep "IN" | grep "NONE" | awk '{print $NF}')
    fi

    #we default use the last one device's first format and first rate
    cap_format=$(cat /proc/asound/$1/stream0 | sed -n "${capture_line_head},${capture_line_end}p" | grep "Format" | head -n 1| awk -F ":" '{print $2}' | awk -F "," '{print $1}' | sed "s/ //")
    cap_rate=$(cat /proc/asound/$1/stream0 | sed -n "${capture_line_head},${capture_line_end}p" | grep "Rates" | head -n 1 | awk -F ":" '{print $2}' | awk -F "," '{print $1}' | sed "s/ //")
    cap_channel=$(cat /proc/asound/$1/stream0 | sed -n "${capture_line_head},${capture_line_end}p" | grep "Channels" | head -n 1 | awk -F ":" '{print $2}' | awk -F "," '{print $1}' | sed "s/ //")
}

# Function:     select_audio_file
# Description   select right audio file base on soudcard configure information
select_audio_file()
{
    if [ "$cap_channel" = "1" ]; then
        #audio11k16M.wav  audio16k24M-S24_LE.wav  audio22k32M.wav
        #cap_format_array=("S16_LE" "S24LE" "S32_LE")
        cap_format_string=(16M 24M-S24_LE 32M)
    else
        #audio11k16S.wav audio16k24S-S24_LE.wav  audio22k32S.wav
        #cap_format_array=("S16_LE" "S24LE" "S32_LE")
        cap_format_string=(16S 24S-S24_LE 32S)
    fi

    cap_format_array=(S16_LE S24_LE S32_LE)
    local i_index=0
    for i in ${cap_format_array[@]}
    do
        if [ "$i" = "$cap_format" ]; then
            break
        fi
        i_index=`expr $i_index + 1`
    done

    if [ $i_index -eq ${#cap_format_array[@]} ]; then
        #echo can't find match format in cap_for_array
        exit 1
    fi

    cap_format_new="${cap_format_string[$i_index]}"
    # fix searching 441k issue, actually it need 44k
    # remove the last 3 characters
    cap_rate_new=$(echo $cap_rate | sed "s/...$/k/g")

    audio_file_name=audio${cap_rate_new}${cap_format_new}.wav

    echo $audio_file_name
}


# Function:     check_soundcard_node
# Description   get the soundcard devnum
check_soundcard_node()
{
    for devnode in $(ls /proc/asound/ | grep card[0-9])
    do
        if [ ! -z $(echo $1 | grep $devnode) ]; then
            # to avoid the devnode is a loudspeaker, check the devnode is microphne
            if [ "$2" = "microphone" ]; then
                micro_flag=$(cat /proc/asound/$devnode/stream0 | grep "Capture")
                if [ ! -z "$micro_flag" ]; then
                    echo $devnode
                fi
            elif [ "$2" = "loudspeaker" ]; then
                loud_flag=$(cat /proc/asound/$devnode/stream0 | grep "Playback")
                if [ ! -z "$loud_flag" ]; then
                    echo $devnode
                fi
            else
                # something was wrong
                exit 1
            fi
        fi
    done
}

# Function:     check_cdc_device
# Description   check what usb device was simulated by TWR-K64
check_cdc_device()
{
    RC=1
    if [ -c /dev/$k64_port ];then
        case $1 in
            "camera")
                echo '^' > /dev/$k64_port
                sleep 3
                device=$(cat ${usb_dir}/*/product)
                for dev in $device;
                do
                    if [ "$dev" = "VID_CDC" ];then
                        RC=0
                        break
                    else
                        continue
                    fi
                done
                ;;
            "mouse"|"keyboard")
                echo "#" > /dev/$k64_port
                sleep 3
                device=$(cat ${usb_dir}/*/product)
                for dev in $device;
                do
                    if [ $dev = "HID_CDC" ];then
                        RC=0
                        break
                    else
                        continue
                    fi
                done
                ;;
            "microphone")
                echo '$' > /dev/$k64_port
                sleep 3
                device=$(cat ${usb_dir}/*/product)
                for dev in $device;
                do
                    if [ "$dev" = "AGE_CDC" ];then
                        RC=0
                        break
                    else
                        continue
                    fi
                done
                ;;
            "loudspeaker")
                echo '@' > /dev/$k64_port
                sleep 3
                device=$(cat ${usb_dir}/*/product)
                for dev in $device;
                do
                    if [ "$dev" = "SPK_CDC" ];then
                        RC=0
                        break
                    else
                        continue
                    fi
                done
                ;;
        esac
        if [ $RC -eq 1 ];then
            #TWR-k64 switch failed.
            return $RC
        fi
    else
        RC=9
        exit $RC
    fi
}

# Function:     check_usb_disk
# Description   find the usb device
# Parament:     disk,camera,mouse,microphone,loudspeaker
check_usb_device()
{
    if [ -n "$tf_env" ] && [ -z "$2" ] && [ "$1" != "disk" ];then
        check_cdc_device $1
        RC=$?
        if [ $RC -ne 0 ];then
            return $RC
        fi
    fi

    cd /sys/bus/usb/devices
    for i_dev in $(ls -d  *[0-9]:[0-9]*)
    do
        cd $i_dev
        if [ "$1" = "camera" ]; then
            pach_strs=`ls video4linux/*/index`
            if [ -z "$pach_strs" ]; then
                cd ..
                continue
            fi
            for pach_str in $pach_strs; do
                pach_str=`dirname $pach_str`
                idx=`cat $pach_str/index`
                if [ $idx -eq 0 ]; then
                    break
                fi
            done
            if [ ! -z $pach_str ]; then
                check_video_node $pach_str
            fi
        elif [ "$1" = "disk" ]; then
            #find out all USB disks directory
            pach_str=$(find /sys -name uevent | grep "sd[a-z]" | grep "usb")
            if [ ! -z "$pach_str" ]; then
                check_disk_node $pach_str
            fi
            return 0 
            # for disk, no need to do loop again since check_disk_node 
            # will loop all available USB disk
        elif [ "$1" = "mouse" ]; then
            dev_identify=$(find -name uevent | grep "mouse" | head -n 1)
            if [ ! -z "$dev_identify" ]; then
                # -w : match absolutely
                pach_str=$(find -name uevent | grep -w "event[0-9]*" | head -n 1)
                if [ ! -z "$pach_str" ]; then
                    check_mouse_node $pach_str
                fi
            fi
            ## keyboard returen like "input12 event6"
        elif [ "$1" = "keyboard" ]; then
            dev_identify=$(cat uevent | grep "DRIVER=usbhid" | head -n 1)
            if [ ! -z "$dev_identify" ]; then
                keyboard_node=$(find -name uevent | grep "input[0-9]" | grep "event[0-9]" | head -n 1 | sed "s/uevent//" | awk -F "\/" '{print $3;print $4}')
                echo "$keyboard_node"
            fi
            ## for microphone and loudspeaker, they are very similar, but we don't merge them in order to easy read for user
        elif [ "$1" = "microphone" -o "$1" = "loudspeaker" ]; then
            pach_str=$(find -name uevent | grep -w "card[0-9]*" | head -n 1)
            if [ ! -z "$pach_str" ]; then
                check_soundcard_node $pach_str $1
            fi
        fi
        cd .. >/dev/null 2>&1
    done
}

###########################################################################
#
#   TGE-LV-USB-HOST-3001a
#
##########################################################################
HOST3001a()
{
    RC=0
    TCID="HOST3001a"
    echo "=============================="
    echo "=     start $TCID      ="

    #connect acroname
    acroname_operation connect

    camera_node=$(check_usb_device "camera")

    if [ -z "$camera_node" ]; then
        echo "Can't find the usb camera"
        RC=9
        return $RC
    fi
    # check whether we plugin multi camera. if it true, use the last one
    multi_flag=$(echo $camera_node | grep " ")
    if [ ! -z "$multi_flag" ]; then
        camera_node=$(echo $camera_node | awk '{print $NF}')
    fi

    if [ -n "$tf_env" ];then
        modprobe -a -r uvcvideo
        sleep 1
        modprobe uvcvideo quirks=2
    fi

    i_ct=0
    tmp_file=$(mktemp -d)
    while [ $i_ct -lt 5 ]
    do
        for m in $md; do
            sleep 3
            rtc_wakeup.sh -T 50 -m $m || { RC=44; break; }
        done
        # we don't use the vooya tool to watch the capture
        i_ct=`expr $i_ct + 1`
    done &
    `find /unit_tests/ -name mxc_v4l2_capture.out | sort -n | sed -n '1p'` -uvc -f YUYV -d /dev/$camera_node -ow 320 -oh 240 -c 1000 $tmp_file.yuv || RC=44
    # we don't use the vooya tool to watch the capture
    rm -rf $tmp_file.yuv

    #disconnect acroname
    acroname_operation disconnect

    return $RC
}

###########################################################################
#
#   TGE-LV-USB-HOST-3005a
#
##########################################################################
HOST3005a()
{
    RC=0
    TCID="HOST3005a"
    echo "=============================="
    echo "=     start $TCID      ="

    #connect acroname
    acroname_operation connect

    #make sure snd-usb-audio.ko in build in module
    modprobe -a snd-usb-audio >/dev/null 2>&1
    sleep 5
    loudspeaker_node=$(check_usb_device "loudspeaker")
    if [ -z "$loudspeaker_node" ]; then
        echo "Can't find the usb loudspeaker"
        RC=9
        break
    fi
    # check whether we plugin multi microphone. if it true, use the last one
    multi_flag=$(echo $loudspeaker_node | grep " ")
    if [ ! -z "$multi_flag" ]; then
        loudspeaker_node=$(echo "$multi_flag" | awk '{print $NF}')
    fi
    get_soundcard_configure $loudspeaker_node "loudspeaker"
    node_devnum=${soundcard_num}
    audiofile=$(select_audio_file) || RC=$?
    cd $STREAM_PATH/alsa_stream_music && ls $audiofile
    if [ $? -ne 0 ]; then
        echo "Can't find audio file, please check it by manual"
        RC=1
        break
    fi
    #aplay audio file
    sleep 10
    aplay -Dhw:$node_devnum $audiofile
    if [ $? != 0 ]; then
        # dev was found and support, but aplay error
        RC=22
        return $RC
    fi
    cp /mnt/nfs/test_stream/alsa_stream_music/0flower-48khz.wav /dev/ || RC=127

    {
        i=0
        while [ $i -lt 5 ]
        do
            for m in $md; do
                rtc_wakeup.sh -T 50 -m $m || { RC=44; break; }
                sleep 3
            done
            let i=i+1
        done
    }&

    aplay -Dplughw:$node_devnum /dev/0flower-48khz.wav || RC=44

    modprobe -a -r snd-usb-audio >/dev/null 2>&1
    sleep 10

    #disconnect acroname
    acroname_operation disconnect

    return $RC
}


###########################################################################
#
#   TGE-LV-USB-HOST-3006a
#
##########################################################################
HOST3006a()
{
    RC=0
    TCID="HOST3006a"
    echo "=============================="
    echo "=     start $TCID      ="

    #connect acroname
    acroname_operation connect

    #make sure snd-usb-audio.ko in build in module
    modprobe -a snd-usb-audio >/dev/null 2>&1
    sleep 5
    microphone_node=$(check_usb_device "microphone")
    if [ -z "$microphone_node" ]; then
        echo "Can't find the usb microphone"
        RC=9
        break
    fi
    # check whether we plugin multi microphone. if it true, use the last one
    multi_flag=$(echo $microphone_node | grep " ")
    if [ ! -z "$multi_flag" ]; then
        microphone_node=$(echo "$multi_flag" | awk '{print $NF}')
    fi
    get_soundcard_configure $microphone_node "microphone"
    node_devnum=${soundcard_num}
    node_capture_format=${cap_format}
    node_capture_rate=${cap_rate}
    node_capture_channel=${cap_channel}
    arecord_file=$(mktemp -d)
    sleep 10
    arecord -Dhw:${node_devnum} -r ${node_capture_rate} -c ${node_capture_channel} -f ${node_capture_format} -d 20 /dev/tmpfile.wav
    if [ $? != 0 ]; then
        # dev was found but not support, maybe the devnode need to check
        if [ ! -z "$cap_endpoint_flag" ]; then
            RC=11
        else
            # dev was found and support, but arecord error
            RC=22
        fi
        return $RC
    fi
    echo "please use headphone on board to check the record file output!"
    board_hdphone=$(aplay -l |grep "audio"| awk '{print $2}'|cut -c 1 | head -n 1)
    aplay -Dplughw:$board_hdphone /dev/tmpfile.wav||{ RC=33;return $RC;}
    rm -rf /dev/tmpfile.wav
    {
         i=0
         while [ $i -lt 5 ]
         do
             for m in $md; do
                 rtc_wakeup.sh -T 50 -m $m || { RC=33; break; }
                 sleep 10
             done
             let i=i+1
         done
    }&
    arecord -Dhw:${node_devnum} -r ${node_capture_rate} -c ${node_capture_channel} -f ${node_capture_format} -d 60 /dev/tmpfile.wav || RC=33
    echo "please use headphone on board to check the record file output!"
    aplay -Dplughw:$board_hdphone /dev/tmpfile.wav|| RC=44
    rm -rf /dev/tmpfile.wav
    modprobe -a -r snd-usb-audio >/dev/null 2>&1
    sleep 2

    #disconnect acroname
    acroname_operation disconnect

    return $RC
}


###########################################################################
#
#   TGE-LV-USB-HOST-DVFS-0001
#
#   Note : Script for this case
#
##########################################################################
DVFS0001()
{
    RC=0
    TCID="DVFS0001"

    #connect acroname
    acroname_operation connect

    echo "=============================="
    echo "=     start $TCID      ="

    cd

    md=""
    grep mem /sys/power/state && md="mem"
    grep standby /sys/power/state && md="standby $md"
    disk_node=$(check_usb_device "disk")
    #delete duplicated device node
    disk_node=`echo "$disk_node" | sort | uniq`
    if [ -z "$disk_node" ]; then
        echo "Can't find the usb disk"
        RC=9
        return $RC
    fi
    # check whether we plugin multi disk. if it true, use the last one
    multi_flag=$(echo $disk_node | grep " ")
    if [ ! -z "$multi_flag" ]; then
        disk_node=$(echo "$multi_flag" | awk '{print $NF}')
    fi

    #delete the previous partiton to get a clean running env
    del_partition ${disk_node}
    disk_partion=$(cat /proc/partitions | grep ${disk_node}[1-9] | head -n 1 | awk '{print $NF}')
    if [ -z "$disk_partion" ]; then
        create_a_partition $disk_node
        disk_partion=$partition
    fi

    if [ -z "$disk_partion" ]; then
        echo "Auto create disk partition failed, please creat a partition for $disk_node"
        RC=1
        return $RC
    fi
    sleep 3
    umount_partition ${disk_node} 2>&1
    umount /mnt/sdx 2>&1
    rm /mnt/sdx/test.txt
    mkdir -p /mnt/sdx && mount /dev/$disk_partion /mnt/sdx||\
        { echo "y" | mkfs.ext4 /dev/$disk_partion ;mount /dev/$disk_partion /mnt/sdx; }
     mount_dir=$(mount | grep $disk_partion | awk '{print $3}')

    #set the governor
    pre_gov=`cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`
    echo interactive > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

    #do Power mode test
    for m in $md; do
        rtc_wakeup.sh -T 50 -m $m || { RC=0; return $RC; }
        #Test point1 - U-Disk still exists
        cat /proc/partitions | grep ${disk_node}
        if [ $? -ne 0 ]; then
            echo  "U-Disk disappears after ${m} mode"
            RC=9
            return $RC
        fi
        #Test point2 - U-Disk still works
        mount | grep $disk_partion && echo "hello world" > /mnt/sdx/test.txt || return 9
        uc=`cat /mnt/sdx/test.txt`
        if [ "$uc" != "hello world" ]; then
            echo "Disk can't work normally after ${m} mode"
            RC=9
            return 9
        fi
        cat /sys/devices/system/cpu/cpu*/cpufreq/stats/time_in_state
    done

    umount_partition ${disk_node}
    echo ${pre_gov} > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

    #disconnect acroname
    acroname_operation disconnect

    return $RC
}

###########################################################################
#
#   TGE-LV-USB-HDS-001a
#
#   Note : for step 8,9  see TGE-LV-USB-HDS-001c
#
##########################################################################
HDS001a()
{
    RC=0

    #connect acroname
    acroname_operation connect

    TCID="HDS001a"
    echo "=============================="
    echo "=     start $TCID      ="

    disk_node=$(check_usb_device "disk")
    #delete duplicated device node
    disk_node=`echo "$disk_node" | sort | uniq`
    if [ -z "$disk_node" ]; then
        echo "Can't find the usb disk"
        RC=9
        return $RC
    fi
    # check whether we plugin multi disk. if it true, use the last one
    multi_flag=$(echo $disk_node | grep " ")
    if [ ! -z "$multi_flag" ]; then
        disk_node=$(echo "$multi_flag" | awk '{print $NF}')
    fi

    #delete the previous partiton to get a clean running env
    del_partition ${disk_node}
    disk_partion=$(cat /proc/partitions | grep ${disk_node}[1-9] | head -n 1 | awk '{print $NF}')
    if [ -z "$disk_partion" ]; then
        create_a_partition $disk_node
        disk_partion=$partition
    fi

    if [ -z "$disk_partion" ]; then
        echo "Auto create disk partition failed, please creat a partition for $disk_node"
        RC=1
        return $RC
    fi
    sleep 3
    umount_partition ${disk_node} 2>&1
    umount /mnt/sdx 2>&1
    mkdir -p /mnt/sdx && mount /dev/$disk_partion /mnt/sdx||\
        { mkfs.vfat /dev/$disk_partion ;mount /dev/$disk_partion /mnt/sdx; }
     mount_dir=$(mount | grep $disk_partion | awk '{print $3}')
     bonnie\+\+ -d $mount_dir -u 0:0 -s 64 -r 32 || RC=22
    ri=0
    dd if=/dev/zero of=/var/storage.img bs=1M count=64 && mkfs.vfat /var/storage.img || RC=22
    while [ $ri -lt 10 ] && [ $RC -eq 0 ]; do
        if [ -n "$CFS" ]; then
            usb_configfs.sh -m
        else
            modprobe -a g_mass_storage file=/var/storage.img removable=1
        fi
        #make sure host can still recognize the usb device
        #get_scsi.sh 4
        get_scsi.sh $host_pass $host_username $host_ip $acro_scpt_loc $arco_channel 4
        if [ $? -ne 0 ]; then
           echo "USB Host can't recognize u-disk after loading gadget driver. Test Fail!"
           RC=9
        fi

        #clean
        if [ -n "$CFS" ]; then
            usb_configfs.sh -c
        else
            modprobe -a -r g_mass_storage
        fi
        #make sure host can still recognize the usb device
        #get_scsi.sh 4
        get_scsi.sh $host_pass $host_username $host_ip $acro_scpt_loc $arco_channel 4
        if [ $? -ne 0 ]; then
           echo "USB Host can't recognize u-disk after loading gadget driver. Test Fail!"
           RC=9
        fi
        let ri=ri+1
        echo $ri
    done
    umount $mount_dir

    #disconnect acroname
    acroname_operation disconnect
    return $RC
}

###########################################################################
#
#   TGE-LV-USB-LOADABLE-0010a
#
#   Note :  support step.1. 2. 4. 5. 7
#           For step 6 . related caseid TGE-LV-USB-LOADABLE-0010b
#           For step 3 . related caseid TGE-LV-USB-LOADABLE-0010c
#
##########################################################################
LOADABLE0010a()
{
    RC=0
    TCID="LOADABLE0010a"
    echo "--------------------------------------------------"
    echo "Reminder: This case need use special kernel"

    sleep 10

    #connect acroname
    acroname_operation connect

    echo "=============================="
    echo "=     start $TCID      ="

    disk_node=$(check_usb_device "disk")
    #delete duplicated device node
    disk_node=`echo "$disk_node" | sort | uniq`
    if [ -z "$disk_node" ]; then
        echo "Can't find the usb disk"
        RC=9
        return $RC
    fi
    # check whether we plugin multi disk. if it true, use the last one
    multi_flag=$(echo $disk_node | grep " ")
    if [ ! -z "$multi_flag" ]; then
        disk_node=$(echo "$multi_flag" | awk '{print $NF}')
    fi

    #delete the previous partiton to get a clean running env
    del_partition ${disk_node}
    disk_partion=$(cat /proc/partitions | grep ${disk_node}[1-9] | head -n 1 | awk '{print $NF}')
    if [ -z "$disk_partion" ]; then
        create_a_partition $disk_node
        disk_partion=$partition
    fi

    if [ -z "$disk_partion" ]; then
        echo "Auto create disk partition failed, please creat a partition for $disk_node"
        RC=1
        return $RC
    fi

    #step 2
    sleep 3
    umount_partition ${disk_node}
    modprobe -a -r $core_driver; modprobe -a -r $phy
    sleep 5

    si=0
    #while [ $si -lt 20 ]
    while [ $si -lt 2 ]
    do
        modprobe -a $phy && modprobe -a $core_driver && sleep 5 && get_scsi.sh $host_pass $host_username $host_ip $acro_scpt_loc $arco_channel 4 || { RC=22; break; }
        umount_partition ${disk_node}
        modprobe -a -r $core_driver && modprobe -a -r $phy || { RC=22; break; }
        let si=si+1
        echo $si
    done

    if [ $RC -ne 0 ]; then
        #echo test fail
        return $RC
    fi

    #step 4
    modprobe -a $phy && modprobe -a $core_driver

    #connect acroname
    acroname_operation connect

    sleep 5
    umount_partition ${disk_node}
    umount /mnt/sdx

    #disconnect acroname
    acroname_operation disconnect

    si=0
    #while [ $si -lt 20 ]
    while [ $si -lt 2 ]
    do
        modprobe -a $phy && modprobe -a $core_driver && sleep 5 && get_scsi.sh $host_pass $host_username $host_ip $acro_scpt_loc $arco_channel 4 && \
            umount_partition ${disk_node}; \
         modprobe -a -r $core_driver && modprobe -a -r $phy && let si=si+1 || {  RC=22; break; }
        echo $si
    done

    #load the USB driver back again
    modprobe -a $phy && modprobe -a $core_driver

    #connect acroname
    acroname_operation connect

    sleep 6
    umount_partition ${disk_node}
    umount /mnt/sdx

    mkdir -p /mnt/sdx && mount /dev/$disk_partion /mnt/sdx|| \
        { mkfs.vfat /dev/$disk_partion ;mount /dev/$disk_partion /mnt/sdx; }
    mount_dir=$(mount | grep $disk_partion | awk '{print $3}')
    bon=$(df |grep "$disk_partion")
    echo $bon
    sleep 2
    bon_dir=$(df |grep "$disk_partion" |awk '{print $6}' |sed 's/ //g')
    bonnie\+\+ -d $bon_dir -u 0:0 -s 64 -r 32 || { RC=22; echo "Bonnie++ Failed"; return $RC; }

    limit=0
    limit=$(df |grep "$disk_partion" |awk '{print $4}' |sed 's/ //g')
    limit=$(expr $limit - 1)
    if [ $limit -lt 12800 ];then
        size=$limit
    else
        size=12800
    fi

     dt of=/mnt/sdx/test_file bs=4k limit=${size}k passes=20&
     bgpid=$!
     i=1
     while [ $i -lt 6 ]
     do
         echo "This is $i times suspend&resume"
         for m in $md; do
             rtc_wakeup.sh -T 50 -m $m || { RC=51; kill -9 $bgpid; return $RC; }
             sleep 3
         done
         let i=i+1
    done
    wait $bgpid
    umount $mount_dir

     #step 5 Module dependance test
     #this step, the result is fail is expect
     if [ $platfm -ne 82 ]; then
         #skip this step for i.mx8mq
         umount_partition ${disk_node}
         modprobe -a -r $phy && modprobe -a -r $core_driver
         if [ $? -eq 0 ]; then
             RC=51
             return $RC
         fi
         umount_partition ${disk_node}
         modprobe -a -r $core_driver; modprobe -a -r $phy
         if [ $? -ne 0 ]; then
             RC=52
             return $RC
         fi
         sleep 2
         modprobe -a $phy && modprobe -a $core_driver
         if [ $? -ne 0 ]; then
             RC=53
             return $RC
         fi
     fi
     sleep 3

    #disconnect acroname
    acroname_operation disconnect

     return $RC
}


###########################################################################
#
#   TGE-LV-USB-LOADABLE-0014a
#
#   Note :  support step.1. 2. 4. 5.
#           For step 3 . related caseid TGE-LV-USB-LOADABLE-0014c
#
##########################################################################
LOADABLE0014a()
{
    RC=0
    TCID="LOADABLE0014a"
    echo "--------------------------------------------------"
    echo "Reminder: This case need use special kernel and dtb"
    echo "--------------------------------------------------"
    sleep 10
    echo "=============================="
    echo "=     start $TCID      ="
    
    #connect acroname
    acroname_operation connect
    
    modprobe -a $phy && modprobe -a $core_driver
    disk_node=$(check_usb_device "disk")
    #delete duplicated device node
    disk_node=`echo "$disk_node" | sort | uniq`
    if [ -z "$disk_node" ]; then
        echo "Can't find the usb disk"
        RC=9
        return $RC
    fi
    # check whether we plugin multi disk. if it true, use the last one
    multi_flag=$(echo $disk_node | grep " ")
    if [ ! -z "$multi_flag" ]; then
        disk_node=$(echo "$disk_node" | awk '{print $NF}')
    fi

    #delete the previous partiton to get a clean running env
    del_partition ${disk_node}
    disk_partion=$(cat /proc/partitions | grep ${disk_node}[1-9] | head -n 1 | awk '{print $NF}')
    if [ -z "$disk_partion" ]; then
        create_a_partition $disk_node
        disk_partion=$partition
    fi

    if [ -z "$disk_partion" ]; then
        echo "Auto create disk partition failed, please creat a partition for $disk_node"
        RC=1
        return $RC
    fi

    #step 2
    sleep 3
    umount_partition ${disk_node}
    modprobe -a -r $core_driver; modprobe -a -r $phy
    sleep 5

    #disconnect acroname
    acroname_operation disconnect

    si=0

    #connect acroname
    acroname_operation connect

    while [ $si -lt 20 ]
    do
        modprobe -a $phy && modprobe -a $core_driver && sleep 3 && get_scsi.sh $host_pass $host_username $host_ip $acro_scpt_loc $arco_channel 4 && \
            umount_partition ${disk_node}; \
         modprobe -a -r $core_driver && modprobe -a -r $phy && let si=si+1 || {  RC=22; break; }
        echo $si
    done

    if [ $RC -ne 0 ]; then
        #echo test fail
        return $RC
    fi

    #step 4

    #connect acroname
    acroname_operation connect

    modprobe -a $phy && modprobe -a $core_driver
    sleep 5
    umount_partition ${disk_node}
    umount /mnt/sdx
    mkdir -p /mnt/sdx && mount /dev/$disk_partion /mnt/sdx|| \
        { mkfs.vfat /dev/$disk_partion ;mount /dev/$disk_partion /mnt/sdx; }
    mount_dir=$(mount | grep $disk_partion | awk '{print $3}')
    bon=$(df |grep "$disk_partion")
    echo $bon
    sleep 2
    bon_dir=$(df |grep "$disk_partion" |awk '{print $6}' |sed 's/ //g')
    bonnie\+\+ -d $bon_dir -u 0:0 -s 64 -r 32 || RC=22

    limit=0
    limit=$(df |grep "$disk_partion" |awk '{print $4}' |sed 's/ //g')
    limit=$(expr $limit - 1)
    if [ $limit -lt 12800 ];then
        size=$limit
    else
        size=12800
    fi

    dt of=/mnt/sdx/test_file bs=4k limit=${size}k passes=20&
    bgpid=$!
    i=1
    while [ $i -lt 6 ]
    do
        echo "This is $i times Suspend&Resume"
        for m in $md; do
            rtc_wakeup.sh -T 50 -m $m || { RC=9; kill -9 $bgpid; return $RC; }
            sleep 3
        done
        let i=i+1
    done
    wait $bgpid
    umount $mount_dir
    #step 5
    dd if=/dev/zero of=/var/storage.img bs=1M count=64 && mkfs.vfat /var/storage.img || RC=22
    ri=0
    while [ $ri -lt 10 ] && [ $RC -eq 0 ]; do
        if [ -n "$CFS" ]; then
            usb_configfs.sh -m
        else
            modprobe -a g_mass_storage file=/var/storage.img removable=1
        fi
        #make sure host can still recognize the usb device
        #new_disk_node=$(check_usb_device "disk" "no")
        get_scsi.sh $host_pass $host_username $host_ip $acro_scpt_loc $arco_channel 4
        if [ $? -ne 0 ]; then
           echo "USB Host can't recognize u-disk after loading gadget driver. Test Fail!"
           RC=9
        fi

        if [ -n "$CFS" ]; then
            usb_configfs.sh -c
        else
            modprobe -a -r g_mass_storage
        fi
        get_scsi.sh $host_pass $host_username $host_ip $acro_scpt_loc $arco_channel 4
        if [ $? -ne 0 ]; then
           echo "USB Host can't recognize u-disk after unloading gadget driver. Test Fail!"
           RC=9
        fi
        let ri=ri+1
        echo $ri
    done
    sleep 3
    umount_partition ${disk_node}
    modprobe -a -r $core_driver; modprobe -a -r $phy
    sleep 3

    #disconnect acroname
    acroname_operation disconnect

    return $RC
}

###########################################################################
#
#   TGE-LV-USB-LOADABLE-0014c
#
#   Note : step3:Hotplug test
#
##########################################################################
LOADABLE0010c()
{
    RC=0
    TCID="LOADABLE0014c"
    echo "--------------------------------------------------"
    echo "Reminder: This case need use special kernel and dtb"
    echo "--------------------------------------------------"
    sleep 10

    echo "=============================="
    echo "=     start $TCID      ="

    if [ -n "$tf_env" ];then
        check_cdc_device "mouse" || exit $RC
    fi
    modprobe -a $phy && modprobe -a $core_driver
    sleep 5

    #disconnect acroname
    acroname_operation disconnect

    i=1
    while [ $i -lt 6 ]
    do
        #disconnect acroname
        acroname_operation disconnect
        echo "testing $i times usb mouse plugin/plugout"
        #if [ -c /dev/$k64_port ];then
        #    echo 5 > /dev/$k64_port
        #    sleep 5
        #    de_init_cnt=$(ls -l /sys/class/input/ | grep -m 1 usb | wc -l)
        #else
        #    echo "It seems TWR-K64 image or hub broken"
        #    RC=9
        #    return $RC
        #fi
        #sleep 60

        de_init_cnt=$(ls -l /sys/class/input/ | grep -m 1 usb | wc -l)
        sleep 6
        #connect acroname
        acroname_operation connect

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

    #disconnect acroname
    acroname_operation disconnect

    return $RC
}

# Function:     - get_usb_device
# Description   - get all usb scsi devices
get_usb_device()
{
    #TODO give TCID
    TCID="GET_ALL_USB_SCSI_DEVICES"
    #TODO give TST_COUNT
    TST_COUNT=1
    RC=1

    #TODO add function test script here
    scsi_dir=/sys/class/scsi_device
    scsi_device=`ls $scsi_dir`
    if [ -z "$scsi_device" ];then
        #no scsi device, exit
        exit 1
    fi
    for i in $scsi_device; do
        usb_node=`readlink $scsi_dir/$i | grep usb`
        if [ -n "$usb_node" ];then
            usb_devices=`ls $scsi_dir/$i/device/block`
        fi
    done

    if [ -n "$usb_devices" ]; then
        echo $usb_devices
        RC=0
    fi

    return $RC
}

# Function:     - test_case_02
# Description   - test USB disk partition
test_case_02()
{
    #TODO give TCID
    TCID="TEST_USB_DISK_PARTITION"
    #TODO give TST_COUNT
    TST_COUNT=2
    RC=0

    #connect acroname
    acroname_operation connect

    disk_node=$(check_usb_device "disk")
    #delete duplicated device node
    disk_node=`echo "$disk_node" | sort | uniq`
    if [ -z "$disk_node" ]; then
        echo "Can't find the usb disk"
        RC=9
        return $RC
    fi
    # check whether we plugin multi disk. if it true, use the last one
    multi_flag=$(echo $disk_node | grep " ")
    if [ ! -z "$multi_flag" ]; then
        disk_node=$(echo "$disk_node" | awk '{print $NF}')
    fi

    disk_partion=$(cat /proc/partitions | grep ${disk_node}[1-9] | head -n 1 | awk '{print $NF}')
    if [ -n "$disk_partion" ]; then
        umount_partition $disk_node
        del_partition $disk_node
    fi

    create_a_partition $disk_node
    disk_partion=$partition

    if [ -z "$disk_partion" ]; then
        echo "Auto create disk partition failed, please creat a partition for $disk_node"
        RC=1
    fi

    #disconnect acroname
    acroname_operation disconnect

    return $RC
}

# Function:     - test_case_03
# Description   - test IO stress
test_case_03()
{
    #TODO give TCID
    TCID="TEST_IO_STRESS"
    #TODO give TST_COUNT
    TST_COUNT=3
    RC=3

    #connect acroname
    acroname_operation connect

    disk_node=$(check_usb_device "disk")
    #delete duplicated device node
    disk_node=`echo "$disk_node" | sort | uniq`
    if [ -z "$disk_node" ]; then
        echo "Can't find the usb disk"
        RC=9
        return $RC
    fi
    # check whether we plugin multi disk. if it true, use the last one
    multi_flag=$(echo $disk_node | grep " ")
    if [ ! -z "$multi_flag" ]; then
        disk_node=$(echo "$disk_node" | awk '{print $NF}')
    fi

    #delete the previous partiton to get a clean running env
    del_partition ${disk_node}
    disk_partion=$(cat /proc/partitions | grep ${disk_node}[1-9] | head -n 1 | awk '{print $NF}')
    if [ -z "$disk_partion" ]; then
        create_a_partition $disk_node
        disk_partion=$partition
    fi

    sleep 3
    umount_partition ${disk_node}
    umount /media/sdx

    limit=0
    mkdir -p /media/sdx
    mount /dev/$disk_partion /media/sdx || return $RC
    sleep 3
    limit=$(df |grep "$disk_partion" |awk '{print $4}' |sed 's/ //g')
    limit=$(expr $limit - 1)
    if [ $limit -lt 12800 ];then
        size=$limit
    else
        size=12800
    fi

     bonnie++ -d /media/sdx -u 0:0 -s 64 -r 32 || return $RC
     sleep 3
     dt of=/media/sdx/test_file bs=4k limit=${size}k passes=20 || return $RC

    if [ "$?" -eq 0 ];then
        RC=0
    fi

    #disconnect acroname
    acroname_operation disconnect

    return $RC
}

# Function:     - test_case_04
# Description   - test USB mouse move event
test_case_04()
{
    #TODO give TCID
    TCID="usb_mouse_move_evtest"
    #TODO give TST_COUNT
    TST_COUNT=4
    RC=4

    #connect acroname
    acroname_operation connect

   
    if [ -n "$tf_env" ];then
        check_cdc_device "mouse" || exit $RC
    fi
    #inputNo=`ls -l /sys/class/input/ | grep -m 1 usb | cut -d '/' -f 14`
    inputNo=`ls -l /sys/class/input/ | grep -m 1 usb | awk -F "/" '{print $(NF-1)}'`
    evNo=`find /sys/class/input/$inputNo/ -name "event*" | cut -d '/' -f 6`

    if [ -n "$evNo" ];then
        #usb_ev_testapp /dev/input/$evNo > /tmp/usb.log &
	
	# Replaced 'usb_ev_testapp' function with 'evtest' command
	# Used 'tee' command to redirect log
        evtest /dev/input/$evNo | tee /tmp/usb.log &
        usbpid=$!
        sleep 2
        kill $usbpid

        mouse_parm=$(cat /tmp/usb.log | sed -n -e '3p' | cut -d: -f2 | sed 's/"//g' | sed 's/ //g')

	# To make the testcase generic grepping the mouse keyword from the device name
	cat /tmp/usb.log | sed -n -e '3p' | cut -d: -f2 | sed 's/"//g' | sed 's/ //g' | grep -i mouse 
	mouse_parm_all=$?
        if [ $mouse_parm = "FREESCALESEMICONDUCTORINC.HID_CDCDEVICE" ] || [ $mouse_parm_all -eq 0 ];then
            RC=0
        else
            echo "usb mouse event failed"
            RC=4
        fi
    fi

    #disconnect acroname
    acroname_operation disconnect

    return $RC
}

# Function:     - test_case_05
# Description   - usb host remove test
test_case_05()
{
    #TODO give TCID
    TCID="usb_host_remove_test"
    #TODO give TST_COUNT
    TST_COUNT=5
    RC=5

    if [ -n "$tf_env" ];then
        check_cdc_device "mouse" || exit $RC
    fi
    #plugin/plugout test
    i=1
    while [ $i -lt 50 ]
    do
        echo "testing $i times usb mouse plugin/plugout"
        if [ -c /dev/$k64_port ];then
            t1=`date -d now +%s`
            echo 1 > /dev/$k64_port
            t2=`date -d now +%s`
            let dt=t2-t1
            if [ $dt -gt 7 ]; then # TWR-K64 untrustble removed, need to retry
                echo "ACM ack time too long, need retry this time"
                sleep 4
                continue
            fi
            sleep 1
            de_init_cnt=$(ls -l /sys/class/input/ | grep -m 1 usb | wc -l)
        else
            echo "TWR-K64 port not found"
        fi
        sleep 12
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

    return $RC
}

acroname_operation()
{
    case $1 in
        connect)
            sshpass -p $host_pass ssh $host_username@$host_ip -y python $acro_scpt_loc control $arco_channel && sleep 4 || RC=100
            ;;
        disconnect)
            sshpass -p $host_pass ssh $host_username@$host_ip -y python $acro_scpt_loc disable && sleep 4 || RC=101
            ;;
    esac
}

usage()
{
    echo
#    echo "$0 <CASE ID> "
    echo "$0 <host password> <host username> <host ip addr> <Acromame script location in host> <Channel of device conencted to Acroname> <CASE ID> "
    echo "CASE LIST:"
    echo "  HOST3001a  HOST3005a  HOST3006a"
    echo "  HDS001a     LOADABLE0010a   LOADABLE0014a"
    echo "  LOADABLE0010c  LOADABLE0014c"
    echo "1: get all usb scsi devices"
    echo "2: test USB disk partition"
    echo "3: test IO performance"
    echo "4: test USB mouse move event"
    echo "5: usb host remove test"
    echo "Example:"
    echo "  usb_host_board.sh HOST3005a"
    echo
    echo "As a tool : use it to check usb device"
#    echo "$0 check_usb_device <USB Category>"
    echo "$0 <host password> <host username> <host ip addr> <Acromame script location in host> <Channel of device conencted to Acroname> check_usb_device <USB Category>"
    echo "USB Category:"
    echo "  disk | mouse | microphone"
    echo "  loudspeaker | camera | keyboard"
    echo
    echo "Example:"
#    echo "  usb_host_board.sh check_usb_device camera"
    echo "  usb_host_board.sh <host password> <host username> <host ip addr> <Acromame script location in host> <Channel of device conencted to Acroname> check_usb_device camera"
    echo
    exit 1
}

 #main function
 export TST_TOTAL=8
 RC=0
 #if [ $# -ne 1 -a $# -ne 2 ]
 if [ $# -ne 6 -a $# -ne 7 ]
 then
     usage
 fi

 #acroname params
 host_pass=$1
 host_username=$2
 host_ip=$3
 acro_scpt_loc=$4
 arco_channel=$5

 setup || exit $RC

 rinfo=`uname -r | cut -d '.' -f 1-2 | sed 's/\.//'`
 if [ $rinfo -ge 49 ]; then
     CFS="configfs"
 fi

 SPEED="480"
# if [ "$2" = "SS" ]; then
 if [ "$7" = "SS" ]; then
     SPEED="5000"
 fi

 #case "$1" in
 case "$6" in
     HOST3001a|HOST3005a|HOST3006a| \
         HDS001a|LOADABLE0010a|LOADABLE0014a |\
         LOADABLE0010c)
#     $1 || exit $RC
     $6 || exit $RC
              ;;
     LOADABLE0014c)
         LOADABLE0010c || exit $RC
         ;;
     HOSTDVFS0001)
         DVFS0001 || exit $RC
         ;;
     check_usb_device)
#         $1 $2 || exit $RC
         $1 $2 || exit $RC
         ;;
     1)
         get_usb_device || exit $RC
         ;;
     2)
         test_case_02 || exit $RC
         ;;
     3)
         test_case_03 || exit $RC
         ;;
     4)
         test_case_04 || exit $RC
         ;;
     5)
         test_case_05 || exit $RC
         ;;
     *)
         usage
         ;;
esac

#if [ $# -eq 1 ]; then
if [ $# -eq 6 ]; then
    if [ $RC -eq 0 ]; then
        tst_resm TPASS "test PASS"
    else
        tst_resm TFAIL "test FAIL"
    fi
fi
