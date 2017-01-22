#!/bin/bash
# Developed by Luca Coppadoro July 2014
# Help system inspired by Fred Weinhaus' scripts on ImageMagick
# 
# USAGE: autoshoot -f filename [-p port] [-d]
# USAGE: autoshoot [-h or -help]
# 
# OPTIONS:
# 
# -f      filename          name of the picture to take with gphoto2 and save
#                           in the current directory; 
#                           best not to use spaces in the name.
#
# -p      port              optional name of the usb port on the Raspberry Pi rev.B 
#                           where the camera is connected: <lower> or <upper>
#                           Default: the first camera found by gphoto2
#
# -d                        run in debug mode (no photo will be taken)
#
# -h, --help                show full help
#
###
# NAME: AUTOSHOOT 
# 
# PURPOSE: To take a picture with gphoto2 by automatically adjust the exposure 
# values (if the camera supports it) for day, night, sunrise and sunset.
# 
# DESCRIPTION: AUTOSHOOT takes a picture from the optionally specified USB port
# in the Rasperry Pi, using gphoto2. The exposure settings are selected with the 
# help of a companion script to have a better picture for day, night, and around
# sunset and sunrise. The picture is saved in the current directory with the 
# file name specified.
# 
# COMPATIBILIY: AUTOSHOOT is designed and tested on the Raspberry Pi rev.B,
# but might work elsewhere (e.g. Pi rev. B+, BeagleBoneBlack). 
# No guarantee that trapping of inconsistent parameters is complete and 
# foolproof.  
# It is NOT compatible with Mac OS X (as of v.10.9.4) due to incompatible 
# versions of 'bash' and 'date'.
# Use At Your Own Risk.
#
######
# 

################################################
# Globals
################################################
# used because crontab likes absolute paths
mydir="/var/www/"  # where this script lives on the pi
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games
# these absolute paths don't hurt either
mygrep="/bin/grep"
mysed="/bin/sed"
myawk="/usr/bin/awk"

################################################
# LOCATION SPECIFICS
# Descriptive names about this webcam and timezone settings
################################################
thislocation="cortina" 
thisWebcam="webcam-nord"
my_location_yahoo_code=714726
# this caption will be written under the webcam image
mycaption="Vista sulle Tofane - www.casarossacortina.it"
# the space separating the caption text from the date
# carful with its length if you want to right-justify the date.
caption2dateSpace="                                                  "
# set time for camera; it should be +2h (7200sec) for CET summertime, and 
# +1h for normal CET. 
# redirect stderr (2) to null to hide errors, also check exit status using || operator
#gphoto2 --set-config /main/other/d034=$(($(date '+%s')+7200)) 1>/dev/null || {
#    echo "GPhoto2 complained while setting camera date and time, abort." >&2
#    exit $?
#}
# camera zoom value for gphoto2
zoom_cam=35
# slideshow on aruba will start these minutes before (<=>negative value) sunrise...  
slideshow_start_before_sunrise=-45
# ...and stop these minutes after sunset
slideshow_stop_after_sunset=45

################################################
# FTP INFO 
################################################
# ftp site credentials
user=
pass=
# server ftp address
server=
# destination dire on server
dest_dir=
# url of the php script to create the slideshow image
image_resize_and_copy="http://....../imageresize_and_copy.php"
# same things but to a local server for backup
archive_user=
archive_pass=
archive_server=
archive_dest_dir=

################################################ 
# OVERLAY LOGO IMAGE
# A png or gif image to use as overlaid logo 
#################################################
logoCortina="my_logo_here.png"

#################################################
# GPHOTO2 command line options 
#################################################
# gphoto2 parameters that are ALWAYS used
default_parameters="--capture-image-and-download --force-overwrite"
# exposure for day and night
ev_day="--set-config zoom=$zoom_cam --set-config imagesize=0 --set-config imagequality=0 \
        --set-config iso=1 --set-config shootingmode=2 \
        --set-config aperture=8"
ev_night="--set-config zoom=$zoom_cam --set-config imagesize=0 --set-config imagequality=0 \
          --set-config iso=3 --set-config shootingmode=1 \
          --set-config shutterspeed=0"
# Exposure table for sunset/sunrise transition
# usage: ["minutes before/after sunrise/sunset"]="exposure string" 
# The exposure string will be used n minutes before/after sunrise
# NOTE: better limit the window in [-60, +60] minutes around the event.
# At most latitudes that will not cause issues, but some edge cases are not 
# handled correctly otherwise
declare -A ev_table_sunrise=( ["-45"]="$ev_day" )
declare -A ev_table_sunset=( ["45"]="$ev_night" )

#####################################################################
#####################################################################
# PROGRAM LOGIC STARTS HERE - CAREFUL WITH THE CODE BELOW
#####################################################################
#####################################################################
errMsg() 
{
    #echo ""
    echo $1 >&2
    #echo ""
    exit 1
}

