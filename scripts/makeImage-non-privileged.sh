#!/bin/bash
# For non-privileged LXD container
set -e
set -u

if [ -e ./firmadyne.config ]; then
    source ./firmadyne.config
elif [ -e ../firmadyne.config ]; then
    source ../firmadyne.config
else
    echo "Error: Could not find 'firmadyne.config'!"
    exit 1
fi

if check_number $1; then
    echo "Usage: makeImage.sh <image ID> [<architecture]"
    exit 1
fi
IID=${1}

if check_root; then
    echo "Error: This script requires root privileges!"
    exit 1
fi

if [ $# -gt 1 ]; then
    if check_arch "${2}"; then
        echo "Error: Invalid architecture!"
        exit 1
    fi

    ARCH=${2}
else
    echo -n "Querying database for architecture... "
    ARCH=$(psql -d firmware -U firmadyne -h 127.0.0.1 -t -q -c "SELECT arch from image WHERE id=${1};")
    ARCH="${ARCH#"${ARCH%%[![:space:]]*}"}"
    echo "${ARCH}"
    if [ -z "${ARCH}" ]; then
        echo "Error: Unable to lookup architecture. Please specify {armel,mipseb,mipsel} as the second argument!"
        exit 1
    fi
fi

echo "----Running----"
WORK_DIR=`get_scratch ${IID}`
IMAGE=`get_fs ${IID}`
IMAGE_DIR=`get_fs_mount ${IID}`
CONSOLE=`get_console ${ARCH}`
LIBNVRAM=`get_nvram ${ARCH}`

echo "----Creating working directory ${WORK_DIR}----"
mkdir -p "${WORK_DIR}"
chmod a+rwx "${WORK_DIR}"
chown -R "${USER}" "${WORK_DIR}"
chgrp -R "${USER}" "${WORK_DIR}"

if [ ! -e "${TARBALL_DIR}/${IID}.tar.gz" ]; then
    echo "Error: Cannot find tarball of root filesystem for ${IID}!"
    exit 1
fi


TARBALL_SIZE=$(tar ztvf "${TARBALL_DIR}/${IID}.tar.gz" --totals 2>&1 |tail -1|cut -f4 -d' ')
MINIMUM_IMAGE_SIZE=$((TARBALL_SIZE + 10 * 1024 * 1024))
echo "----The size of root filesystem '${TARBALL_DIR}/${IID}.tar.gz' is $TARBALL_SIZE-----"
IMAGE_SIZE=8388608
while [ $IMAGE_SIZE -le $MINIMUM_IMAGE_SIZE ]
do
    IMAGE_SIZE=$((IMAGE_SIZE*2))
done

echo "----Creating QEMU Image ${IMAGE} with size ${IMAGE_SIZE}----"
qemu-img create -f raw "${IMAGE}" $IMAGE_SIZE
chmod a+rw "${IMAGE}"

echo "----Creating Filesystem----"
virt-format --filesystem=ext2 -a "${IMAGE}"

echo "----Making QEMU Image Mountpoint at ${IMAGE_DIR}----"
if [ ! -e "${IMAGE_DIR}" ]; then
    mkdir "${IMAGE_DIR}"
    chown "${USER}" "${IMAGE_DIR}"
fi

# Use guestfish
guestfish -a "${IMAGE}" -m /dev/sda1 <<EOF
mkdir /firmadyne/
mkdir /firmadyne/libnvram/
mkdir /firmadyne/libnvram.override/
tar-in "${TARBALL_DIR}/${IID}.tar.gz" / compress:gzip xattrs:true acls:true
mknod-c 666 4 65 /firmadyne/ttyS1
EOF
sleep 1

echo "----Mounting QEMU Image Partition 1----"
guestmount -a "${IMAGE}" -m /dev/sda1 "${IMAGE_DIR}"
sleep 1

echo "----Patching Filesystem (chroot)----"
cp $(which busybox) "${IMAGE_DIR}"
cp "${SCRIPT_DIR}/fixImage-non-privileged.sh" "${IMAGE_DIR}"
chroot "${IMAGE_DIR}" /busybox ash /fixImage-non-privileged.sh
rm "${IMAGE_DIR}/fixImage-non-privileged.sh"
rm "${IMAGE_DIR}/busybox"

echo "----Setting up FIRMADYNE----"
cp "${CONSOLE}" "${IMAGE_DIR}/firmadyne/console"
chmod a+x "${IMAGE_DIR}/firmadyne/console"

cp "${LIBNVRAM}" "${IMAGE_DIR}/firmadyne/libnvram.so"
chmod a+x "${IMAGE_DIR}/firmadyne/libnvram.so"

cp "${SCRIPT_DIR}/preInit.sh" "${IMAGE_DIR}/firmadyne/preInit.sh"
chmod a+x "${IMAGE_DIR}/firmadyne/preInit.sh"

DEV_FILECOUNT="$(find ${IMAGE_DIR}/dev -maxdepth 1 -type b -o -type c -print | wc -l)"

echo "----Unmounting QEMU Image----"
guestunmount "${IMAGE_DIR}"
sleep 1

# add default device nodes if current /dev does not have greater
# than 5 device nodes
if [ $DEV_FILECOUNT -lt "5" ]; then
    echo "Warning: Recreating device nodes!"

    guestfish -a "${IMAGE}" -m /dev/sda1 <<EOF
    mknod-c 660 1 1 /dev/mem
    mknod-c 640 1 2 /dev/kmem
    mknod-c 666 1 3 /dev/null
    mknod-c 666 1 5 /dev/zero
    mknod-c 444 1 8 /dev/random
    mknod-c 444 1 9 /dev/urandom
    mknod-c 666 1 13 /dev/armem

    mknod-c 666 5 0 /dev/tty
    mknod-c 622 5 1 /dev/console
    mknod-c 666 5 2 /dev/ptmx

    mknod-c 622 4 0 /dev/tty0
    mknod-c 660 4 64 /dev/ttyS0
    mknod-c 660 4 65 /dev/ttyS1
    mknod-c 660 4 66 /dev/ttyS2
    mknod-c 660 4 67 /dev/ttyS3

    mknod-c 644 100 0 /dev/adsl0
    mknod-c 644 108 0 /dev/ppp
    mknod-c 666 251 0 /dev/hidraw0

    mkdir-p /dev/mtd
    mknod-c 644  90 0 /dev/mtd/0
    mknod-c 644  90 2 /dev/mtd/1
    mknod-c 644  90 4 /dev/mtd/2
    mknod-c 644  90 6 /dev/mtd/3
    mknod-c 644  90 8 /dev/mtd/4
    mknod-c 644  90 10 /dev/mtd/5
    mknod-c 644  90 12 /dev/mtd/6
    mknod-c 644  90 14 /dev/mtd/7
    mknod-c 644  90 16 /dev/mtd/8
    mknod-c 644  90 18 /dev/mtd/9
    mknod-c 644  90 20 /dev/mtd/10

    mknod-c 644 90 0 /dev/mtd0
    mknod-c 644 90 1 /dev/mtdr0
    mknod-c 644 90 2 /dev/mtd1
    mknod-c 644 90 3 /dev/mtdr1
    mknod-c 644 90 4 /dev/mtd2
    mknod-c 644 90 5 /dev/mtdr2
    mknod-c 644 90 6 /dev/mtd3
    mknod-c 644 90 7 /dev/mtdr3
    mknod-c 644 90 8 /dev/mtd4
    mknod-c 644 90 9 /dev/mtdr4
    mknod-c 644 90 10 /dev/mtd5
    mknod-c 644 90 11 /dev/mtdr5
    mknod-c 644 90 12 /dev/mtd6
    mknod-c 644 90 13 /dev/mtdr6
    mknod-c 644 90 14 /dev/mtd7
    mknod-c 644 90 15 /dev/mtdr7
    mknod-c 644 90 16 /dev/mtd8
    mknod-c 644 90 17 /dev/mtdr8
    mknod-c 644 90 18 /dev/mtd9
    mknod-c 644 90 19 /dev/mtdr9
    mknod-c 644 90 20 /dev/mtd10
    mknod-c 644 90 21 /dev/mtdr10

    mkdir-p /dev/mtdblock
    mknod-b 644 31 0 /dev/mtdblock/0
    mknod-b 644 31 1 /dev/mtdblock/1
    mknod-b 644 31 2 /dev/mtdblock/2
    mknod-b 644 31 3 /dev/mtdblock/3
    mknod-b 644 31 4 /dev/mtdblock/4
    mknod-b 644 31 5 /dev/mtdblock/5
    mknod-b 644 31 6 /dev/mtdblock/6
    mknod-b 644 31 7 /dev/mtdblock/7
    mknod-b 644 31 8 /dev/mtdblock/8
    mknod-b 644 31 9 /dev/mtdblock/9
    mknod-b 644 31 10 /dev/mtdblock/10

    mknod-b 644 31 0 /dev/mtdblock0
    mknod-b 644 31 1 /dev/mtdblock1
    mknod-b 644 31 2 /dev/mtdblock2
    mknod-b 644 31 3 /dev/mtdblock3
    mknod-b 644 31 4 /dev/mtdblock4
    mknod-b 644 31 5 /dev/mtdblock5
    mknod-b 644 31 6 /dev/mtdblock6
    mknod-b 644 31 7 /dev/mtdblock7
    mknod-b 644 31 8 /dev/mtdblock8
    mknod-b 644 31 9 /dev/mtdblock9
    mknod-b 644 31 10 /dev/mtdblock10

    mkdir-p /dev/tts
    mknod-c 660 4 64 /dev/tts/0
    mknod-c 660 4 65 /dev/tts/1
    mknod-c 660 4 66 /dev/tts/2
    mknod-c 660 4 67 /dev/tts/3
EOF
    sleep 1
fi
