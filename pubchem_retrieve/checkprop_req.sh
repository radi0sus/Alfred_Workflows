#comp=$1
comp=$compound

# delete leading and trailing whitespaces
comp=$(echo "$comp" | sed 's/^[ ]*//;s/[ ]*$//')


# Properties to retrieve from PubChem
prop="Title,MolecularFormula,MolecularWeight,ExactMass,InChIKey,IsomericSMILES,IUPACName"

# api request with HTTP status code 
resp=$(curl -s -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "name=$comp" \
  -w "%{http_code}" https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/cids/TXT | \
    # in case that there are more than cids, take the first one; also submit HTTP status code 
      { head -n 1; tail -n 1; } | tr -d '\n')

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
          | jq '.title = .PropertyTable.Properties[0].IUPACName 
          | .subtitle = "IUPAC Name" 
          |  .arg = .PropertyTable.Properties[0].IUPACName 
          | .icon.path= "./images/temp.png" 
          | del(.PropertyTable)')
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
    # get CAS; for CAS 'pug_view' instead of 'pug rest' api
    CAS=$(curl -s https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/$cid/JSON?heading=CAS \
          | jq '.Record.Section[] 
          | .Section[] | .Section[] 
          | select(.TOCHeading == "CAS") 
          | .Information[0].Value.StringWithMarkup[].String' \
          | tr -d '"')
    # CAS for Alfred
    casn=$(jq -n --arg cas "$CAS" '.title = $cas 
          | .subtitle = "CAS Number" 
          | .arg = $cas 
          | .icon.path= "./images/temp.png"')

    # all properties for clipboard
    cname=$(echo "$name" | jq '.arg')
    cinam=$(echo "$inam" | jq '.arg')
    cmolf=$(echo "$molf" | jq '.arg')
    cmolw=$(echo "$molw" | jq '.arg')
    cemas=$(echo "$emas" | jq '.arg')
    cinci=$(echo "$inci" | jq '.arg')
    cismi=$(echo "$ismi" | jq '.arg')
    ccasn=$(echo "$casn" | jq '.arg')
    cowww=$(echo "$owww" | jq '.arg')
    allp=$(jq -n --arg name "$cname" --arg inam "$cinam" --arg molf "$cmolf" \
                 --arg molw "$cmolw" --arg emas "$cemas" --arg inci "$cinci" \
                 --arg ismi "$cismi" --arg casn "$ccasn" --arg owww "$cowww" \
                 '.title = "Copy all of the above to the clipboard" 
                | .subtitle = $name 
                | .arg = ["allprop",$name,$inam,$molf,$molw,$emas,$inci,$ismi,$casn,$owww]
                | .icon.path= "./images/temp.png"') 
    # build list of items
    new_req="{\"items\": [ $name, $inam, $molf, $molw, $emas, $inci, $ismi, $casn, $owww, $allp]}"
fi

# show in Alfred
cat << EOB

$new_req

EOB