declare Sundata_Convert12h_to_24h_RETURN
Sundata_Convert12h_to_24h() {
#
# convert to 24h sunrise hour
#

    local time_12h=$1      # ${sunrise[0]} 
    local meridian=$2      # ${sunrise[2]} = am or pm

    # echo time_12h: $time_12h >&2
    # echo meridian: $meridian >&2

    if [[ $meridian = "pm" ]]; then
        if [[ $time_12h = "12" ]]; then
            # if hour is 12pm (early afternoon) it remains 12 in 24h format too
            Sundata_Convert12h_to_24h_RETURN=12
        else 
            # add 12 hours
            Sundata_Convert12h_to_24h_RETURN=$(($time_12h + 12))
        fi
    elif [[ $meridian = "am" ]]; then
        if [[ $time_12h = "12" ]]; then
            # if hour is 12am it becomes 0 in 24h format
            Sundata_Convert12h_to_24h_RETURN="00"
        else 
            # no change
            Sundata_Convert12h_to_24h_RETURN="$time_12h"
        fi
    fi

    # echo Sundata_Convert12h_to_24h_RETURN: $Sundata_Convert12h_to_24h_RETURN >&2
}

function Sundata()
{
    # SUNDATA()
    # Use yahoo.com to get sun raise/set times for given locations
    # 
    # -r,   -sr,   --rise,        --sunrise
    #         print sunrise time (12h format)
    # -rh,  -srh,  --rise-hour,   --sunrise-hour
    #         print sunrise hour (24h format)
    # -rm,  -srm,  --rise-minutes --sunrise-minutes
    #         print sunrise minutes
    # -s,   -ss,   --set,         --sunset
    #         print sunset time (12h format)
    # -sh,  -ssh,  --set-hour,    --sunset-hour 
    #         print sunset hour (24h format)
    # -sm,  -ssm,  --set-minutes, --sunset-minutes 
    #         print sunset minutes
    # -c2r, -c2sr, --countdown-to-sunrise
    #         print countdown to sunrise in minutes
    # -c2s, -c2ss, --countdown-to-sunset
    #         print minutes to sunset in minutes

    #
    # set default parameters
    #
    local location=""
    local cortina_loc=$my_location_yahoo_code
    local result=""
    local sundata=""
    local debug=""

    #
    # get command line arguments
    #
    # test for correct number of arguments and get values
    if [ $# -eq 0 ]
        then
        # help information
        echo ""
        fullHelp
        exit 0
    elif [ $# -gt 2 ]
        then
        errMsg "--- TOO MANY ARGUMENTS WERE PROVIDED ---"
    else
        while [[ $# -gt 0 ]]; do
            # get parameter values
            case "$1" in
                -diano) # get locations
                        location="$diano_loc"
                        ;;
                -cortina)
                        location="$cortina_loc"
                        ;;
                -r|-sr|--rise|--sunrise)
                        result="sunrise"
                        ;;                
                -rh|-srh|--rise-hour|--sunrise-hour)
                        result="sunrise-hour"
                        ;;                
                -rm|-srm|--rise-minutes|--sunrise-minutes)
                        result="sunrise-minutes"
                        ;;                
                -s|-ss|--set|--sunset)
                        result="sunset"
                        ;;                
                -sh|-ssh|--set-hour|--sunset-hour)
                        result="sunset-hour"
                        ;;                
                -sm|-ssm|--set-minutes|--sunset-minutes)
                        result="sunset-minutes"
                        ;;                
                -c2r|-c2sr|--countdown-to-sunrise)
                        result="countdown-to-sunrise"
                        ;;                
                -c2s|-c2ss|--countdown-to-sunset)
                        result="countdown-to-sunset"
                        ;;                
                -d)    # debug flag
                       debug="true"
                       ;;
                -h|--help)    # help information
                       #echo ""
                       fullHelp
                       exit 0
                       ;;
                -*)    # any other - argument
                       errMsg "--- UNKNOWN OPTION: $1 ---"
                       ;;
                 *)    # end of arguments
                       #echo "UNKNOWN OPTION: $1"
                       #exit 1
                       ;;
            esac
            shift   # next option
        done
    fi

    # validate inputs
    [ "$location" = "" ] && errMsg "--- UNKNOWN LOCATION ---"
    #[ "$debug" = "true" ] && echo location: $location >&2

    # get sundata from yahoo
    oldifs="$IFS" # save input field separator
    IFS=$'\n'     # set newline as new separator
    sundata=($(/usr/bin/curl -s http://weather.yahooapis.com/forecastrss?w=$location | \
        $mygrep astronomy | \
        $myawk -F\" '{print $2 "\n" $4;}'))
    IFS="$oldifs"    # restore original separator
    
    #echo sundata[0]: ${sundata[0]} >&2
    #echo sundata[1]: ${sundata[1]} >&2

    # if sundata is valid, save it
    # note the escaped space in the regex
    if [[ "${sundata[0]}" =~ [0-9]{0,2}:[0-9]{1,2}\ (am|pm)  ]]; then
            #echo "Saving valid sundata..." >&2 
            echo "${sundata[0]}" > "$mydir"sundata.txt 
            echo "${sundata[1]}" >> "$mydir"sundata.txt
    else
        echo "Invalid sundata from yahoo. Loading from disk last saved sundata..." >&2 
        # if not, reuse the last saved data
        oldifs="$IFS"    # save input field separator
        IFS=$'\n'        # set newline as new separator
        sundata=($(cat "$mydir"sundata.txt))
        IFS="$oldifs"    # restore original separator
        # if that's not valid, panic
        if [[ "${sundata[0]}" =~ [0-9]{0,2}:[0-9]{1,2}\ (am|pm)  ]]; then
            echo "...using last valid saved sundata" >&2 
        else
            echo "Saved sundata also invalid. Panic." >&2 
            errMsg "No valid sun data found"
        fi
    fi

    # parse the times in two meaningful arrays
    # set internal field separator to both 'space' and ':'
    oldifs="$IFS" # save input field separator
    IFS=" :"
    sunrise=(${sundata[0]})  # = (5, 42, am)
    sunset=(${sundata[1]})   # = (8, 51, pm)
    # restore original separator
    IFS="$oldifs"

    #echo sunrise: ${sunrise[@]} >&2
    #echo sunset: ${sunset[@]} >&2

    #
    # convert to 24h sunrise hour
    #
    declare sunrise_24h
    Sundata_Convert12h_to_24h "${sunrise[0]}" "${sunrise[2]}"
    sunrise_24h=$Sundata_Convert12h_to_24h_RETURN
    #echo sunrise_24h: $sunrise_24h >&2

    #
    # convert to 24h sunset hour
    #
    declare sunset_24h
    Sundata_Convert12h_to_24h "${sunset[0]}" "${sunset[2]}"
    sunset_24h=$Sundata_Convert12h_to_24h_RETURN
    #echo sunset_24h: $sunset_24h >&2

    #
    # minutes
    #
    # sunrise minutes
    sunrise_min=${sunrise[1]}
    # echo sunrise_min: $sunrise_min >&2

    # sunset minutes
    sunset_min=${sunset[1]}
    # echo sunset_min: $sunset_min >&2


    #
    # time now
    #
    timenow_24h=$(date +%0H)
    timenow_min=$(date +%0M)

    # convert times in minutes since midnight
    # NOTE: number starting with '0' are by default octal in bash, 
    #       so we force base 10 with '10#'
    timenow_abs=$((10#$timenow_24h*60 + 10#$timenow_min))
    sunrise_abs=$((10#$sunrise_24h*60 + 10#$sunrise_min))
    sunset_abs=$((10#$sunset_24h*60 + 10#$sunset_min))

    # echo sunrise_abs: $sunrise_abs >&2
    # echo sunset_abs: $sunset_abs >&2

    #
    # return the required time fields
    #
    case "$result" in
        sunrise)
                echo "${sunrise[@]}"
                ;;                
        sunrise-hour)
                echo "$sunrise_24h"
                ;;                
        sunrise-minutes)
                echo "$sunrise_min"
                ;;                
        sunset)
                echo "${sunset[@]}"
                ;;                
        sunset-hour)
                echo "$sunset_24h"
                ;;                
        sunset-minutes)
                echo "$sunset_min"
                ;;                
        countdown-to-sunrise)
                echo $(( $timenow_abs-$sunrise_abs ))
                ;;                
        countdown-to-sunset)
                echo $(( $timenow_abs-$sunset_abs ))
                ;;                
        *)    # end of arguments
               echo "No sun data format specified" >&2
               exit 1
               ;;
    esac

    exit 0
}

