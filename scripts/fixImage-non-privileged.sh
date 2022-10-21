#!/bin/sh

# use busybox statically-compiled version of all binaries
BUSYBOX="/busybox"

# print input if not symlink, otherwise attempt to resolve symlink
resolve_link() {
    TARGET=$($BUSYBOX readlink $1)
    if [ -z "$TARGET" ]; then
        echo "$1"
    fi
    echo "$TARGET"
}

backup_file(){
    if [ -f "$1" ]; then
        echo "Backing up $1 to ${1}.bak"
        $BUSYBOX cp "$1" "${1}.bak"
    fi
}

rename_file(){
    if [ -f "$1" ]; then
        echo "Renaming $1 to ${1}.bak"
        $BUSYBOX mv "$1" "${1}.bak"
    fi
}

remove_file(){
    if [ -f "$1" ]; then
        echo "Removing $1"
        $BUSYBOX rm -f "$1"
    fi
}
# make /etc and add some essential files
$BUSYBOX mkdir -p "$(resolve_link /etc)"
if [ ! -s /etc/TZ ]; then
    echo "Creating /etc/TZ!"
    $BUSYBOX mkdir -p "$(dirname $(resolve_link /etc/TZ))"
    echo "EST5EDT" > "$(resolve_link /etc/TZ)"
fi

if [ ! -s /etc/hosts ]; then
    echo "Creating /etc/hosts!"
    $BUSYBOX mkdir -p "$(dirname $(resolve_link /etc/hosts))"
    echo "127.0.0.1 localhost" > "$(resolve_link /etc/hosts)"
fi

PASSWD=$(resolve_link /etc/passwd)
SHADOW=$(resolve_link /etc/shadow)
if [ ! -s "$PASSWD" ]; then
    echo "Creating $PASSWD!"
    $BUSYBOX mkdir -p "$(dirname $PASSWD)"
    echo "root::0:0:root:/root:/bin/sh" > "$PASSWD"
else
    backup_file $PASSWD
    backup_file $SHADOW
    if ! $BUSYBOX grep -sq "^root:" $PASSWD ; then
        echo "No root user found, creating root user with shell '/bin/sh'"
        echo "root::0:0:root:/root:/bin/sh" > "$PASSWD"
        $BUSYBOX [ ! -d '/root' ] && $BUSYBOX mkdir /root
    fi

    if [ -z "$($BUSYBOX grep -Es '^root:' $PASSWD |$BUSYBOX grep -Es ':/bin/sh$')" ] ; then
        echo "Fixing shell for root user"
        $BUSYBOX sed -ir 's/^(root:.*):[^:]+$/\1:\/bin\/sh/' $PASSWD
    fi

    if [ ! -z "$($BUSYBOX grep -Es '^root:[^:]+' $PASSWD)" -o ! -z "$($BUSYBOX grep -Es '^root:[^:]+' $SHADOW)" ]; then
        echo "Unlocking and blanking default root password. (*May not work since some routers reset the password back to default when booting)"
        $BUSYBOX sed -ir 's/^(root:)[^:]+:/\1:/' $PASSWD
        $BUSYBOX sed -ir 's/^(root:)[^:]+:/\1:/' $SHADOW
    fi
fi

# make /dev and add default device nodes if current /dev does not have greater
# than 5 device nodes (device nodes added later)
$BUSYBOX mkdir -p "$(resolve_link /dev)"

# create a gpio file required for linksys to make the watchdog happy
if ($BUSYBOX grep -sq "/dev/gpio/in" /bin/gpio) ||
  ($BUSYBOX grep -sq "/dev/gpio/in" /usr/lib/libcm.so) ||
  ($BUSYBOX grep -sq "/dev/gpio/in" /usr/lib/libshared.so); then
    echo "Creating /dev/gpio/in!"
    $BUSYBOX mkdir -p /dev/gpio
    echo -ne "\xff\xff\xff\xff" > /dev/gpio/in
fi

# prevent system from rebooting
#echo "Removing /sbin/reboot!"
#rm -f /sbin/reboot
remove_file /etc/scripts/sys_resetbutton

# add some default nvram entries
if $BUSYBOX grep -sq "ipv6_6to4_lan_ip" /sbin/rc; then
    echo "Creating default ipv6_6to4_lan_ip!"
    echo -n "2002:7f00:0001::" > /firmadyne/libnvram.override/ipv6_6to4_lan_ip
fi

if $BUSYBOX grep -sq "time_zone_x" /lib/libacos_shared.so; then
    echo "Creating default time_zone_x!"
    echo -n "0" > /firmadyne/libnvram.override/time_zone_x
fi

if $BUSYBOX grep -sq "rip_multicast" /usr/sbin/httpd; then
    echo "Creating default rip_multicast!"
    echo -n "0" > /firmadyne/libnvram.override/rip_multicast
fi

if $BUSYBOX grep -sq "bs_trustedip_enable" /usr/sbin/httpd; then
    echo "Creating default bs_trustedip_enable!"
    echo -n "0" > /firmadyne/libnvram.override/bs_trustedip_enable
fi

if $BUSYBOX grep -sq "filter_rule_tbl" /usr/sbin/httpd; then
    echo "Creating default filter_rule_tbl!"
    echo -n "" > /firmadyne/libnvram.override/filter_rule_tbl
fi

if $BUSYBOX grep -sq "rip_enable" /sbin/acos_service; then
    echo "Creating default rip_enable!"
    echo -n "0" > /firmadyne/libnvram.override/rip_enable
fi

rename_file /etc/securetty
