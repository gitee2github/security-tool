#!/bin/sh
#######################################################################################
#
# Copyright (c) Huawei Technologies Co., Ltd. 2019. All rights reserved.
# security-tool licensed under the Mulan PSL v1.
# You can use this software according to the terms and conditions of the Mulan PSL v1.
# You may obtain a copy of Mulan PSL v1 at:
#     http://license.coscl.org.cn/MulanPSL
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR
# PURPOSE.
# See the Mulan PSL v1 for more details.
# Description: openEuler Security Tool
#
#######################################################################################
# name of this script
readonly NAME=`basename $0`
# working directory
readonly WORKD=`pwd`/
# the separator of fields of security configration file
readonly FIELD_SEP='@'

# distinction
DST=""
# security configuration file
SCONF=""
# USER security configuration file
USR_SCONF=""
# File where to write log
LOGFILE=""
# flag
SILENT=0
# execute configure item's id
EXECID=0
# temporary target of decompress and compress
TMPTARGET="openEuler"

# distinction type(rootfs, ar, cpio.gz)
DST_TYPE="rootfs"
# directory of decompressed rootfs
ROOTFS=""
# distinction name when it's not rootfs
AR_F=""
GZ_F=""

##############################################################################

#=============================================================================
# Function Name: pushd/popd
# Description  : the same to standard pushd/popd except that no info printed
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function pushd()
{
    builtin pushd "$@" > /dev/null
    return $?
}
function popd()
{
    builtin popd "$@" > /dev/null
    return $?
}