function Evinfo() 
{
    echo "Calculating exposure..." >&2

    #
    # analyse the exposure tables
    #
    # find the max minutes before the sunrise
    max_minutes_before_sunrise=0
    for these_minutes_before_sunrise in ${!ev_table_sunrise[@]}
    do
        # remember, I want the lowest negative number!
        if (( $these_minutes_before_sunrise < $max_minutes_before_sunrise )); then
            max_minutes_before_sunrise=$these_minutes_before_sunrise
        fi
    done
    # find the max minutes after sunrise 
    max_minutes_after_sunrise=0
    for these_minutes_after_sunrise in ${!ev_table_sunrise[@]}
    do
        # remember, I want the highest positive number!
        if (( $these_minutes_after_sunrise > $max_minutes_after_sunrise )); then
            max_minutes_after_sunrise=$these_minutes_after_sunrise
        fi
    done
    # find the max minutes before sunset
    max_minutes_before_sunset=0
    for these_minutes_before_sunset in ${!ev_table_sunset[@]}
    do
        # remember, I want the lowest negative number!
        if (( $these_minutes_before_sunset < $max_minutes_before_sunset )); then
            max_minutes_before_sunset=$these_minutes_before_sunset
        fi
    done
    # find the max minutes after sunset
    max_minutes_after_sunset=0
    for these_minutes_after_sunset in ${!ev_table_sunset[@]}
    do
        # remember, I want the highest positive number!
        if (( $these_minutes_after_sunset > $max_minutes_after_sunset )); then
            max_minutes_after_sunset=$these_minutes_after_sunset
        fi
    done

    #
    # get info about sunrise/set
    #
    minutes2sunset=$(Sundata -$thislocation -c2s)
    minutes2sunrise=$(Sundata -$thislocation -c2r)
    # clever trick for ternary operator
    # echo $minutes2sunset minutes $( (($minutes2sunset <= 0)) && echo "to" || echo "after" ) sunset >&2
    # echo $minutes2sunrise minutes $( (($minutes2sunrise <= 0)) &&  echo "to" || echo "after" ) sunrise >&2

    # set SUNRISE exposure 
    # if we are within the sunrise window
    if (( $minutes2sunrise >= $max_minutes_before_sunrise )) && \
       (( $minutes2sunrise <= $max_minutes_after_sunrise )); then
        # find the key for exposure value closest to the current minutes missing to sunrise
        # when less minutes that the key are missing to sunrise
        # start by getting the lowest possible key (=furthest away before sunrise)
        higest_lower_key_value=$max_minutes_before_sunrise
        for key in ${!ev_table_sunrise[@]}
        do
            # find the max among the keys smaller than my minutes
            if (( $minutes2sunrise > $key)); then
                # save the max of the possible keys, it will be the closest
                # to the actual missing minutes
                if (( $key > $higest_lower_key_value )); then
                    # append the key to the array of possible exposures
                    higest_lower_key_value=$key
                fi
            fi
        done
        set_exposure=${ev_table_sunrise[$higest_lower_key_value]}
    # set SUNSET exposure 
    # if we are within the sunset window
    elif (( $minutes2sunset >= $max_minutes_before_sunset )) && \
       (( $minutes2sunset <= $max_minutes_after_sunset )); then
        # start by getting the lowest possible key (=furthest away before sunset)
        closest_lower_minutes_to_sunset_from_table=$max_minutes_before_sunset
        for these_minutes_to_sunset_from_table in ${!ev_table_sunset[@]}
        do
            # if we are past a given entry in the table 
            # find that entry and use its value as my exposure
            if (( $minutes2sunset > $these_minutes_to_sunset_from_table)) && \
               (( $these_minutes_to_sunset_from_table > $closest_lower_minutes_to_sunset_from_table )); then
                closest_lower_minutes_to_sunset_from_table=$these_minutes_to_sunset_from_table
            fi
        done
        set_exposure=${ev_table_sunset["$closest_lower_minutes_to_sunset_from_table"]}
    # set DAY exposure
    # true if we are after sunrise window AND before sunset window
    elif (( $minutes2sunrise >= $max_minutes_after_sunrise )) && \
         (( $minutes2sunset <= $max_minutes_before_sunset )) ; then
        # if we are after sunrise AND 
        # before sunset
        set_exposure=$ev_day
    # set NIGHT exposure
    # true if we are after sunset window (which is true only until
    # midnight), OR before sunrise window (from midnight to sunrise)
    elif (( $minutes2sunset >= $max_minutes_after_sunset )) || \
         (( $minutes2sunrise <= $max_minutes_before_sunrise )); then
        # if we are after sunset OR 
        # before sunrise
        set_exposure=$ev_night
    else 
        echo "*** Out of boundaries with exposure calculation ***" >&2
        echo "*** defaulting to ev_day *** " >&2
        set_exposure=$ev_day    
    fi

    #debug
    #echo key: $closest_lower_minutes_to_sunset_from_table
    #echo set_exposure: $set_exposure


    #
    # Return exposure value
    # 
    echo $set_exposure
    #echo Exposure is: $set_exposure >&2 
    # emergency exposure...
    #echo $ev_day
    exit 0
}

