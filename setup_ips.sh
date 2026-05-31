set -ex
ssh -o StrictHostKeyChecking=no algofi "ip addr flush dev enp195s0f0; ip addr add 10.0.1.1/24 dev enp195s0f0; ip link set dev enp195s0f0 up; ip addr flush dev enp193s0f1; ip addr add 10.0.2.1/24 dev enp193s0f1; ip link set dev enp193s0f1 up"
ssh -o StrictHostKeyChecking=no goracle "ip addr flush dev enp195s0f1; ip addr add 10.0.1.2/24 dev enp195s0f1; ip link set dev enp195s0f1 up; ip addr flush dev enp195s0f0; ip addr add 10.0.3.1/24 dev enp195s0f0; ip link set dev enp195s0f0 up"
ssh -o StrictHostKeyChecking=no zone "ip addr flush dev enp193s0f1; ip addr add 10.0.2.2/24 dev enp193s0f1; ip link set dev enp193s0f1 up; ip addr flush dev enp195s0f1; ip addr add 10.0.3.2/24 dev enp195s0f1; ip link set dev enp195s0f1 up"

# Install iperf3
for node in algofi goracle zone; do
  ssh -o StrictHostKeyChecking=no $node 'apt-get update && apt-get install -y iperf3'
done

# Start iperf3 servers
ssh -o StrictHostKeyChecking=no algofi "killall iperf3 || true; iperf3 -s -D"
ssh -o StrictHostKeyChecking=no goracle "killall iperf3 || true; iperf3 -s -D"
ssh -o StrictHostKeyChecking=no zone "killall iperf3 || true; iperf3 -s -D"

# Test Ping
echo "=== PING TESTS ==="
ssh -o StrictHostKeyChecking=no algofi "ping -c 3 10.0.1.2"
ssh -o StrictHostKeyChecking=no algofi "ping -c 3 10.0.2.2"
ssh -o StrictHostKeyChecking=no goracle "ping -c 3 10.0.3.2"

# Test iperf3
echo "=== IPERF TESTS ==="
ssh -o StrictHostKeyChecking=no algofi "iperf3 -c 10.0.1.2 -t 3"
ssh -o StrictHostKeyChecking=no algofi "iperf3 -c 10.0.2.2 -t 3"
ssh -o StrictHostKeyChecking=no goracle "iperf3 -c 10.0.3.2 -t 3"
