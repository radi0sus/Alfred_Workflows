query=$1
# from Alfred input
comp=$query
# delete leading and trailing whitespaces
comp=$(echo "$comp" | sed 's/^[ ]*//;s/[ ]*$//')
# replace whitespace with '+'
comp=$(echo "$comp" | sed 's/ /+/g')
# replace / with '%2F'
comp=$(echo "$comp" | sed 's/\//%2F/g')

# at least 3 characters (necessary for autocomplete)
if [ ${#comp} -ge 3 ]; then
    # autocomplete api; limit is 8
    autocomp=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/autocomplete/compound/$comp/JSON?limit=8)
    # check if zero matches
    if [[ $(echo "$autocomp" | jq -r '.total') == 0 ]]; then
        # user input in case there are no matches from autocomplete
        autocomp=$(jq -n --arg title "$query" --arg arg "$query" '.items = [{"title": $title, "arg": $arg}]')
    else 
        # show 8 autocomplete suggestions
        autocomp=$(echo "$autocomp" | \
        jq '{"items": [. ["title"] = .dictionary_terms.compound[] 
            | .arg = .title 
            | del(.status, .code, .total,.dictionary_terms)]}' | \
            # the last one (No. 9) is the user input
            jq --arg title "$query" --arg arg "$query" '.items += [{"title": $title, "arg": $arg}]')
    fi
else
    # warning if less than 3 letters
    autocomp=$(jq -n '{"items": [{ "title": "Warning! Type at least 3 letters.", "icon": { "path": "./images/warning.png" } }]}')
fi

# display in Alfred
cat << EOB

$autocomp

EOB