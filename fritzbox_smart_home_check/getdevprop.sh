#!/bin/zsh

# credentials for FRITZ!Box login
# Alfred
if [ -n "${usecred}" ]; then
    # from credential file
    source "${credloc}"
    user="$user"
    pass="$pass"
    fbox="$fbox"
else
    # from Alfred Configure Workflow
    user="${user}"
    pass="${pass}"
    fbox="${address}"
fi

# No Alfred
#source ~/.fbcredentials
#user="$user"
#pass="$pass"
#fbox="$fbox"

# fetch challenge
# see FRITZ!Box documentation
challenge=$(curl -s -k "$fbox/login_sid.lua" | xmllint --xpath "//Challenge/text()" -)
sleep 0.25

# warning and exit in case of fetching a challenge problems
if [ -z "$challenge" ]; then
    json_output=$(jq -nR '{"items": [{ "title": "Warning! Problem fetching a challenge.", "icon": { "path": "./images/warning.png" } }]}')
    echo "$json_output"
    exit 1
fi

# login FRITZ!Box
# see FRITZ!Box documentation
md5=$(echo -n $challenge"-"$pass | iconv -f ISO8859-1 -t UTF-16LE | md5 | awk '{print substr($0,1,32)}')
response=$challenge-$md5
sid=$(curl -i -s -k -d "response=$response&username=$user" "$fbox" | grep -oE '"sid":"[^"]+"' | sed 's/"sid":"\([^"]*\)"/\1/')
sleep 0.25

# warning and exit in case of login problems
if [ -z "$sid" ]; then
    json_output=$(jq -nR '{"items": [{ "title": "Warning! Login problem.", "icon": { "path": "./images/warning.png" } }]}')
    echo "$json_output"
    exit 1
fi

# fetch device list from FRITZ!Box
devlist=$(curl -s -k $fbox'/webservices/homeautoswitch.lua?switchcmd=getdevicelistinfos&sid'=$sid | xmllint --format -)

# get AIN, ID, FunctionBit, Firmware Version, Product Name, Name, Status: present / not present
devain=$(echo $devlist | xmllint --xpath "//device[@manufacturer='AVM']/@identifier" - | awk -F'"' '{print $2}' | tr -d ' ')
devid=$(echo $devlist | xmllint --xpath "//device[@manufacturer='AVM']/@id" - | awk -F'"' '{print $2}')
devfbit=$(echo $devlist | xmllint --xpath "//device[@manufacturer='AVM']/@functionbitmask" - | awk -F'"' '{print $2}')
devfvers=$(echo $devlist | xmllint --xpath "//device[@manufacturer='AVM']/@fwversion" - | awk -F'"' '{print $2}') 
devpname=$(echo $devlist | xmllint --xpath "//device[@manufacturer='AVM']/@productname" - | awk -F'"' '{print $2}')
devname=$(echo $devlist | xmllint --xpath "//device[@manufacturer='AVM']/name/text()" - )
devpres=$(echo $devlist | xmllint --xpath "//device[@manufacturer='AVM']/present/text()" - )

get_prop() {
    # fetch a property method 1
    local proplist=""
    local prop="$1"
    local fac="$2"
    local prec="$3"
    local typ="$4"
    local unit="$5"
    
    echo "$devid" | while IFS= read -r dev; do
        # Check if the device has a certain tag
        dev_prop=$(echo "$devlist" | xmllint --xpath "//device[@manufacturer='AVM'][@id='$dev'][$prop]/$prop/text()" - 2>/dev/null)
        if [ -z "$dev_prop" ]; then
            proplist+=" \n"
        else
            dev_prop_rounded=$(echo "scale=$prec; $dev_prop / $fac" | bc)
            proplist+="$typ$((dev_prop / fac))$unit ·\n"
        fi
    done

    proplist=$(echo "$proplist" | sed '/^$/d')
    echo "$proplist"
}