#=============================================================================
# Function Name: fn_test_params_num
# Description  : test if the num of params is the right num(do not support flexible parameters), quit otherwise
# Parameter    : params_num
# Returns      : none
#=============================================================================
function _fn_test_params_num()
{
    if [ $# -lt 3 ] || [ $2 -ne $3 ]; then
        echo "Line $1: num of params $2 not equals to $3"
        exit 1
    fi
}
alias fn_test_params_num='_fn_test_params_num $LINENO $#'

#=============================================================================
# Function Name: fn_test_type
# Description  : test if the specific file type by a keyword
# Parameter    : file, keyword(directory, cpio archive, gzip compressed, ar archive, ...)
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_test_type()
{
    fn_test_params_num 2

    file "$1"| awk -F: '{print $2}' |grep "$2" >/dev/null
    return $?
}

#=============================================================================
# Function Name: fn_get_fullpath
# Description  : get absolute path name of file
# Parameter    : file
# Returns      : fullpath
#=============================================================================
function fn_get_fullpath()
{
    fn_test_params_num 1

    local p=$1
    local out

    if [ "${p:0:1}" = "/" ]; then
        echo $p
        return
    fi

    pushd `dirname $p`
    out=`pwd`
    popd
    echo $out"/"`basename $p`
}

#=============================================================================
# Function Name: fn_escape_string
# Description  : set special character(/) in the string to be escaped
# Parameter    : string
# Returns      : escaped string
#=============================================================================
function fn_escape_string()
{
    fn_test_params_num 1

    echo "$1"| sed 's/\//\\\//g'| sed 's/\./\\\./g'| sed 's/\[/\\[/g'| sed 's/\]/\\]/g' | sed 's/\$/\\\$/g' | sed 's/\*/\\\*/g'
}

#=============================================================================
# Function Name: fn_log
# Description  : write a message to log file or console
# Parameter    : lineno level(error, warn, info) message
# Returns      : none
#=============================================================================
function fn_log()
{
    fn_test_params_num 3

    local lno=$1
    local level=$2
    shift 2

    if [ $SILENT -eq 0 ] || [ "$level" = "error" ]; then
        output=$@
        opt=`echo $output | grep -e "success$"`
        if [ $? -eq 0 ];then
            output=`echo $opt | sed -r 's/success$/\\\033\\[32;1msuccess\\\033\\[0m/g'`
        fi
        opt=`echo $output | grep -e "fail$"`
        if [ $? -eq 0 ];then
            output=`echo $opt | sed -r 's/fail$/\\\033\\[31;1mfail\\\033\\[0m/g'`
        fi
        echo -e "[$NAME:$lno] [$level] $output"
    fi

    echo "`date +%Y-%m-%d\ %H:%M:%S` [$NAME:$lno] [$level] $@" >> $LOGFILE
}
alias fn_error='fn_log $LINENO error'
alias fn_warn='fn_log $LINENO warn'
alias fn_info='fn_log $LINENO info'

#=============================================================================
# Function Name: fn_exit
# Description  : to be excuted when exit with return value(0 ok, 1 params error, 2 hardening error)
# Parameter    : status(0 ok, otherwise error), [message]
# Returns      : none
#=============================================================================
function fn_exit()
{
    fn_test_params_num 1
    local s=$1
    # cleanup when destination is cpio.gz
        if [ "$DST_TYPE" = "tar.gz" ]; then
                if [ $s -eq 0 ]; then
                        local new_initrd=$WORKD`basename $GZ_F`".secure"
                        pushd $ROOTFS
                        tar -cf -- "$ROOTFS/$TMPTARGET" *
                        gzip <"$ROOTFS/$TMPTARGET" > $new_initrd
                        fn_info "hardened initrd is $new_initrd"
                        popd
                fi

                # cleanup rootfs
                rm -rf $ROOTFS
        fi

    # cleanup when destination is cpio.gz
    if [ "$DST_TYPE" = "cpio.gz" ]; then
        if [ $s -eq 0 ]; then
            local new_initrd=$WORKD`basename $GZ_F`".secure"
            pushd $ROOTFS
            find . |cpio --quiet -co |gzip > $new_initrd
            fn_info "hardened initrd is $new_initrd"
            popd
        fi

        # cleanup rootfs
        rm -rf $ROOTFS
    fi

    # cleanup when destination is ar target
    if [ "$DST_TYPE" = "ar" ]; then
        if [ $s -eq 0 ]; then
            local new_ar=$WORKD`basename $AR_F`".secure"
            cp $AR_F $new_ar

            pushd $ROOTFS
            find . |cpio --quiet -co|gzip > $GZ_F
            popd
            ar -r $new_ar $GZ_F
            if [ $? -eq 0 ]; then
                fn_info "initrd.cpio.gz updated"
            else
                fn_error "fail to replace initrd.cpio.gz in $AR_F by $GZ_F"
                fn_exit 1
            fi

            # update checksum in new ar target
            rm -f checksum
            ar -x $new_ar checksum
            if [ -f checksum ]; then
                local sum=`cksum $GZ_F | awk '{print $1}'`
                sed -i "s/^initrd\.cpio\.gz.*/initrd\.cpio\.gz $sum/" checksum
                ar -r $new_ar checksum
                rm checksum
                fn_info "checksum updated"
            fi

            fn_info "finish updating, new target is $new_ar"
        fi

        # cleanup initrd and rootfs
        fn_info "cleanup GZ [$GZ_F] and ROOTFS [$ROOTFS]"
        rm -f $GZ_F
        rm -rf $ROOTFS
    fi

    # log
    fn_info "========exit, status is [$s]========"
    exit $s
}

#=============================================================================
# Function Name: fn_usage
# Description  : print help messages to console
# Parameter    : none
# Returns      : none
#=============================================================================
function fn_usage()
{
    cat <<EOF
    openEuler Security Tool
    Usage:     $NAME [Options]
    Options
        -c config_file
            Specify the security configuration file
	-u config_file
	    Specify the security configuration file for users
        -d distinction
            AR format target or cpio.gz format rootfs to be hardened
        -l log_file
            Specify a file to save logs, which is default openEuler-security.log
        -x item_id
            Specify the id of security configuration item to be hardened
        -h
            Display help messages
        -s
            Silent mode, without any confirmation or generic printing
EOF
}

#=============================================================================
# Function Name: fn_parse_params
# Description  : parse all the parameters from user
# Parameter    : user params
# Returns      : none
#=============================================================================
function fn_parse_params()
{
    local args=$@

    if [ $# -eq 0 ] || [ "$1" = "-h" ]; then
        fn_usage
        exit 0
    fi

    while getopts c:u:d:l:x:s arg $args
    do
        case "$arg" in
        c) SCONF=`fn_get_fullpath $OPTARG`;;
        u) USR_SCONF=`fn_get_fullpath $OPTARG`;;
        d) DST=`fn_get_fullpath $OPTARG`;;
        l) LOGFILE=`fn_get_fullpath $OPTARG`;;
        s) SILENT=1;;
        x) EXECID=$OPTARG;;
        *) echo "unknown args:$args"
           fn_usage
           exit 1;;
        esac
    done

    # Test if dst and conf is valid
    if [ ! -e "$DST" ]; then
        echo "distinction [$DST] not existed"
        exit 1
    fi

    if [ ! -e "$SCONF" ]; then
        echo "config_file [$SCONF] not existed"
        exit 1
    fi

    if [ ! -e "$USR_SCONF" ]; then
        echo "config_file [$USR_SCONF] not existed"
        exit 1
    fi

    # first get LOGFILE resolved
    if [ "$LOGFILE" = "" ]; then
        LOGFILE=$WORKD'openEuler-security.log'
    fi
    mkdir -p `dirname $LOGFILE`
    touch $LOGFILE
    chown root:root $LOGFILE
    chmod 600 $LOGFILE

    # Confirmation
    if [ $SILENT -eq 0 ]; then
        while true
        do
            echo -n "Are you sure to do security hardening on $DST[Y/N]:"
            read rep
            if [ "$rep" = "n" ] || [ "$rep" = "N" ]; then
                fn_info "exit $NAME by user..."
                fn_exit 0
            elif [ "$rep" = "y" ] || [ "$rep" = "Y" ]; then
                break
            fi
        done
        unset rep
    fi

    readonly DST
    readonly SCONF
    readonly LOGFILE
    readonly SILENT
    readonly EXECID

    fn_info "working dir is [$WORKD], logging file is [$LOGFILE]"
    fn_info "parsing params[$args] done"
}

