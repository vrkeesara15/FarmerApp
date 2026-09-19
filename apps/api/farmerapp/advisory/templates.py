"""FM-007 pilot crop calendars: the seed templates of the six pilot crops (SPEC 0.3).

Day offsets count from ``crop_plot.sowing_date`` (transplanting for paddy and chilli, as in
the VA-F05 calendar), durations are the window the task can be done in. Timings follow the
generally published PJTSAU / ICAR crop production guides for Telangana; titles and short
instructions exist in the five launch languages (NF-008) and deliberately carry no product,
dose or SKU (DX-007: product advice comes from label claims, never from the calendar).

TODO-HUMAN: the tenant agronomist reviews offsets and wording (and a translator the
non-English texts) through ``/v1/calendar/templates``; the seed never overwrites an edited
template (it only adds missing keys).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.advisory.models import CropTaskTemplate, TaskType
from farmerapp.catalog.crops import Crop

SOURCE = "PJTSAU / ICAR crop production guides (assumption, M7; agronomist review pending)"

#: Short titles per launch language.
TITLES: dict[str, dict[str, str]] = {
    "transplant": {
        "en": "Transplant seedlings",
        "te": "నాట్లు వేయండి",
        "hi": "पौध की रोपाई करें",
        "kn": "ಸಸಿಗಳನ್ನು ನಾಟಿ ಮಾಡಿ",
        "mr": "रोपांची लागवड करा",
    },
    "sow": {
        "en": "Sow the seed",
        "te": "విత్తనం విత్తండి",
        "hi": "बुवाई करें",
        "kn": "ಬೀಜ ಬಿತ್ತನೆ ಮಾಡಿ",
        "mr": "पेरणी करा",
    },
    "basal": {
        "en": "Apply basal fertiliser",
        "te": "దుక్కి ఎరువు వేయండి",
        "hi": "बेसल खाद डालें",
        "kn": "ಮೂಲ ಗೊಬ್ಬರ ಹಾಕಿ",
        "mr": "पायाभूत खत द्या",
    },
    "top_dress_1": {
        "en": "First top dressing",
        "te": "మొదటి పై ఎరువు",
        "hi": "पहली ऊपरी खाद",
        "kn": "ಮೊದಲ ಮೇಲುಗೊಬ್ಬರ",
        "mr": "पहिला वरखत",
    },
    "top_dress_2": {
        "en": "Second top dressing",
        "te": "రెండవ పై ఎరువు",
        "hi": "दूसरी ऊपरी खाद",
        "kn": "ಎರಡನೇ ಮೇಲುಗೊಬ್ಬರ",
        "mr": "दुसरा वरखत",
    },
    "irrigate": {
        "en": "Irrigate",
        "te": "నీరు పెట్టండి",
        "hi": "सिंचाई करें",
        "kn": "ನೀರು ಹಾಯಿಸಿ",
        "mr": "पाणी द्या",
    },
    "irrigate_critical": {
        "en": "Irrigate at the critical stage",
        "te": "కీలక దశలో నీరు పెట్టండి",
        "hi": "महत्वपूर्ण अवस्था में सिंचाई करें",
        "kn": "ನಿರ್ಣಾಯಕ ಹಂತದಲ್ಲಿ ನೀರು ಹಾಯಿಸಿ",
        "mr": "महत्त्वाच्या अवस्थेत पाणी द्या",
    },
    "weed": {
        "en": "Weed control",
        "te": "కలుపు నివారణ",
        "hi": "खरपतवार नियंत्रण",
        "kn": "ಕಳೆ ನಿಯಂತ್ರಣ",
        "mr": "तण नियंत्रण",
    },
    "scout_pest": {
        "en": "Check for pests; spray only if needed",
        "te": "పురుగులను గమనించండి; అవసరమైతేనే పిచికారీ",
        "hi": "कीट देखें; ज़रूरत हो तभी छिड़काव",
        "kn": "ಕೀಟ ಪರಿಶೀಲಿಸಿ; ಅಗತ್ಯವಿದ್ದರೆ ಮಾತ್ರ ಸಿಂಪಡಿಸಿ",
        "mr": "किडींची पाहणी करा; गरज असेल तरच फवारणी",
    },
    "scout_disease": {
        "en": "Check for disease; spray only if needed",
        "te": "తెగుళ్లను గమనించండి; అవసరమైతేనే పిచికారీ",
        "hi": "रोग देखें; ज़रूरत हो तभी छिड़काव",
        "kn": "ರೋಗ ಪರಿಶೀಲಿಸಿ; ಅಗತ್ಯವಿದ್ದರೆ ಮಾತ್ರ ಸಿಂಪಡಿಸಿ",
        "mr": "रोगांची पाहणी करा; गरज असेल तरच फवारणी",
    },
    "harvest": {
        "en": "Harvest",
        "te": "కోత కోయండి",
        "hi": "कटाई करें",
        "kn": "ಕೊಯ್ಲು ಮಾಡಿ",
        "mr": "काढणी करा",
    },
    "picking": {
        "en": "Start picking",
        "te": "కాయలు తెంపడం ప్రారంభించండి",
        "hi": "तुड़ाई शुरू करें",
        "kn": "ಕೊಯ್ಲು ಆರಂಭಿಸಿ",
        "mr": "तोडणी सुरू करा",
    },
}

#: One-line instructions per launch language (no products, no doses).
INSTRUCTIONS: dict[str, dict[str, str]] = {
    "transplant": {
        "en": "Plant 2-3 healthy seedlings per hill in rows; keep a thin film of water.",
        "te": "వరుసలలో కుదురుకు 2-3 ఆరోగ్యకరమైన మొక్కలు నాటండి; పలుచని నీటి పొర ఉంచండి.",
        "hi": "पंक्तियों में प्रति स्थान 2-3 स्वस्थ पौधे लगाएँ; पानी की पतली परत रखें।",
        "kn": "ಸಾಲುಗಳಲ್ಲಿ ಪ್ರತಿ ಗುಣಿಗೆ 2-3 ಆರೋಗ್ಯಕರ ಸಸಿ ನೆಡಿ; ತೆಳು ನೀರಿನ ಪದರ ಇಡಿ.",
        "mr": "ओळीत प्रत्येक ठिकाणी 2-3 निरोगी रोपे लावा; पाण्याचा पातळ थर ठेवा.",
    },
    "sow": {
        "en": "Use treated seed at the recommended spacing and depth, in moist soil.",
        "te": "ప్రక్రియ చేసిన విత్తనాన్ని సిఫారసు చేసిన దూరం, లోతులో తేమ నేలలో విత్తండి.",
        "hi": "उपचारित बीज अनुशंसित दूरी और गहराई पर नम मिट्टी में बोएँ।",
        "kn": "ಉಪಚರಿಸಿದ ಬೀಜವನ್ನು ಶಿಫಾರಸು ಅಂತರ ಮತ್ತು ಆಳದಲ್ಲಿ ತೇವ ಮಣ್ಣಿನಲ್ಲಿ ಬಿತ್ತಿ.",
        "mr": "प्रक्रिया केलेले बियाणे शिफारस अंतर व खोलीवर ओलसर जमिनीत पेरा.",
    },
    "basal": {
        "en": "Mix the recommended fertiliser into the soil at the last ploughing.",
        "te": "చివరి దుక్కిలో సిఫారసు చేసిన ఎరువును నేలలో కలపండి.",
        "hi": "अंतिम जुताई के समय अनुशंसित खाद मिट्टी में मिलाएँ।",
        "kn": "ಕೊನೆಯ ಉಳುಮೆಯಲ್ಲಿ ಶಿಫಾರಸು ಗೊಬ್ಬರವನ್ನು ಮಣ್ಣಿನಲ್ಲಿ ಬೆರೆಸಿ.",
        "mr": "शेवटच्या नांगरणीवेळी शिफारस केलेले खत जमिनीत मिसळा.",
    },
    "top_dress_1": {
        "en": "Apply the first split of nitrogen when the soil is moist; avoid rain days.",
        "te": "నేల తేమగా ఉన్నప్పుడు మొదటి విడత నత్రజని వేయండి; వర్షం రోజులు వద్దు.",
        "hi": "मिट्टी नम हो तब नाइट्रोजन की पहली किस्त दें; बारिश के दिन टालें।",
        "kn": "ಮಣ್ಣು ತೇವವಿದ್ದಾಗ ಸಾರಜನಕದ ಮೊದಲ ಕಂತು ನೀಡಿ; ಮಳೆ ದಿನ ತಪ್ಪಿಸಿ.",
        "mr": "जमीन ओलसर असताना नत्राचा पहिला हप्ता द्या; पावसाचे दिवस टाळा.",
    },
    "top_dress_2": {
        "en": "Apply the second split of nitrogen; skip it if the crop is already dark green.",
        "te": "రెండవ విడత నత్రజని వేయండి; పంట ముదురు ఆకుపచ్చగా ఉంటే అవసరం లేదు.",
        "hi": "नाइट्रोजन की दूसरी किस्त दें; फसल गहरी हरी हो तो न दें।",
        "kn": "ಸಾರಜನಕದ ಎರಡನೇ ಕಂತು ನೀಡಿ; ಬೆಳೆ ಗಾಢ ಹಸಿರಾಗಿದ್ದರೆ ಬೇಡ.",
        "mr": "नत्राचा दुसरा हप्ता द्या; पीक गडद हिरवे असल्यास देऊ नका.",
    },
    "irrigate": {
        "en": "Water when the topsoil is dry; do not flood for long.",
        "te": "పై నేల ఆరినప్పుడు నీరు పెట్టండి; ఎక్కువ సేపు నిల్వ ఉంచవద్దు.",
        "hi": "ऊपरी मिट्टी सूखने पर पानी दें; देर तक पानी न भरें।",
        "kn": "ಮೇಲ್ಮಣ್ಣು ಒಣಗಿದಾಗ ನೀರು ಹಾಯಿಸಿ; ಹೆಚ್ಚು ಹೊತ್ತು ನಿಲ್ಲಿಸಬೇಡಿ.",
        "mr": "वरची माती कोरडी झाल्यावर पाणी द्या; जास्त वेळ पाणी साचवू नका.",
    },
    "irrigate_critical": {
        "en": "Do not let the crop face water stress now; it cuts the yield.",
        "te": "ఈ దశలో పంటకు నీటి ఎద్దడి రానివ్వకండి; దిగుబడి తగ్గుతుంది.",
        "hi": "इस समय फसल को पानी की कमी न होने दें; उपज घटती है।",
        "kn": "ಈ ಹಂತದಲ್ಲಿ ಬೆಳೆಗೆ ನೀರಿನ ಕೊರತೆ ಆಗಬಾರದು; ಇಳುವರಿ ಕಡಿಮೆಯಾಗುತ್ತದೆ.",
        "mr": "या अवस्थेत पिकाला पाण्याचा ताण पडू देऊ नका; उत्पादन घटते.",
    },
    "weed": {
        "en": "Remove weeds by hand or an approved weedicide in the right window.",
        "te": "చేతితో లేదా సిఫారసు చేసిన కలుపు మందుతో సరైన సమయంలో కలుపు తీయండి.",
        "hi": "हाथ से या अनुमोदित खरपतवारनाशी से सही समय पर खरपतवार हटाएँ।",
        "kn": "ಕೈಯಿಂದ ಅಥವಾ ಅನುಮೋದಿತ ಕಳೆನಾಶಕದಿಂದ ಸರಿಯಾದ ಸಮಯದಲ್ಲಿ ಕಳೆ ತೆಗೆಯಿರಿ.",
        "mr": "हाताने किंवा मान्य तणनाशकाने योग्य वेळी तण काढा.",
    },
    "scout_pest": {
        "en": "Walk the field; photograph any damage in Crop Doctor before spraying.",
        "te": "పొలం తిరిగి చూడండి; పిచికారీకి ముందు నష్టాన్ని క్రాప్ డాక్టర్‌లో ఫోటో తీయండి.",
        "hi": "खेत में घूमें; छिड़काव से पहले नुकसान की फोटो क्रॉप डॉक्टर में लें।",
        "kn": "ಹೊಲ ಸುತ್ತಿ ನೋಡಿ; ಸಿಂಪಡಣೆಗೆ ಮುನ್ನ ಹಾನಿಯ ಫೋಟೋ ಕ್ರಾಪ್ ಡಾಕ್ಟರ್‌ನಲ್ಲಿ ತೆಗೆಯಿರಿ.",
        "mr": "शेतात फिरा; फवारणीपूर्वी नुकसानीचा फोटो क्रॉप डॉक्टरमध्ये घ्या.",
    },
    "scout_disease": {
        "en": "Look for spots or wilting; photograph them in Crop Doctor before spraying.",
        "te": "మచ్చలు, వాడిపోవడం గమనించండి; పిచికారీకి ముందు క్రాప్ డాక్టర్‌లో ఫోటో తీయండి.",
        "hi": "धब्बे या मुरझाना देखें; छिड़काव से पहले क्रॉप डॉक्टर में फोटो लें।",
        "kn": "ಚುಕ್ಕೆ ಅಥವಾ ಬಾಡುವಿಕೆ ನೋಡಿ; ಸಿಂಪಡಣೆಗೆ ಮುನ್ನ ಕ್ರಾಪ್ ಡಾಕ್ಟರ್‌ನಲ್ಲಿ ಫೋಟೋ ತೆಗೆಯಿರಿ.",
        "mr": "ठिपके किंवा मर पाहा; फवारणीपूर्वी क्रॉप डॉक्टरमध्ये फोटो घ्या.",
    },
    "harvest": {
        "en": "Harvest at maturity in dry weather; dry the produce before storage.",
        "te": "పక్వానికి వచ్చాక పొడి వాతావరణంలో కోయండి; నిల్వకు ముందు ఆరబెట్టండి.",
        "hi": "पकने पर सूखे मौसम में कटाई करें; भंडारण से पहले सुखाएँ।",
        "kn": "ಬಲಿತ ನಂತರ ಒಣ ಹವಾಮಾನದಲ್ಲಿ ಕೊಯ್ಯಿರಿ; ಸಂಗ್ರಹಕ್ಕೆ ಮುನ್ನ ಒಣಗಿಸಿ.",
        "mr": "पक्व झाल्यावर कोरड्या हवामानात काढणी करा; साठवणीपूर्वी वाळवा.",
    },
    "picking": {
        "en": "Pick mature produce every few days; respect the pre-harvest interval of sprays.",
        "te": "కొన్ని రోజులకొకసారి పక్వమైనవి తెంపండి; పిచికారీ తర్వాత వేచి ఉండే కాలం పాటించండి.",
        "hi": "हर कुछ दिन में पकी उपज तोड़ें; छिड़काव के बाद की प्रतीक्षा अवधि मानें।",
        "kn": "ಕೆಲವು ದಿನಗಳಿಗೊಮ್ಮೆ ಬಲಿತದ್ದನ್ನು ಕೊಯ್ಯಿರಿ; ಸಿಂಪಡಣೆಯ ಕಾಯುವ ಅವಧಿ ಪಾಲಿಸಿ.",
        "mr": "दर काही दिवसांनी पक्व माल तोडा; फवारणीनंतरचा प्रतीक्षा कालावधी पाळा.",
    },
}


@dataclass(frozen=True)
class Task:
    key: str  # suffix of the task key (``<crop>.<key>``)
    phrase: str  # TITLES / INSTRUCTIONS key
    task_type: TaskType
    day_offset: int
    duration_days: int
    stage: str | None
    category: str | None = None


_S, _I, _F, _P, _H = (
    TaskType.SOW,
    TaskType.IRRIGATE,
    TaskType.FERTILISE,
    TaskType.SPRAY,
    TaskType.HARVEST,
)

#: SPEC 0.3 pilot crops. Offsets from sowing / transplanting.
PILOT_CALENDARS: dict[str, tuple[Task, ...]] = {
    "paddy": (
        Task("basal", "basal", _F, 0, 1, "sown", "fertiliser"),
        Task("transplant", "transplant", _S, 0, 2, "sown", "seed"),
        Task("weed", "weed", _P, 3, 5, "vegetative", "herbicide"),
        Task("irrigate_early", "irrigate", _I, 7, 3, "vegetative"),
        Task("top_dress_1", "top_dress_1", _F, 21, 3, "vegetative", "fertiliser"),
        Task("scout_pest", "scout_pest", _P, 30, 5, "vegetative", "pesticide"),
        Task("top_dress_2", "top_dress_2", _F, 45, 3, "vegetative", "fertiliser"),
        Task("scout_disease", "scout_disease", _P, 55, 5, "flowering", "fungicide"),
        Task("irrigate_flowering", "irrigate_critical", _I, 70, 7, "flowering"),
        Task("harvest", "harvest", _H, 115, 10, "maturity"),
    ),
    "cotton": (
        Task("basal", "basal", _F, 0, 1, "sown", "fertiliser"),
        Task("sow", "sow", _S, 0, 2, "sown", "seed"),
        Task("weed", "weed", _P, 20, 7, "vegetative", "herbicide"),
        Task("top_dress_1", "top_dress_1", _F, 30, 3, "vegetative", "fertiliser"),
        Task("scout_pest", "scout_pest", _P, 40, 5, "vegetative", "pesticide"),
        Task("top_dress_2", "top_dress_2", _F, 60, 3, "flowering", "fertiliser"),
        Task("irrigate_flowering", "irrigate_critical", _I, 65, 10, "flowering"),
        Task("scout_bollworm", "scout_pest", _P, 75, 7, "fruiting", "pesticide"),
        Task("harvest", "picking", _H, 150, 20, "maturity"),
    ),
    "chilli": (
        Task("basal", "basal", _F, 0, 1, "sown", "fertiliser"),
        Task("transplant", "transplant", _S, 0, 2, "sown", "seed"),
        Task("irrigate_early", "irrigate", _I, 5, 3, "vegetative"),
        Task("weed", "weed", _P, 20, 7, "vegetative", "herbicide"),
        Task("top_dress_1", "top_dress_1", _F, 30, 3, "vegetative", "fertiliser"),
        Task("scout_pest", "scout_pest", _P, 35, 5, "vegetative", "pesticide"),
        Task("top_dress_2", "top_dress_2", _F, 60, 3, "flowering", "fertiliser"),
        Task("scout_disease", "scout_disease", _P, 70, 7, "flowering", "fungicide"),
        Task("irrigate_fruiting", "irrigate_critical", _I, 80, 10, "fruiting"),
        Task("harvest", "picking", _H, 120, 30, "maturity"),
    ),
    "maize": (
        Task("basal", "basal", _F, 0, 1, "sown", "fertiliser"),
        Task("sow", "sow", _S, 0, 2, "sown", "seed"),
        Task("weed", "weed", _P, 15, 7, "vegetative", "herbicide"),
        Task("top_dress_1", "top_dress_1", _F, 25, 3, "vegetative", "fertiliser"),
        Task("scout_pest", "scout_pest", _P, 20, 7, "vegetative", "pesticide"),
        Task("top_dress_2", "top_dress_2", _F, 45, 3, "vegetative", "fertiliser"),
        Task("irrigate_tasselling", "irrigate_critical", _I, 55, 10, "flowering"),
        Task("harvest", "harvest", _H, 95, 10, "maturity"),
    ),
    "tomato": (
        Task("basal", "basal", _F, 0, 1, "sown", "fertiliser"),
        Task("transplant", "transplant", _S, 0, 2, "sown", "seed"),
        Task("irrigate_early", "irrigate", _I, 3, 3, "vegetative"),
        Task("top_dress_1", "top_dress_1", _F, 25, 3, "vegetative", "fertiliser"),
        Task("scout_pest", "scout_pest", _P, 30, 5, "flowering", "pesticide"),
        Task("scout_disease", "scout_disease", _P, 40, 5, "flowering", "fungicide"),
        Task("top_dress_2", "top_dress_2", _F, 45, 3, "fruiting", "fertiliser"),
        Task("irrigate_fruiting", "irrigate_critical", _I, 50, 10, "fruiting"),
        Task("harvest", "picking", _H, 65, 25, "maturity"),
    ),
    "groundnut": (
        Task("basal", "basal", _F, 0, 1, "sown", "fertiliser"),
        Task("sow", "sow", _S, 0, 2, "sown", "seed"),
        Task("weed", "weed", _P, 15, 7, "vegetative", "herbicide"),
        Task("scout_pest", "scout_pest", _P, 30, 5, "vegetative", "pesticide"),
        Task("irrigate_pegging", "irrigate_critical", _I, 40, 10, "flowering"),
        Task("scout_disease", "scout_disease", _P, 50, 7, "fruiting", "fungicide"),
        Task("irrigate_pod", "irrigate", _I, 65, 7, "fruiting"),
        Task("harvest", "harvest", _H, 105, 10, "maturity"),
    ),
}


async def seed_crop_task_templates(session: AsyncSession, tenant_id: uuid.UUID) -> int:
    """Add the pilot templates the tenant does not have yet (by crop and task key; season
    NULL = every season). Idempotent; never touches an existing template."""
    crops = {
        c.code: c.id
        for c in (
            await session.execute(
                select(Crop).where(Crop.tenant_id == tenant_id, Crop.deleted_at.is_(None))
            )
        ).scalars()
    }
    existing = {
        (crop_id, key)
        for crop_id, key in (
            await session.execute(
                select(CropTaskTemplate.crop_id, CropTaskTemplate.task_key).where(
                    CropTaskTemplate.tenant_id == tenant_id,
                    CropTaskTemplate.season.is_(None),
                    CropTaskTemplate.deleted_at.is_(None),
                )
            )
        ).tuples()
    }
    added = 0
    for code, tasks in PILOT_CALENDARS.items():
        crop_id = crops.get(code)
        if crop_id is None:
            continue
        for order, task in enumerate(tasks):
            key = f"{code}.{task.key}"
            if (crop_id, key) in existing:
                continue
            session.add(
                CropTaskTemplate(
                    tenant_id=tenant_id,
                    crop_id=crop_id,
                    season=None,
                    task_key=key,
                    task_type=task.task_type.value,
                    day_offset=task.day_offset,
                    duration_days=task.duration_days,
                    stage=task.stage,
                    titles=dict(TITLES[task.phrase]),
                    instructions=dict(INSTRUCTIONS[task.phrase]),
                    product_category=task.category,
                    sort_order=order * 10,
                    source=SOURCE,
                )
            )
            added += 1
    if added:
        await session.flush()
    return added


__all__ = ["INSTRUCTIONS", "PILOT_CALENDARS", "TITLES", "Task", "seed_crop_task_templates"]
