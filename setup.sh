#!/bin/bash

# this script assumes we're running ubuntu server 16.04+/debian 8+

# note : 1>&2 --> redirect stdout to stderr
#        2>&1 --> redirect stderr to stdout
if [[ $EUID -ne 0 ]]; then
   echo "You must be root to do this." 1>&2
   exit 1
fi

initialwd=$(pwd)

cd "$(dirname "$0")" # set script dir as working dir

read -p "Install dependencies ? [y/n] " userinput

if [[ $userinput == y ]]; then
    apt update && apt install python3 qemu-kvm libvirt-bin virtinst bridge-utils

    if !( apt update && apt install qemu-kvm libvirt-bin virtinst bridge-utils ) 2>&1 ; then
        echo "Failed to install dependencies"
        exit 1
    fi
fi

read -p "Create bridge ? [y/n] " userinput

if [[ $userinput == y ]]; then
    # backup conf in case of fuckup
    if !(cp /etc/network/interfaces /etc/network/interfaces_$(date '+%Y_%m_%d_%H_%M_%S')) 2>&1 ; then
        echo "Could not backup conf"
        exit 1
    fi

    echo "Available network interfaces"
    echo "----------------------------"

    ls /sys/class/net 2>&1

    read -p "Interface to bridge: " netInterface
    read -p "Bridge name: " bridgeName

    if !( python3 create_bridge.py $netInterface $bridgeName) 2>&1 ; then
        echo "Failed to create bridge"
        exit 1
    fi
fi

read -p "Disable netfilter (improves bridge performance & security) ? [y/n] " userinput

if [[ $userinput == y ]]; then
    # we only have to disable netfilter if its module is loaded
    if (lsmod | grep br_netfilter); then
        if !( python3 disable_netfilter.py ) 2>&1 ; then
            echo "Failed to create bridge"
            exit 1
        fi
    else
        echo "br_netfilter module not loaded, skipping."
    fi
fi

read -p "Apply new networking rules (will restart the network) ? [y/n] " userinput

if [[ $userinput == y ]]; then
    # restart the network service
    echo "If connected over ssh you might get disconnected now."
    if !( systemctl restart networking.service ) 2>&1 ; then
        exit 1
    fi
    # apply the netfilter rules if any
    if !( sysctl -p /etc/sysctl.conf ) 2>&1 ; then
        exit 1
    fi

    echo "Bridge interfaces"
    echo "-----------------"
    brctl show 2>&1
fi

read -p "Create new vm storage ? [y/n] " userinput

if [[ $userinput == y ]]; then
    read -p "storage name: " storageName
    read -p "storage size (in GB): " storageSize

    if !(qemu-img create -f raw "/var/lib/libvirt/images/"$storageName".img" $storageSize"G") 2>&1 ; then
        echo "Could not create storage"
        exit 1
    fi
    echo "storage "$storageName" created as /var/lib/libvirt/images/"$storageName".img"
fi

read -p "Create new vm ? [y/n] " userinput

if [[ $userinput == y ]]; then

    echo "Bridge interfaces"
    echo "-----------------"
    brctl show 2>&1
    echo "Storage"
    echo "-------"
    ls /var/lib/libvirt/images/ 2>&1

    while [[ $userok != y ]]; do
        read -p "vm name: " vmname
        read -p "vcpus count: " vcpus
        read -p "memory (in MB): " memory
        read -p "bridge interface: " bridgeInterface
        read -p "storage name (xxx.img): " storageName
        read -p "url to linux distro iso (leave empty for ubuntu server 16.04.2): " distroUrl
        read -p "url to linux distro iso sha256 checksum (leave empty for ubuntu server 16.04.2): " checksumUrl
        read -p "vnc port (used for install): " vncport
        read -p "Proceed with install ? [y/n] " userok
    done

    if [[ $distroUrl ==  ""]]; then
        distroUrl="http://releases.ubuntu.com/16.04.2/ubuntu-16.04.2-server-amd64.iso"
        checksumUrl="http://releases.ubuntu.com/16.04.2/SHA256SUMS"
    fi

    # -nc : only download if file not already present
    if !(wget -nc -P /var/lib/libvirt/boot $distroUrl) 2>&1 ; then
        echo "Could not download iso"
        exit 1
    fi

    # overwrite if existing
    if !(wget $checksumUrl -O /var/lib/libvirt/boot/sha256sums) 2>&1 ; then
        echo "Could not download checksums"
        exit 1
    fi

    # compare sums
    cd /var/lib/libvirt/boot
    if !(sha256sum -c sha256sums --ignore-missing) 2>&1 ; then
        echo "Sum mismatch"
        # remove faulty iso
        rm -i ${distroUrl##*/}
        exit 1
    fi
    cd "$(dirname "$0")"
    echo "iso checksum verified"

    echo "VM install"
    echo "----------------"
    echo "vnc will be available at bridge_ip:"$vncport
    echo "tigervnc ex : vncviewer 192.168.0.123::"$vncport
    echo "You might want to disable vnc after the install"
    echo "use 'virsh edit "$vmname"' and comment the vnc xml"
    echo "then use 'virsh define /etc/libvirt/qemu/"$vmname".xml'"
    echo "to reload the vm configuration"
    echo

    if !(virt-install --name $vmname --memory $memory --vcpus $vcpus\ 
    --disk "path=/var/lib/libvirt/images/"$storageName",bus=virtio" \ 
    --network bridge=$bridgeName --cdrom=/var/lib/libvirt/boot/${distroUrl##*/} \ 
    --graphics vnc,listen=0.0.0.0,port=$vncport) 2>&1 ; then
        echo "VM install failed. Please check the install parameters"
        exit 1
    fi
fi

# restore the inital work dir
cd $initialwd
echo "setup done"