#=============================================================================
# Function Name: fn_pre_hardening
# Description  : uncompress ar or cpio.gz source to rootfs
# Parameter    : none
# Returns      : none
#=============================================================================
function fn_pre_hardening()
{
    fn_info "begin pre_hardening"

    if [ -d "$DST" ]; then
        ROOTFS=$DST
        fn_info "hardening destination is a rootfs dir [$ROOTFS]"
        return
    fi

    fn_test_type "$DST" "ar archive"
    if [ $? -eq 0 ]; then
        DST_TYPE="ar"
        AR_F=$DST
        GZ_F=$WORKD"initrd.cpio.gz"
        if [ -f "$GZ_F" ]; then
            rm -f $GZ_F
            fn_warn "existed $GZ_F removed"
        fi

        pushd $WORKD
        ar -x $AR_F $GZ_F
        if [ $? -ne 0 ] || [ ! -f "$GZ_F" ]; then
            fn_error "fail to extract initrd.cpio.gz from [$AR_F]"
            fn_exit 2
        fi
        popd
    else
        fn_test_type "$DST" "gzip compressed"
        if [ $? -eq 0 ]; then
            GZ_F=$DST
        else
            fn_error "destination format not ar or cpio.gz, quit..."
            fn_exit 2
        fi
    fi

    fn_info "pre_hardening: GZ is [$GZ_F]"

    ROOTFS=$WORKD"initrd.`date +%Y%m%d%H%M%S`"
    mkdir -p $ROOTFS
    if [ ! -d "$ROOTFS" ]; then
        fn_error "fail to mkdir [$ROOTFS]"
        fn_exit 2
    fi

    # fill rootfs dir with filesystem
    pushd $ROOTFS
    zcat $GZ_F > "$ROOTFS/$TMPTARGET"
    if [ $? -ne 0 ]; then
        fn_error "fail to extract [$GZ_F] to $ROOTFS/$TMPTARGET"
        fn_exit 2
    fi

    fn_test_type "$ROOTFS/$TMPTARGET" "cpio archive"
    if [ $? -eq 0 ]; then
        cpio --quiet -id <"$ROOTFS/$TMPTARGET" >/dev/null
        if [ $? -ne 0 ]; then
            fn_error "fail to extract [$GZ_F] to $ROOTFS"
            fn_exit 2
        fi
        if [ "$DST_TYPE" != "ar" ];then
            DST_TYPE="cpio.gz"
        fi
    else
        tar -xvf "$ROOTFS/$TMPTARGET" >/dev/null
        if [ $? -ne 0 ]; then
            fn_error "fail to extract [$GZ_F] to $ROOTFS"
            fn_exit 2
        fi
        DST_TYPE="tar.gz"
    fi
    rm -f "$ROOTFS/$TMPTARGET"
    popd

    fn_info "pre_hardening done"
}

