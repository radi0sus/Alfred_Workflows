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

# Date Format (only for months)
export LC_TIME="$dateformat"

# No Alfred
#source ~/.fbcredentials
#user="$user"
#pass="$pass"
#fbox="$fbox"

# fetch challenge FRITZ!Box
# see FRITZ!Box documentation
challenge=$(curl -s -k "$fbox/login_sid.lua" | xmllint --xpath "//Challenge/text()" -)
sleep 0.25

# warning and exit in case of fetching a challenge problems
if [ -z "$challenge" ]; then
    json_output=$(jq -nR '{ "response": "## Warning! Problem fetching a challenge."}')
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
    json_output=$(jq -nR '{ "response": "## Warning! Login problem."}')
    echo "$json_output"
    exit 1
fi

# process values from arg of script filter
while IFS= read -r line; do
    devinfo+=("$line")
done <<< "$1"

#>&2 echo "${devinfo[2]}"

# fetch device statistics
devstat=$(curl -s -k "$fbox/webservices/homeautoswitch.lua?ain=${devinfo[2]}&switchcmd=getbasicdevicestats&sid=$sid" | xmllint --format -)
#echo "$devstat"

# temperature: count grid datatime values <= see FRITZ!Box documentation
countt=$(echo $devstat | xmllint --xpath "string(//devicestats/temperature/stats/@count)" -)
gridt=$(echo $devstat | xmllint --xpath "string(//devicestats/temperature/stats/@grid)" -)
datatimet=$(echo $devstat | xmllint --xpath "string(//devicestats/temperature/stats/@datatime)" -)
valuest=$(echo $devstat | xmllint --xpath "string(//devicestats/temperature/stats/text())" -)

# humidity: count grid datatime values <= see FRITZ!Box documentation
counth=$(echo $devstat | xmllint --xpath "string(//devicestats/humidity/stats/@count)" -)
gridh=$(echo $devstat | xmllint --xpath "string(//devicestats/humidity/stats/@grid)" -)
datatimeh=$(echo $devstat | xmllint --xpath "string(//devicestats/humidity/stats/@datatime)" -)
valuesh=$(echo $devstat | xmllint --xpath "string(//devicestats/humidity/stats/text())" -)

# voltage: count grid datatime values <= see FRITZ!Box documentation
countv=$(echo $devstat | xmllint --xpath "string(//devicestats/voltage/stats/@count)" -)
gridv=$(echo $devstat | xmllint --xpath "string(//devicestats/voltage/stats/@grid)" -)
datatimev=$(echo $devstat | xmllint --xpath "string(//devicestats/voltage/stats/@datatime)" -)
valuesv=$(echo $devstat | xmllint --xpath "string(//devicestats/voltage/stats/text())" -)

# power: count grid datatime values <= see FRITZ!Box documentation
countp=$(echo $devstat | xmllint --xpath "string(//devicestats/power/stats/@count)" -)
gridp=$(echo $devstat | xmllint --xpath "string(//devicestats/power/stats/@grid)" -)
datatimep=$(echo $devstat | xmllint --xpath "string(//devicestats/power/stats/@datatime)" -)
valuesp=$(echo $devstat | xmllint --xpath "string(//devicestats/power/stats/text())" -)

# energy yearly stats: count grid datatime values <= see FRITZ!Box documentation
countey=$(echo $devstat | xmllint --xpath "string(//devicestats/energy/stats[position()=1]/@count)" -)
gridey=$(echo $devstat | xmllint --xpath "string(//devicestats/energy/stats[position()=1]/@grid)" -)
datatimeey=$(echo $devstat | xmllint --xpath "string(//devicestats/energy/stats[position()=1]/@datatime)" -)
valuesey=$(echo $devstat | xmllint --xpath "string(//devicestats/energy/stats[position()=1]/text())" -)

# energy monthly stats: count grid datatime values <= see FRITZ!Box documentation
countem=$(echo $devstat | xmllint --xpath "string(//devicestats/energy/stats[position()=2]/@count)" -)
gridem=$(echo $devstat | xmllint --xpath "string(//devicestats/energy/stats[position()=2]/@grid)" -)
datatimeem=$(echo $devstat | xmllint --xpath "string(//devicestats/energy/stats[position()=2]/@datatime)" -)
valuesem=$(echo $devstat | xmllint --xpath "string(//devicestats/energy/stats[position()=2]/text())" -)

