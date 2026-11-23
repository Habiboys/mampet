# Integrasi animasi MamPet untuk Antigravity

Paket pilot menggunakan **Embergon, ID 01, `fire_dragon`, Baby, Api, Rare**. Identitas pemuatan aset adalah slug dan fase, sedangkan nama tampilan diambil dari metadata. Inventaris mencatat seluruh 20 monster dan path sumber untuk 60 bentuk. [Inventaris aset](docs/ANIMATION_ASSET_INVENTORY.md)

## Koleksi OpenBone

Indeks koleksi mencatat setiap pasangan slug dan fase. `exported` berarti paket lolos validasi OpenBone dan tersedia untuk uji integrasi. `review_only` menandai paket yang bisa dibuka untuk meninjau identitas ilustrasi dan perlu dikecualikan dari pemuatan produksi. `source_blocked` menandai sumber yang belum bisa dipakai untuk rigging. [Indeks koleksi](assets/animated_monsters/collection_manifest.json)

Lembar tinjauan menampilkan pose `sleep` dan `special` untuk ketiga fase. [Monster 01–05](assets/animated_monsters/previews/collection_01.jpg) · [Monster 06–10](assets/animated_monsters/previews/collection_02.jpg) · [Monster 11–15](assets/animated_monsters/previews/collection_03.jpg) · [Monster 16–20](assets/animated_monsters/previews/collection_04.jpg)

Koleksi memuat 58 paket untuk uji integrasi dan satu paket tinjauan. Seluruh 59 paket memiliki layer mata dan mulut, tujuh klip, dan tujuh GIF. Uji geometri 60 Hz mencakup 52.817 pose tanpa segitiga terbalik. Pose netral dan perbandingan master tersedia untuk setiap paket.

Paket batch menyediakan `rig/character.obone` dan `exports/character.obonb`. Atlas biner batch memakai setengah resolusi tekstur master untuk pemuatan di perangkat. Rig editor tetap menggunakan tekstur master pada folder `layers/`. Gunakan `exports[].path`, `state_machine.name`, `clips.<nama>.loop` dan `clips.<nama>.trigger` dari manifest setiap bentuk. Durasi `idle` batch adalah 3,2 detik. Properti `surface.eyes_attachment` dan `surface.mouth_attachment` mencatat ketersediaan slot ekspresi.

State `sleep` tetap berulang sampai trigger lain dijalankan. Semua klip lain selain `idle` kembali ke `idle` secara otomatis. Klik wajah memicu `pet`. Nama trigger sama pada setiap bentuk, sehingga event host dapat dipetakan secara seragam. Nama state machine mengikuti nama monster dan fase, misalnya `EmbergonYoung`.

Sproutle Young membutuhkan ilustrasi sumber yang valid. Sproutle Adult memakai master arsip yang menampilkan desain rusa serupa Floradeer dan tersedia untuk tinjauan saja. Periksa kualitas pemutaran, konsumsi memori, dan penanganan fase tanpa paket di Android sebelum rilis. [Indeks koleksi](assets/animated_monsters/collection_manifest.json)

`tools/monster_openbone_specs.json` menyimpan titik anatomi per bentuk. `tools/monster_openbone_face_guides.json` menyimpan panduan tambahan yang diukur pada ilustrasi master. `python tools/monster_openbone_batch.py --server <path-bin.js> --workers 5` membuat paket yang masih belum tersedia. `--repair-faces` mengulang paket bila tingkat cakupan attachment wajah bertambah. `python tools/monster_openbone_gallery.py` memeriksa referensi, checksum ekspor, metadata GIF dan preview sebelum membuat empat lembar tinjauan koleksi.

## Revisi ekspresi wajah

Revisi tersedia untuk 57 bentuk. Mata terbuka baru digambar pada 30 bentuk yang master-nya bermata terpejam. Empat ilustrasi bersenyum tertutup mendapat gambar mulut terbuka baru. Embergon Baby memakai paket pilot yang sudah memiliki pose wajah terpisah. Status sumber Sproutle tetap tercatat di indeks koleksi.