#=============================================================================
# Function Name: fn_check_rootfs
# Description  : examine if rootfs is a standard hiberarchy
# Parameter    : none
# Returns      : none
#=============================================================================
function fn_check_rootfs()
{
    for i in bin usr/bin sbin usr/sbin etc boot lib home root opt var tmp proc sys mnt
    do
        if [ ! -d "$ROOTFS/$i" ]; then
            if [ $i == "boot" ];then
                continue
            fi
            fn_error "[$ROOTFS] is not a standard openEuler rootfs"
            fn_exit 2
        fi
    done
    if [ ! -d "$ROOTFS"/boot ]; then
        fn_info "[$ROOTFS] is a openEuler iSula rootfs"
    fi
}

#=============================================================================
# Function Name: fn_handle_key
# Description  : deal with configurations referred to key and value
# Parameter    : operator, file, key, f4, f5
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_handle_key()
{
    fn_test_params_num 5

    local op file
    op=$1
    file=$2

    file=$ROOTFS$file
    if [ ! -w "$file" ]; then
        fn_warn "file [$file] not existed or writable"
        return 1
    fi

    # key and value with string escaped
    local key f4 f5
    key=`fn_escape_string "$3"`
    f4=`fn_escape_string "$4"`
    f5=`fn_escape_string "$5"`

    # to ingore the differences of key caused by blank characters
    echo "$key" | egrep "^-e.*"
    if [[ $? == 0 ]]
    then
        local grepkey="[[:blank:]]*"`echo "$key" | sed -r 's/[[:blank:]]+/[[:blank:]]\+/g'`
    else
        local grepkey="[[:blank:]]*"`echo $key | sed -r 's/[[:blank:]]+/[[:blank:]]\+/g'`
    fi

    case "$op" in
    # d@file@key
    d)
        grep -E "$grepkey" $file >/dev/null
        if [ $? -eq 0 ]; then
            # comment a line
            sed -ri "s/^[^#]*$grepkey/#&/" $file
            return $?
        else
            return 0
        fi
        ;;
    # m@file@key[@value]
    m)
        grep -E "^$grepkey" $file >/dev/null
        if [ $? -eq 0 ]; then
            sed -ri "s/^$grepkey.*/$key$f4/g" $file
        else
            # add a blank line to file because sed cannot deal with empty file by 'a'
            if [ ! -s $file ]; then
                echo >> $file
            fi

            sed -i "\$a $key$f4" $file
        fi

        return $?
        ;;
    # sm@file@key[@value] similar to m: strict modify on the origin position
    sm)
        grep -E "^$grepkey" $file >/dev/null
        if [ $? -eq 0 ]; then
            sed -ri "s/$key.*/$key$f4/g" $file
        else
            # add a blank line to file because sed cannot deal with empty file by 'a'
            if [ ! -s $file ]; then
                echo >> $file
            fi
            sed -i "\$a $key$f4" $file
        fi

        return $?
        ;;
    # M@file@key@key2[@value2]
    M)
        grep -E "^$grepkey" $file >/dev/null
        if [ $? -eq 0 ]; then
            grep "^$grepkey.*$f4" $file >/dev/null
            if [ $? -eq 0 ]; then
                sed -ri "/^$grepkey/ s/$f4[^[:space:]]*/$f4$f5/g" $file
            else
                sed -ri "s/^$grepkey.*/&$f4$f5/g" $file
            fi

            return $?
        else
            fn_warn "key [$key] not found in [$file]"
            return 1
        fi
        ;;
    *)
        fn_error "bad operator [$op]"
        return 1
        ;;
    esac
}

