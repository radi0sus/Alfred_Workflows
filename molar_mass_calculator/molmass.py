import sys  # query input
import json # json for Alfred Script Filter
import re   # regular expressions

# empirical formula from Alfred input
query = sys.argv[1]

# dict with atomic weights
atomic_weights = {
    'H' : 1.0080,'He' : 4.0026, 'Li' : 6.940, 'Be' : 9.0122,
    'B' : 10.810, 'C' : 12.011, 'N' : 14.007, 'O' : 15.999,
    'F' : 18.998, 'Ne' : 20.180, 'Na' : 22.990, 'Mg' : 24.305,
    'Al' : 26.982, 'Si' : 28.085, 'P' : 30.974, 'S' : 32.060,
    'Cl' : 35.450, 'Ar' : 39.950, 'K' : 39.098, 'Ca' : 40.078,
    'Sc' : 44.956, 'Ti' : 47.867, 'V' : 50.942, 'Cr' : 51.996,
    'Mn' : 54.938, 'Fe' : 55.845, 'Co' : 58.933, 'Ni' : 58.693,
    'Cu' : 63.546, 'Zn' : 65.38, 'Ga' : 69.723, 'Ge' : 72.631,
    'As' : 74.922, 'Se' : 78.971, 'Br' : 79.904, 'Kr' : 84.798,
    'Rb' : 84.468, 'Sr' : 87.62, 'Y' : 88.906, 'Zr' : 91.224,
    'Nb' : 92.906, 'Mo' : 95.95, 'Tc' : 98.907, 'Ru' : 101.07,
    'Rh' : 102.906, 'Pd' : 106.42, 'Ag' : 107.868, 'Cd' : 112.414,
    'In' : 114.818, 'Sn' : 118.711, 'Sb' : 121.760, 'Te' : 126.7,
    'I' : 126.904, 'Xe' : 131.294, 'Cs' : 132.905, 'Ba' : 137.328,
    'La' : 138.905, 'Ce' : 140.116, 'Pr' : 140.908, 'Nd' : 144.243,
    'Pm' : 144.913, 'Sm' : 150.36, 'Eu' : 151.964, 'Gd' : 157.25,
    'Tb' : 158.925, 'Dy': 162.500, 'Ho' : 164.930, 'Er' : 167.259,
    'Tm' : 168.934, 'Yb' : 173.055, 'Lu' : 174.967, 'Hf' : 178.49,
    'Ta' : 180.948, 'W' : 183.84, 'Re' : 186.207, 'Os' : 190.23,
    'Ir' : 192.217, 'Pt' : 195.085, 'Au' : 196.967, 'Hg' : 200.592,
    'Tl' : 204.383, 'Pb' : 207.2, 'Bi' : 208.980, 'Po' : 208.982,
    'At' : 209.987, 'Rn' : 222.081, 'Fr' : 223.020, 'Ra' : 226.025,
    'Ac' : 227.028, 'Th' : 232.038, 'Pa' : 231.036, 'U' : 238.029,
    'Np' : 237, 'Pu' : 244, 'Am' : 243, 'Cm' : 247
}

# dict for sub-script numbers
utf_sub_dict = {
    "0" : "₀",
    "1" : "₁",
    "2" : "₂",
    "3" : "₃",
    "4" : "₄",
    "5" : "₅",
    "6" : "₆",
    "7" : "₇",
    "8" : "₈",
    "9" : "₉",
}

def calc_mm_mf(formula):
    # calculate molar mass and mass fractions
    # regex to match elements and their counts
    regex = r'([A-Z][a-z]*)(\d*)'
    
    # intit vars
    molar_mass = 0
    element_counts = {}
    sum_formula = ""

    # iterate through matches
    for match in re.finditer(regex, formula):
        element = match.group(1)
        count = int(match.group(2)) if match.group(2) else 1
        
        if element in atomic_weights:
            molar_mass += atomic_weights[element] * count
            element_counts[element] = element_counts.get(element, 0) + count
            # build empirical formula from recognized elements and their counts
            if count > 1:
                sum_formula += element + str(count)
            else:
                sum_formula += element 

    # calculate mass fraction
    mass_fraction = {element: (atomic_weights[element] * count) / \
                     molar_mass for element, count in element_counts.items()}

    return molar_mass, mass_fraction, sum_formula

def si_form(formula):
    # simplify empirical formula
    # sum all elements; e.g. C10H12H2C5 => C15H14
    # C, H, N first; e.g. ClArC3N2H3 => C3H3N2ArCl
    element_counts = {}
    for match in re.finditer(r'([A-Z][a-z]*)(\d*)', formula):
        element = match.group(1)
        count = int(match.group(2)) if match.group(2) else 1
        element_counts[element] = element_counts.get(element, 0) + count
    
    # sort elements, C, H, N, O first
    sorted_elements = sorted(element_counts.items(), key=lambda x: \
                      ('CHNO'.index(x[0]) if x[0] in 'CHNO' else float('inf'), x[0]))
    
    simplified_formula = ''.join(f"{element}{count if count > 1 else ''}" \
                         for element, count in sorted_elements)
    return simplified_formula

# numbers to subscript numbers
def num_to_sub(formula):
    return re.sub(r'\d', lambda m: utf_sub_dict[m.group()], formula)

# get empirical formula from Alfred input 
formula = query
# calc molar mass, mass fractions and empirical formula
molar_mass, mass_fraction, sum_formula = calc_mm_mf(formula)


# organize mass fractions; C: xx%, H xx%...
# C, H, N, O first
sorted_mf = sorted(mass_fraction.items(), key=lambda x: \
            ('CHNO'.index(x[0]) if x[0] in 'CHNO' else float('inf'), x[0]))
fr_str = ""
for element, fraction in sorted_mf:
    fr_str += f"{element}: {fraction:.2%}, "
fr_str = fr_str.rstrip(', ')    

# 
print(json.dumps(
    {"items": [
    {
        "title": num_to_sub(si_form(sum_formula)) + ": " + f"{molar_mass:.2f} g/mol",
        "subtitle": fr_str,
        "arg": [num_to_sub(si_form(sum_formula)),f"{molar_mass:.2f}",fr_str],
        "icon": {
            "path": "./images/calc.png"
        }
    }
]}))