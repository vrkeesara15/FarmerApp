"""M6 part of the demo seed: the public bootstrap corpus (M6-KICKOFF, SPEC 3.3 steps 1-2).

For each pilot crop, 10-12 common problems (the crop's own ``pest_or_disease`` masters plus
the polyphagous ones: aphids, nitrogen deficiency, waterlogging, drought stress) become
**approved** ``corpus_problem`` rows marked ``source = public`` with names in the five
languages, a symptom checklist (English; translations are a human gate) and cultural
practices (English + Telugu), each with ``M6Profile.images_per_problem`` **synthetic**
placeholder images (``diagnosis.images.synthetic_leaf``) embedded with the configured encoder
and approved in one ``corpus_version`` (1).

No licensed field dataset is present, so the images are generated; they only exercise the
pipeline. Real field images are a human gate (SPEC 3.3 step 3: officers photograph scouting
cases, the agronomist labels weekly; 150+ approved images per problem before it counts as
"high confidence capable"); PlantVillage-like public data may only bootstrap and stays
``source = public``.
"""

from __future__ import annotations

import hashlib
import re
import uuid
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from functools import lru_cache
from typing import Any

from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import PestOrDisease, ProblemType
from farmerapp.diagnosis.encoder import ImageEncoder
from farmerapp.diagnosis.images import synthetic_leaf
from farmerapp.diagnosis.models import (
    CorpusImage,
    CorpusProblem,
    CorpusSource,
    CorpusStatus,
    CorpusVersion,
    ImagePart,
    Severity,
)
from farmerapp.jobs.seed_catalog import PROBLEMS
from farmerapp.uploads.blobstore import BlobStore