#=============================================================================
# Function Name: fn_handle_command
# Description  : deal with configurations referred to operations to files
# Parameter    : command[option], files
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_handle_command()
{
    fn_test_params_num 2

    local op=$1
    local files=$2
    local status=0

    # add ROOTFS path for every file
    for file in `echo "$files" | awk -v rf="$ROOTFS" '{
        for(i=1; i<=NF; i++) {
                       printf "%s%s\n",rf,$i
        }
    }'`; do
        ${op} ${file} >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            status=1
        fi
    done
    unset f

    return $status
}

#=============================================================================
# Function Name: fn_handle_cp
# Description  : deal with configurations referred to operations to files
# Parameter    : src_file dst_file
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_handle_cp()
{
    fn_test_params_num 2

    src_file=$1
    dst_file=$2

    cp -p $src_file $ROOTFS/$dst_file
    if [ $? -ne 0 ]; then
        return 1
    else
        return 0
    fi
}

#=============================================================================
# Function Name: fn_handle_systemctl
# Description  : start or stop services
# Parameter    : service_name service_status
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_handle_systemctl()
{
    fn_test_params_num 2

    syetem_service_name=$1
    syetem_service_status=$2

    systemctl ${syetem_service_status} ${syetem_service_name}

    return $?
}

#=============================================================================
# Function Name: fn_handle_umask
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_handle_umask()
{
    fn_test_params_num 2

    local target=$1
    local value=$2
    local ret=0

    if [ "$target" == "user" ]
    then
        echo "umask $value" >> "$ROOTFS/etc/bashrc"
        echo "umask $value" >> "$ROOTFS/etc/csh.cshrc"
        for file in $(find "$ROOTFS/etc/profile.d/" -type f)
        do
           echo '' >> $file # 防止配置文件末尾没有换行符的情况
           echo "umask $value" >> $file
        done
    elif [ "$target" == "deamon" ]
    then
        echo "umask $value" >> "$ROOTFS/etc/sysconfig/init"
    else
        ret=1
    fi

    return $ret
}

#=============================================================================
# Function Name: fn_handle_ln
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_handle_ln()
{
    fn_test_params_num 3

    local arg=$1
    local target=$2
    local link_file=$3
    chroot $ROOTFS  ln "$arg" "$target" "$link_file"
    return $?
}


#=============================================================================
# Function Name: fn_harden_rootfs
# Description  : harden the rootfs, according to configuration file
# Parameter    : none
# Returns      : none
#=============================================================================
function fn_harden_rootfs()
{
    fn_check_rootfs

    fn_info "---begin hardening rootfs by [$SCONF]---"
    local status
    local f1 f2 f3 f4 f5 f6

    #  do configuration traversal, with comments and lines starting with blankspace ignored
    grep -v '^#' $SCONF| grep -v '^$'| grep -Ev '^[[:space:]]+'| while read line
    do
        f1=`echo "$line" | awk -F$FIELD_SEP '{print $1}'`
        if [ $EXECID -ne 0 ] && [ "$EXECID" -ne "$f1" ];then
            continue
        fi

        if [[ $line =~ "@@" ]]
        then
	PRE_IFS=$IFS
	IFS='@'
            arr=($line)
	    IFS=$PRE_IFS
            pos=1
            for ((i=2;i<${#arr[*]};i++))
            do
                if [[ x${arr[$i]} = x ]]
                then
                    tem="${arr[$((i-1))]}@${arr[$((i+1))]}"
                    i=$((i+1))
                    arr[$pos]=$tem
                    arr[$i]=$tem
                else
                    pos=$((pos+1))
                    arr[$pos]=${arr[$i]}
                fi
            done

            pos=$((pos+1))
            for ((j=$pos;j<${#arr[*]};j++))
            do
                arr[$j]=
            done

            f2=${arr[1]}
            f3=${arr[2]}
            f4=${arr[3]}
            f5=${arr[4]}
            f6=${arr[5]}
        else
            f2=`echo "$line" | awk -F$FIELD_SEP '{print $2}'`
            f3=`echo "$line" | awk -F$FIELD_SEP '{print $3}'`
            f4=`echo "$line" | awk -F$FIELD_SEP '{print $4}'`
            f5=`echo "$line" | awk -F$FIELD_SEP '{print $5}'`
            f6=`echo "$line" | awk -F$FIELD_SEP '{print $6}'`
        fi

        case "$f2" in
        d|m|sm|M)
            fn_handle_key "$f2" "$f3" "$f4" "$f5" "$f6"
            status=$?
            ;;
        cp)
            fn_handle_cp "$f3" "$f4"
            status=$?
            ;;
        systemctl)
            fn_handle_systemctl "$f3" "$f4"
            status=$?
            ;;
        umask)
            fn_handle_umask "$f3" "$f4"
            status=$?
            ;;
        ln)
            fn_handle_ln "$f3" "$f4" "$f5"
            status=$?
            ;;
        *)
            fn_handle_command "$f2" "$f3"
            status=$?
            ;;
        esac

        if [ $status -eq 0 ]; then
            fn_info "-harden [$line]: success"
        else
            fn_warn "-harden [$line]: fail"
        fi
    done
    unset line
    fn_info "---end hardening rootfs---"

    fn_check_rootfs
}

