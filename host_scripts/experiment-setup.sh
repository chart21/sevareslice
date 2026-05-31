#!/bin/bash

# Experiment setup-script to be run locally on experiment server

# exit on error
set -e
# log every command
set -x

REPO_DIR=$(pos_get_variable repo_dir --from-global)
REPO2_DIR=$(pos_get_variable repo2_dir --from-global)
EXPERIMENT=$(pos_get_variable experiment --from-global)
# SMC protocols to compile
ipaddr="$1"
SWAP="$2"
network="$3"
read -r -a nodes <<< "$4"
groupsize=${#nodes[*]}


#######
#### set networking environment
#######

# driver for Intel Network Adapter for E810 100G card
installDriver() {
	wget -O ice-1.13.7.tar.gz "https://sourceforge.net/projects/e1000/files/ice%20stable/1.13.7/ice-1.13.7.tar.gz/download"
	tar -xf ice-1.13.7.tar.gz
	cd ice-1.13.7/src/
	make install &> makelog || true
	cd ..
	mkdir -p /lib/firmware/updates/intel/ice/ddp/
	cp ddp/ice-1.3.35.0.pkg /lib/firmware/updates/intel/ice/ddp/
	modprobe -r ice
	modprobe ice
}

# If the testnodes are directly connected from NIC to NIC and
# not via a switch, we need to create individual networks for each
# NIC pair and route the network through the correct NIC
# this is not an ideal situation for big party numbers

nic0=$(pos_get_variable "$(hostname)"NIC0 --from-global)
nic1=$(pos_get_variable "$(hostname)"NIC1 --from-global) || nic1=0
nic2=$(pos_get_variable "$(hostname)"NIC2 --from-global) || nic2=0

ips=()

get_nic_to_peer() {
	local peer_ipaddr="$1"
	local default_nic="$2"
	# map ipaddr back to host name
	# nodes is the array of reserved nodes. The i-th node has ipaddr = i + 2
	local peer_name="${nodes[$((peer_ipaddr - 2))]}"
	
	# query global-variables.yml for the specific comment
	# e.g., "gardNIC0: enp193s0f1      # To Goracle"
	local line
	line=$(grep -i "^$(hostname)NIC[0-9]:" "$REPO2_DIR/global-variables.yml" | grep -i "to ${peer_name}" | head -n 1)
	if [ -n "$line" ]; then
		echo "$line" | cut -d':' -f2 | awk '{print $1}'
	else
		# fallback to the default nic passed in
		echo "$default_nic"
	fi
}

######
### three nodes indirect connection topology setup
### node 2 --- node 1 --- node 3
### for 25G+ speeds set MTU
###if [ "$(hostname | grep -cE "gard|goracle|zone")" -eq 1 ]; then
###
###	# install ddp drivers
###	installDriver
###
###	# store other participants ips
###	for i in $(seq 2 $((groupsize+1))); do
###		[ "$ipaddr" -ne "$i" ] && ips+=( "$i" )
###	done
###
###	ip addr add 10.10."$network"."$ipaddr"/24 dev "$nic0"
###	ip link set dev "$nic0" mtu 9700
###	ip link set dev "$nic0" up
###
###	if [ "$ipaddr" -eq 2 ]; then
###		# activate forwarding for the center node
###		sysctl -w net.ipv4.ip_forward=1
###		ip addr add 10.10."$network"."$ipaddr"/24 dev "$nic1"
###		ip link set dev "$nic1" mtu 9700
###		ip link set dev "$nic1" up
###		# route via correct NICs
###		ip route add 10.10."$network".3 dev "$nic0"
###		ip route add 10.10."$network".4 dev "$nic1"
###	# this is probably not required since the routes should be set automatically
###	elif [ "$ipaddr" -eq 3 ]; then
###		ip route add 10.10."$network".4 via 10.10."$network".2
###	else
###		ip route add 10.10."$network".3 via 10.10."$network".2
###	fi
#### three nodes direct connection topology if true
###elif [ "$nic1" != 0 ]; then
# four nodes direct connection topology if true
if [ "$groupsize" -ge 4 ] && [ "$nic1" != 0 ] && [ "$nic2" != 0 ]; then

	# to achieve high speeds, install ddp drivers
	highspeed=$(hostname | grep -cE "idex|meld|tinyman|yieldly|algofi|gard|goracle|zone")
	[ "$highspeed" -eq 1 ] && installDriver

	sleep 20

	# verify that nodes array is circularly sorted
	# this is required for the definition of this topology
	
	# specify the ip pair to create the network routes to
	# it's not the ip that is being set to this host
	[ "$ipaddr" -eq 2 ] && ips+=( 3 4 5 )
	[ "$ipaddr" -eq 3 ] && ips+=( 4 5 2 )
	[ "$ipaddr" -eq 4 ] && ips+=( 5 2 3 )
	[ "$ipaddr" -eq 5 ] && ips+=( 2 3 4 )

	nic_peer0=$(get_nic_to_peer "${ips[0]}" "$nic0")
	nic_peer1=$(get_nic_to_peer "${ips[1]}" "$nic1")
	nic_peer2=$(get_nic_to_peer "${ips[2]}" "$nic2")

	ip addr add 10.10."$network"."$ipaddr"/32 dev "$nic_peer0"
	ip addr add 10.10."$network"."$ipaddr"/32 dev "$nic_peer1"
	ip addr add 10.10."$network"."$ipaddr"/32 dev "$nic_peer2"

	ip link set dev "$nic_peer0" up
	ip link set dev "$nic_peer1" up
	ip link set dev "$nic_peer2" up

	ip route add 10.10."$network"."${ips[0]}" dev "$nic_peer0"
	ip route add 10.10."$network"."${ips[1]}" dev "$nic_peer1"
	ip route add 10.10."$network"."${ips[2]}" dev "$nic_peer2"

	# to achieve high speeds, increase mtu
	if [ "$highspeed" -eq 1 ]; then
		ip link set dev "$nic_peer0" mtu 9700
		ip link set dev "$nic_peer1" mtu 9700
		ip link set dev "$nic_peer2" mtu 9700
	fi

# three nodes direct connection topology if true
elif [ "$nic1" != 0 ]; then

	# to achieve high speeds, install ddp drivers
	highspeed=$(hostname | grep -cE "idex|meld|tinyman|yieldly|algofi|gard|goracle|zone")
	[ "$highspeed" -eq 1 ] && installDriver

	sleep 20

	# verify that nodes array is circularly sorted
	# this is required for the definition of this topology
	
	# specify the ip pair to create the network routes to
	# it's not the ip that is being set to this host
	[ "$ipaddr" -eq 2 ] && ips+=( 3 4 )
	[ "$ipaddr" -eq 3 ] && ips+=( 4 2 )
	[ "$ipaddr" -eq 4 ] && ips+=( 2 3 )

	nic_peer0=$(get_nic_to_peer "${ips[0]}" "$nic0")
	nic_peer1=$(get_nic_to_peer "${ips[1]}" "$nic1")

	ip addr add 10.10."$network"."$ipaddr"/32 dev "$nic_peer0"
	ip addr add 10.10."$network"."$ipaddr"/32 dev "$nic_peer1"

	ip link set dev "$nic_peer0" up
	ip link set dev "$nic_peer1" up

	ip route add 10.10."$network"."${ips[0]}" dev "$nic_peer0"
	ip route add 10.10."$network"."${ips[1]}" dev "$nic_peer1"

	# to achieve high speeds, increase mtu
	if [ "$(hostname | grep -cE "idex|meld|tinyman|yieldly|algofi|gard|goracle|zone")" -eq 1 ]; then
		ip link set dev "$nic_peer0" mtu 9700
		ip link set dev "$nic_peer1" mtu 9700
	fi

# here the testhosts are connected via switch
else
	# support any groupsizes
	# store other participants ips
	for i in $(seq 2 $((groupsize+1))); do
		[ "$ipaddr" -ne "$i" ] && ips+=( "$i" )
	done

	ip addr add 10.10."$network"."$ipaddr"/24 dev "$nic0"
	ip link set dev "$nic0" up

fi

# wait for others to finish setup
pos_sync

###
# Networking tests

# don't start test simultaneously
sleep $((ipaddr-2))

# log link test
for ip in "${ips[@]}"; do
	ping -c 5 10.10."$network"."$ip" &>> pinglog || true
done

pos_upload pinglog || true

# log link test
# shellcheck source=../tools/speedtest.sh
source "$REPO2_DIR"/tools/speedtest.sh

{
	startserver

	for serverip in $(seq 2 $((groupsize+1))); do
		for clientip in $(seq 2 $((groupsize+1))); do
			pos_sync
			# skip the server
			[ "$serverip" -eq "$clientip" ] && continue
			# skip other clients for now
			[ "$ipaddr" -ne "$clientip" ] && continue
			# skip the client server roles repetitions, this is here explicitly and not 
			# merged with case one so that this can be deactivated easily if wanted
			[ "$serverip" -gt "$clientip" ] && continue			

			hostname="${hostname::-1}$serverip"
			echo "measured speed between nodes $((serverip-1)) and $((clientip-1))"
			for k in 1 10; do
					threads="$k"
					echo -e "\n Threads: $k"
					startclient | grep total
			done
		done
	done
} > speedtest

stopserver

pos_upload speedtest || true

# set up swap disk for RAM pageswapping measurements
if [ -n "$SWAP" ] && [ -b /dev/nvme0n1 ]; then
	echo "creating swapfile with swap size $SWAP"
	parted -s /dev/nvme0n1 mklabel gpt
	parted -s /dev/nvme0n1 mkpart primary ext4 0% 100%
	mkfs.ext4 -FL swap /dev/nvme0n1
	mkdir /swp
	mkdir /whale
	mount -L swap /swp
	dd if=/dev/zero of=/swp/swp_file bs=1024 count="$SWAP"K
	chmod 600 /swp/swp_file
	mkswap /swp/swp_file
	swapon /swp/swp_file
	 # create ramdisk
    totalram=$(free -m | grep "Mem:" | awk '{print $2}')
	mount -t tmpfs -o size="$totalram"M swp /whale
	# preoccupy ram and only leave 16 GiB for faster experiment runs
	# it was observed, that more than that was never required and 
	# falloc is slow in loops on nodes with large ram
	ram=$((16*1024))
	availram=$(free -m | grep "Mem:" | awk '{print $7}')
	fallocate -l $((availram-ram))M /whale/filler
fi

echo "experiment setup successful"