#: Kannada and Marathi names (Telugu / Hindi come from ``seed_catalog.PROBLEMS``). Machine-
#: assisted: native-speaker review is a human gate (NF-008).
KN_MR: Mapping[str, tuple[str, str]] = {
    "paddy_blast": ("ಬೆಂಕಿ ರೋಗ", "करपा रोग"),
    "paddy_sheath_blight": ("ಕವಚ ಕೊಳೆ ರೋಗ", "आवरण करपा"),
    "paddy_blb": ("ಬ್ಯಾಕ್ಟೀರಿಯಾ ಎಲೆ ಮಚ್ಚೆ ರೋಗ", "जिवाणूजन्य करपा"),
    "paddy_bph": ("ಕಂದು ಜಿಗಿಹುಳು", "तपकिरी तुडतुडे"),
    "paddy_stem_borer": ("ಹಳದಿ ಕಾಂಡ ಕೊರಕ", "पिवळा खोडकिडा"),
    "paddy_leaf_folder": ("ಎಲೆ ಸುರುಳಿ ಹುಳು", "पाने गुंडाळणारी अळी"),
    "paddy_zinc_deficiency": ("ಸತುವಿನ ಕೊರತೆ", "जस्ताची कमतरता"),
    "paddy_weeds": ("ಕಳೆಗಳು", "तण"),
    "cotton_pink_bollworm": ("ಗುಲಾಬಿ ಕಾಯಿ ಕೊರಕ", "गुलाबी बोंडअळी"),
    "cotton_whitefly": ("ಬಿಳಿ ನೊಣ", "पांढरी माशी"),
    "cotton_jassids": ("ಜಿಗಿ ಹುಳು", "तुडतुडे"),
    "cotton_aphids": ("ಸಸ್ಯ ಹೇನು", "मावा"),
    "cotton_leaf_reddening": ("ಎಲೆ ಕೆಂಪಾಗುವಿಕೆ", "पाने लाल होणे"),
    "cotton_bacterial_blight": ("ಬ್ಯಾಕ್ಟೀರಿಯಾ ಅಂಗಮಾರಿ", "जिवाणूजन्य करपा"),
    "cotton_weeds": ("ಕಳೆಗಳು", "तण"),
    "chilli_thrips": ("ಥ್ರಿಪ್ಸ್ ನುಸಿ", "फुलकिडे"),
    "chilli_mites": ("ನುಸಿ", "कोळी"),
    "chilli_leaf_curl": ("ಎಲೆ ಮುದುರು ರೋಗ", "चुरडा मुरडा"),
    "chilli_anthracnose": ("ಹಣ್ಣು ಕೊಳೆ ರೋಗ", "फळकूज"),
    "chilli_powdery_mildew": ("ಬೂದಿ ರೋಗ", "भुरी"),
    "chilli_damping_off": ("ಸಸಿ ಸಾಯುವ ರೋಗ", "रोपे कोलमडणे"),
    "maize_fall_armyworm": ("ಸೈನಿಕ ಹುಳು", "लष्करी अळी"),
    "maize_stem_borer": ("ಕಾಂಡ ಕೊರಕ", "खोडकिडा"),
    "maize_turcicum_blight": ("ಎಲೆ ಅಂಗಮಾರಿ", "पानावरील करपा"),
    "maize_zinc_deficiency": ("ಸತುವಿನ ಕೊರತೆ", "जस्ताची कमतरता"),
    "maize_weeds": ("ಕಳೆಗಳು", "तण"),
    "maize_rust": ("ತುಕ್ಕು ರೋಗ", "तांबेरा"),
    "tomato_early_blight": ("ಮುಂಚಿನ ಅಂಗಮಾರಿ", "लवकर येणारा करपा"),
    "tomato_late_blight": ("ತಡವಾದ ಅಂಗಮಾರಿ", "उशिरा येणारा करपा"),
    "tomato_fruit_borer": ("ಹಣ್ಣು ಕೊರಕ", "फळ पोखरणारी अळी"),
    "tomato_leaf_curl": ("ಎಲೆ ಮುದುರು ರೋಗ", "पर्णगुच्छ"),
    "tomato_bacterial_wilt": ("ಬ್ಯಾಕ್ಟೀರಿಯಾ ಸೊರಗು ರೋಗ", "जिवाणूजन्य मर"),
    "tomato_whitefly": ("ಬಿಳಿ ನೊಣ", "पांढरी माशी"),
    "groundnut_tikka": ("ಎಲೆ ಚುಕ್ಕೆ ರೋಗ", "टिक्का रोग"),
    "groundnut_rust": ("ತುಕ್ಕು ರೋಗ", "तांबेरा"),
    "groundnut_leaf_miner": ("ಎಲೆ ಸುರಂಗ ಹುಳು", "पाने पोखरणारी अळी"),
    "groundnut_white_grub": ("ಬಿಳಿ ಗೊಣ್ಣೆ ಹುಳು", "हुमणी"),
    "groundnut_stem_rot": ("ಕಾಂಡ ಕೊಳೆ ರೋಗ", "खोडकूज"),
    "groundnut_bud_necrosis": ("ಮೊಗ್ಗು ಕೊಳೆ ರೋಗ", "शेंडा मर"),
    "aphids": ("ಸಸ್ಯ ಹೇನು", "मावा"),
    "nitrogen_deficiency": ("ಸಾರಜನಕದ ಕೊರತೆ", "नत्राची कमतरता"),
    "waterlogging": ("ನೀರು ನಿಲ್ಲುವಿಕೆ", "पाणी साचणे"),
    "drought_stress": ("ಬರ ಒತ್ತಡ", "पाण्याचा ताण"),
}

