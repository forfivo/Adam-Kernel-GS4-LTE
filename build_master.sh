#!/bin/sh
export PLATFORM="TW"
export BASE="alucard"
export MREV="KK4.4"
export CURDATE=`date "+%m.%d.%Y"`
export MUXEDNAMELONG="forfivo-$BASE-SGS4-$MREV-$PLATFORM-$CARRIER-$CURDATE"
export MUXEDNAMESHRT="forfivo-$BASE-SGS4-$MREV-$PLATFORM-$CARRIER*"
export VER="--$MUXEDNAMELONG--"
export KERNELDIR=`readlink -f .`
export PARENT_DIR=`readlink -f ..`
export INITRAMFS_DEST=$KERNELDIR/kernel/usr/initramfs
export INITRAMFS_SOURCE=`readlink -f ..`/Ramdisks/$PLATFORM"_"$CARRIER"4.4"
export CONFIG_$PLATFORM_BUILD=y
export PACKAGEDIR=$PARENT_DIR/Packages/$PLATFORM
#Enable FIPS mode
export USE_SEC_FIPS_MODE=true
export ARCH=arm
#export CROSS_COMPILE=/home/gm/Documentos/android_prebuilt_toolchains-master/arm-linux-androideabi-4.7/bin/arm-linux-androideabi-
export CROSS_COMPILE=../linaro_toolchains_2014/arm-cortex_a15-linux-gnueabihf-linaro_4.7.4-2014.01/bin/arm-cortex_a15-linux-gnueabihf-
export KERNEL_CONFIG=forfivo_defconfig;

time_start=$(date +%s.%N)

