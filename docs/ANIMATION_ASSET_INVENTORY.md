# Inventaris aset MamPet

Inventaris menggunakan manifest di dalam masing-masing ZIP. Pemeriksaan memuat semua PNG, menguji CRC, memeriksa format, ukuran 1024 × 1024 dan kanal RGBA, lalu menguji adanya piksel transparan dan opak. Duplikat diperiksa dengan hash piksel RGBA setelah menormalkan RGB piksel transparan penuh.

## Monster

- PNG terverifikasi 60/60.
- Salinan byte identik di path manifest 0. Master byte identik di `<stage>/original.png` 58. Varian lokal 2. File yang perlu diekstrak 0.
- Manifest lokal identik.
- `assets/monsters/leaf_spirit/young.png` memiliki 15 warna pada area alpha > 127 (0.3% kanvas).
- Format pada path aset lokal 60 PNG P 400 × 400.
- Path yang hanya memiliki varian lokal di lokasi yang diperiksa `assets/monsters/leaf_spirit/young.png`, `assets/monsters/leaf_spirit/adult.png`.

## Telur

- PNG terverifikasi 12/12.
- Salinan byte identik di path manifest 0. Master byte identik di `<stage>/original.png` 0. Varian lokal 12. File yang perlu diekstrak 0.
- Manifest lokal identik.
- Format pada path aset lokal 12 PNG P 400 × 400.

## Rekonsiliasi sumber

- 20 ID dan slug cocok antara daftar permintaan, tabel PRD §7, dan manifest monster. Nama, elemen dan rarity mengikuti tabel spesies PRD dan daftar permintaan. Manifest ZIP monster mencatat ID, slug dan path per fase.
- Baris tabel PRD menghasilkan 12 Common, 5 Uncommon dan 3 Rare, sesuai dengan ringkasan PRD.
- PRD §9.1 dan manifest telur memakai nama bernomor. Pasangan path generik di PRD §15 berbeda dari nama file arsip.
- PNG `leaf_spirit/adult.png` dan `forest_deer/adult.png` menampilkan desain rusa serupa dengan perbedaan pose, tanduk, dan dedaunan. Keduanya berbeda secara piksel, mengoreksi catatan duplikat eksak pada `MONSTER_ANIMATION_PIPELINE.md`. Identitas ilustrasi Sproutle Adult perlu dikonfirmasi sebelum rigging.
- Distribusi lokal monster sudah memuat sprite untuk Flutter dan backup master. Paket ini membaca master Embergon langsung dari ZIP.

