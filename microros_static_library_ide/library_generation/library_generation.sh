#!/bin/bash

export BASE_PATH=/project/$MICROROS_LIBRARY_FOLDER
export STM32_VERSION=1.18.0

######## Check existing library ########
if [ -f "$BASE_PATH/libmicroros/libmicroros.a" ]; then
    echo "micro-ROS library found. Skipping..."
    echo "Delete $MICROROS_LIBRARY_FOLDER/libmicroros/ for rebuild."
    exit 0
fi
######## Trying to retrieve CFLAGS ########
export RET_CFLAGS=$(find /project -type f -name *.mk -exec cat {} \; | python3 $BASE_PATH/library_generation/extract_flags.py)
RET_CODE=$?

if [ $RET_CODE = "0" ]; then
    echo "Found CFLAGS:"
    echo "-------------"
    echo $RET_CFLAGS
    echo "-------------"
else
    echo "Error retrieving croscompiler flags"
    exit 1;
fi


######## Init ########
echo "install dependencies"
apt-get update
apt-get install -y gnupg ca-certificates apt-utils apt-transport-https zenity

echo "add nexus repository"
cp $BASE_PATH/library_generation/nexus-repo-public.gpg.key /tmp/repo.key
cp $BASE_PATH/library_generation/apt.list /etc/apt/sources.list.d/alpen-apt.list

mkdir -p /etc/apt/keyrings
cat /tmp/repo.key | gpg --dearmor -o /etc/apt/keyrings/nexus-repo-public.gpg
apt-get update

echo "install stm32 toolchain"
export DISPLAY=:0
yes | apt-get install -y st-stm32cubeclt-$STM32_VERSION
export PATH=/opt/st/stm32cubeclt_$STM32_VERSION/GNU-tools-for-STM32/bin:$PATH

export TOOLCHAIN_PREFIX=/opt/st/stm32cubeclt_$STM32_VERSION/GNU-tools-for-STM32/bin/arm-none-eabi-
#export TOOLCHAIN_PREFIX=/usr/bin/arm-none-eabi-

cd /uros_ws

source /opt/ros/$ROS_DISTRO/setup.bash
source install/local_setup.bash

ros2 run micro_ros_setup create_firmware_ws.sh generate_lib

######## Adding extra packages ########
pushd firmware/mcu_ws > /dev/null

    # Workaround: Copy just tf2_msgs
    git clone -b ros2 https://github.com/ros2/geometry2
    cp -R geometry2/tf2_msgs ros2/tf2_msgs
    rm -rf geometry2

    # Import user defined packages
    mkdir extra_packages
    pushd extra_packages > /dev/null
        USER_CUSTOM_PACKAGES_DIR=$BASE_PATH/../../microros_component/extra_packages 
    	if [ -d "$USER_CUSTOM_PACKAGES_DIR" ]; then
    		cp -R $USER_CUSTOM_PACKAGES_DIR/* .
		fi
        if [ -f $USER_CUSTOM_PACKAGES_DIR/extra_packages.repos ]; then
        	vcs import --input $USER_CUSTOM_PACKAGES_DIR/extra_packages.repos
        fi
        cp -R $BASE_PATH/library_generation/extra_packages/* .
        vcs import --input extra_packages.repos
    popd > /dev/null

    if [ ! -z ${MICROROS_USE_EMBEDDEDRTPS+x} ]; then
        rm -rf eProsima/Micro-XRCE-DDS-Client
        rm -rf uros/rmw_microxrcedds

        git clone -b main https://github.com/micro-ROS/rmw_embeddedrtps uros/rmw_embeddedrtps
        git clone -b main https://github.com/micro-ROS/embeddedRTPS uros/embeddedRTPS
    fi

popd > /dev/null

######## Build  ########
if [ ! -z ${MICROROS_USE_EMBEDDEDRTPS+x} ]; then
    ros2 run micro_ros_setup build_firmware.sh $BASE_PATH/library_generation/toolchain.cmake $BASE_PATH/library_generation/colcon-embeddedrtps.meta
else
    ros2 run micro_ros_setup build_firmware.sh $BASE_PATH/library_generation/toolchain.cmake $BASE_PATH/library_generation/colcon.meta
fi

find firmware/build/include/ -name "*.c"  -delete
rm -rf $BASE_PATH/libmicroros
mkdir -p $BASE_PATH/libmicroros/include
cp -R firmware/build/include/* $BASE_PATH/libmicroros/include/
cp -R firmware/build/libmicroros.a $BASE_PATH/libmicroros/libmicroros.a

######## Fix include paths  ########
pushd firmware/mcu_ws > /dev/null
    INCLUDE_ROS2_PACKAGES=$(colcon list | awk '{print $1}' | awk -v d=" " '{s=(NR==1?s:s d)$0}END{print s}')
popd > /dev/null

for var in ${INCLUDE_ROS2_PACKAGES}; do
    if [ -d "$BASE_PATH/libmicroros/include/${var}/${var}" ]; then
        rsync -r $BASE_PATH/libmicroros/include/${var}/${var}/* $BASE_PATH/libmicroros/include/${var}
        rm -rf $BASE_PATH/libmicroros/include/${var}/${var}
    fi
done

######## Generate extra files ########
find firmware/mcu_ws/ros2 \( -name "*.srv" -o -name "*.msg" -o -name "*.action" \) | awk -F"/" '{print $(NF-2)"/"$NF}' > $BASE_PATH/libmicroros/available_ros2_types
find firmware/mcu_ws/extra_packages \( -name "*.srv" -o -name "*.msg" -o -name "*.action" \) | awk -F"/" '{print $(NF-2)"/"$NF}' >> $BASE_PATH/libmicroros/available_ros2_types

cd firmware
echo "" > $BASE_PATH/libmicroros/built_packages
for f in $(find $(pwd) -name .git -type d); do pushd $f > /dev/null; echo $(git config --get remote.origin.url) $(git rev-parse HEAD) >> $BASE_PATH/libmicroros/built_packages; popd > /dev/null; done;

######## Fix permissions ########
sudo chmod -R 777 $BASE_PATH/libmicroros/
sudo chmod -R 777 $BASE_PATH/libmicroros/include/
sudo chmod -R 777 $BASE_PATH/libmicroros/libmicroros.a