echo "Remove old Package Files"
rm -rf $PACKAGEDIR/*

echo "Setup Package Directory"
mkdir -p $PACKAGEDIR/system/app
mkdir -p $PACKAGEDIR/system/lib/modules
mkdir -p $PACKAGEDIR/system/etc/init.d
mkdir -p $PACKAGEDIR/system/xbin
mkdir -p $PACKAGEDIR/props
mkdir -p $PACKAGEDIR/wanam

echo "Create initramfs dir"
mkdir -p $INITRAMFS_DEST

echo "Remove old initramfs dir"
rm -rf $INITRAMFS_DEST/*

echo "Copy new initramfs dir"
cp -R $INITRAMFS_SOURCE/* $INITRAMFS_DEST

echo "chmod initramfs dir"
chmod -R g-w $INITRAMFS_DEST/*
rm $(find $INITRAMFS_DEST -name EMPTY_DIRECTORY -print)
rm -rf $(find $INITRAMFS_DEST -name .git -print)

echo "Remove old zImage"
rm $PACKAGEDIR/zImage
rm arch/arm/boot/zImage

echo "Remove old boot.img"
# remove previous boot.img files
if [ -e $PACKAGEDIR/boot.img ]; then
	rm $PACKAGEDIR/boot.img;
fi;

echo "Make the kernel"
make VARIANT_DEFCONFIG=jf_$CARRIER"_defconfig" $KERNEL_CONFIG SELINUX_DEFCONFIG=selinux_defconfig

# copy new config
cp $KERNELDIR/.config $KERNELDIR/arch/arm/configs/$KERNEL_CONFIG;

echo "Modding .config file - "$VER
sed -i 's,CONFIG_LOCALVERSION="-faux-SGS4",CONFIG_LOCALVERSION="'$VER'",' .config

# remove all old modules before compile
for i in `find $KERNELDIR/ -name "*.ko"`; do
	rm -f $i;
done;
for i in `find $PACKAGEDIR/system/lib/modules/ -name "*.ko"`; do
	rm -f $i;
done;

# copy config
if [ ! -f $KERNELDIR/.config ]; then
	cp $KERNELDIR/arch/arm/configs/$KERNEL_CONFIG $KERNELDIR/.config;
fi;

# read config
. $KERNELDIR/.config;
make -j`grep 'processor' /proc/cpuinfo | wc -l`

echo "Copy modules to Package"
cp -a $(find . -name *.ko -print |grep -v initramfs) $PACKAGEDIR/system/lib/modules/

if [ $ADD_KTWEAKER = 'Y' ]; then
	cp ./com.ktoonsez.KTweaker.apk $PACKAGEDIR/system/app/com.ktoonsez.KTweaker.apk
	cp ./com.ktoonsez.KTmonitor.apk $PACKAGEDIR/system/app/com.ktoonsez.KTmonitor.apk
fi;

HOST_CHECK=`uname -n`
NUMBEROFCPUS=$(expr `grep processor /proc/cpuinfo | wc -l` + 1);
echo $HOST_CHECK

echo "Making kernel";
make -j${NUMBEROFCPUS} || exit 1;

echo "Copy modules to Package"
for i in `find $KERNELDIR -name '*.ko'`; do
	cp -av $i $PACKAGEDIR/system/lib/modules/;
done;

for i in `find $PACKAGEDIR/system/lib/modules/ -name '*.ko'`; do
	${CROSS_COMPILE}strip --strip-unneeded $i;
done;

if [ -e $KERNELDIR/arch/arm/boot/zImage ]; then
	echo "Copy zImage to Package"
	cp arch/arm/boot/zImage $PACKAGEDIR/zImage

	echo "Make boot.img"
	./mkbootfs $INITRAMFS_DEST | gzip > $PACKAGEDIR/ramdisk.gz
	./mkbootimg --cmdline 'console=null androidboot.hardware=qcom user_debug=31 msm_rtb.filter=0x3F ehci-hcd.park=3 maxcpus=4' --kernel $PACKAGEDIR/zImage --ramdisk $PACKAGEDIR/ramdisk.gz --base 0x80200000 --pagesize 2048 --ramdisk_offset 0x02000000 --output $PACKAGEDIR/wanam/boot.img 
	if [ $EXEC_LOKI = 'Y' ]; then
		echo "Executing loki"
		./loki_patch-linux-x86_64 boot aboot$CARRIER.img $PACKAGEDIR/boot.img $PACKAGEDIR/boot.lok
		rm $PACKAGEDIR/wanam/boot.img
	fi;
	cd $PACKAGEDIR
	if [ $EXEC_LOKI = 'Y' ]; then
		cp -R ../META-INF-SEC ./META-INF
	else
		cp -R ../META-INF .
	fi;
	cp -R ../props .
	cp ../system/app/STweaks.apk ./system/app/
	cp ../system/app/Superuser.apk ./system/app/
	cp ../system/etc/install-recovery.sh ./system/etc/
	cp -R ../system/xbin ./system/
	rm ramdisk.gz
	rm zImage
	rm ../$MUXEDNAMESHRT.zip
	zip -r ../$MUXEDNAMELONG.zip .

	time_end=$(date +%s.%N)
	echo -e "${BLDYLW}Total time elapsed: ${TCTCLR}${TXTGRN}$(echo "($time_end - $time_start) / 60"|bc ) ${TXTYLW}minutes${TXTGRN} ($(echo "$time_end - $time_start"|bc ) ${TXTYLW}seconds) ${TXTCLR}"

	FILENAME=../$MUXEDNAMELONG.zip
	FILESIZE=$(stat -c%s "$FILENAME")
	echo "Size of $FILENAME = $FILESIZE bytes."
	
	read -p "Do you want to flash the kernel now? (y/n):" reboot_recovery
	if [ $reboot_recovery = 'y' ]; then
	  $KERNELDIR/adb-install-update.sh "$PARENT_DIR/Packages/$MUXEDNAMELONG.zip"
	fi;

	echo "Done!"
	rm ../$MREV-$PLATFORM-$CARRIER"-version.txt"
	exec >>../$MREV-$PLATFORM-$CARRIER"-version.txt" 2>&1
	echo "$MUXEDNAMELONG,$FILESIZE,http://ktoonsez.jonathanjsimon.com/sgs4/$PLATFORM/$MUXEDNAMELONG.zip"
	
	cd $KERNELDIR
else
	echo "KERNEL DID NOT BUILD! no zImage exist"
fi;
