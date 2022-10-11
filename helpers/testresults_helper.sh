#!/bin/bash
# shellcheck disable=SC2154,2034

# where we find the experiment results
resultpath="$RPATH/${NODES[0]}/"

# verify testresults
verifyExperiment() {

    # handle yao -O protocol variant, for some reason the result is only at node[1]
    # move to resultpath location
    while IFS= read -r file; do
        mv "$file" "$resultpath"
    done < <(find "$RPATH/${NODES[1]}/" -name "testresultsBINARYyaoO*" -print)

    for cdomain in "${CDOMAINS[@]}"; do
        declare -n cdProtocols="${cdomain}PROTOCOLS"
        for protocol in "${cdProtocols[@]}"; do
            protocol=${protocol::-8}
            
            i=0
            loopinfo=$(find "$resultpath" -name "*$i.loop*" -print -quit)
            # while we find a next loop info file do
            while [ -n "$loopinfo" ]; do

                # get pos filepath of the measurements for the current loop
                experimentresult=$(find "$resultpath" -name "testresults$cdomain${protocol}_run*$i" -print -quit)
                verificationresult=$(find "$resultpath" -name "measurementlog${cdomain}_run*$i" -print -quit)

                # check existance of files
                if [ ! -f "$experimentresult" ] || [ ! -f "$verificationresult" ]; then
                    styleOrange "  Skip $protocol - File not found error: $experimentresult"
                    continue 2
                fi

                # verify experiment result - call experiment specific verify script
                chmod +x experiments/"$EXPERIMENT"/verify.py
                match=$(experiments/"$EXPERIMENT"/verify.py "$experimentresult" "$verificationresult")
                if [ "$match" != 1 ]; then
                    styleOrange "  Skip $protocol - $match at $experimentresult";
                    continue 2;
                fi
                ((++i))
                loopinfo=$(find "$resultpath" -name "*$i.loop*" -print -quit)
            done

            # only pass if while-loop actually entered
            [ "$i" -gt 0 ] && okfail ok "  verified - test passed for $protocol"
        done
    done
}

############
# Export experiment data from the pos_upload-ed logs into two tables
############
exportExperimentResults() {

    # set up location
    datatableShort="$EXPORTPATH/data/E${EXPERIMENT::2}_short_results.csv"
    datatableFull="$EXPORTPATH/data/E${EXPERIMENT::2}_full_results.csv"
    mkdir -p "$datatableShort"
    rm -rf "$datatableShort"

    dyncolumns=""
    # get the dynamic column names from the first .loop info file
    loopinfo=$(find "$resultpath" -name "*loop*" -print -quit)
    
    # check if loop file exists
    if [ -z "$loopinfo" ]; then
        okfail fail "nothing to export - no loop file found"
        return
    fi

    for columnname in $(jq -r 'keys_unsorted[]' "$loopinfo"); do
        dyncolumns+="$columnname"
        case "$columnname" in
            freqs) dyncolumns+="(GHz)";;
            quotas|packetdrops) dyncolumns+="(%)";;
            latencies) dyncolumns+="(ms)";;
            bandwidths) dyncolumns+="(Mbs)";;
        esac
        dyncolumns+=";"
    done

    # generate header line of data dump with column information
    echo -e "nodes;program;c.domain;adv.model;protocol;partysize;${dyncolumns}runtime(s);maxPhyRAM(MiB);P0commRounds;P0dataSent(MB);ALLdataSent(MB)" >> "$datatableShort"
    echo -e "nodes;program;c.domain;adv.model;protocol;partysize;comp.P0intin;comp.P1intin;comp.P2intin;comp.P0bitin;comp.P1bitin;compP2bitin;comp.intbits;comp.inttriples;comp.bittriples;comp.vmrounds;${dyncolumns}runtime(s);maxPhyRAM(MiB);P0commRounds;P0dataSent(MB);ALLdataSent(MB);Tx(MB);Tx(rounds);Tx(s);Rx(MB);Rx(rounds);Rx(s);Brcasting(MB);Brcasting(rounds);Brcasting(s);TxRx(MB);TxRx(rounds);TxRx(s);Passing(MB);Passing(rounds);Passing(s);Part.Brcasting(MB);Part.Brcasting(rounds);Part.Brcasting(s);Ex(MB);Ex(rounds);Ex(s);Ex1to1(MB);Ex1to1(rounds);Ex1to1(s);Rx1to1(MB);Rx1to1(rounds);Rx1to1(s);Tx1to1(MB);Tx1to1(rounds);Tx1to1(s);Txtoall(MB);Txtoall(rounds);Txtoall(s);" >> "$datatableFull"
    # nodes info in every row, static
    usednodes="${NODES[*]}" 

    # grab all the measurement information and append it to the datatable
    for cdomain in "${CDOMAINS[@]}"; do
        declare -n cdProtocols="${cdomain}PROTOCOLS"
        for protocol in "${cdProtocols[@]}"; do