Paket dengan `expression_revision` memakai `eyes_open` dan `mouth_relaxed` sebagai pose diam. Mata yang semula terpejam digambar ulang pada layer terpisah. Senyum asli tetap dapat muncul sebagai ekspresi gembira. Kedipan menggunakan dua pose kelopak antara, lalu kelopak menutup dan membuka kembali. `eat` berpindah di antara mulut rileks, terbuka sebagian, terbuka, dan kunyah. Pada Zephlet dan Pingochef, rahang bawah bergerak di bawah paruh atas yang dipertahankan dari ilustrasi master.

Nama klip, trigger, dan path OBONB mengikuti manifest masing-masing bentuk. Gunakan paket ekspor yang baru bersama manifest satu foldernya. Dalam folder `previews/`, `face_expressions.jpg` memperlihatkan master dan crop dari pose yang dirender OpenBone. GIF preview juga memakai pose yang dihitung oleh runtime OpenBone. Rig dan tekstur produksi tersedia melalui `.obone` dan `.obonb`.

Sepuluh bentuk Adult memakai ilustrasi ImageGen yang digambar dengan mata terbuka. Daftarnya mencakup Embergon, Mossolith, Puddinghoul, Mellibee, Frostelle, Floradeer, Pingochef, Stellacat, Sporella, dan Bambalu. PNG gambar ulang tersimpan di `source/redrawn.png` dengan checksum pada `drawing_source`. `source/original.png` menyimpan master ZIP sebagai referensi perbandingan. Embergon, Frostelle, dan Floradeer menampilkan satu mata karena ilustrasi mereka menghadap samping.

Revisi ekspresi 7 menutup kelopak di pusat mata hasil gambar ulang. Tekstur di balik kelopak direkonstruksi dengan warna yang diukur dari area wajah setempat. Pingochef menggerakkan bagian bawah paruh pada sambungan untuk pose makan. [Perbandingan kelopak Adult](assets/animated_monsters/previews/imagegen_adult_lids.jpg)

Reproduksi revisi dengan menambahkan `--expressions --existing-only` ke perintah batch. `--forms <slug>/<fase>` membatasi regenerasi ke satu bentuk atau daftar bentuk. [Ekspresi 01–05](assets/animated_monsters/previews/expressions_01.jpg) · [Ekspresi 06–10](assets/animated_monsters/previews/expressions_02.jpg) · [Ekspresi 11–15](assets/animated_monsters/previews/expressions_03.jpg) · [Ekspresi 16–20](assets/animated_monsters/previews/expressions_04.jpg)

## Rincian pilot Embergon Baby

## Berkas dan format

Direktori paket `assets/animated_monsters/fire_dragon/baby/` memiliki isi berikut.

| Berkas atau folder | Kegunaan |
|---|---|
| `animation_manifest.json` | Identitas, path relatif terhadap lokasi manifest, versi alat, format, klip, trigger, durasi, loop dan hasil pengujian |
| `exports/embergon_baby.obonb` | Data runtime biner OpenBone dan atlas tekstur transparan tertanam. Satu berkas berisi ketujuh klip dan state machine |
| `rig/embergon_baby.obone` | Proyek editor OpenBone yang bisa diedit. Path teksturnya relatif ke `../layers/` |
| `layers/` | PNG RGBA untuk permukaan tubuh dan attachment ekspresi |
| `source/original.png` | Salinan master Baby dari ZIP, dengan SHA-256 tercatat di manifest |
| `previews/` | Tujuh GIF pada 25 fps, pose netral transparan, contact sheet, perbandingan, dan `interactive.html` untuk mencoba trigger |

## Pemuatan lokal