#=============================================================================
# Function Name: fn_harden_usr_conf
# Description  : harden the user conf, according to configuration file usr_security.conf
# Parameter    : none
# Returns      : none
#=============================================================================
function fn_harden_usr_conf()
{
    fn_check_rootfs

    fn_info "---begin hardening SUER CONF by [$USR_SCONF]---"
    local status
    local f1 f2 f3 f4 f5 f6

    #  do configuration traversal, with comments and lines starting with blankspace ignored
    grep -v '^#' $USR_SCONF| grep -v '^$'| grep -Ev '^[[:space:]]+'| while read line
    do
        f1=`echo "$line" | awk -F$FIELD_SEP '{print $1}'`
        if [ $EXECID -ne 0 ] && [ "$EXECID" -ne "$f1" ];then
            continue
        fi

        if [[ $line =~ "@@" ]]
        then
            #eval $(echo $line | awk '{split($0, filearray, "@");for(i in filearray)print "arr["i"]="filearray[i]}')
PRE_IFS=$IFS
IFS='@'
        arr=($line)
IFS=$PRE_IFS
            pos=1
            for ((i=2;i<${#arr[*]};i++))
            do
                if [[ x${arr[$i]} = x ]]
                then
                    tem="${arr[$((i-1))]}@${arr[$((i+1))]}"
                    i=$((i+1))
                    arr[$pos]=$tem
                    arr[$i]=$tem
                else
                    pos=$((pos+1))
                    arr[$pos]=${arr[$i]}
                fi
            done

            pos=$((pos+1))
            for ((j=$pos;j<${#arr[*]};j++))
            do
                arr[$j]=
            done

            f2=${arr[1]}
            f3=${arr[2]}
            f4=${arr[3]}
            f5=${arr[4]}
            f6=${arr[5]}
        else
            f2=`echo "$line" | awk -F$FIELD_SEP '{print $2}'`
            f3=`echo "$line" | awk -F$FIELD_SEP '{print $3}'`
            f4=`echo "$line" | awk -F$FIELD_SEP '{print $4}'`
            f5=`echo "$line" | awk -F$FIELD_SEP '{print $5}'`
            f6=`echo "$line" | awk -F$FIELD_SEP '{print $6}'`
        fi
 
        case "$f2" in
        d|m|sm|M)
            fn_handle_key "$f2" "$f3" "$f4" "$f5" "$f6"
            status=$?
            ;;
        cp)
            fn_handle_cp "$f3" "$f4"
            status=$?
            ;;
        systemctl)
            fn_handle_systemctl "$f3" "$f4"
            status=$?
            ;;
        umask)
            fn_handle_umask "$f3" "$f4"
            status=$?
            ;;
        ln)
            fn_handle_ln "$f3" "$f4" "$f5"
            status=$?
            ;;
        *)
            fn_handle_command "$f2" "$f3"
            status=$?
            ;;
        esac

        if [ $status -eq 0 ]; then
            fn_info "-harden [$line]: success"
        else
            fn_warn "-harden [$line]: fail"
        fi
    done
    unset line
    fn_info "---end hardening USER CONF---"

    fn_check_rootfs
}

