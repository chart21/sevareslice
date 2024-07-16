#!/bin/bash
# shellcheck disable=SC1091,2154

#
# Script is run locally on experiment server.
#

# exit on error
set -e
# log every command
set -x

# load global variables
REPO_DIR=$(pos_get_variable repo_dir --from-global)
REPO2_DIR=$(pos_get_variable repo2_dir --from-global)
manipulate=$(pos_get_variable manipulate --from-global)
# load loop variables/switches
size=$(pos_get_variable input_size --from-loop)
protocol=$(pos_get_variable protocol --from-loop)
datatype=$(pos_get_variable datatype --from-loop)
preprocess=$(pos_get_variable preprocess --from-loop)
splitroles=$(pos_get_variable splitroles --from-loop)
packbool=$(pos_get_variable packbool --from-loop)
optshare=$(pos_get_variable optshare --from-loop)
ssl=$(pos_get_variable ssl --from-loop)
threads=$(pos_get_variable threads --from-loop)
fun=$(pos_get_variable function --from-loop)
txbuffer=$(pos_get_variable txbuffer --from-loop)
rxbuffer=$(pos_get_variable rxbuffer --from-loop)
verifybuffer=$(pos_get_variable verifybuffer --from-loop)
comp="g++-12"

timerf="%M (Maximum resident set size in kbytes)\n\
%e (Elapsed wall clock time in seconds)\n\
%P (Percent of CPU this job got)"
player=$1
environ=""
# test types to simulate changing environments like cpu frequency or network latency
read -r -a types <<< "$2"
network=10.10."$3"
partysize=$4
# experiment type to allow small differences in experiments
etype=$5
touch testresults

cd "$REPO_DIR"

ipA="$network".2
ipB="$network".3
ipC="$network".4
ipD="$network".5

{
    # echo "./scripts/config.sh -p $player -n $size -d $datatype -s $protocol -e $preprocess -h $ssl -x $comp"
    echo "make -j COMPILER=$comp SPLITROLES=$splitroles PARTY=$player NUM_INPUTS=$size PROTOCOL=$protocol DATTYPE=$datatype PRE=$preprocess COMPRESS=$packbool USE_SSL=$ssl PROCESS_NUM=$threads FUNCTION_IDENTIFIER=$fun SEND_BUFFER=$txbuffer RECV_BUFFER=$rxbuffer VERIFY_BUFFER=$verifybuffer"

    
    /bin/time -f "$timerf" make -j COMPILER="$comp" SPLITROLES="$splitroles" PARTY="$player" NUM_INPUTS="$size" \
        PROTOCOL="$protocol" DATTYPE="$datatype" PRE="$preprocess" COMPRESS="$packbool" \
        USE_SSL="$ssl" PROCESS_NUM="$threads" FUNCTION_IDENTIFIER="$fun" SEND_BUFFER="$txbuffer" RECV_BUFFER="$rxbuffer" VERIFY_BUFFER="$verifybuffer" 
    
    echo "$(du -BM executables/run-P* | cut -d 'M' -f 1 | head -n 1) (Binary file size in MiB)"

} |& tee testresults

echo -e "\n========\n" >> testresults

####
#  environment manipulation section start
####
# shellcheck source=../host_scripts/manipulate.sh
source "$REPO2_DIR"/host_scripts/manipulate.sh

case " ${types[*]} " in
    *" CPUS "*)
        limitCPUs;;&
    *" RAM "*)
        limitRAM;;&
    *" QUOTAS "*)
        setQuota;;&
    *" FREQS "*)
        setFrequency;;&
    *" BANDWIDTHS "*)
        # check whether to manipulate a combination
        case " ${types[*]} " in
            *" LATENCIES "*)
                setLatencyBandwidth;;
            *" PACKETDROPS "*) # a.k.a. packet loss
                setBandwidthPacketdrop;;
            *)
                limitBandwidth;;
        esac;;
    *" LATENCIES "*)
        if [[ " ${types[*]} " == *" PACKETDROPS "* ]]; then
            setPacketdropLatency
        else
            setLatency
        fi;;
    *" PACKETDROPS "*)
        setPacketdrop;;
esac

####
#  environment manipulation section stop
####

success=true

pos_sync --timeout 600

if [ "$splitroles" -eq 2 ]; then
    /bin/time -f "$timerf" timeout 1000s ./scripts/run.sh -s "$splitroles" -p "$player" -a "$ipA" -b "$ipB" -c "$ipC" -d "$ipD" &>> testresults || success=false