1. Cari paket dengan pasangan `fire_dragon/baby`. Baca `animation_manifest.json` dan jadikan direktori manifest sebagai dasar resolusi path.
2. Bundel `exports/embergon_baby.obonb` dan manifest bersama aset aplikasi. Buka OBONB dengan runtime yang membaca format OpenBone 0.4.8 dan mendukung mesh berbobot, pergantian attachment, trigger serta transisi state machine. Atlas sudah tertanam sehingga pemutaran paket ini dapat berjalan dari penyimpanan lokal.
3. Aktifkan `EmbergonBaby` pada layer `Motion`. Artboard adalah 1024 × 1024 dengan origin skeleton di (512, 870). Gunakan fit seragam dan pertahankan padding artboard untuk lompatan dan rentang sayap.
4. Saat runtime atau paket suatu fase tidak tersedia, gunakan sprite fase tersebut dari manifest sumber. Untuk pemeriksaan di desktop, buka `previews/interactive.html` dan coba tombol trigger atau klik wajah.

Loader MamPet saat ini membaca skema `assets/monsters/<slug>/<stage>/rig.json` dan `animations.json`. Renderer itu menggambar layer dengan transformasi affine. OBONB membutuhkan runtime OpenBone dengan deformasi per verteks. Validasi paket menggunakan OpenBone MCP. Kompatibilitas, startup, konsumsi memori, dan kelancaran runtime Flutter di perangkat Android perlu diuji oleh Antigravity.

## State machine dan tindakan

| State dan klip | Durasi | Loop | Trigger | Gerak utama |
|---|---:|:---:|---|---|
| `idle` | 3,4 dtk | Ya | State awal atau `wake` | Napas, kedip, gerak kecil kepala, sayap dan ekor |
| `happy` | 1,4 dtk | Sekali | `happy` | Persiapan, lompatan gembira, kepak, pendaratan |
| `pet` | 1,0 dtk | Sekali | `pet` | Kepala miring, mata terpejam dan ekor merespons |
| `eat` | 1,8 dtk | Sekali | `eat` | Menyambut makanan, mengunyah, lalu tersenyum |
| `sleep` | 3,6 dtk | Ya | `sleep` | Mata terpejam, kepala menunduk, sayap rileks, napas panjang |
| `play` | 2,0 dtk | Sekali | `play` | Dua lompatan menyamping, berganti arah |
| `special` | 1,8 dtk | Sekali | `special` | Dua kepakan besar dan tekukan ekor susulan |

Trigger bersifat satu kali. Klik pada hitbox wajah memicu `pet`. Host dapat memicu reaksi yang sama melalui input `pet`. Gunakan satu jalur per interaksi. Semua trigger dapat berpindah dari state aktif. Reaksi sekali jalan kembali ke `idle` pada akhir klip, dengan cross-fade keluar selama 0,12 detik. Cross-fade masuk berlangsung 0,08 detik untuk reaksi, 0,11 detik untuk `sleep`, dan 0,13 detik untuk `wake`. `sleep` tetap berulang sampai ada trigger yang mengubah state, misalnya `wake`.

Saat host memutar nama klip secara langsung, gunakan properti `clips.<nama>.loop` di manifest. Pada jalur state machine, pakai konfigurasi loop bawaan. `special` adalah ekspresi spesifik naga, sedangkan evolusi adalah perubahan paket fase.

## Pergantian fase

PRD menetapkan `baby` untuk level 1–9, `young` untuk 10–24, dan `adult` untuk 25–30. Gunakan pasangan slug dan fase baru untuk mencari paket saat evolusi terjadi. Muat aset target sebelum memulai cross-fade dan mulai rig target di state awal. Jika paket fase target berstatus `review_only` atau `source_blocked`, gunakan keputusan fallback proyek untuk bentuk tersebut. Sprite sumber yang valid tetap tersedia melalui manifest inventaris.

## Rekonstruksi dan standar pilot