############protocol=${protocol::-8}

            advModel=""
            setAdvModel "$protocol"
            i=0
            # get loopfile path for the current variables
            loopinfo=$(find "$resultpath" -name "*$i.loop*" -print -quit)
            echo "  exporting $protocol"
            # while we find a next loop info file do
            while [ -n "$loopinfo" ]; do
                loopvalues=""
                # extract loop var values
                for value in $(jq -r 'values[]' "$loopinfo"); do
                    loopvalues+="$value;"
                done

                # the actual number of participants
                partysize=""
                setPartySize "$protocol"
                
                # get pos filepath of the measurements for the current loop
                compileinfo=$(find "$resultpath" -name "measurementlog${cdomain}_run*$i" -print -quit)
                runtimeinfo=$(find "$resultpath" -name "testresults$cdomain${protocol}_run*$i" -print -quit)
                if [ ! -f "$runtimeinfo" ] || [ ! -f "$compileinfo" ]; then
                    styleOrange "    Skip - File not found error: runtimeinfo or compileinfo"
                    continue 2
                fi

                ## Minimum result measurement information
                ######
                # extract measurement
                runtime=$(grep "Time =" "$runtimeinfo" | awk '{print $3}')
                maxRAMused=$(grep "maxresident)k" "$runtimeinfo" | awk '{print $6}' | cut -d 'm' -f 1)
                [ -n "$maxRAMused" ] && maxRAMused="$((maxRAMused/1024))"

                commRounds=$(grep "Data sent =" "$runtimeinfo" | awk '{print $7}')
                dataSent=$(grep "Data sent =" "$runtimeinfo" | awk '{print $4}')
                globaldataSent=$(grep "Global data sent =" "$runtimeinfo" | awk '{print $5}')
                basicComm="${commRounds:-NA};${dataSent:-NA};${globaldataSent:-NA}"

                # put all collected info into one row (Short)
                basicInfo="${usednodes// /,};$EXPERIMENT;$cdomain;$advModel;$protocol;$partysize"
                echo -e "$basicInfo;$loopvalues$runtime;$maxRAMused;$basicComm" >> "$datatableShort"

                ## Full result measurement information
                ######
                # extract compile information (this is repeated many times, potential to optimize)
                p0intin=$(grep " integer inputs from player 0" "$compileinfo" | awk '{print $1}')
                p1intin=$(grep " integer inputs from player 1" "$compileinfo" | awk '{print $1}')
                p2intin=$(grep " integer inputs from player 2" "$compileinfo" | awk '{print $1}')
                p0bitin=$(grep " bit inputs from player 0" "$compileinfo" | awk '{print $1}')
                p1bitin=$(grep " bit inputs from player 1" "$compileinfo" | awk '{print $1}')
                p2bitin=$(grep " bit inputs from player 2" "$compileinfo" | awk '{print $1}')
                inputs="${p0intin:-NA};${p1intin:-NA};${p2intin:-NA};${p0bitin:-NA};${p1bitin:-NA};${p2bitin:-NA}"

                intbits=$(grep " integer bits" "$compileinfo" | awk '{print $1}')
                inttriples=$(grep " integer triples" "$compileinfo" | awk '{print $1}')
                bittriples=$(grep " bit triples" "$compileinfo" | awk '{print $1}')
                vmrounds=$(grep " virtual machine rounds" "$compileinfo" | awk '{print $1}')

                compilevalues="$inputs;${intbits:-NA};${inttriples:-NA};${bittriples:-NA};${vmrounds:-NA}"

                declare {Tx,Rx,broadcast,TxRx,passing,partBroadcast,Ex,Ex1to1,Rx1to1,Tx1to1,Txtoall}=""
                # infolineparser $1=regex $2=var-reference $3=column1 $4=column2 $5=column3
                infolineparser "Sending directly " "Tx" 3 6 9
                infolineparser "Receiving directly " "Rx" 3 6 9
                infolineparser "Broadcasting " "broadcast" 2 5 8
                infolineparser "Sending/receiving " "TxRx" 2 5 8
                infolineparser "Passing around " "passing" 3 6 9
                infolineparser "Partial broadcasting " "partBroadcast" 3 6 9
                infolineparser "Exchanging " "Ex" 2 5 8
                infolineparser "Exchanging one-to-one " "Ex1to1" 3 6 9
                infolineparser "Receiving one-to-one " "Rx1to1" 3 6 9
                infolineparser "Sending one-to-one " "Tx1to1" 3 6 9
                infolineparser "Sending to all " "Txtoall" 4 7 10

                measurementvalues="$runtime;$maxRAMused;$basicComm;$Tx;$Rx;$broadcast;$TxRx;$passing;$partBroadcast;$Ex;$Ex1to1;$Rx1to1;$Tx1to1;$Txtoall"

                # put all collected info into one row (Full)
                echo -e "$basicInfo;$compilevalues;$loopvalues$measurementvalues" >> "$datatableFull"

                # locate next loop file
                ((++i))
                loopinfo=$(find "$resultpath" -name "*$i.loop*" -print -quit)
            done
        done
    done
    # check if there was something exported
    rowcount=$(wc -l "$datatableShort" | awk '{print $1}')
    if [ "$rowcount" -lt 2 ];then
        okfail fail "nothing to export"
        rm "$datatableShort"
        return
    fi

    # create a tab separated table for pretty formating
    # convert .csv -> .tsv
    column -s ';' -t "$datatableShort" > "${datatableShort::-3}"tsv
    column -s ';' -t "$datatableFull" > "${datatableFull::-3}"tsv
    okfail ok "exported short and full results (${datatableShort::-3}tsv)"

