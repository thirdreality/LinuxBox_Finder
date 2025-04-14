#!/bin/bash

BINC_COMMIT_ID="31328349141f35ec3656b26284a73b735d969b20"
current_dir=$(pwd)

/usr/bin/git --version

/usr/bin/git pull
/usr/bin/git submodule update --init --recursive

if [ -d "${current_dir}/bluez_inc" ]; then
    echo "Updating bluez_inc ..."
    cd "${current_dir}/bluez_inc"; /usr/bin/git checkout ${BINC_COMMIT_ID}
fi

if [ -d "${current_dir}/bluez_inc/build" ]; then
    echo "Build bluez_inc ..."
    cd ${current_dir}/bluez_inc/build
    cmake ..
    make
else
    echo "Build bluez_inc first time ..."
    mkdir -p ${current_dir}/bluez_inc/build
    cd ${current_dir}/bluez_inc/build
    cmake ..
    make
fi

echo "Build hubv3-btgatt-server ..."
cd ${current_dir}; make V=1