#: DX-007 cultural treatments by problem type (English + Telugu; the rest is a human gate).
CULTURAL: Mapping[str, dict[str, list[str]]] = {
    ProblemType.DISEASE.value: {
        "en": [
            "Remove and destroy badly affected leaves and plants",
            "Avoid excess nitrogen and overhead watering",
            "Rotate crops and sow certified, disease-free seed",
        ],
        "te": [
            "బాగా దెబ్బతిన్న ఆకులు, మొక్కలను తీసివేసి నాశనం చేయండి",
            "అధిక నత్రజని, పై నుండి నీరు పెట్టడం మానండి",
            "పంట మార్పిడి చేయండి, ధృవీకరించిన విత్తనం వాడండి",
        ],
    },
    ProblemType.PEST.value: {
        "en": [
            "Scout twice a week; set pheromone or yellow sticky traps",
            "Keep bunds and field edges free of weeds",
            "Protect natural enemies: avoid sprays that are not needed",
        ],
        "te": [
            "వారానికి రెండుసార్లు పంటను పరిశీలించండి; లింగాకర్షక / పసుపు జిగురు బుట్టలు పెట్టండి",
            "గట్లు, పొలం అంచులు కలుపు లేకుండా ఉంచండి",
            "మిత్ర పురుగులను కాపాడండి: అవసరం లేని పిచికారీలు చేయకండి",
        ],
    },
    ProblemType.NUTRIENT.value: {
        "en": [
            "Test the soil and follow the recommended dose",
            "Apply farmyard manure or compost before sowing",
        ],
        "te": [
            "భూసార పరీక్ష చేయించి సిఫారసు చేసిన మోతాదు వాడండి",
            "విత్తే ముందు పశువుల ఎరువు లేదా కంపోస్టు వేయండి",
        ],
    },
    ProblemType.ABIOTIC.value: {
        "en": [
            "Fix drainage or the irrigation schedule",
            "Mulch to keep soil moisture even",
        ],
        "te": [
            "నీటి పారుదల లేదా తడుల షెడ్యూలు సరిచేయండి",
            "నేల తేమ నిలిచేలా మల్చింగ్ చేయండి",
        ],
    },
}

GENERIC_CODES: tuple[str, ...] = ("aphids", "nitrogen_deficiency", "waterlogging", "drought_stress")
SEVERITIES = (Severity.LOW, Severity.MEDIUM, Severity.HIGH)
SEED_BUCKET = "corpus"


@dataclass(frozen=True)
class M6Profile:
    images_per_problem: int = 6
    crops: tuple[str, ...] | None = None  # None = every pilot crop of the tenant
    problems_per_crop: int | None = None  # None = all (10-12)
    write_blobs: bool = False


M6_FULL = M6Profile()
#: Test fixture: two paddy problems with enough images for a high-confidence corpus answer.
M6_SMALL = M6Profile(images_per_problem=8, crops=("paddy",), problems_per_crop=3)


def symptom_list(text: str) -> list[str]:
    parts = [p.strip() for p in re.split(r"[;,]", text) if p.strip()]
    return [p[0].upper() + p[1:] for p in parts]


def corpus_codes(crop_code: str, available: set[str]) -> list[str]:
    """The seeded problem codes of a crop: its own masters, then the polyphagous ones."""
    own = [p.code for p in PROBLEMS if p.crop == crop_code and p.code in available]
    return own + [c for c in GENERIC_CODES if c in available]


@lru_cache(maxsize=4096)
def _image(code: str, variant: int) -> bytes:
    return synthetic_leaf(code, variant)