##### push to measurement data git
####repourl=$(grep "repoupload" global-variables.yml | cut -d ':' -f 2-)
##### check if upload git does not exist yet
####if [ ! -d git-upload/.git ]; then
####    # clone the upload git repo
####    # default to trust server fingerprint authenticity (usually insecure)
####    GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' git clone "${repourl// /}" git-upload
####fi
####
####echo " pushing experiment measurement data to git repo$repourl"
####cd git-upload || error ${LINENO} "${FUNCNAME[0]} cd into gitrepo failed"
####{
####    # a pull is not really required, but for small sizes it doesn't hurt
####    git pull
####    # copy from local folder to git repo folder
####    cp -r ../"${EXPORTPATH::-12}" results/
####    git add . 
####    git commit -a -m "script upload"
####    git push 
####} &> /dev/null || error ${LINENO} "${FUNCNAME[0]} git upload failed"
    okfail ok " upload success" 
}

infolineparser() {
    # infolineparser $1=regex $2=var-reference $3=column1 $4=column2 $5=column3
    regex="$1"
    # get reference
    declare -n target="$2"

    MB=$(grep "$regex" "$runtimeinfo" | head -n 1 | awk -v c="$3" '{print $c}')
    Rounds=$(grep "$regex" "$runtimeinfo" | head -n 1 | awk -v c="$4" '{print $c}')
    Sec=$(grep "$regex" "$runtimeinfo" | head -n 1 | awk -v c="$5" '{print $c}')
    target="${MB:-NA};${Rounds:-NA};${Sec:-NA}"
}

# find out and set a protocols adversary model
setAdvModel() {
    protocol="$1"
    if [[ " ${maldishonestProtocols[*]} " == *" $protocol "* ]]; then
        advModel=maldishonest
    elif [[ " ${covertdishonestProtocols[*]} " == *" $protocol "* ]]; then
        advModel=covertdishonest
    elif [[ " ${semidishonestProtocols[*]} " == *" $protocol "* ]]; then
        advModel=semidishonest
    elif [[ " ${malhonestProtocols[*]} " == *" $protocol "* ]]; then
        advModel=malhonest
    elif [[ " ${semihonestProtocols[*]} " == *" $protocol "* ]]; then
        advModel=semihonest
    fi
}

# find out the actual party size, the nodecount does not imply the size
# since the program only uses as many nodes needed from all available
setPartySize() {

    protocol="$1"
    nodecount="${#NODES[*]}"
    partysize=""

    if [[ " ${N4Protocols[*]} " == *" $protocol "* ]]; then
        partysize="4"
    elif [[ " ${N3Protocols[*]} " == *" $protocol "* ]]; then
        partysize="3"
    elif [[ " ${N2Protocols[*]} " == *" $protocol "* ]]; then
        partysize="2"
    fi

    partysize=${partysize:-$nodecount}

}