function Upload() 
{

    #
    # default values
    #
    local debug=""
    local filename=""
    local tempfile="added_to_slideshow_ok"

    #
    # get command line arguments
    #
    while [[ $# -gt 0 ]]; do
        # get parameter values
        case "$1" in
            -f)    # debug flag
                   shift  # to get the next parameter
                   filename="$1"
                   ;;
            -d)    # debug flag
                   debug="true"
                   ;;
             -)    # STDIN and end of arguments
                   #break
                   ;;
            -*)    # any other - argument
                   echo "UNKNOWN OPTION: $1"
                   exit 1
                   ;;
             *)    # end of arguments
                   #echo "UNKNOWN OPTION: $1"
                   #exit 1
                   ;;
        esac
        shift   # next option
    done

    #
    # Warn about unspecified parameters
    #
    [ "$filename" = "" ] && (echo "No ftp filename specified: -f <filename>" ; exit 1)

    echo
    echo "Uploading..."
    #
    # Upload it to the ftp server
    #
    # setup ftp program
    ftp_command="/usr/bin/ncftpput -T .tmp -u $user -p $pass $server $dest_dir $filename"
    # run it if not debugging
    [ "$debug" = "true" ] && echo $ftp_command || $ftp_command 2>&1

    echo
    echo "Adding daytime pics to slideshow on server..."
    # Only add this picture to the slideshow in daylight
    minutes2sunset=$(Sundata -$thislocation -c2s)
    minutes2sunrise=$(Sundata -$thislocation -c2r)

    # From n min before sunrise to m min after sunset, upload
    if (( $minutes2sunrise >= $slideshow_start_before_sunrise )) && (( $minutes2sunset <= $slideshow_stop_after_sunset )); then
        # echo minutes2sunrise = $minutes2sunrise >&2
        # echo slideshow_start_before_sunrise = $slideshow_start_before_sunrise >&2
        # echo minutes2sunset = $minutes2sunset >&2
        # echo slideshow_stop_after_sunset = $slideshow_stop_after_sunset >&2

        # invoke a server side php script to create a resized copy on the server for the slideshow
        /usr/bin/wget -nv -O "${mydir}${tempfile}" $image_resize_and_copy 2>&1
    else
        echo "Not daytime, nothing to add."
    fi
}

