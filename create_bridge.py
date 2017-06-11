#!/usr/bin/env python3

# doc : https://wiki.libvirt.org/page/Networking#Bridged_networking_.28aka_.22shared_physical_device.22.29

# example bridge config
#   auto br0
#   iface br0 inet static
#   address	192.168.0.170
#   netmask	255.255.255.0
#   gateway	192.168.0.1
#   dns-nameservers	8.8.8.8 8.8.4.4
#   bridge_ports enp3s0f2
#   bridge_stp on
#   bridge_maxwait 0

import re
import argparse
import sys

parser = argparse.ArgumentParser()
parser.add_argument("netInterface")
parser.add_argument("bridgeName")
args = parser.parse_args()

netInterface = args.netInterface
bridgeName = args.bridgeName

if(netInterface == bridgeName):
    print("The netInterface and bridgeName must be different !")
    sys.exit(1)

inCfgBlock = False
interfaceFound = False

with open("/etc/network/interfaces","r+") as f:
    content = []
    for line in f:
        m = re.match("^\s*auto ([a-z0-9]*)\s*$", line)
        if(m and m.group(1) == netInterface):
            # we reached our interface conf
            # make sure it's unique
            if(interfaceFound):
                print("The same interface already exists in the network conf !")
                sys.exit(1)

            interfaceFound = True
            inCfgBlock = True
        elif(m and m.group(1) == bridgeName):
            print("The bridgeName already exists in the network conf !")
            sys.exit(1)
        elif(m):
            # we have a match with an unkown interface name
            # we probably reached the next interface's configuration
            inCfgBlock = False
        
        if(not inCfgBlock):
            # only save the other interfaces
            content.append(line)
            
    # we went through the entire configuration
    if(not interfaceFound):
        print("The interface {} was not found !".format(netInterface))
        sys.exit(1)
    
    userOk = "n"
    bridgeCfgContent = []

    while(userOk != "y"):
        bridgeCfgContent = [] # clear
        bridgeCfgContent.append("auto {}\n".format(bridgeName))
        bridgeCfgContent.append("iface {} inet static\n".format(bridgeName))
        bridgeCfgContent.append("address {}\n".format(input("Bridge address: ")))
        bridgeCfgContent.append("netmask {}\n".format(input("Bridge netmask: ")))
        bridgeCfgContent.append("gateway {}\n".format(input("Bridge gateway: ")))
        bridgeCfgContent.append("dns-nameservers {}\n".format(input("Bridge dns-nameservers: ")))
        bridgeCfgContent.append("bridge_ports {}\n".format(netInterface))
        bridgeCfgContent.append("bridge_stp on\n")
        bridgeCfgContent.append("bridge_maxwait 0\n\n")

        print("\nbridge configuration\n--------------------\n")
        for l in bridgeCfgContent:
            print(l, end='')

        userOk = input("\nBridge configuration correct ? [y/n] ")
    
    content = content + bridgeCfgContent

    # rewrite the config to disk
    for l in content:
        f.write(l)

print("configuration written in /etc/network/interfaces")
