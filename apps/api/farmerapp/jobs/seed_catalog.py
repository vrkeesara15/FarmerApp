"""Static catalogue for the demo seed (M3-KICKOFF): products, packs, the pest / disease
master for the six pilot crops and the label-claim fixtures.

Everything here is **demo data**. Active ingredients, formulations, pack sizes and HSN codes
are realistic; doses, PHI and prices are plausible label values, not CIB&RC records — every
claim is written with ``source_ref = SEED_SOURCE_REF`` so the agronomist gate (SPEC 14.6)
replaces them before anything is recommended to a farmer. GST rates follow the current
schedule: seeds for sowing are nil-rated (HSN 1006 / 1005 / 1207 / 1209 / 1202 — SPEC's
"5 % seeds" was checked and corrected), fertilisers 5 % (3102-3105), pesticides 18 %
(3808), bio-pesticides 12 %, manual sprayers 12 % (8424), tarpaulins 18 % (3926).

``"{OB}"`` in a product name / brand is the tenant's own-brand label (``FCC`` for Future
Crop Care, ``GFL`` for Green Fields).
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field

from farmerapp.catalog.models import DoseUnit, PackUnit, ProblemType, ProductCategory

OWN_BRAND_LABEL: Mapping[str, str] = {"fcc": "FCC", "gfl": "GFL"}
OWN = "{OB}"

PPE_TEXT = (
    "Wear long sleeves, trousers, rubber gloves, protective goggles and a mask while mixing "
    "and spraying. Do not eat, drink or smoke. Wash exposed skin and clothes after use."
)
SAFETY_TEXT = (
    "Keep away from children, food and animal feed. Spray in the morning or evening, not "
    "against the wind. Do not enter the sprayed field for 24 hours. Dispose of the empty "
    "container by puncturing and burying; never reuse it."
)
NUTRIENT_SAFETY_TEXT = (
    "Apply to moist soil or as a foliar spray in the evening. Do not mix with alkaline "
    "solutions. Store dry, away from children."
)
HERBICIDE_SAFETY_TEXT = (
    "Use a flood-jet or flat-fan nozzle and a separate sprayer. Avoid drift to neighbouring "
    "crops. Do not spray on a windy day or before rain."
)


@dataclass(frozen=True)
class Pack:
    value: str  # Decimal literal
    unit: PackUnit
    mrp_paise: int


@dataclass(frozen=True)
class Claim:
    crop: str  # crop code
    problem: str  # pest_or_disease code
    dose_per_acre: str
    dose_value: str  # Decimal literal
    dose_unit: DoseUnit
    dose_per_tank_15l: str | None
    phi_days: int | None
    efficacy_tier: int


@dataclass(frozen=True)
class SeedProduct:
    key: str
    name: str
    brand: str
    category: ProductCategory
    hsn: str
    gst_rate_bp: int
    packs: tuple[Pack, ...]
    active_ingredient: str | None = None
    formulation: str | None = None
    names: Mapping[str, str] = field(default_factory=dict)
    description: str | None = None
    claims: tuple[Claim, ...] = ()

    @property
    def own_brand(self) -> bool:
        return OWN in self.brand


@dataclass(frozen=True)
class SeedProblem:
    code: str
    name: str
    type: ProblemType
    crop: str | None  # crop code; None = any crop
    scientific_name: str | None
    names: Mapping[str, str]
    symptoms: str


P, D, N, A = ProblemType.PEST, ProblemType.DISEASE, ProblemType.NUTRIENT, ProblemType.ABIOTIC

PROBLEMS: tuple[SeedProblem, ...] = (
    # paddy
    SeedProblem(
        "paddy_blast",
        "Rice blast",
        D,
        "paddy",
        "Magnaporthe oryzae",
        {"te": "అగ్గి తెగులు", "hi": "ब्लास्ट रोग"},
        "Spindle-shaped spots with grey centres on leaves; neck rot at panicle",
    ),
    SeedProblem(
        "paddy_sheath_blight",
        "Sheath blight",
        D,
        "paddy",
        "Rhizoctonia solani",
        {"te": "పొడ కుళ్ళు", "hi": "पर्णच्छद अंगमारी"},
        "Oval greenish-grey lesions on the leaf sheath near the water line",
    ),
    SeedProblem(
        "paddy_blb",
        "Bacterial leaf blight",
        D,
        "paddy",
        "Xanthomonas oryzae",
        {"te": "ఆకు ఎండు తెగులు", "hi": "जीवाणु पत्ती झुलसा"},
        "Yellow water-soaked streaks from the leaf tip and margins, wavy edges",
    ),
    SeedProblem(
        "paddy_bph",
        "Brown planthopper",
        P,
        "paddy",
        "Nilaparvata lugens",
        {"te": "సుడి దోమ", "hi": "भूरा फुदका"},
        "Hopper burn: circular patches of dried plants; insects at the stem base",
    ),
    SeedProblem(
        "paddy_stem_borer",
        "Yellow stem borer",
        P,
        "paddy",
        "Scirpophaga incertulas",
        {"te": "కాండం తొలుచు పురుగు", "hi": "तना छेदक"},
        "Dead hearts in the vegetative stage, white ears at heading",
    ),
    SeedProblem(
        "paddy_leaf_folder",
        "Leaf folder",
        P,
        "paddy",
        "Cnaphalocrocis medinalis",
        {"te": "ఆకు ముడత పురుగు", "hi": "पत्ती लपेटक"},
        "Longitudinally folded leaves with white scraped streaks",
    ),
    SeedProblem(
        "paddy_zinc_deficiency",
        "Zinc deficiency (khaira)",
        N,
        "paddy",
        None,
        {"te": "జింక్ లోపం", "hi": "खैरा रोग"},
        "Rusty brown spots on older leaves, stunted plants 2-4 weeks after transplanting",
    ),
    SeedProblem(
        "paddy_weeds",
        "Weeds in transplanted paddy",
        P,
        "paddy",
        None,
        {"te": "కలుపు", "hi": "खरपतवार"},
        "Grassy and broadleaf weeds emerging within 10 days of transplanting",
    ),
    # cotton
    SeedProblem(
        "cotton_pink_bollworm",
        "Pink bollworm",
        P,
        "cotton",
        "Pectinophora gossypiella",
        {"te": "గులాబీ రంగు కాయ తొలుచు పురుగు", "hi": "गुलाबी सुंडी"},
        "Rosetted flowers, bore holes on bolls, pink larvae inside locules",
    ),
    SeedProblem(
        "cotton_whitefly",
        "Whitefly",
        P,
        "cotton",
        "Bemisia tabaci",
        {"te": "తెల్ల దోమ", "hi": "सफेद मक्खी"},
        "Tiny white insects under leaves, sooty mould, leaf curl",
    ),
    SeedProblem(
        "cotton_jassids",
        "Jassids (leafhopper)",
        P,
        "cotton",
        "Amrasca biguttula",
        {"te": "పచ్చ దోమ", "hi": "हरा तेला"},
        "Leaf margins turn yellow then red and curl downward (hopper burn)",
    ),
    SeedProblem(
        "cotton_aphids",
        "Aphids",
        P,
        "cotton",
        "Aphis gossypii",
        {"te": "పేనుబంక", "hi": "माहू"},
        "Curled young leaves, honeydew and sooty mould, colonies on tender shoots",
    ),
    SeedProblem(
        "cotton_leaf_reddening",
        "Leaf reddening (magnesium)",
        N,
        "cotton",
        None,
        {"te": "ఆకు ఎర్రబారుట", "hi": "पत्ती लाल होना"},
        "Older leaves turn red between veins at boll development, shed early",
    ),
    SeedProblem(
        "cotton_bacterial_blight",
        "Bacterial blight",
        D,
        "cotton",
        "Xanthomonas citri pv. malvacearum",
        {"te": "బాక్టీరియా ఆకు మచ్చ", "hi": "जीवाणु झुलसा"},
        "Angular water-soaked spots on leaves, black arm on stems, boll rot",
    ),
    SeedProblem(
        "cotton_weeds",
        "Weeds in cotton",
        P,
        "cotton",
        None,
        {"te": "కలుపు", "hi": "खरपतवार"},
        "Grassy and broadleaf weeds in the first 45 days",
    ),
    # chilli
    SeedProblem(
        "chilli_thrips",
        "Thrips",
        P,
        "chilli",
        "Scirtothrips dorsalis",
        {"te": "తామర పురుగు", "hi": "थ्रिप्स"},
        "Upward curling of leaves, silvery streaks, stunted growth",
    ),
    SeedProblem(
        "chilli_mites",
        "Yellow mite",
        P,
        "chilli",
        "Polyphagotarsonemus latus",
        {"te": "నల్లి", "hi": "पीला माइट"},
        "Downward curling of leaves, elongated petioles, bronzing",
    ),
    SeedProblem(
        "chilli_leaf_curl",
        "Leaf curl virus",
        D,
        "chilli",
        "Chilli leaf curl virus",
        {"te": "ఆకు ముడత వైరస్", "hi": "पत्ती मरोड़ विषाणु"},
        "Puckered, curled leaves, shortened internodes, no fruit set",
    ),
    SeedProblem(
        "chilli_anthracnose",
        "Anthracnose / fruit rot",
        D,
        "chilli",
        "Colletotrichum capsici",
        {"te": "కాయ కుళ్ళు", "hi": "फल सड़न"},
        "Sunken circular spots with black dots on ripening fruit, die-back of twigs",
    ),
    SeedProblem(
        "chilli_powdery_mildew",
        "Powdery mildew",
        D,
        "chilli",
        "Leveillula taurica",
        {"te": "బూడిద తెగులు", "hi": "चूर्णिल आसिता"},
        "White powdery growth on the lower leaf surface, yellowing, leaf drop",
    ),
    SeedProblem(
        "chilli_damping_off",
        "Damping off (nursery)",
        D,
        "chilli",
        "Pythium spp.",
        {"te": "నారు కుళ్ళు", "hi": "आर्द्रगलन"},
        "Seedlings topple at the collar in patches of the nursery",
    ),
    # maize
    SeedProblem(
        "maize_fall_armyworm",
        "Fall armyworm",
        P,
        "maize",
        "Spodoptera frugiperda",
        {"te": "కత్తెర పురుగు", "hi": "फॉल आर्मीवर्म"},
        "Ragged holes and sawdust-like frass in the whorl, larva with inverted Y on head",
    ),
    SeedProblem(
        "maize_stem_borer",
        "Maize stem borer",
        P,
        "maize",
        "Chilo partellus",
        {"te": "కాండం తొలుచు పురుగు", "hi": "तना छेदक"},
        "Pin holes on leaves, dead hearts, tunnelled stems",
    ),
    SeedProblem(
        "maize_turcicum_blight",
        "Turcicum leaf blight",
        D,
        "maize",
        "Exserohilum turcicum",
        {"te": "ఆకు ఎండు తెగులు", "hi": "टर्सिकम झुलसा"},
        "Long elliptical greyish lesions starting on the lower leaves",
    ),
    SeedProblem(
        "maize_zinc_deficiency",
        "Zinc deficiency",
        N,
        "maize",
        None,
        {"te": "జింక్ లోపం", "hi": "जिंक की कमी"},
        "Broad white or yellow bands either side of the midrib on young leaves",
    ),
    SeedProblem(
        "maize_weeds",
        "Weeds in maize",
        P,
        "maize",
        None,
        {"te": "కలుపు", "hi": "खरपतवार"},
        "Grassy and broadleaf weeds in the first 30 days",
    ),
    # tomato
    SeedProblem(
        "tomato_early_blight",
        "Early blight",
        D,
        "tomato",
        "Alternaria solani",
        {"te": "ఆకు మచ్చ తెగులు", "hi": "अगेती झुलसा"},
        "Brown spots with concentric rings on older leaves, yellow halo",
    ),
    SeedProblem(
        "tomato_late_blight",
        "Late blight",
        D,
        "tomato",
        "Phytophthora infestans",
        {"te": "ఆలస్య ఎండు తెగులు", "hi": "पछेती झुलसा"},
        "Water-soaked patches turning brown, white growth under leaves in humid weather",
    ),
    SeedProblem(
        "tomato_fruit_borer",
        "Fruit borer",
        P,
        "tomato",
        "Helicoverpa armigera",
        {"te": "కాయ తొలుచు పురుగు", "hi": "फल छेदक"},
        "Circular holes in fruit, larva feeding with head inside the fruit",
    ),
    SeedProblem(
        "tomato_leaf_curl",
        "Leaf curl virus",
        D,
        "tomato",
        "Tomato leaf curl virus",
        {"te": "ఆకు ముడత వైరస్", "hi": "पत्ती मरोड़"},
        "Upward curling, yellowing and thickening of leaves, stunted bushy plants",
    ),
    SeedProblem(
        "tomato_bacterial_wilt",
        "Bacterial wilt",
        D,
        "tomato",
        "Ralstonia solanacearum",
        {"te": "బాక్టీరియా వడలు తెగులు", "hi": "जीवाणु म्लानि"},
        "Sudden wilting of green plants; milky ooze from a cut stem in water",
    ),
    SeedProblem(
        "tomato_whitefly",
        "Whitefly",
        P,
        "tomato",
        "Bemisia tabaci",
        {"te": "తెల్ల దోమ", "hi": "सफेद मक्खी"},
        "White insects under leaves; spreads leaf curl virus",
    ),
    # groundnut
    SeedProblem(
        "groundnut_tikka",
        "Tikka leaf spot",
        D,
        "groundnut",
        "Cercospora arachidicola",
        {"te": "టిక్కా ఆకు మచ్చ", "hi": "टिक्का रोग"},
        "Dark brown circular spots with yellow halo on leaves, defoliation",
    ),
    SeedProblem(
        "groundnut_rust",
        "Rust",
        D,
        "groundnut",
        "Puccinia arachidis",
        {"te": "కుంకుమ తెగులు", "hi": "रतुआ"},
        "Orange pustules on the lower leaf surface, leaves dry but stay attached",
    ),
    SeedProblem(
        "groundnut_leaf_miner",
        "Leaf miner",
        P,
        "groundnut",
        "Aproaerema modicella",
        {"te": "ఆకు తొలుచు పురుగు", "hi": "पत्ती सुरंगक"},
        "Blister-like mines on leaflets, webbed and folded leaves",
    ),
    SeedProblem(
        "groundnut_white_grub",
        "White grub",
        P,
        "groundnut",
        "Holotrichia consanguinea",
        {"te": "తెల్ల పురుగు", "hi": "सफेद गिडार"},
        "Plants wilt and die in patches; C-shaped grubs at the roots",
    ),
    SeedProblem(
        "groundnut_stem_rot",
        "Stem rot",
        D,
        "groundnut",
        "Sclerotium rolfsii",
        {"te": "కాండం కుళ్ళు", "hi": "तना सड़न"},
        "Yellowing and wilting; white fungal threads and mustard-like sclerotia at the base",
    ),
    # M6 corpus seed additions (10 problems per pilot crop)
    SeedProblem(
        "maize_rust",
        "Common rust",
        D,
        "maize",
        "Puccinia sorghi",
        {"te": "తుప్పు తెగులు", "hi": "गेरुई रोग"},
        "Small cinnamon-brown powdery pustules on both leaf surfaces; leaves dry early",
    ),
    SeedProblem(
        "groundnut_bud_necrosis",
        "Peanut bud necrosis",
        D,
        "groundnut",
        "Groundnut bud necrosis virus (thrips-borne)",
        {"te": "మొవ్వు కుళ్ళు", "hi": "कली परिगलन"},
        "Chlorotic ring spots on young leaves; terminal bud dies; plants stunted and bushy",
    ),
    # any crop
    SeedProblem(
        "aphids",
        "Aphids",
        P,
        None,
        "Aphididae",
        {"te": "పేనుబంక", "hi": "माहू"},
        "Soft-bodied insects on tender shoots, honeydew, curled leaves",
    ),
    SeedProblem(
        "nitrogen_deficiency",
        "Nitrogen deficiency",
        N,
        None,
        None,
        {"te": "నత్రజని లోపం", "hi": "नाइट्रोजन की कमी"},
        "Uniform pale yellowing starting on older leaves, thin stems",
    ),
    SeedProblem(
        "waterlogging",
        "Waterlogging",
        A,
        None,
        None,
        {"te": "నీరు నిలువ", "hi": "जलभराव"},
        "Wilting despite wet soil, yellowing from the lower leaves after heavy rain",
    ),
    SeedProblem(
        "drought_stress",
        "Drought stress",
        A,
        None,
        None,
        {"te": "కరువు ఒత్తిడి", "hi": "सूखे का तनाव"},
        "Leaf rolling in the afternoon, scorching of margins, flower drop",
    ),
)

ML, G, L, KG = DoseUnit.ML, DoseUnit.G, DoseUnit.L, DoseUnit.KG
ml, g, kg, pcs = PackUnit.ML, PackUnit.G, PackUnit.KG, PackUnit.PCS


def _seed(
    key: str,
    name: str,
    brand: str,
    crop: str,
    hsn: str,
    packs: tuple[Pack, ...],
    te: str,
    description: str,
) -> SeedProduct:
    return SeedProduct(
        key,
        name,
        brand,
        ProductCategory.SEED,
        hsn,
        0,
        packs,
        names={"te": te},
        description=description,
    )


PRODUCTS: tuple[SeedProduct, ...] = (
    # ------------------------------------------------------------------ seeds (nil-rated)
    _seed(
        "seed_paddy_bpt",
        f"{OWN} Samba Mahsuri BPT-5204 paddy seed",
        OWN,
        "paddy",
        "1006",
        (Pack("25", kg, 145000), Pack("10", kg, 62000)),
        "వరి విత్తనం BPT-5204",
        "Certified fine-grain paddy seed, 145 days",
    ),
    _seed(
        "seed_paddy_mtu",
        "MTU-1010 paddy seed",
        "Nuziveedu",
        "paddy",
        "1006",
        (Pack("25", kg, 135000), Pack("10", kg, 58000)),
        "వరి విత్తనం MTU-1010",
        "Short-duration paddy, 120 days",
    ),
    _seed(
        "seed_cotton_own",
        f"{OWN} Bhoomi BG-II cotton seed",
        OWN,
        "cotton",
        "1207",
        (Pack("475", g, 86400),),
        "పత్తి విత్తనం",
        "Bt cotton hybrid, 475 g packet",
    ),
    _seed(
        "seed_cotton_rch",
        "RCH-659 BG-II cotton seed",
        "Rasi",
        "cotton",
        "1207",
        (Pack("475", g, 86400), Pack("950", g, 172800)),
        "పత్తి విత్తనం RCH-659",
        "Bt cotton hybrid",
    ),
    _seed(
        "seed_chilli_own",
        f"{OWN} Teja chilli seed",
        OWN,
        "chilli",
        "1209",
        (Pack("10", g, 45000), Pack("50", g, 210000)),
        "మిరప విత్తనం తేజ",
        "Hot chilli hybrid",
    ),
    _seed(
        "seed_chilli_us",
        "US-341 chilli seed",
        "Nunhems",
        "chilli",
        "1209",
        (Pack("10", g, 62000), Pack("50", g, 290000)),
        "మిరప విత్తనం US-341",
        "Chilli hybrid for the plains",
    ),
    _seed(
        "seed_maize_own",
        f"{OWN} DHM-117 maize seed",
        OWN,
        "maize",
        "1005",
        (Pack("4", kg, 120000),),
        "మొక్కజొన్న విత్తనం",
        "Single-cross maize hybrid",
    ),
    _seed(
        "seed_maize_nk",
        "NK-6240 maize seed",
        "Syngenta",
        "maize",
        "1005",
        (Pack("4", kg, 165000), Pack("8", kg, 320000)),
        "మొక్కజొన్న విత్తనం NK-6240",
        "High-yielding maize hybrid",
    ),
    _seed(
        "seed_tomato_own",
        f"{OWN} Arka Rakshak tomato seed",
        OWN,
        "tomato",
        "1209",
        (Pack("10", g, 38000),),
        "టమాటా విత్తనం",
        "Triple-disease-resistant tomato hybrid",
    ),
    _seed(
        "seed_tomato_saaho",
        "Saaho tomato seed",
        "Syngenta",
        "tomato",
        "1209",
        (Pack("10", g, 95000), Pack("50", g, 450000)),
        "టమాటా విత్తనం సాహో",
        "Firm, long-shelf-life tomato",
    ),
    _seed(
        "seed_groundnut_own",
        f"{OWN} K-6 groundnut seed",
        OWN,
        "groundnut",
        "1202",
        (Pack("30", kg, 420000), Pack("15", kg, 215000)),
        "వేరుశనగ విత్తనం K-6",
        "Spanish bunch groundnut, 110 days",
    ),
    _seed(
        "seed_groundnut_lepakshi",
        "Kadiri Lepakshi groundnut seed",
        "APSSDC",
        "groundnut",
        "1202",
        (Pack("30", kg, 390000),),
        "వేరుశనగ విత్తనం లేపాక్షి",
        "Drought-tolerant",
    ),
    # ------------------------------------------------------------------ fertilisers (5 %)
    SeedProduct(
        "fert_urea",
        "Urea 46% N",
        "IFFCO",
        ProductCategory.FERTILISER,
        "3102",
        500,
        (Pack("45", kg, 26650),),
        names={"te": "యూరియా"},
        description="Neem-coated urea, 45 kg bag",
        claims=(
            Claim(
                "paddy", "nitrogen_deficiency", "25 kg/acre top dressing", "25", KG, None, None, 1
            ),
            Claim(
                "maize", "nitrogen_deficiency", "30 kg/acre at knee height", "30", KG, None, None, 1
            ),
        ),
    ),
    SeedProduct(
        "fert_dap",
        "DAP 18-46-0",
        "IFFCO",
        ProductCategory.FERTILISER,
        "3105",
        500,
        (Pack("50", kg, 135000),),
        names={"te": "డిఏపి"},
        description="Basal phosphate",
    ),
    SeedProduct(
        "fert_mop",
        "Muriate of potash 60% K2O",
        "IPL",
        ProductCategory.FERTILISER,
        "3104",
        500,
        (Pack("50", kg, 170000), Pack("25", kg, 88000)),
        names={"te": "పొటాష్"},
    ),
    SeedProduct(
        "fert_ssp",
        "Single super phosphate 16%",
        "Coromandel",
        ProductCategory.FERTILISER,
        "3103",
        500,
        (Pack("50", kg, 58000), Pack("25", kg, 30000)),
        names={"te": "సూపర్ ఫాస్ఫేట్"},
    ),
    SeedProduct(
        "fert_npk",
        "Gromor 20-20-0-13",
        "Coromandel",
        ProductCategory.FERTILISER,
        "3105",
        500,
        (Pack("50", kg, 142500),),
        names={"te": "20-20-0-13"},
    ),
    SeedProduct(
        "fert_zinc",
        f"{OWN} Zinc sulphate 21%",
        OWN,
        ProductCategory.FERTILISER,
        "2833",
        500,
        (Pack("1", kg, 9500), Pack("5", kg, 43000)),
        names={"te": "జింక్ సల్ఫేట్"},
        description="Heptahydrate, soil or foliar",
        claims=(
            Claim(
                "paddy",
                "paddy_zinc_deficiency",
                "10 kg/acre soil application",
                "10",
                KG,
                "75 g (foliar 0.5 %)",
                None,
                1,
            ),
            Claim(
                "maize",
                "maize_zinc_deficiency",
                "10 kg/acre soil application",
                "10",
                KG,
                "75 g (foliar 0.5 %)",
                None,
                1,
            ),
        ),
    ),
    SeedProduct(
        "fert_micro",
        f"{OWN} Micro-Plus foliar micronutrient mix",
        OWN,
        ProductCategory.FERTILISER,
        "3105",
        500,
        (Pack("500", g, 32000), Pack("1", kg, 58000)),
        names={"te": "మైక్రో ప్లస్"},
        description="Mg, Zn, Fe, Mn, B, Cu chelated mix for foliar spray",
        claims=(
            Claim(
                "cotton",
                "cotton_leaf_reddening",
                "1 kg/acre foliar in 2 sprays",
                "1",
                KG,
                "50 g",
                None,
                1,
            ),
        ),
    ),
    SeedProduct(
        "fert_wsf",
        f"{OWN} 19-19-19 water soluble",
        OWN,
        ProductCategory.FERTILISER,
        "3105",
        500,
        (Pack("1", kg, 16500), Pack("500", g, 9000)),
        names={"te": "19-19-19"},
    ),
    # ------------------------------------------------------------------ insecticides (18 %)
    SeedProduct(
        "ins_imida_own",
        f"{OWN} Imida 17.8 SL",
        OWN,
        ProductCategory.PESTICIDE,
        "3808",
        1800,
        (Pack("50", ml, 15000), Pack("100", ml, 28000), Pack("250", ml, 62000)),
        active_ingredient="Imidacloprid 17.8% SL",
        formulation="SL",
        names={"te": "ఇమిడా"},
        description="Systemic insecticide for sucking pests",
        claims=(
            Claim("cotton", "cotton_aphids", "50 ml/acre", "50", ML, "5 ml", 40, 1),
            Claim("cotton", "cotton_jassids", "50 ml/acre", "50", ML, "5 ml", 40, 1),
            Claim("cotton", "cotton_whitefly", "50 ml/acre", "50", ML, "5 ml", 40, 2),
            Claim("paddy", "paddy_bph", "50 ml/acre", "50", ML, "5 ml", 30, 2),
            Claim("chilli", "chilli_thrips", "60 ml/acre", "60", ML, "6 ml", 40, 2),
        ),
    ),
    SeedProduct(
        "ins_imida_bayer",
        "Confidor 17.8 SL",
        "Bayer",
        ProductCategory.PESTICIDE,
        "3808",
        1800,
        (Pack("100", ml, 39500),),
        active_ingredient="Imidacloprid 17.8% SL",
        formulation="SL",
        names={"te": "కాన్ఫిడార్"},
        claims=(
            Claim("cotton", "cotton_aphids", "50 ml/acre", "50", ML, "5 ml", 40, 1),
            Claim("cotton", "cotton_jassids", "50 ml/acre", "50", ML, "5 ml", 40, 1),
            Claim("paddy", "paddy_bph", "50 ml/acre", "50", ML, "5 ml", 30, 2),
        ),
    ),
    SeedProduct(
        "ins_chlorpyrifos",
        f"{OWN} Chloro 20 EC",
        OWN,
        ProductCategory.PESTICIDE,
        "3808",
        1800,
        (Pack("500", ml, 34000), Pack("1", PackUnit.L, 62000)),
        active_ingredient="Chlorpyrifos 20% EC",
        formulation="EC",
        names={"te": "క్లోరో"},
        claims=(
            Claim("paddy", "paddy_stem_borer", "500 ml/acre", "500", ML, "50 ml", 15, 2),
            Claim("cotton", "cotton_aphids", "400 ml/acre", "400", ML, "40 ml", 15, 3),
            Claim(
                "groundnut",
                "groundnut_white_grub",
                "1 l/acre with irrigation",
                "1000",
                ML,
                None,
                20,
                1,
            ),
        ),
    ),
    SeedProduct(
        "ins_lambda",
        f"{OWN} Lambda 5 EC",
        OWN,
        ProductCategory.PESTICIDE,
        "3808",
        1800,
        (Pack("250", ml, 42000), Pack("500", ml, 78000)),
        active_ingredient="Lambda-cyhalothrin 5% EC",
        formulation="EC",
        names={"te": "లాంబ్డా"},
        claims=(
            Claim("cotton", "cotton_pink_bollworm", "200 ml/acre", "200", ML, "20 ml", 7, 2),
            Claim("tomato", "tomato_fruit_borer", "150 ml/acre", "150", ML, "15 ml", 5, 2),
            Claim("chilli", "chilli_thrips", "150 ml/acre", "150", ML, "15 ml", 5, 3),
            Claim("paddy", "paddy_leaf_folder", "100 ml/acre", "100", ML, "10 ml", 15, 2),
        ),
    ),
    SeedProduct(
        "ins_emamectin",
        "Proclaim 5 SG",
        "Syngenta",
        ProductCategory.PESTICIDE,
        "3808",
        1800,
        (Pack("100", g, 78000), Pack("250", g, 178000)),
        active_ingredient="Emamectin benzoate 5% SG",
        formulation="SG",
        names={"te": "ప్రోక్లెయిమ్"},
        claims=(
            Claim("cotton", "cotton_pink_bollworm", "80 g/acre", "80", G, "8 g", 10, 1),
            Claim("tomato", "tomato_fruit_borer", "80 g/acre", "80", G, "8 g", 5, 1),
            Claim("maize", "maize_fall_armyworm", "80 g/acre", "80", G, "8 g", 7, 1),
            Claim("chilli", "chilli_mites", "80 g/acre", "80", G, "8 g", 5, 2),
        ),
    ),
    SeedProduct(
        "ins_spinosad",
        "Tracer 45 SC",
        "Corteva",
        ProductCategory.PESTICIDE,
        "3808",
        1800,
        (Pack("75", ml, 145000),),
        active_ingredient="Spinosad 45% SC",
        formulation="SC",
        names={"te": "ట్రేసర్"},
        claims=(
            Claim("cotton", "cotton_pink_bollworm", "60 ml/acre", "60", ML, "6 ml", 7, 1),
            Claim("chilli", "chilli_thrips", "64 ml/acre", "64", ML, "6 ml", 3, 1),
            Claim("tomato", "tomato_fruit_borer", "64 ml/acre", "64", ML, "6 ml", 3, 1),
            Claim("maize", "maize_fall_armyworm", "60 ml/acre", "60", ML, "6 ml", 7, 2),
        ),
    ),
    SeedProduct(
        "ins_thiamethoxam",
        "Actara 25 WG",
        "Syngenta",
        ProductCategory.PESTICIDE,
        "3808",
        1800,
        (Pack("100", g, 62000), Pack("250", g, 145000)),
        active_ingredient="Thiamethoxam 25% WG",
        formulation="WG",
        names={"te": "ఆక్టారా"},
        claims=(
            Claim("cotton", "cotton_jassids", "40 g/acre", "40", G, "4 g", 21, 1),
            Claim("cotton", "cotton_whitefly", "40 g/acre", "40", G, "4 g", 21, 2),
            Claim("paddy", "paddy_bph", "40 g/acre", "40", G, "4 g", 21, 1),
            Claim("tomato", "tomato_whitefly", "80 g/acre", "80", G, "8 g", 5, 2),
        ),
    ),
    SeedProduct(
        "ins_acephate",
        f"{OWN} Acephate 75 SP",
        OWN,
        ProductCategory.PESTICIDE,
        "3808",
        1800,
        (Pack("250", g, 28000), Pack("500", g, 52000)),
        active_ingredient="Acephate 75% SP",
        formulation="SP",
        names={"te": "ఎసిఫేట్"},
        claims=(
            Claim("cotton", "cotton_jassids", "300 g/acre", "300", G, "20 g", 21, 3),
            Claim("chilli", "chilli_thrips", "300 g/acre", "300", G, "20 g", 15, 3),
            Claim("paddy", "paddy_stem_borer", "300 g/acre", "300", G, "20 g", 15, 3),
        ),
    ),
    SeedProduct(
        "ins_neem",
        f"{OWN} Neem oil 1500 ppm",
        OWN,
        ProductCategory.PESTICIDE,
        "3808",
        1200,
        (Pack("250", ml, 17500), Pack("500", ml, 32000), Pack("1", PackUnit.L, 58000)),
        active_ingredient="Azadirachtin 0.15% EC (neem oil 1500 ppm)",
        formulation="EC",
        names={"te": "వేప నూనె"},
        description="Bio-pesticide; safe near harvest",
        claims=(
            Claim("chilli", "chilli_thrips", "1 l/acre", "1000", ML, "75 ml", 3, 3),
            Claim("cotton", "cotton_whitefly", "1 l/acre", "1000", ML, "75 ml", 3, 3),
            Claim("cotton", "cotton_aphids", "1 l/acre", "1000", ML, "75 ml", 3, 3),
            Claim("tomato", "tomato_whitefly", "1 l/acre", "1000", ML, "75 ml", 3, 3),
            Claim("paddy", "paddy_leaf_folder", "1 l/acre", "1000", ML, "75 ml", 3, 3),
        ),
    ),
    # ------------------------------------------------------------------ fungicides (18 %)
    SeedProduct(
        "fun_mancozeb",
        f"{OWN} Manco 75 WP",
        OWN,
        ProductCategory.FUNGICIDE,
        "3808",
        1800,
        (Pack("500", g, 38000), Pack("1", kg, 72000)),
        active_ingredient="Mancozeb 75% WP",
        formulation="WP",
        names={"te": "మాంకో"},
        claims=(
            Claim("tomato", "tomato_early_blight", "600 g/acre", "600", G, "30 g", 5, 2),
            Claim("tomato", "tomato_late_blight", "600 g/acre", "600", G, "30 g", 5, 2),
            Claim("groundnut", "groundnut_tikka", "800 g/acre", "800", G, "40 g", 7, 2),
            Claim("chilli", "chilli_anthracnose", "600 g/acre", "600", G, "30 g", 5, 3),
            Claim("maize", "maize_turcicum_blight", "600 g/acre", "600", G, "30 g", 10, 2),
        ),
    ),
    SeedProduct(
        "fun_carbendazim",
        "Bavistin 50 WP",
        "Crystal",
        ProductCategory.FUNGICIDE,
        "3808",
        1800,
        (Pack("100", g, 12500), Pack("500", g, 52000)),
        active_ingredient="Carbendazim 50% WP",
        formulation="WP",
        names={"te": "బావిస్టిన్"},
        claims=(
            Claim("paddy", "paddy_sheath_blight", "200 g/acre", "200", G, "15 g", 15, 3),
            Claim("chilli", "chilli_powdery_mildew", "200 g/acre", "200", G, "15 g", 7, 3),
            Claim("groundnut", "groundnut_stem_rot", "250 g/acre drench", "250", G, "15 g", 20, 2),
            Claim(
                "chilli",
                "chilli_damping_off",
                "200 g/acre nursery drench",
                "200",
                G,
                "15 g",
                None,
                2,
            ),
        ),
    ),
    SeedProduct(
        "fun_azoxystrobin",
        "Amistar 23 SC",
        "Syngenta",
        ProductCategory.FUNGICIDE,
        "3808",
        1800,
        (Pack("100", ml, 68000), Pack("250", ml, 155000)),
        active_ingredient="Azoxystrobin 23% SC",
        formulation="SC",
        names={"te": "అమిస్టార్"},
        claims=(
            Claim("paddy", "paddy_blast", "200 ml/acre", "200", ML, "20 ml", 21, 1),
            Claim("paddy", "paddy_sheath_blight", "200 ml/acre", "200", ML, "20 ml", 21, 1),
            Claim("tomato", "tomato_early_blight", "200 ml/acre", "200", ML, "20 ml", 3, 1),
            Claim("chilli", "chilli_anthracnose", "200 ml/acre", "200", ML, "20 ml", 3, 1),
            Claim("groundnut", "groundnut_rust", "200 ml/acre", "200", ML, "20 ml", 14, 2),
        ),
    ),
    SeedProduct(
        "fun_copper",
        f"{OWN} Copper 50 WP",
        OWN,
        ProductCategory.FUNGICIDE,
        "3808",
        1800,
        (Pack("250", g, 19500), Pack("500", g, 36000), Pack("1", kg, 68000)),
        active_ingredient="Copper oxychloride 50% WP",
        formulation="WP",
        names={"te": "కాపర్"},
        claims=(
            Claim("tomato", "tomato_bacterial_wilt", "1 kg/acre drench", "1000", G, "50 g", 7, 2),
            Claim("paddy", "paddy_blb", "1 kg/acre", "1000", G, "50 g", 15, 2),
            Claim("cotton", "cotton_bacterial_blight", "1 kg/acre", "1000", G, "50 g", 10, 2),
            Claim("chilli", "chilli_anthracnose", "1 kg/acre", "1000", G, "50 g", 7, 2),
        ),
    ),
    SeedProduct(
        "fun_propiconazole",
        "Tilt 25 EC",
        "Syngenta",
        ProductCategory.FUNGICIDE,
        "3808",
        1800,
        (Pack("100", ml, 42000), Pack("500", ml, 185000)),
        active_ingredient="Propiconazole 25% EC",
        formulation="EC",
        names={"te": "టిల్ట్"},
        claims=(
            Claim("groundnut", "groundnut_rust", "200 ml/acre", "200", ML, "20 ml", 21, 1),
            Claim("groundnut", "groundnut_tikka", "200 ml/acre", "200", ML, "20 ml", 21, 1),
            Claim("paddy", "paddy_sheath_blight", "200 ml/acre", "200", ML, "20 ml", 30, 2),
        ),
    ),
    SeedProduct(
        "fun_hexaconazole",
        f"{OWN} Hexa 5 SC",
        OWN,
        ProductCategory.FUNGICIDE,
        "3808",
        1800,
        (Pack("250", ml, 24000), Pack("1", PackUnit.L, 82000)),
        active_ingredient="Hexaconazole 5% SC",
        formulation="SC",
        names={"te": "హెక్సా"},
        claims=(
            Claim("paddy", "paddy_sheath_blight", "400 ml/acre", "400", ML, "30 ml", 30, 2),
            Claim("chilli", "chilli_powdery_mildew", "400 ml/acre", "400", ML, "30 ml", 7, 2),
            Claim("groundnut", "groundnut_tikka", "400 ml/acre", "400", ML, "30 ml", 21, 3),
        ),
    ),
    SeedProduct(
        "fun_tricyclazole",
        "Beam 75 WP",
        "Dow",
        ProductCategory.FUNGICIDE,
        "3808",
        1800,
        (Pack("120", g, 52000),),
        active_ingredient="Tricyclazole 75% WP",
        formulation="WP",
        names={"te": "బీమ్"},
        claims=(Claim("paddy", "paddy_blast", "120 g/acre", "120", G, "9 g", 30, 1),),
    ),
    # ------------------------------------------------------------------ herbicides (18 %)
    SeedProduct(
        "her_pretilachlor",
        f"{OWN} Preti 50 EC",
        OWN,
        ProductCategory.HERBICIDE,
        "3808",
        1800,
        (Pack("500", ml, 36000), Pack("1", PackUnit.L, 66000)),
        active_ingredient="Pretilachlor 50% EC",
        formulation="EC",
        names={"te": "ప్రెటి"},
        claims=(
            Claim(
                "paddy",
                "paddy_weeds",
                "500 ml/acre within 3 days of transplanting",
                "500",
                ML,
                "40 ml",
                None,
                1,
            ),
        ),
    ),
    SeedProduct(
        "her_glyphosate",
        "Roundup 41 SL",
        "Bayer",
        ProductCategory.HERBICIDE,
        "3808",
        1800,
        (Pack("1", PackUnit.L, 48000),),
        active_ingredient="Glyphosate 41% SL",
        formulation="SL",
        names={"te": "రౌండప్"},
        description="Non-selective; directed spray only",
        claims=(
            Claim(
                "cotton",
                "cotton_weeds",
                "1 l/acre directed inter-row",
                "1000",
                ML,
                "75 ml",
                None,
                2,
            ),
        ),
    ),
    SeedProduct(
        "her_pendimethalin",
        "Stomp 30 EC",
        "BASF",
        ProductCategory.HERBICIDE,
        "3808",
        1800,
        (Pack("1", PackUnit.L, 58000),),
        active_ingredient="Pendimethalin 30% EC",
        formulation="EC",
        names={"te": "స్టాంప్"},
        claims=(
            Claim("cotton", "cotton_weeds", "1 l/acre pre-emergence", "1000", ML, "75 ml", None, 1),
            Claim("maize", "maize_weeds", "1 l/acre pre-emergence", "1000", ML, "75 ml", None, 1),
        ),
    ),
    SeedProduct(
        "her_atrazine",
        f"{OWN} Atra 50 WP",
        OWN,
        ProductCategory.HERBICIDE,
        "3808",
        1800,
        (Pack("500", g, 22000),),
        active_ingredient="Atrazine 50% WP",
        formulation="WP",
        names={"te": "ఆట్రా"},
        claims=(
            Claim("maize", "maize_weeds", "500 g/acre pre-emergence", "500", G, "40 g", None, 1),
        ),
    ),
    # ------------------------------------------------------------------ growth (18 %)
    SeedProduct(
        "gro_humic",
        f"{OWN} Humi-Gold humic acid 12%",
        OWN,
        ProductCategory.GROWTH,
        "3824",
        1800,
        (Pack("250", ml, 15500), Pack("500", ml, 28000), Pack("1", PackUnit.L, 48000)),
        names={"te": "హ్యూమి గోల్డ్"},
        description="Root growth promoter",
    ),
    SeedProduct(
        "gro_seaweed",
        "Biozyme seaweed extract",
        "Biostadt",
        ProductCategory.GROWTH,
        "3101",
        1800,
        (Pack("500", ml, 42000), Pack("1", PackUnit.L, 78000)),
        names={"te": "బయోజైమ్"},
    ),
    # ------------------------------------------------------------------ tools
    SeedProduct(
        "tool_knapsack",
        "Knapsack sprayer 16 L",
        "Aspee",
        ProductCategory.TOOL,
        "8424",
        1200,
        (Pack("1", pcs, 245000),),
        names={"te": "స్ప్రేయర్"},
    ),
    SeedProduct(
        "tool_battery_sprayer",
        f"{OWN} Battery sprayer 16 L",
        OWN,
        ProductCategory.TOOL,
        "8424",
        1200,
        (Pack("1", pcs, 385000),),
        names={"te": "బ్యాటరీ స్ప్రేయర్"},
    ),
    SeedProduct(
        "tool_tarpaulin",
        "Tarpaulin 24x18 ft",
        "Silpaulin",
        ProductCategory.TOOL,
        "3926",
        1800,
        (Pack("1", pcs, 165000),),
        names={"te": "టార్పాలిన్"},
    ),
)

#: The five products of the SMALL profile (10 SKUs, 5 claims once capped).
SMALL_PRODUCT_KEYS: tuple[str, ...] = (
    "seed_paddy_bpt",  # 2 packs
    "fert_zinc",  # 2 packs, 2 claims x 2 packs
    "ins_imida_own",  # 2 packs, 5 claims x 2 packs
    "fun_mancozeb",  # 2 packs
    "ins_chlorpyrifos",  # 2 packs
)


def own_brand_label(slug: str) -> str:
    return OWN_BRAND_LABEL.get(slug, slug.upper())


__all__ = [
    "HERBICIDE_SAFETY_TEXT",
    "NUTRIENT_SAFETY_TEXT",
    "OWN",
    "OWN_BRAND_LABEL",
    "PPE_TEXT",
    "PROBLEMS",
    "PRODUCTS",
    "SAFETY_TEXT",
    "SMALL_PRODUCT_KEYS",
    "Claim",
    "Pack",
    "SeedProblem",
    "SeedProduct",
    "own_brand_label",
]
