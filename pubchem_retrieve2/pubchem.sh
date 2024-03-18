#!/usr/bin/env bash

# numbers to subscript numbers
subscript_numbers() {
    local input_formula="$1"
    local output_formula=""

    output_formula=$(echo "$input_formula" | \
                     sed 's/0/₀/g; 
                          s/1/₁/g; 
                          s/2/₂/g; 
                          s/3/₃/g; 
                          s/4/₄/g; 
                          s/5/₅/g; 
                          s/6/₆/g; 
                          s/7/₇/g; 
                          s/8/₈/g; 
                          s/9/₉/g')
    echo "$output_formula"
}

# replace COD entry with link to COD
generate_codlinks() {
    local cod_links=""
    for cod_id in "$@"; do
        cod_id=${cod_id//,/}
        if [[ $cod_id =~ [0-9]+ ]]; then
            cod_links+="[$cod_id](https://www.crystallography.net/cod/$cod_id.html), "
        fi
    done
    echo "$cod_links" 
}

# replace CCDC entry with link to CCDC
generate_ccdclinks() {
    local ccdc_links=""
    for ccdc_id in "$@"; do
        ccdc_id=${ccdc_id//,/}
        if [[ $ccdc_id =~ [0-9]+ ]]; then
            ccdc_links+="[$ccdc_id](https://www.ccdc.cam.ac.uk/structures/Search?Ccdcid=$ccdc_id), "
        fi
    done
    echo "$ccdc_links" 
}

# replace pictogram with pictrogram.png bitmap
# not working yet in Alfred
generate_pictlinks() {
    local pict_links=""
    for pict_id in "$@"; do
        #pict_id=${pict_id//,/}
        # not working in Alfred yet , only last pic is shown
        pict_links+="![$pict_id](./images/$pict_id.png) " 
    done
    echo "$pict_links" 
}

# compound from Script Filter selection 
comp=$1
#comp=$compound

# delete leading and trailing whitespaces
comp=$(echo "$comp" | sed 's/^[ ]*//;s/[ ]*$//')

# Properties to retrieve from PubChem
prop="Title,MolecularFormula,MolecularWeight,ExactMass,InChIKey,IsomericSMILES,IUPACName"

# for InChIKey
regexp="[A-Z]{14}-[A-Z]{10}-[A-Z]{1}"

# api request with HTTP status code 
if [[ $comp =~ $regexp ]]; then
    # for InChIKey
    resp=$(curl -s -X POST \
       -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "inchikey=$comp" \
       -w "%{http_code}" https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/inchikey/cids/TXT | \
      # in case that there are more than cids, take the first one; also submit HTTP status code 
        awk 'NR==1 ; END{print}' | tr -d '\n')
else
    # for name
    resp=$(curl -s -X POST \
       -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "name=$comp" \
       -w "%{http_code}" https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/cids/TXT | \
      # in case that there are more than one cid, take the first one; also submit HTTP status code 
        awk 'NR==1 ; END{print}' | tr -d '\n')
fi

# get HTTP status code
stat=${resp: -3}
# get CID (PubChem internal number)
cid=${resp:0:$((${#resp}-3))}

# if 404 or other codes ...
if [ "$stat" -eq 404 ]; then
    prop=$(jq -n '{"response":"# Error!    \n No CID found for the given compound name.    \n Press **esc** to go back to query."}')
elif [ "$stat" -ne 200 ]; then
    prop=$(jq -n '{"response":"# Error!    \n Unexpected HTTP status code.    \n Press **esc** to go back to query."}')
else
    # api request with CID from above
    req=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/$cid/property/$prop/JSON)

    # download image.
    curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/$cid/PNG -o ./images/temp.png 

########################## Info ########################################################### 
    # only the first info
    info=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/$cid/JSON?heading=Record+Description \
          | jq '.Record.Section[] 
          | .Section[]  
          | .Information[0].Value.StringWithMarkup[].String' \
          | tr -d '"')
    if [ -z "$info" ]; then
        info="not found"
    else 
        info=$(echo "$info" | tr '\n' ',' | tr -d '"' | sed 's/.$//' | sed 's/, */, /g')
    fi

########################## CAS ###########################################################    
    # get CAS; for CAS 'pug_view' instead of 'pug rest' api
    # only first CAS
    CAS=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/$cid/JSON?heading=CAS \
          | jq '.Record.Section[] 
          | .Section[] | .Section[] 
          | .Information[0].Value.StringWithMarkup[].String' \
          | tr -d '"')
    # CAS for Alfred
    if [ -z "$CAS" ]; then
        CAS="not found"
    else
        # generate link to https://commonchemistry.cas.org/
        CAS="[$CAS](https://commonchemistry.cas.org/detail?ref=$CAS)"
    fi
    
########################## Experimental Properties########################################
    expp=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/$cid/JSON/?heading=Experimental+Properties)
    
    # Density
    dens=$(echo "$expp" \
          | jq '.. 
          | objects 
          | select(.TOCHeading == "Density") 
          | .Information[]?.Value?.StringWithMarkup[]?.String')
    if [ -z "$dens" ]; then
        dens="not found"
    else 
        dens=$(echo "$dens" | tr '\n' ',' | tr -d '"' | sed 's/.$//' | sed 's/, */, /g')
    fi
    
    # Melting Point
    melp=$(echo "$expp" \
          | jq '.. 
          | objects 
          | select(.TOCHeading == "Melting Point") 
          | .Information[]?.Value?.StringWithMarkup[]?.String')
    if [ -z "$melp" ]; then
        melp="not found"
    else 
        melp=$(echo "$melp" | tr -d ',' | tr '\n' ',' | tr -d '"' | sed 's/.$//' | sed 's/, */, /g')
    fi
    
    # Boiling Point
    bolp=$(echo "$expp" \
          | jq '.. 
          | objects 
          | select(.TOCHeading == "Boiling Point") 
          | .Information[]?.Value?.StringWithMarkup[]?.String')
    if [ -z "$bolp" ]; then
        bolp="not found"
    else 
        bolp=$(echo "$bolp" | tr -d ',' | tr '\n' ',' | tr -d '"' | sed 's/.$//' | sed 's/, */, /g')
    fi
    
############################## CrystalStructures #########################################
    cnum=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/$cid/JSON/?heading=Crystal+Structures)
    # CCDC Numbers: https://www.ccdc.cam.ac.uk/structures/ 
    ccdc=$(echo "$cnum" | \
       jq '.. 
       | objects
       | select(.TOCHeading == "CCDC Number") 
       | .Information[]?.Value?.StringWithMarkup[]?.String')
    if [ -z "$ccdc" ]; then
        ccdc="not found"
    else 
        ccdc=$(echo "$ccdc" | tr '\n' ',' | tr -d '"' | sed 's/.$//' | sed 's/, */, /g')
        # generate link(s) to https://www.ccdc.cam.ac.uk/structures/ 
        ccdc=$(generate_ccdclinks $ccdc)
        ccdc=$(echo "$ccdc" | sed 's/,[[:space:]]*$//')
    fi
    # COD Numbers
    codn=$(echo "$cnum" | \
       jq '.. 
       | objects
       | select(.TOCHeading == "COD Number") 
       | .Information[]?.Value?.StringWithMarkup[]?.String')
    if [ -z "$codn" ]; then
        codn="not found"
    else 
        codn=$(echo "$codn" | tr '\n' ',' | tr -d '"' | sed 's/.$//' | sed 's/, */, /g')
        # generate link(s) to https://www.crystallography.net
        codn=$(generate_codlinks $codn)
        codn=$(echo "$codn" | sed 's/,[[:space:]]*$//')
    fi
    
########################## Safety ########################################################
    # get safety data with 'pug_view' 
    sfty=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/$cid/JSON?heading=Safety+and+Hazards)
    
    # pictogram text
    pict=$(echo "$sfty" \
          | jq '.Record.Section[0] 
          | .Section[0] | .Section[0] 
          | .Information[0].Value.StringWithMarkup[].Markup[].Extra')
    if [ -z "$pict" ] || [[ "$pict" == *"CID"* ]]; then
        pict="not found"
        # show pictogram bitmap(s) instead of text
        # not working yet in Alfred
        #picl="not found"
    else
        pict=$(echo $pict | sed 's/ "/, /g' |  tr -d '"')
        # show pictogram bitmaps instead of text 
        # not working yet in Alfred
        #pict_ns=$(echo $pict | tr -d ' ') 
        #pict_sk=$(echo $pict_ns | sed 's/,/ /g') 
        #picl=$(generate_pictlinks $pict_sk)
    fi
    # signal word
    sign=$(echo "$sfty" \
          | jq '.Record.Section[0] 
          | .Section[0] | .Section[0] 
          | .Information[1].Value.StringWithMarkup[].String')
    if [ -z "$sign" ]; then
        sign="not found"
    else
        sign=$(echo "$sign" | tr -d '"')
    fi
    # GHS hazard statement codes
    hsta=$(echo "$sfty" \
          | jq '.Record.Section[0] 
          | .Section[0] | .Section[0] 
          | .Information[2].Value.StringWithMarkup[].String')
    if [ -z "$hsta" ]; then
        hsta="not found"
    else
        hsta=$(echo "$hsta" | grep -o 'H[0-9][0-9][0-9]' \
               | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//')
    fi
    # GHS precautionary statement codes
    psta=$(echo "$sfty" \
           | jq '.Record.Section[0] 
           | .Section[0] | .Section[0] 
           | .Information[3].Value.StringWithMarkup[0].String')
    if [ "$psta" == null ]; then
        psta="not found"
    else
        psta=$(echo $psta | sed 's/"//g; s/and//g')
    fi
    
    # numbers tu subscript numbers in Molecular Formula
    molf=$(echo "$req" | jq '.PropertyTable.Properties[0].MolecularFormula')
    molf=$(subscript_numbers $molf | tr -d '"')
    
    prop=$(echo "$req" \
          | jq --arg info "$info" --arg molf "$molf" --arg cid  "$cid"  --arg cas "$CAS" \
               --arg dens "$dens" --arg melp "$melp" --arg bolp "$bolp" \
               --arg ccdc "$ccdc" --arg codn "$codn" \
               --arg picl "$picl" --arg pict "$pict" --arg sign "$sign"\
               --arg hsta "$hsta" --arg psta "$psta" \
                '{
                response: (
                           "# " + .PropertyTable.Properties[0].Title + "    \n" +
                           "![" + .PropertyTable.Properties[0].Title + "](./images/temp.png)" + "    \n" + 
                           "**IUPAC Name:** " + .PropertyTable.Properties[0].IUPACName + "    \n" +
                           "**Information:** " + $info + "    \n" +
                           "##### Properties    \n" +
                           # "**Molecular Formula:** " + .PropertyTable.Properties[0].MolecularFormula + "    \n" + 
                           "**Molecular Formula:** " + $molf + "    \n" + 
                           "**Molecular Weight:** " + .PropertyTable.Properties[0].MolecularWeight  + " g/mol    \n" + 
                           "**Exact Mass:** " + .PropertyTable.Properties[0].ExactMass + " g/mol    \n" +
                           "**InChIKey:** " + .PropertyTable.Properties[0].InChIKey + "    \n" +
                           "**Isomeric SMILES:** " + .PropertyTable.Properties[0].IsomericSMILES + "    \n" +
                           "##### Physical Properties    \n" +
                           "**Melting Point:** " + $melp + "    \n" + 
                           "**Boiling Point:** " + $bolp + "    \n" +
                           "**Density:** " + $dens + "     \n" + 
                           "##### Identifiers    \n" +
                           "**CID:** " + "[" + $cid + "](https://pubchem.ncbi.nlm.nih.gov/compound/" + $cid + ")" + "    \n" +
                           "**CAS:** " + $cas  + "    \n" + 
                           "##### Related Crystal Structures    \n" +
                           "**CCDC:** " + $ccdc  + "    \n" +
                           "**COD:** "  + $codn  + "    \n" +
                           "##### Safety Information    \n" +
                           # $picl + "    \n" +  - not working yet
                           "**Pictogram(s):** " + $pict + "    \n" + 
                           "**Signal Word:** " + $sign + "    \n" + 
                           "**GHS Hazard Statement Codes:** " + $hsta + "    \n" + 
                           "**GHS Precautionary Statement Codes:** " + $psta  
                           ),
                } + del(.PropertyTable) ')
fi

# show in Alfred
echo "$prop"