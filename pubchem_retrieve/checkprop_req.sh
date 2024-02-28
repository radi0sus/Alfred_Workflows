#comp=$1
comp=$compound

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
    new_req=$(jq -n '{"items": [{"title": "Error! No CID found for the given compound name.", "icon": { "path": "./images/warning.png" } }]}')
elif [ "$stat" -ne 200 ]; then
    new_req=$(jq -n '{"items": [{"title": "Error: Unexpected HTTP status code.", "icon": { "path": "./images/warning.png" } }]}')
else
    # api request with CID from above
    req=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/$cid/property/$prop/JSON)
    # download image; it's to small, but...
    curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/$cid/PNG -o ./images/temp.png 
    # get Molecular Formula
    molf=$(echo "$req" \
          | jq '.title = .PropertyTable.Properties[0].MolecularFormula 
          | .subtitle = "Molecular Formula" 
          | .arg = .PropertyTable.Properties[0].MolecularFormula 
          | .icon.path= "./images/temp.png"  
          | del(.PropertyTable)')
    # get the Molecular Weight
    molw=$(echo "$req" \
          | jq '.title = .PropertyTable.Properties[0].MolecularWeight + " g/mol" 
          | .subtitle = "Molecular Weight" 
          | .arg = .PropertyTable.Properties[0].MolecularWeight + " g/mol" 
          | .icon.path= "./images/temp.png"  
          | del(.PropertyTable)')
    # get Exact Mass
    emas=$(echo "$req" \
          | jq '.title = .PropertyTable.Properties[0].ExactMass 
          | .subtitle = "Exact Mass" 
          | .arg = .PropertyTable.Properties[0].ExactMass 
          | .icon.path= "./images/temp.png" 
          | del(.PropertyTable)')
    # get Title
    name=$(echo "$req" \
          | jq '.title = .PropertyTable.Properties[0].Title 
          | .subtitle = "Name" | .arg = .PropertyTable.Properties[0].Title 
          | .icon.path= "./images/temp.png" | del(.PropertyTable)')
    # get IUPAC Name
    inam=$(echo "$req" \
          | jq 'if has("PropertyTable") and (.PropertyTable.Properties[0].IUPACName 
          | length > 0) then 
            .title = .PropertyTable.Properties[0].IUPACName 
          | .subtitle = "IUPAC Name" 
          | .arg = .PropertyTable.Properties[0].IUPACName 
          | .icon.path= "./images/temp.png" 
          | del(.PropertyTable)
    else
          .title = "not found"
          | .subtitle = "IUPAC Name" 
          | .arg = "not found" 
          | .icon.path= "./images/temp.png" 
          | del(.PropertyTable)
          end')
    # get InChI
    inci=$(echo "$req" \
          | jq '.title = .PropertyTable.Properties[0].InChIKey 
          | .subtitle = "InChIKey" 
          | .arg = .PropertyTable.Properties[0].InChIKey 
          | .icon.path= "./images/temp.png" 
          | del(.PropertyTable)')
    # get SMILES
    ismi=$(echo "$req" \
          | jq '.title = .PropertyTable.Properties[0].IsomericSMILES 
          | .subtitle = "Isomeric SMILES" 
          | .arg = .PropertyTable.Properties[0].IsomericSMILES 
          | .icon.path= "./images/temp.png" 
          | del(.PropertyTable)')
    # link to compound
    owww=$(echo "$req" \
          | jq --arg cid "$cid" '.title = "https://pubchem.ncbi.nlm.nih.gov/compound/" + $cid 
          | .subtitle = "Open PubChem WebSite" 
          | .arg = "https://pubchem.ncbi.nlm.nih.gov/compound/" + $cid 
          | .icon.path= "./images/temp.png" 
          | del(.PropertyTable)')
########################## CAS ###########################################################
    # get CAS; for CAS 'pug_view' instead of 'pug rest' api
    CAS=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/$cid/JSON?heading=CAS \
          | jq '.Record.Section[] 
          | .Section[] | .Section[] 
          | .Information[0].Value.StringWithMarkup[].String' \
          | tr -d '"')
    # CAS for Alfred
    if [ -z "$CAS" ]; then
        CAS="not found"
    fi
    casn=$(jq -n --arg cas "$CAS" '.title = $cas 
          | .subtitle = "CAS Number" 
          | .arg = $cas 
          | .icon.path= "./images/temp.png"')
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
    # density for Alfred
    dens=$(jq -n --arg dens "$dens" '.title = $dens 
          | .subtitle = "Density (Densities)" 
          | .arg = $dens 
          | .icon.path= "./images/temp.png"')

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
    # melting point for Alfred
    melp=$(jq -n --arg melp "$melp" '.title = $melp 
          | .subtitle = "Melting Point(s)"
          | .arg = $melp 
          | .icon.path= "./images/temp.png"')
          
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
    # boiling point for Alfred
    bolp=$(jq -n --arg bolp "$bolp" '.title = $bolp 
          | .subtitle = "Boiling Point(s)"
          | .arg = $bolp 
          | .icon.path= "./images/temp.png"')
          
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
    else
        pict=$(echo $pict | sed 's/ "/, /g' |  tr -d '"')
    fi
    # pictogram text for Alfred
    pict=$(jq -n --arg pict "$pict" '.title = $pict 
          | .subtitle = "Pictogram(s) Text" 
          | .arg = $pict 
          | .icon.path= "./images/temp.png"')
    
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
    # signal word for Alfred
    sign=$(jq -n --arg sign "$sign" '.title = $sign 
          | .subtitle = "Signal Word" 
          | .arg = $sign 
          | .icon.path= "./images/temp.png"')
    
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
    # GHS hazard statement codes for Alfred
    hsta=$(jq -n --arg hsta "$hsta" '.title = $hsta 
          | .subtitle = "GHS Hazard Statement Codes" 
          | .arg = $hsta 
          | .icon.path= "./images/temp.png"')
    
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
    # GHS precautionary statement codes for Alfred
    psta=$(jq -n --arg psta "$psta" '.title = $psta 
          | .subtitle = "GHS Precautionary Statement Codes" 
          | .arg = $psta 
          | .icon.path= "./images/temp.png"')
          
############################## CrystalStructures #########################################
    # CCDC Numbers + COD Numbers
    cnum=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/$cid/JSON/?heading=Crystal+Structures)
    # CCDC Numbers:  https://www.ccdc.cam.ac.uk/structures/ 
    ccdc=$(echo "$cnum" | \
       jq '.. 
       | objects
       | select(.TOCHeading == "CCDC Number") 
       | .Information[]?.Value?.StringWithMarkup[]?.String')
    if [ -z "$ccdc" ]; then
        ccdc="not found"
    else 
        ccdc=$(echo "$ccdc" | tr '\n' ',' | tr -d '"' | sed 's/.$//' | sed 's/, */, /g')
    fi
    # CCDC Numbers for Alfred: https://www.ccdc.cam.ac.uk/structures/ 
    ccdc=$(jq -n --arg ccdc "$ccdc" '.title = $ccdc 
          | .subtitle = "Related CCDC Number(s)"
          | .arg = $ccdc 
          | .icon.path= "./images/temp.png"')
    
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
    fi
    # COD Numbers for Alfred: https://www.crystallography.net/cod/search.html
    codn=$(jq -n --arg codn "$codn" '.title = $codn 
          | .subtitle = "Related COD Number(s)" 
          | .arg = $codn 
          | .icon.path= "./images/temp.png"')
          
################ all properties for clipboard ###########################################
    cname=$(echo "$name" | jq '.arg')
    cinam=$(echo "$inam" | jq '.arg')
    cmolf=$(echo "$molf" | jq '.arg')
    cmolw=$(echo "$molw" | jq '.arg')
    cemas=$(echo "$emas" | jq '.arg')
    cinci=$(echo "$inci" | jq '.arg')
    cismi=$(echo "$ismi" | jq '.arg')
    ccasn=$(echo "$casn" | jq '.arg')
    cowww=$(echo "$owww" | jq '.arg')
    cdens=$(echo "$dens" | jq '.arg')
    cmelp=$(echo "$melp" | jq '.arg')
    cbolp=$(echo "$bolp" | jq '.arg')
    cpict=$(echo "$pict" | jq '.arg')
    chsta=$(echo "$hsta" | jq '.arg')
    cpsta=$(echo "$psta" | jq '.arg')
    csign=$(echo "$sign" | jq '.arg')
    cccdc=$(echo "$ccdc" | jq '.arg')
    ccodn=$(echo "$codn" | jq '.arg')
    allp=$(jq -n --arg name "$cname" --arg inam "$cinam" --arg molf "$cmolf" \
                 --arg molw "$cmolw" --arg emas "$cemas" --arg inci "$cinci" \
                 --arg ismi "$cismi" --arg casn "$ccasn" --arg owww "$cowww" \
                 --arg dens "$cdens" --arg melp "$cmelp" --arg bolp "$cbolp"\
                 --arg pict "$cpict" --arg hsta "$chsta" --arg psta "$cpsta" \
                 --arg sign "$csign" --arg ccdc "$cccdc" --arg codn "$ccodn"\
                 '.title = "Copy all of the above to the clipboard" 
                | .subtitle = $name 
                | .arg = ["allprop",$name,$inam,$molf,$molw,$emas,$inci,$ismi,$casn,$owww,$dens,$melp,$bolp,$pict,$sign,$hsta,$psta,$ccdc,$codn]
                | .icon.path= "./images/temp.png"') 
    # build list of items
    new_req="{\"items\": [ $name, $inam, $molf, $molw, $emas, $inci, $ismi, $casn, $owww, $dens, $melp, $bolp, $pict, $sign, $hsta, $psta, $ccdc, $codn, $allp]}"
fi

# show in Alfred
cat << EOB

$new_req

EOB