generate_xydata() {
    # +%b month, +%d day
    # values grid datatime (<= see FRITZ!Box documentation) 
    # unix epoch => human
    local values_array=("${(@s/,/)1}")
    local values_array=("${(@Oa)values_array}")
    local grid="$2"
    local datatime="$3"
    local timeval="$4"
    local name="$5"
    # number of values
    # open tempfile for data
    local count=${#values_array}
    local tmp_data=$(mktemp /tmp/"$name"_data.XXXXXX)

    for ((i = 0; i < count; i++)); do
        local timestamp=$((datatime - grid * (count - i - 1)))
        local formatted_date=$(date -r "$timestamp" "$timeval")
        echo "$formatted_date" "${values_array[$i+1]}" >> "$tmp_data"
    done

    echo "$tmp_data"
}

gen_bar_chart() {
    # generate a bar chart with gnuplot
    # xy_data name_of_the_plot.png title xlabel ylabel division_factor (Wh > kWh = 1000)
    local tmp_data=$1
    local name=$2
    local title=$3
    local xlabel=$4
    local ylabel=$5
    local fac=$(($6))
    
    # format the gnuplot bar chart    
    local gnuplot_commands="
        set terminal png size 900,300 transparent truecolor enhanced font 'Helvetica,10.5'
        set output './images/$name.png'
        set title '$title'
        #set xlabel '$xlabel'
        set ylabel '$ylabel'
        set xdata time
        set timefmt '%Y-%m-%d' 
        set boxwidth 0.5 relative
        #set xtics rotate by -45
        set style fill solid border -1

        # Disable frame and ticks
        unset border
        set xtics nomirror
        unset ytics
        unset key
        set yrange [0.00001:*]
        set cbrange [0.00001:*]
        
        #set colorbox user origin graph 1.01, graph 0 size 0.01, graph 1 noborder
        #set rmargin at screen 0.95
        #set palette rgb 33,13,10
        #set palette rgbformulae 3,11,6
        #set palette rgbformulae 7,5,15 
        #set format cb '%.1f'
        set palette defined ( 0 '#F7FBFF',\
              1 '#DEEBF7',\
              2 '#C6DBEF',\
              3 '#9ECAE1',\
              4 '#6BAED6',\
              5 '#4292C6',\
              6 '#2171B5',\
              7 '#084594' )
        unset colorbox

        #set multiplot layout 1,2 rowsfirst
        plot '$tmp_data' using 0:(\$2/$fac):(\$2/$fac):xticlabels(1) with boxes palette title '$title', \
        '' using 0:(\$2/$fac):(sprintf('%.2f', \$2/$fac)) with labels offset 0,1 notitle
        "
     # run gnuplot, suppress error messages 
    echo "$gnuplot_commands" | gnuplot - 2>/dev/null

    # delete tempfile
    rm "$tmp_data"
}

gen_bar_chart2() {
    # generate a bar chart with gnuplot
    # xy_data name_of_the_plot.png title xlabel ylabel division_factor (Wh > kWh = 1000) color_range
    local tmp_data=$1
    local name=$2
    local title=$3
    local xlabel=$4
    local ylabel=$5
    local fac=$(($6))
    local cbrange=$7
    local yrange=$8
    local yoffset=$9
    
    local starttime=$(head -n 1 "$tmp_data" | awk '{print $1}')
    local endtime=$(tail -n 1 "$tmp_data" | awk '{print $1}')
    
    # format the gnuplot bar chart
    local gnuplot_commands="
        set terminal png size 900,300 transparent truecolor enhanced font 'Helvetica,10.5'
        set output './images/$name.png'
        set title '$title'
        #set xlabel '$xlabel'
        set ylabel '$ylabel'
        set xdata time
        set timefmt '%d-%H:%M' 
        set format x '%H:%M'
        #set xtics rotate by -45
        #set yrange [:]
        #set xrange [:]
        set boxwidth 1 relative
        set style fill solid border -1

        # Disable frame and ticks
        set border 11
        #unset border
        set xtics nomirror
        #set ytics nomirror
        set y2tics 
        set grid y
        set format y '%.1f'
        #unset ytics
        unset key
        #set autoscale yfix
        set offset 0,0,$yoffset
        set yrange $yrange
        #set yrange [0.00001:*] 
        #set cbrange [0.00001:*] 
        
        #set colorbox user origin graph 1.01, graph 0 size 0.01, graph 1 noborder
        #set rmargin at screen 0.95
        set xrange ['$starttime':'$endtime']
        #set palette rgb 33,13,10
        #set format cb '%.1f'
        set cbrange $cbrange
        #set palette rgbformulae 7,5,15
        set palette defined (0 '#3288BD', \
               1 '#66C2A5',\
               2 '#ABDDA4',\
               3 '#E6F598',\
               4 '#FEE08B',\
               5 '#FDAE61',\
               6 '#F46D43',\
               7 '#D53E4F')
        unset colorbox
        
        #plot '$tmp_data' using 1:(\$2/$fac):(\$2/$fac) with impulses linewidth 5 palette title '$title' 
        plot '$tmp_data' using 1:(\$2/$fac):(\$2/$fac) with boxes palette title '$title' 
        "
    # run gnuplot, suppress error messages 
    echo "$gnuplot_commands" | gnuplot - 2>/dev/null

    # delete tempfile
    rm "$tmp_data"
}

# generate x,y data
# values grid datatime (<= see FRITZ!Box documentation) timeval name
tmp_data_ey=$(generate_xydata "${valuesey[@]}" "$gridey" "$datatimeey" "+%b" "eny")
tmp_data_em=$(generate_xydata "${valuesem[@]}" "$gridem" "$datatimeem" "+%d" "enm")
tmp_data_t=$(generate_xydata "${valuest[@]}" "$gridt" "$datatimet" "+%d-%H:%M" "temp")
tmp_data_h=$(generate_xydata "${valuesh[@]}" "$gridh" "$datatimeh" "+%d-%H:%M" "hum")
tmp_data_p=$(generate_xydata "${valuesp[@]}" "$gridp" "$datatimep" "+%d-%H:%M" "pow")
tmp_data_v=$(generate_xydata "${valuesv[@]}" "$gridv" "$datatimev" "+%d-%H:%M" "vol")

# plot x,y data with gnuplot
# xy_data name_of_the_plot.png title xlabel ylabel division_factor (Wh > kWh = 1000)
gen_bar_chart "$tmp_data_ey" "kwh_p_y" "kWh / ${month}" "${month}" "kWh" "1000"
gen_bar_chart "$tmp_data_em" "kwh_p_m" "kWh / ${day}" "${day}" "kWh" "1000"
# xy_data name_of_the_plot.png title xlabel ylabel division_factor (Wh > kWh = 1000) color_range y-autoscale y-offset
gen_bar_chart2 "$tmp_data_t" "temp_p_h" "${temp}" "${hour}" "°C" "10" "[-10:35]" "[*:*]" "1,1"
gen_bar_chart2 "$tmp_data_h" "hum_p_h" "${hum}" "${hour}" "%" "1" "[0:100]" "[*:*]" "1,1"
gen_bar_chart2 "$tmp_data_p" "pow_p_h" "${pow}" "${hour}" "W" "100" "[0:600]" "[0.00001:*]" "0,0"
gen_bar_chart2 "$tmp_data_v" "vol_p_h" "${vol}" "${hour}" "V" "1000" "[210:240]" "[*:*]" "1,1"

# show in Alfred
jq -n --arg name "${devinfo[1]}" --arg ain "${devinfo[2]}" --arg id "${devinfo[3]}" \
      --arg pname "${devinfo[4]}" --arg vers "${devinfo[5]}" --arg fbit "${devinfo[6]}" \
      --arg pres "${devinfo[7]}" --arg bat "${devinfo[8]}" --arg temp "${devinfo[9]}" \
      --arg hum "${devinfo[10]}" --arg pow "${devinfo[11]}" --arg vol "${devinfo[12]}" \
      --arg en "${devinfo[13]}" --arg sw "${devinfo[14]}"  --arg icon "${devinfo[15]}" \
'{
  "response": (
               "**Name**: " + $name + " · " +
               "**Type**: " + $pname + " · " +
               "**ID**: " + $id + " · " +
               "**AIN**: " + $ain + " · " +
               "**FW**: " + $vers + " " + "    \n" +
               "\n" +
               "![](./images/kwh_p_y.png)    \n" +
               "![](./images/kwh_p_m.png)    \n" +
               "![](./images/temp_p_h.png)    \n" +
               "![](./images/hum_p_h.png)    \n" +
               "![](./images/pow_p_h.png)    \n" +
               "![](./images/vol_p_h.png) "
              )
}'