#=============================================================================
# Function Name: fn_harden_nouser_nogroup
# Description  : Remove nouser and nogroup files
# Parameter    : none
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_harden_nouser_nogroup()
{
    local option=""
    local command="chown -R root.root"
    local dir=""
    local file=""
    local dirs=`mount | awk '{ if($5!="proc" && $1!="/proc")print $3}'`

    for option in -nouser -nogroup; do
        for dir in ${dirs}; do
            for file in `find $dir -xdev $option`; do
                fn_handle_command "$command" "$file"
            done
        done
    done
}

#=============================================================================
# Function Name: fn_harden_grub2
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_harden_grub2()
{
    echo -e "cat <<EOF\nset superusers="root"\npassword_pbkdf2 root grub.pbkdf2.sha512.10000.5A45748D892672FDA02DD3B6F7AE390AC6E6D532A600D4AC477D25C7D087644697D8A0894DFED9D86DC2A27F4E01D925C46417A225FC099C12DBD3D7D49A7425.2BD2F5BF4907DCC389CC5D165DB85CC3E2C94C8F9A30B01DACAA9CD552B731BA1DD3B7CC2C765704D55B8CD962D2AEF19A753CBE9B8464E2B1EB39A3BB4EAB08\nEOF\n" >> /etc/grub.d/00_header
    if [ -d /boot/efi/EFI/openEuler -a -d /sys/firmware/efi ]; then
        grub2-mkconfig -o /boot/efi/EFI/openEuler/grub.cfg
    fi
}
# Function Name: fn_harden_sysctl
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_harden_sysctl()
{
    /sbin/sysctl -p /etc/sysctl.conf
}

#============================================================================
# Function Name: fn_baseStripInvalidLink
# Description  : removing invalidlink
#============================================================================
function fn_baseStripInvalidLink()
{
    echo '
#!/bin/bash

for path in /etc /lib /lib64 /usr /var
do
    find $path -type l -follow -exec ls {} \; | while read link_file
    do
        if [ ! -z "$(ls -l $link_file | grep -v '/boot/')" ];then
            stat -L $link_file 1>/dev/null 2>&1
            [ "$?" != 0 ] && rm -f $link_file && echo "Removing invalidlink:$link_file"
        fi
    done
done ' > $ROOTFS/baseStripInvalidLink.sh
    echo $ROOTFS
    chroot $ROOTFS chmod u+x baseStripInvalidLink.sh
    chroot $ROOTFS sh baseStripInvalidLink.sh
    chroot $ROOTFS rm -rf baseStripInvalidLink.sh
}

#=============================================================================
# Function Name: fn_main
# Description  : main function
# Parameter    : command line params
# Returns      : 0 on success, otherwise on fail
#=============================================================================
function fn_main()
{
    # operator must be root
    if [ `id -u` -ne 0 ]; then
        echo "You must be logged in as root."
        exit 1
    fi

    # parse user params
    fn_parse_params "$@"

    # pre-process
    fn_pre_hardening

    if [ "x${OPENEULER_SECURITY}" = "x0" ]
    then
        # harden rootfs
        fn_harden_rootfs

	# harden grub2
        fn_harden_grub2

        fn_harden_sysctl

        sed -i "s/^OPENEULER_SECURITY=.*$/OPENEULER_SECURITY=1/g" /etc/openEuler_security/security
    elif [ "x${OPENEULER_SECURITY}" = "x1" ]
    then
        fn_harden_sysctl
    else
        echo "the value of OPENEULER_SECURITY is unexpected! please check it."
    fi

    # harden user conf
    fn_harden_usr_conf

    # disable the service in system start
    systemctl disable openEuler-security.service

    # do cleanup and exit
    fn_exit 0
}

# check cancel action and do cleanup
trap "echo 'canceled by user...'; fn_exit 1" INT TERM
# main entrance

fn_main "$@"

exit 0

