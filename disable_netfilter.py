#!/usr/bin/env python3

# doc : https://wiki.libvirt.org/page/Networking#Bridged_networking_.28aka_.22shared_physical_device.22.29

import re
import sys

with open("/etc/sysctl.conf","r+") as f:
    content = []
    for line in f:
        m_ip6 = re.match("^\s*net\.bridge\.bridge-nf-call-ip6tables = [0-1]\s*$", line)
        m_ip = re.match("^\s*net\.bridge\.bridge-nf-call-iptables = [0-1]\s*$", line)
        m_arp = re.match("^\s*net\.bridge\.bridge-nf-call-arptables = [0-1]\s*$", line)

        if(m_ip6 or m_ip or m_arp):
            pass # discard existing netfilter rules
        else:
            content.append(line)
    
    # add our rules at the end of the conf file
    content.append("net.bridge.bridge-nf-call-ip6tables = 0\n")
    content.append("net.bridge.bridge-nf-call-iptables = 0\n")
    content.append("net.bridge.bridge-nf-call-arptables = 0\n\n")

    for l in content:
        f.write(l)

print("configuration written in /etc/sysctl.conf")

# workaround : https://bugs.launchpad.net/ubuntu/+source/procps/+bug/50093
with open("/etc/rc.local") as f:
    content = []
    for line in f:
        m_exit0 = re.match("^\s*exit 0\s*$", line)

        if(m_exit0):
            # add our cmds at the end of the rc.local
            content.append("/sbin/sysctl -p /etc/sysctl.conf\n")
            content.apend("iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS  --clamp-mss-to-pmtu\n")
            content.append("exit 0\n")
        else:
            content.append(line)

    for l in content:
        f.write(l)

print("configuration written /etc/rc.local")