| ID | Nama | Slug | Elemen | Rarity | Baby | Young | Adult |
|---|---|---|---|---|---|---|---|
| 01 | Embergon | `fire_dragon` | Api | Rare | `assets/monsters/fire_dragon/baby.png` | `assets/monsters/fire_dragon/young.png` | `assets/monsters/fire_dragon/adult.png` |
| 02 | Grovongo | `leaf_gorilla` | Alam | Uncommon | `assets/monsters/leaf_gorilla/baby.png` | `assets/monsters/leaf_gorilla/young.png` | `assets/monsters/leaf_gorilla/adult.png` |
| 03 | Zephlet | `sky_bird` | Angin | Common | `assets/monsters/sky_bird/baby.png` | `assets/monsters/sky_bird/young.png` | `assets/monsters/sky_bird/adult.png` |
| 04 | Foxili | `fox` | Api | Common | `assets/monsters/fox/baby.png` | `assets/monsters/fox/young.png` | `assets/monsters/fox/adult.png` |
| 05 | Bubblu | `water_slime` | Air | Uncommon | `assets/monsters/water_slime/baby.png` | `assets/monsters/water_slime/young.png` | `assets/monsters/water_slime/adult.png` |
| 06 | Sproutle | `leaf_spirit` | Alam | Common | `assets/monsters/leaf_spirit/baby.png` | `assets/monsters/leaf_spirit/young.png` | `assets/monsters/leaf_spirit/adult.png` |
| 07 | Axolumi | `pink_axolotl` | Air | Common | `assets/monsters/pink_axolotl/baby.png` | `assets/monsters/pink_axolotl/young.png` | `assets/monsters/pink_axolotl/adult.png` |
| 08 | Cacopaw | `dessert_panda` | Misteri | Common | `assets/monsters/dessert_panda/baby.png` | `assets/monsters/dessert_panda/young.png` | `assets/monsters/dessert_panda/adult.png` |
| 09 | Bellmori | `lamb` | Bumi | Uncommon | `assets/monsters/lamb/baby.png` | `assets/monsters/lamb/young.png` | `assets/monsters/lamb/adult.png` |
| 10 | Crustello | `bread_turtle` | Bumi | Common | `assets/monsters/bread_turtle/baby.png` | `assets/monsters/bread_turtle/young.png` | `assets/monsters/bread_turtle/adult.png` |
| 11 | Marinox | `sea_dragon` | Air | Rare | `assets/monsters/sea_dragon/baby.png` | `assets/monsters/sea_dragon/young.png` | `assets/monsters/sea_dragon/adult.png` |
| 12 | Mossolith | `moss_golem` | Bumi | Common | `assets/monsters/moss_golem/baby.png` | `assets/monsters/moss_golem/young.png` | `assets/monsters/moss_golem/adult.png` |
| 13 | Puddinghoul | `dessert_ghost` | Misteri | Rare | `assets/monsters/dessert_ghost/baby.png` | `assets/monsters/dessert_ghost/young.png` | `assets/monsters/dessert_ghost/adult.png` |
| 14 | Mellibee | `bee_moth` | Angin | Common | `assets/monsters/bee_moth/baby.png` | `assets/monsters/bee_moth/young.png` | `assets/monsters/bee_moth/adult.png` |
| 15 | Frostelle | `ice_fox` | Air | Common | `assets/monsters/ice_fox/baby.png` | `assets/monsters/ice_fox/young.png` | `assets/monsters/ice_fox/adult.png` |
| 16 | Floradeer | `forest_deer` | Alam | Uncommon | `assets/monsters/forest_deer/baby.png` | `assets/monsters/forest_deer/young.png` | `assets/monsters/forest_deer/adult.png` |
| 17 | Pingochef | `chef_penguin` | Air | Common | `assets/monsters/chef_penguin/baby.png` | `assets/monsters/chef_penguin/young.png` | `assets/monsters/chef_penguin/adult.png` |
| 18 | Stellacat | `mage_cat` | Misteri | Uncommon | `assets/monsters/mage_cat/baby.png` | `assets/monsters/mage_cat/young.png` | `assets/monsters/mage_cat/adult.png` |
| 19 | Sporella | `mushroom` | Alam | Common | `assets/monsters/mushroom/baby.png` | `assets/monsters/mushroom/young.png` | `assets/monsters/mushroom/adult.png` |
| 20 | Bambalu | `bamboo_panda` | Alam | Common | `assets/monsters/bamboo_panda/baby.png` | `assets/monsters/bamboo_panda/young.png` | `assets/monsters/bamboo_panda/adult.png` |

### Path telur di arsip

- `assets/eggs/01_fire_cracked.png`
- `assets/eggs/01_fire_intact.png`
- `assets/eggs/02_water_cracked.png`
- `assets/eggs/02_water_intact.png`
- `assets/eggs/03_nature_cracked.png`
- `assets/eggs/03_nature_intact.png`
- `assets/eggs/04_wind_cracked.png`
- `assets/eggs/04_wind_intact.png`
- `assets/eggs/05_earth_cracked.png`
- `assets/eggs/05_earth_intact.png`
- `assets/eggs/06_mystery_cracked.png`
- `assets/eggs/06_mystery_intact.png`