function Archive() 
{
    local fullres_filename=$1
    local timenow=$(date +%Y-%m-%d_%H-%M)
    local filedate=$(LANG=it_IT.UTF-8 /bin/date -r $1 +%Y-%m-%d_%H-%M)
    local archive_filename="${mydir}${filedate}".jpg

    echo
    echo "Archiving full resolution image..."
    # create a renamed copy of full-res file with date
    # and upload renamed copy to archive
    cp "$fullres_filename" "$archive_filename"
    /usr/bin/ncftpput -m -u "$archive_user" -p "$archive_pass" "$archive_server" \
                      "$archive_dest_dir" "$archive_filename"
    # delete renamed copy
    rm "$archive_filename"
}

function Label() 
{

    local myconvert="/usr/bin/convert"
    local mycomposite="/usr/bin/composite"
    local mymogrify="/usr/bin/mogrify"
    local verbose="-verbose"
    
    local text=$(/usr/bin/identify -format %[EXIF:DateTime] $1)
    local filedate=$(LANG=it_IT.UTF-8 /bin/date -r $1 "+%a %d %b %Y %H:%M")
    
    echo
    echo "Resizing image..."

    # resize full res to 1600x1200 and get new width
    $mymogrify $verbose -resize 1600x1200 "$1"
    local width=$(/usr/bin/identify -format %w $1)

    echo
    echo "Adding image description and overlay..."
    
    # add caption to image
    $myconvert $verbose \
        -size ${width}x63 -background '#00000080' -fill white \
        -font Helvetica-Bold -pointsize 32 -gravity center \
        caption:" $mycaption $caption2dateSpace $filedate  " \
        miff:- | \
        $mycomposite $verbose -gravity south \
                  - \
                  "$1" \
                  miff:- |
        $mycomposite $verbose -gravity northeast \
                  "${mydir}${logoCortina}"  \
                  - \
                  "$1"
}