class CorpusSeeder:
    def __init__(
        self,
        tenant_id: uuid.UUID,
        profile: M6Profile,
        *,
        today: date,
        users: Sequence[User],
        rows: Mapping[str, list[Any]],
        add: Callable[[Any], None],
        encoder: ImageEncoder,
        blobs: BlobStore | None = None,
    ) -> None:
        self.tid, self.profile, self.today = tenant_id, profile, today
        self.rows, self.add, self.encoder, self.blobs = rows, add, encoder, blobs
        self.agronomist = next((u for u in users if u.role == UserRole.AGRONOMIST), None)

    def _sid(self, kind: str, key: str) -> uuid.UUID:
        return uuid.uuid5(self.tid, f"{kind}:{key}")

    async def generate(self) -> None:
        crops: dict[str, Crop] = {c.code: c for c in self.rows["crop"]}
        masters: dict[str, PestOrDisease] = {p.code: p for p in self.rows["pest_or_disease"]}
        specs = {p.code: p for p in PROBLEMS}
        approved_at = datetime.combine(self.today - timedelta(days=30), time(10), tzinfo=UTC)
        agronomist = self.agronomist.id if self.agronomist else None
        problem_ids: list[uuid.UUID] = []
        image_ids: list[uuid.UUID] = []
        wanted = self.profile.crops or tuple(crops)
        for crop_code in wanted:
            crop = crops.get(crop_code)
            if crop is None:
                continue
            codes = corpus_codes(crop_code, set(masters))
            if self.profile.problems_per_crop is not None:
                codes = codes[: self.profile.problems_per_crop]
            for code in codes:
                master, spec = masters[code], specs[code]
                kn, mr = KN_MR.get(code, (spec.name, spec.name))
                problem = CorpusProblem(
                    id=self._sid("corpus_problem", f"{crop_code}/{code}"),
                    tenant_id=self.tid,
                    pest_or_disease_id=master.id,
                    crop_id=crop.id,
                    problem_type=master.type,
                    names={"en": spec.name, **dict(spec.names), "kn": kn, "mr": mr},
                    symptoms={"en": symptom_list(spec.symptoms)},
                    cultural_practices=CULTURAL.get(master.type, {}),
                    status=CorpusStatus.APPROVED.value,
                    source=CorpusSource.PUBLIC.value,
                    labelled_by=agronomist,
                    reviewed_by=agronomist,
                    reviewed_at=approved_at,
                    approved_by=agronomist,
                    approved_at=approved_at,
                    approved_in_version=1,
                    notes="M6 public bootstrap seed (synthetic placeholder images).",
                )
                self.add(problem)
                problem_ids.append(problem.id)
                datas = [_image(code, v) for v in range(self.profile.images_per_problem)]
                vectors = await self.encoder.encode(datas)
                for variant, (data, vector) in enumerate(zip(datas, vectors, strict=True)):
                    sha = hashlib.sha256(data).hexdigest()
                    key = f"{self.tid}/corpus/{sha}"
                    uri = f"gs://{SEED_BUCKET}/{key}"
                    if self.blobs is not None:
                        uri = await self.blobs.put(key, data, content_type="image/jpeg")
                    image = CorpusImage(
                        id=self._sid("corpus_image", f"{crop_code}/{code}/{variant}"),
                        tenant_id=self.tid,
                        problem_id=problem.id,
                        crop_id=crop.id,
                        blob_uri=uri,
                        sha256=sha,
                        embedding=vector,
                        encoder_name=self.encoder.info.name,
                        encoder_version=self.encoder.info.version,
                        stage=None,
                        part=ImagePart.LEAF.value,
                        severity=SEVERITIES[variant % len(SEVERITIES)].value,
                        region=None,
                        season=None,
                        source=CorpusSource.PUBLIC.value,
                        status=CorpusStatus.APPROVED.value,
                        labelled_by=agronomist,
                        approved_by=agronomist,
                        approved_at=approved_at,
                        approved_in_version=1,
                    )
                    self.add(image)
                    image_ids.append(image.id)
        if problem_ids:
            self.add(
                CorpusVersion(
                    id=self._sid("corpus_version", "1"),
                    tenant_id=self.tid,
                    version=1,
                    approved_by=agronomist,
                    note="M6 public bootstrap seed (source=public, synthetic images)",
                    changes={
                        "problems": [str(p) for p in problem_ids],
                        "images": [str(i) for i in image_ids],
                        "retired": [],
                    },
                    created_at=approved_at,
                )
            )


__all__ = [
    "CULTURAL",
    "GENERIC_CODES",
    "KN_MR",
    "M6_FULL",
    "M6_SMALL",
    "CorpusSeeder",
    "M6Profile",
    "corpus_codes",
    "symptom_list",
]