else
    if [ "$protocol" -eq 4 ]; then
        /bin/time -f "$timerf" timeout 1000s ./scripts/run.sh -s "$splitroles" -p "$player" -a "$ipA" -b "$ipB" &>> testresults || success=false
    elif [ "$protocol" -lt 7 ]; then
        /bin/time -f "$timerf" timeout 1000s ./scripts/run.sh -s "$splitroles" -p "$player" -a "$ipA" -b "$ipB" -c "$ipC" &>> testresults || success=false
    else
        /bin/time -f "$timerf" timeout 1000s ./scripts/run.sh -s "$splitroles" -p "$player" -a "$ipA" -b "$ipB" -c "$ipC" -d "$ipD" &>> testresults || success=false
    fi
fi


    # divide external runtime x*j
    # Todo: divide normal binary run by j*j


        # binary:   calculate mean of j results running concurrent ( /j *j )
        # 3nodes:   calculate mean of 6*j results running concurrent ( /6*j *6*j )
        # 3-4nodes: calculate mean of 24*j results running concurrent ( /24*j *24*j )
        # 4nodes:   calculate mean of 24*j results running concurrent ( /24*j *24*j )
    #default divisor
    divisor=1
    divisorExt=1
        
        [ "$splitroles" -eq 0 ] && divisor=$((threads*threads)) && divisorExt=$((threads))
        [ "$splitroles" -eq 1 ] && divisor=$((6*6*threads*threads)) && divisorExt=$((6*threads))
        [ "$splitroles" -eq 2 ] && divisor=$((24*24*threads*threads)) && divisorExt=$((24*threads))
        [ "$splitroles" -eq 3 ] && divisor=$((24*24*threads*threads)) && divisorExt=$((24*threads))

        # sum=$(grep "measured to initialize program" testresults | cut -d 's' -f 2 | awk '{print $5}' | paste -s -d+ | bc)
        # average=$(echo "scale=6;$sum / $divisor" | bc -l)
        # echo "Time measured to initialize program: ${average}s" &>> testresults
           max=$(grep "measured to initialize program" testresults | cut -d 's' -f 2 | awk '{print $5}' | sort -nr | head -1) 
        average=$(echo "scale=6;$max / $divisorExt" | bc -l)
        echo "Time measured to initialize program: ${average}s" &>> testresults

        if [ "$preprocess" -eq 1 ]; then
            # sum=$(grep "preprocessing chrono" testresults | cut -d 's' -f 4 | awk '{print $3}' | paste -s -d+ | bc)
            # average=$(echo "scale=6;$sum / $divisor" | bc -l)
        # echo "Time measured to perform preprocessing chrono: ${average}s" &>> testresults
        max=$(grep "preprocessing chrono" testresults | cut -d 's' -f 4 | awk '{print $3}' | sort -nr | head -1) 
            average=$(echo "scale=6;$max / $divisorExt" | bc -l)
        echo "Time measured to perform preprocessing chrono: ${average}s" &>> testresults
        fi

        sum=$(grep "computation clock" testresults | cut -d 's' -f 2 | awk '{print $6}' | paste -s -d+ | bc)
        average=$(echo "scale=6;$sum / $divisor" | bc -l)
        echo "Time measured to perform computation clock: ${average}s" &>> testresults

        sum=$(grep "computation getTime" testresults | cut -d 's' -f 2 | awk '{print $6}' | paste -s -d+ | bc)
        average=$(echo "scale=6;$sum / $divisor" | bc -l)
        echo "Time measured to perform computation getTime: ${average}s" &>> testresults

    max=$(grep "computation chrono" testresults | cut -d 's' -f 2 | awk '{print $6}' | sort -nr | head -1)
        average=$(echo "scale=6;$max / $divisorExt" | bc -l)
        echo "Time measured to perform computation chrono: ${average}s" &>> testresults
    # sum=$(grep "computation chrono" testresults | cut -d 's' -f 2 | awk '{print $6}' | paste -s -d+ | bc)
        # average=$(echo "scale=6;$sum / $divisor" | bc -l)
        # echo "Time measured to perform computation chrono: ${average}s" &>> testresults

        runtimeext=$(grep "Elapsed wall clock" testresults | tail -n 1 | cut -d ' ' -f 1)
        average=$(echo "scale=6;$runtimeext / $divisorExt" | bc -l)
        echo "$average (Elapsed wall clock time in seconds)" &>> testresults


    pos_sync

    ####
    #  environment manipulation reset section start
    ####

    case " ${types[*]} " in

        *" FREQS "*)
            resetFrequency;;&
        *" RAM "*)
            unlimitRAM;;&
        *" BANDWIDTHS "*|*" LATENCIES "*|*" PACKETDROPS "*)
            resetTrafficControl;;&
        *" CPUS "*)
            unlimitCPUs
    esac

    ####
    #  environment manipulation reset section stop
    ####

    echo "experiment finished"  >> testresults
    pos_upload --loop testresults
    # pos_upload --loop terminal_output.txt
    # abort if no success
    $success