function Gphoto2smart() 
{

    # NOTE: must use bash, not sh

    # DESCRIPTION:
    # This script allows you to tell gphoto2 to take an action on the camera attached
    # to a specific USB physical port ("upper" or "lower" by default, but these
    # names can be changed). This is useful because the normal logic port IDs used
    # by gphoto2 (like usb:001,004) can change between reboots of the Pi or of the
    # cameras. The physical port ID does not change.
    # 

    ##################################################
    ### NOTE: set the following values accordingly ###
    #
    # 1) full path to the gphoto2 executable
    #
    local gphoto_path="/usr/local/bin/gphoto2"

    #
    # 2) Descriptive name for the usb ports used on the cmd line
    #
    # These can be changed to something you like if you want
    # like for example the subject the camera is pointing at
    local usb_phy_port_lower_name="lower"
    local usb_phy_port_upper_name="upper"
    local all_cameras="all"
    ##################################################

    #
    # gphoto autodetect for logic usb ports numbers
    #
    #gp="Canon PowerShot S3 IS (PTP mode) usb:001,005
    #Canon PowerShot S3 IS (PTP mode) usb:001,004"
    local gp
    # note: declare $gp as local but define on separate line so that 
    # subshell exit status can be captured
    gp=$($gphoto_path --auto-detect)
    #echo gp = $gp >&2
    # check exit status
    if (($? > 0)); then
        echo "GPhoto2 complained, abort." >&2
        # send exit signal; not sure if this exits the function or
        # the whole shell script
        kill -s TERM $TOP_PID
        exit 1
    fi

    #
    # lsusb -t output for mapping logic ports to physical ones
    #
    #lsusb_t="1-1.2:1.0: No such file or directory
    #1-1.3:1.0: No such file or directory
    #/:  Bus 01.Port 1: Dev 1, Class=root_hub, Driver=dwc_otg/1p, 480M
    #    |local __ Port 1: Dev 2, If 0, Class=hub, Driver=hub/5p, 480M
    #        |__ Port 1: Dev 3, If 0, Class=vend., Driver=smsc95xx, 480M
    #        |__ Port 2: Dev 4, If 0, Class=still, Driver=, 480M
    #        |__ Port 3: Dev 5, If 0, Class=still, Driver=, 480M"
    local lsusb_t 
    lsusb_t=$(lsusb -t 2>&1)
    # check exit status
    if (($? > 0)); then
        echo "lsusb complained, abort." >&2
        # send exit signal
        kill -s TERM $TOP_PID
        exit 1
    fi

    #
    # Physical ports IDs on a Raspberry Pi version B. See lsusb output above.
    # NOTE: it's ok to hardcode the IDs here because they never change
    #
    # DO NOT EDIT
    local usb_phy_port_lower_id="2"  
    # DO NOT EDIT
    local usb_phy_port_upper_id="3"


    #
    # Extract in an array the logic usb ports from gphoto output with sed. If no camera
    # has been detected, exit.
    # Sed command explanation:
    # s/.../.../...     search command
    # .*                any number of characters
    # \(...\)           token to extract
    # usb:[0-9]*,[0-9]* the string "usb:" followed by the string "<any number of digits>,<any
    #                   number of digits>"
    # \1                print the matched token back to stdout
    #
    local usb_logic_ports
    usb_logic_ports=($(echo "$gp" 2>&1 | $mygrep "usb:" | $mysed 's/.*\(usb:[0-9]*,[0-9]*\).*/\1/'))
    #echo usb_logic_ports = "${usb_logic_ports[@]}" >&2
    if ((${#usb_logic_ports[@]} == 0)); then
        echo "No camera detected." >&2
        # send exit signal
        kill -s TERM $TOP_PID
        exit 1
    fi

    #
    # Create and fill an associative array to map a physical usb port number to 
    # the corresponding gphoto2 logic port name
    # For example: usb_ports_phy2logic[usb_phy_port_lower_id] => "usb:001,005"
    #
    declare -A usb_ports_phy2logic
    for logic_port in "${usb_logic_ports[@]}"
    do
        # Here, logic_port is in the form "usb:001,005" 
        # I must extract the logic port number, i.e. the last number in the string (5 in the example above). 
        # The port number is indeed usually 4 or 5, but the counter can go up
        # to 18, 19 or more (usb:001,019). Probaby it can go up to three digits numbers (usb:001,112). 
        # Whatever the logic port number, that number will be shown by lsusb below, and with no
        # leading zeros (=5, 19, or 112). So those must be removed, extracting the substring (005, 019, etc.) 
        # is not enough. After extracting the substring, we can do the magic with some very tricky and 
        # advanced parameter expansion, and extended globbing.
        # See http://www.linuxjournal.com/content/bash-extended-globbing and http://stackoverflow.com/questions/8078167/bizarre-issue-with-printf-in-bash-script09-and-08-are-invalid-numbers-07#comment9903141_8078505
        #
        # Get the substring (from position 8, for 3 char)
        #echo logic_port = $logic_port >&2
        logic_port_num_with_zeros="${logic_port:8:3}"
        #echo logic_port_num_with_zeros = "$logic_port_num_with_zeros" >&2

        # Remove the leading zeros from the substring with parameter expansion
        # Enable extended globbing first (required for the +(0) expansion to work)
        shopt -s extglob
        logic_port_num="${logic_port_num_with_zeros##+(0)}"
        #echo logic_port_num = $logic_port_num >&2

        # replace the number in logic_port
        logic_port=$logic_port_num
        #echo logic_port = $logic_port >&2

        # get the physical port for each logic port
        phy_port=$(echo "$lsusb_t" | $mygrep "Dev ${logic_port}" | \
            $mysed 's/.*Port \([0-9]\): Dev '${logic_port}',.*/\1/')
        #echo phy_port = "$phy_port" >&2
        # map the ports
        usb_ports_phy2logic[$phy_port]=$logic_port
    done


    #
    # Extract in an associative array the camera names; this is not really required, since
    # we use the usb port as camera handle.
    # Note: camera name contains spaces, so the elements of the array must
    # be parsed using the newline separator
    #
    declare -A camera_names
    oldifs="$IFS" # save input field separator
    IFS=$'\n'     # set newline as new separator
    camera_names[$usb_phy_port_lower_name]=$(echo "$gp" 2>&1 | \
        $mygrep "${usb_ports_phy2logic[$usb_phy_port_lower_id]}" | \
        $mysed 's/^\(.*\) '${usb_ports_phy2logic[$usb_phy_port_lower_id]}'.*/\1/')
    camera_names[$usb_phy_port_upper_name]=$(echo "$gp" 2>&1 | \
        $mygrep "${usb_ports_phy2logic[$usb_phy_port_upper_id]}" | \
        $mysed 's/^\(.*\) '${usb_ports_phy2logic[$usb_phy_port_upper_id]}'.*/\1/')
    IFS="$oldifs" # restore original separator


    #
    # Say hello
    #
    echo "Detected ${#usb_logic_ports[@]} camera(s):"
    # lower usb port
    if [[ ${usb_ports_phy2logic[$usb_phy_port_lower_id]} != "" ]]; then
        echo \"${camera_names[$usb_phy_port_lower_name]}\" \
            is on physical port $usb_phy_port_lower_id \(lower\) \
            with logic port ${usb_ports_phy2logic[$usb_phy_port_lower_id]} >&2
    fi
    # upper usb port
    if [[ ${usb_ports_phy2logic[$usb_phy_port_upper_id]} != "" ]]; then
        echo \"${camera_names[$usb_phy_port_upper_name]}\" \
            is on physical port $usb_phy_port_upper_id \(upper\) \
            with logic port ${usb_ports_phy2logic[$usb_phy_port_upper_id]} >&2
    fi


    #
    # Loop through all the cmd line arguments and
    # check what physical port is specified there, save it, then remove it from the cmd line
    #
    #port=""
    local myport=""
    declare argv=($@) # copy $@ without original token split
    local arg_num=0   # because argv is zero-indexed, not 1-indexed like $@

    #echo '$@: '$@
    #echo '${argv[@]}: '${argv[@]}

    for arg in ${argv[@]}  # no "" here to loop across all individual words of argv
    do
        #echo arg: $arg
        case "$arg" in 
            # find the --port option        
            --port)
                # save the next token (which is the port)
                myport=${argv[$((arg_num+1))]}
                #echo "port found: $myport"  >&2
                #port="--port $myport"
                # remove "--port" and "upper/lower/all" port from the command line
                # note that $@ is 1-indexed, but arg_num starts from 0
                #echo $arg_num >&2
                #echo "Arguments: \"$@\"" >&2
                #set -- ${@:1:arg_num} ${@:arg_num + 3:$#}
                #echo "Arguments: \"$@\"" >&2
                #echo '${argv[@]}: '${argv[@]} >&2
                argv=(${argv[@]:0:arg_num} ${argv[@]:arg_num + 2 :$#})
                #echo '${argv[@]}: '${argv[@]} >&2
                ;;
            
            *)
                # no match
                ;;
        esac
        # increment the counter; the $ inside the (()) is optional
        arg_num=$(($arg_num + 1))    
    done

    #echo "myport: $myport" >&2


    #
    # take the picture on the requested port
    #
    if [[ $myport = "" ]]; then

        # just pass the arguments to gphoto2 with no change
        #echo
        echo "No usb port specified, using first camera available" >&2
        $gphoto_path "${argv[@]}"

    elif [[ $myport = $usb_phy_port_lower_name ]] || [[ $myport = ${usb_ports_phy2logic[$usb_phy_port_lower_id]} ]]; then

        # Check that there is indeed a camera connected to the lower port
        if [[ ${usb_ports_phy2logic[$usb_phy_port_lower_id]} != "" ]]; then
            echo >&2
            echo "Taking picture from camera on **LOWER** usb port" >&2
            $gphoto_path --port "${usb_ports_phy2logic[$usb_phy_port_lower_id]}" "${argv[@]}"
        else 
            echo No camera on $myport usb port >&2
        fi

    elif [[ $myport = $usb_phy_port_upper_name ]] || [[ $myport = ${usb_ports_phy2logic[$usb_phy_port_upper_id]} ]]; then

        # Check that there is indeed a camera connected to the lower port
        if [[ ${usb_ports_phy2logic[$usb_phy_port_upper_id]} != "" ]]; then
            echo >&2
            echo "Taking picture from camera on **UPPER** usb port" >&2
            $gphoto_path --port "${usb_ports_phy2logic[$usb_phy_port_upper_id]}" "${argv[@]}"
        else 
            echo No camera on $myport usb port >&2
        fi

    elif [[ $myport = $all_cameras ]]; then

        echo >&2
        echo "Taking picture on all ports (experimental)" >&2
        
        # Take photo on both ports
        # Loop thourgh the arrays and take the photos
        for key in "${!usb_ports_phy2logic[@]}"
        do
            echo $gphoto_path --port "${usb_ports_phy2logic[$key]}" "${argv[@]}" >&2
        done

    else 
        # if no valid port argument found, stop and raise an error
        echo No camera on \"$myport\" usb port  >&2
        echo "Must specify a valid usb port on the command line:" >&2
        echo "     \"--port $usb_phy_port_upper_name\"  to use the camera connected to the upper physical USB port" >&2   
        echo "     \"--port $usb_phy_port_lower_name\"  to use the camera connected to the lower physical USB port" >&2
        echo "     you can omit \"--port ... \" if only one camera is connected, or to use the first camera available" >&2  
        #echo "     \"--port $all_cameras\"  for all cameras (experimental)" >&2
    fi

    exit 0
}

#####################################################################
# MAIN PROGRAM
#####################################################################
#
# default values
#
debug=""                              # true if running in debug mode
set_port=""
set_filename=""

# To enable exiting the whole script from any function
trap "exit 1" TERM
export TOP_PID=$$

PROGNAME=$(type $0 | $myawk '{print $3}')  # search for executable on path
PROGDIR=$(dirname $PROGNAME)            # extract directory of program
PROGNAME=$(basename $PROGNAME)          # base name of program


shortHelp() 
{
    #echo >&2 ""
    #echo >&2 "$PROGNAME:" "$@"
    $mysed >&2 -n '/^###/q;  /^#/!q;  s/^#//;  s/^ //;  4,$p' "$PROGDIR/$PROGNAME"
}
fullHelp() 
{
    #echo >&2 ""
    #echo >&2 "$PROGNAME:" "$@"
    $mysed >&2 -n '/^######/q;  /^#/!q;  s/^#*//;  s/^ //;  4,$p' "$PROGDIR/$PROGNAME"
}

#
# get command line arguments
#
# test for correct number of arguments and get values
if [ $# -eq 0 ]
  then
  # help information
   echo ""
   fullHelp
   exit 0
elif [ $# -gt 5 ]
  then
  errMsg "--- TOO MANY ARGUMENTS WERE PROVIDED ---"
else
    while [[ $# -gt 0 ]]; do
        # get parameter values
        case "$1" in
            -p)    # get port
                   shift  # to get the next parameter
                   set_port="--port $1"
                   ;;
            -f)    # get filename
                   shift  # to get the next parameter
                   set_filename="--filename $mydir$1"
                   ;;
            -d)    # debug flag
                   debug="true"
                   ;;
            -h|--help)    # help information
                   #echo ""
                   fullHelp
                   exit 0
                   ;;
            -*)    # any other - argument
                   errMsg "--- UNKNOWN OPTION: $1 ---"
                   ;;
             *)    # end of arguments
                   #echo "UNKNOWN OPTION: $1"
                   #exit 1
                   ;;
        esac
        shift   # next option
    done
fi

#
# Warn about unspecified parameters
#
#[ "$set_port" = "" ] && (echo "No port specified; will use first camera found by gphoto2") # ; exit 1)
#[ "$set_filename" = "" ] && (echo "No filename specified; will use camera filename") # ; exit 1)

#debug
[ "$debug" = "true" ] && (echo ; echo     set_port: $set_port)
[ "$debug" = "true" ] &&         echo set_filename: $set_filename
[ "$debug" = "true" ] &&         echo set_exposure: $set_exposure

echo Command line parameters ok >&2

#
# Detect cameras
# NOTE: this is also done inside Gphoto2smart() using gphoto2 exit status,
# but this here should be a better way to do it based on actual text
# returned by gphoto2
#
echo Checking cameras...
gphoto_path="/usr/local/bin/gphoto2"
gp_det=$($gphoto_path --auto-detect)
#echo gp_det = $gp_det >&2

gphoto2_cameras=($(echo "$gp_det" 2>&1 | $mygrep "usb:" | $mysed 's/.*\(usb:[0-9]*,[0-9]*\).*/\1/'))
#echo gphoto2_cameras = $gphoto2_cameras >&2

#echo usb_logic_ports = "${usb_logic_ports[@]}" >&2
if ((${#gphoto2_cameras[@]} == 0)); then
    echo "No camera detected." >&2
    # send exit signal
    kill -s TERM $TOP_PID
    exit 1
fi

#
# Get basic camera info for gphoto2 command line parameters
#
gp2s=Gphoto2smart

#
# Get exposure info for gphoto2 command line parameters
#
set_exposure=$(Evinfo)

#
# Take a picture with gphoto2 and save output; the camera name is not strictly necessary
#
# Play a trick with stdout redirection to be able to save the output of this
# command, but at the same time show it on the console
# Duplicate &1 in your shell (in this case to 5) and use &5 in the subshell
# so that you will write to stdout (&1) of the parent shell:
exec 5>&1
gp2="$gp2s $set_exposure $set_filename $set_port $default_parameters"

# if debug, show the command only, else run
#[ "$debug" = "true" ] && (echo ; echo gp2: $gp2) || gp2_out=$($gp2 2>&1 | tee >(cat - >&5)) 
gp2_out=$($gp2 2>&1 | tee >(cat - >&5)) 
# extract filename from gphoto2 output
filename=$(echo "${gp2_out[@]}" 2>&1 | $mygrep "Saving file as" | $mysed 's/^Saving file as \(.*\).*/\1/')

#
# Archive the image
#
Archive "$filename"

#
# Set nice overlay on the image
#
add_label_cmd=Label
$add_label_cmd "$filename"

#
# Upload it to the ftp server
#
myftp_cmd=Upload
$myftp_cmd -f "$filename" 2>&1

echo
echo "Done"

exit 0