Mesh memakai satu tekstur permukaan untuk kepala, torso, sayap, tangan, kaki dan ekor. Bobot verteks memindahkan bagian-bagian tersebut melalui tulang masing-masing dengan peralihan bertahap di leher, bahu, pangkal sayap, pinggul dan pangkal ekor. Topologi mengikuti celah transparan antarcabang siluet sehingga kepakan sayap dapat bergerak relatif terhadap kepala dan ekor. Nama `left` dan `right` mengikuti sisi gambar yang dilihat pengguna.

Mata dan mulut memiliki attachment terpisah pada tulang kepala. Warna kulit yang awalnya tertutup direkonstruksi dari gradien piksel sekitar, kemudian garis kelopak dan senyum dilukis ulang. Kedip serta kunyah memakai pose antara. Attachment berubah secara bertahap melalui urutan pose yang digambar, sementara gerak kepala dan badan memakai kurva keyframe. Posisi setup mempertahankan mulut terbuka dari master. `idle` memakai senyum lebih tenang.

Batch menandai ulang sendi untuk setiap master. Gorila memakai tumpuan badan dan bobot bahu, burung memakai sayap serta bulu, rubah memakai telinga dan ekor, dan slime memakai squash/stretch dengan jangkar lantai. Embergon Young dan Adult memakai posisi sayap dan ekor yang berbeda dari Baby. Sproutle Young dan Adult memiliki temuan sumber yang perlu dibereskan sebelum dijadikan referensi produksi. [Inventaris aset](docs/ANIMATION_ASSET_INVENTORY.md)

Permukaan kontinu mengikuti urutan tumpang tindih master pada sudut tampak ini. Pose yang membuka bagian belakang anggota tubuh atau menukar urutan kedalaman membutuhkan ilustrasi tambahan. Renderer Canvas2D untuk gambar QA dapat menampilkan garis segitiga halus pada pembesaran. Periksa tampilannya pada perangkat dan pada ukuran UI target sebelum memakai pilot sebagai standar rilis untuk 59 bentuk lain.

## Hasil validasi pilot

- OpenBone MCP memeriksa referensi rig, ketujuh state, trigger host, klik wajah, klik di luar hitbox, serta kembali ke `idle` dan bangun dari `sleep`.
- Uji geometri pada 907 pose klip di 60 Hz tidak menemukan inversi segitiga atau mesh melampaui artboard. Uji tambahan pada 546 sampel cross-fade antara pasangan state tidak menemukan inversi.
- Contact sheet memuat 35 pose yang diperiksa secara visual. Pose awal dan akhir `idle` dan `sleep` sama pada data keyframe dan hasil render. Siluet pose setup bertumpang tindih 99,94% dengan master dari ZIP pada ambang alpha 127.
- Preview HTML lulus uji Chrome WebGL dari file lokal dalam mode offline. Trigger `sleep` dan `wake` serta klik wajah berhasil tanpa permintaan HTTP atau kesalahan JavaScript.

## Reproduksi paket

Sumber produksi ada di `tools/embergon_art.py`, `tools/embergon_clips.json`, `tools/embergon_openbone.py`, dan `tools/embergon_preview.py`. Pipeline memakai Python dengan Pillow, NumPy, SciPy dan OpenCV, serta Node.js dan `@openbone/mcp` 0.4.8. `python tools/embergon_openbone.py --resume` mengulang validasi dan ekspor dari rig yang tersimpan. `--rebuild` meregenerasi karya dan rig dari master serta data keyframe. Pengeditan manual pada rig perlu disimpan terpisah sebelum regenerasi. `--server` menerima path `dist/bin.js` dari instalasi OpenBone MCP yang sudah tersedia. Saat path itu diberikan, `tools/embergon_mesh_check.mjs` membaca kembali OBONB yang dihasilkan dan menguji inversi segitiga serta batas kanvas pada sampel 60 Hz.
