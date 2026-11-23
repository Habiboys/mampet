import json
import re

CATALOG_PATH = r"c:\Project\mampet\assets\data\food_catalog_seed_v1.json"


def norm(s):
    s = s.lower().strip()
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


NEW_DAILY_FOODS = [
    {
        "id": "nasi_serealia_051",
        "category_id": "nasi_serealia",
        "canonical_name": "Nasi Telur",
        "aliases": ["nasi telor", "nasi telur ceplok", "nasi telur dadar", "nasi telur pontianak", "nasi orak arik"],
        "description": "Nasi putih hangat dengan telur ceplok, dadar, atau orak-arik berbumbu kecap dan sambal — menu harian favorit sejuta umat.",
        "origin_region": "Indonesia",
    },
    {
        "id": "mie_pasta_051",
        "category_id": "mie_pasta",
        "canonical_name": "Indomie Goreng Telur",
        "aliases": ["indomie goreng", "mie instan goreng", "mie goreng telur", "mie nyemek instan"],
        "description": "Mi goreng instan ikonik dengan telur mata sapi atau dadar dan taburan bawang goreng renyah.",
        "origin_region": "Indonesia",
    },
    {
        "id": "lauk_protein_051",
        "category_id": "lauk_protein",
        "canonical_name": "Telur Dadar Krispi",
        "aliases": ["telor dadar krispi", "telur dadar garing", "telur barendo", "dadar krispi"],
        "description": "Telur dadar renyah berenda pinggirannya yang gurih dan cocok dengan segala jenis sambal.",
        "origin_region": "Indonesia",
    },
    {
        "id": "sup_berkuah_051",
        "category_id": "sup_berkuah",
        "canonical_name": "Sup Oyong Soun",
        "aliases": ["sayur oyong", "sop oyong", "sop gambas soun", "sup gambas"],
        "description": "Kuah bening gurih berisi potongan oyong segar, soun lembut, dan bakso atau telur puyuh.",
        "origin_region": "Indonesia",
    },
    {
        "id": "sayur_nabati_051",
        "category_id": "sayur_nabati",
        "canonical_name": "Sayur Bening Bayam",
        "aliases": ["sayur bayam", "bening bayam jagung", "sayur bayam jagung"],
        "description": "Sayur rumahan kuah bening segar dengan daun bayam, jagung manis, dan aroma temu kunci.",
        "origin_region": "Indonesia",
    },
    {
        "id": "camilan_asin_051",
        "category_id": "camilan_asin",
        "canonical_name": "Cimol Bojot",
        "aliases": ["cimol pedas", "cimol daun jeruk", "cimol bumbu basah", "cimol garut"],
        "description": "Cimol aci kenyal yang dilumuri minyak bawang, cabai merah, dan irisan daun jeruk wangi.",
        "origin_region": "Jawa Barat",
    },
    {
        "id": "kue_dessert_051",
        "category_id": "kue_dessert",
        "canonical_name": "Kue Pukis Cokelat Keju",
        "aliases": ["pukis", "kue pukis", "pukis pandan", "pukis keju"],
        "description": "Kue tradisional empuk beraroma santan dan vanila dengan taburan meses cokelat dan keju parut.",
        "origin_region": "Jawa Tengah",
    },
    {
        "id": "roti_adonan_051",
        "category_id": "roti_adonan",
        "canonical_name": "Roti Bakar Telur Keju",
        "aliases": ["roti telur", "sandwich telur keju", "egg toast", "roti panggang telur"],
        "description": "Roti panggang hangat berisi telur lembut, lelehan keju, dan saus gurih untuk sarapan praktis.",
        "origin_region": "Internasional",
    },
    {
        "id": "kopi_teh_051",
        "category_id": "kopi_teh",
        "canonical_name": "Es Kopi Susu Gula Aren",
        "aliases": ["kopsu gula aren", "es kopsu", "kopi susu kekinian", "kopi aren"],
        "description": "Perpaduan espresso, susu segar creamy, dan sirup gula aren karamel khas kedai kopi Indonesia.",
        "origin_region": "Indonesia",
    },
    {
        "id": "minuman_lain_051",
        "category_id": "minuman_lain",
        "canonical_name": "Es Jeruk Nipis Madu",
        "aliases": ["jeruk nipis madu", "es jeruk nipis", "jeniper", "jeruk madu hangat"],
        "description": "Perasan jeruk nipis segar dipadukan madu alami yang menyegarkan tenggorokan.",
        "origin_region": "Indonesia",
    },
    {
        "id": "ikan_seafood_051",
        "category_id": "ikan_seafood",
        "canonical_name": "Lele Goreng Sambal Lamongan",
        "aliases": ["pecel lele", "lele goreng", "lele penyet", "lele kremes"],
        "description": "Ikan lele goreng garing disajikan dengan lalapan segar dan sambal terasi tomat khas Lamongan.",
        "origin_region": "Jawa Timur",
    },
    {
        "id": "buah_olahan_051",
        "category_id": "buah_olahan",
        "canonical_name": "Rujak Buah Potong",
        "aliases": ["rujak uleg", "rujak manis", "buah potong sambal rujak", "rujak cingur buah"],
        "description": "Aneka potongan buah segar tropis dengan cocolan bumbu kacang gula merah pedas manis.",
        "origin_region": "Indonesia",
    },
]

with open(CATALOG_PATH, "r", encoding="utf-8") as f:
    data = json.load(f)

existing_ids = {item["id"] for item in data["foods"]}
existing_norms = {item["normalized_name"] for item in data["foods"]}

added = 0
for item in NEW_DAILY_FOODS:
    n = norm(item["canonical_name"])
    if item["id"] in existing_ids or n in existing_norms:
        print(f"Skip existing: {item['canonical_name']}")
        continue
    data["foods"].append({
        "id": item["id"],
        "category_id": item["category_id"],
        "canonical_name": item["canonical_name"],
        "normalized_name": n,
        "locale": "id_ID",
        "description": item["description"],
        "origin_region": item["origin_region"],
        "status": "active",
        "aliases": item["aliases"],
    })
    added += 1

data["version"] = "1.1.0"
with open(CATALOG_PATH, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"Added {added} daily Indonesian dishes. Total master foods: {len(data['foods'])}")