get_prop2() {
    # fetch a property method 2
    local proplist=""
    local prop1="$1"
    local prop2="$2"
    local fac="$3"
    local prec="$4"
    local typ="$5"
    local unit="$6"
    
    echo "$devid" | while IFS= read -r dev; do
        # Check if the device has a certain tag
        dev_prop=$(echo "$devlist" | xmllint --xpath "//device[@manufacturer='AVM'][@id='$dev'][$prop1]/$prop1/$prop2/text()" - 2>/dev/null)
        if [ -z "$dev_prop" ]; then
            proplist+=" \n"
        else
            dev_prop_rounded=$(echo "scale=$prec; $dev_prop / $fac" | bc)
            proplist+="$typ$dev_prop_rounded$unit ·\n"
        fi
    done

    proplist=$(echo "$proplist" | sed '/^$/d')
    echo "$proplist"
}

get_prop_bin2() {
    # fetch a property method 3
    local proplist=""
    local prop1="$1"
    local prop2="$2"
    
    echo "$devid" | while IFS= read -r dev; do
        # Check if the device has certain battery tag
        dev_prop=$(echo "$devlist" | xmllint --xpath "//device[@manufacturer='AVM'][@id='$dev'][$prop1]/$prop1/$prop2/text()" - 2>/dev/null)
        if [ -z "$dev_prop" ]; then
            proplist+=" \n"
        else
            if [ "$dev_prop" -eq 0 ]; then
                proplist+="⏻ OFF ·\n"
            else
                proplist+="⏻ ON ·\n"
            fi
        fi
    done

    proplist=$(echo "$proplist" | sed '/^$/d')
    echo "$proplist"
}

get_dev_pic() {
    # get icon.png for specific device, depending on last 3 numbers; FRITZ!DECT 301 => 301
    local icons=("$@")
    local icon_list=()  
    
    echo "$devpname" | while IFS= read -r line; do
        local last_three_num=$(echo "$line" | grep -oE '[0-9]{3}$')
        if [[ "$last_three_num" == "" ]]; then
            icon_list+=("./images/gen.png")
        elif echo "${icons[@]}" | grep -qw "$last_three_num"; then
            icon_list+=("./images/$last_three_num.png")
        else
            # assign general icon for unknown devices
            icon_list+=("./images/gen.png")
        fi
    done

     printf "%s\n" "${icon_list[@]}"
}

# property factor precision label unit
batinfo=$(get_prop "battery" "1" "0" "B: " "%")
# property1 property2 factor precision label unit
# factor because, for example value of T is 210 for 21.0
# precision examples 0: 1; 1: 1.1; 2: 1.11
tempinfo=$(get_prop2 "temperature" "celsius" "10" "1" "T: " "°C")
huminfo=$(get_prop2 "humidity" "rel_humidity" "1" "0" "H: " "%")
volinfo=$(get_prop2 "powermeter" "voltage" "1000" "1" "V: " "V")
powinfo=$(get_prop2 "powermeter" "power" "1000" "1" "P: " "W")
eninfo=$(get_prop2 "powermeter" "energy" "1000" "1" "E: " "kWh")
# property1 property2
swinfo=$(get_prop_bin2 "simpleonoff" "state")

# assign icons for specific devices
icon_list=$(get_dev_pic 200 201 210 301 440)

# show in Alfred
json_output=$(paste <(echo "$devname") <(echo "$devain") <(echo "$devid") \
                    <(echo "$devpname") <(echo "$devfvers") <(echo "$devfbit")\
                    <(echo "$devpres") <(echo "$batinfo") <(echo "$tempinfo") \
                    <(echo "$huminfo") <(echo "$powinfo") <(echo "$volinfo") \
                    <(echo "$eninfo") <(echo "$swinfo") <(echo "$icon_list") | \
            jq -nR '{"cache": {
                            "seconds": 3600,
                            "loosereload": true
                              },
                     "items": 
                    [inputs 
                    | split("\t") 
                    | {"title": .[0],
                       "uid": .[0], 
                       "subtitle": "\(.[8]) \(.[9]) \(.[7]) \(.[11]) \(.[10]) \(.[12]) \(.[13]) ⏼ \(.[6])", 
                       "icon": {
                            "path": .[14]
                                },
                        "mods": {
                                "cmd": {
                                "valid": true,
                                "arg": [.[]],
                                "subtitle": "\(.[3]) · ID \(.[2]) · AIN \(.[1]) · FW \(.[4]) · FB \(.[5]) "
                                        }
                                },
                       "arg": [.[]]}
                    ]}
            ' | tr -s ' ')
echo "$json_output" 

