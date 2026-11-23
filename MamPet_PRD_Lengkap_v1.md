# MamPet — Product Requirements Document (PRD)

Versi 1.0 • 22 November 2026 • Flutter Android-first • local-first

[Ilustrasi: Aset resmi MamPet: karakter dari 20 spesies × 3 fase evolusi]

| Versi dokumen | Status | Platform awal |
| --- | --- | --- |
| 1.0 • 22 November 2026 | Baseline implementasi; balancing dapat direvisi | Flutter • Android-first • local-first |

Dokumen ini adalah spesifikasi kerja end-to-end untuk desain UI/UX, pengembangan Flutter, struktur database, aturan game, penggunaan aset, pengujian, dan kriteria rilis. Semua nama monster ditetapkan sebagai nama kerja resmi MamPet v1 sampai disetujui ulang.

Cakupan aset tersedia: 60 PNG monster (20 Baby + 20 Young + 20 Adult), 12 PNG telur (6 elemen × utuh/retak). File PRD dilengkapi konfigurasi JSON terpisah agar aturan tidak ditulis ulang secara manual.

# Ringkasan eksekutif

MamPet adalah aplikasi mobile pencatatan pengalaman makan. Pengguna menyimpan nama hidangan, foto, deskripsi, harga, waktu dan lokasi; menemukan jenis makanan baru untuk mengisi FoodDex; dan mengembangkan monster melalui XP dari sesi makan. Penemuan kuliner memicu telur spesies baru; tiga sesi makan valid setelah inkubasi membuka animasi penetasan dan monster Baby. Semua 20 spesies terlihat di MonsterDex, sedangkan yang terkunci memakai siluet hitam dan label ???.

| Pilar | Perilaku inti | Hasil pengguna |
| --- | --- | --- |
| Catat | 1 sesi makan berisi ≥1 item makanan | Riwayat, harga, foto pribadi |
| Temukan | ID makanan baru di katalog master | FoodDex dan progres kategori |
| Pelihara | XP ke tepat 1 monster aktif | Level, evolusi, Bond dan Grade |
| Koleksi | Penuhi target unik/hari per kategori | Telur 6 elemen dan 20 spesies |
| Eksplorasi | Lokasi opsional + peta pin | Riwayat pengalaman kuliner |

# Daftar isi

1. Tujuan, prinsip, dan cakupan

2. Persona dan user journey

3. Arsitektur informasi dan navigasi

4. FoodDex dan katalog makanan

5. Pencatatan sesi makan dan validasi

6. Aturan XP dan progres harian

7. Katalog 20 monster MamPet

8. Rarity, Grade, Level, Evolusi, Bond

9. Telur, inkubator, dan penetasan

10. MonsterDex: kartu terbuka dan siluet terkunci

11. Peta kuliner, lokasi, dan harga

12. Desain layar dan komponen UI

13. Model data, indeks, dan transaksi

14. Arsitektur Flutter dan offline-first

15. Spesifikasi aset & animasi

16. Privasi, keamanan, aksesibilitas

17. Edge cases & anti-penyalahgunaan

18. Acceptance criteria dan QA

19. Roadmap pengembangan dan risiko

20. Lampiran konfigurasi dan referensi

# 1. Tujuan, prinsip, dan cakupan

## 1.1 Masalah dan peluang

Pencatatan kuliner biasanya berhenti pada foto atau daftar tempat, sementara game koleksi monster sering tidak terhubung dengan kegiatan sehari-hari. MamPet menggabungkan keduanya: satu catatan makan tetap berguna sebagai jurnal, dan secara opsional memberi progres visual yang menyenangkan.

## 1.2 Tujuan produk

- Mencatat makanan dengan ≤ 6 interaksi inti setelah menu dipilih; foto/harga/lokasi dapat dilewati.
- Menyediakan daftar makanan unik berdasarkan ID katalog, bukan kemiripan gambar.
- Menampilkan 20 spesies monster yang konsisten dengan file aset yang telah dibuat.
- Membuat progres game terasa stabil tanpa mendorong makan berlebihan atau menghabiskan uang.
- Memberikan tampilan peta dan statistik harga tanpa menjadikan lokasi syarat wajib.
- Bekerja tanpa akun atau server untuk fungsi inti pada Android.
## 1.3 Sasaran pengguna

| Persona | Kebutuhan | Pertimbangan |
| --- | --- | --- |
| Pencatat kuliner kasual | Mengingat apa, kapan, dan di mana makan | Form cepat dan foto opsional |
| Kolektor monster | Membuka siluet, telur dan evolusi | Milestone jelas dan adil |
| Penjelajah kuliner | Mencatat tempat dan harga | Pin peta, riwayat dan filter |
| Pengguna rumahan | Tetap berkembang tanpa sering bepergian | Alternatif syarat berbasis hari |

## 1.4 Batasan MVP

Termasuk: Android Flutter; onboarding lokal; FoodDex 12 kategori, master ≥300 item; catatan sesi makan; 20 spesies; telur dan penetasan; level hingga 30; 5 Grade; 3 rarity; enam elemen; MonsterDex siluet; peta pin; ekspor/impor cadangan; statistik dasar.

Tidak termasuk: AI pengenal foto, battle, trading, marketplace, leaderboards online, login wajib, cloud sync, GPS tracking pasif, sistem hunger yang menghukum, pengiriman push, atau penetasan berbasis pembayaran.

## 1.5 Prinsip desain

- Catatan tidak sama dengan penemuan: sesi makan, jenis makanan, dan tempat harus dibedakan.
- Makanan mahal tidak memberi XP, rarity, atau Grade lebih tinggi.
- Tidak ada hukuman karena tidak makan atau tidak membuka aplikasi.
- Rarity adalah sifat spesies; Grade adalah penguasaan kategori; Level berasal dari XP.
- Fitur lokal tetap bekerja saat offline, kecuali pemuatan peta dasar dari provider.
- Setiap aturan pemberian XP dan telur dapat diaudit melalui ledger transaksi.
# 2. Persona dan alur pengguna

## 2.1 Onboarding pertama kali

1. Splash → pilih nama panggilan (opsional) → perkenalan FoodDex dan MonsterDex.
1. Pilih satu starter: Foxili (Api), Sproutle (Alam), atau Axolumi (Air); semuanya Common, Level 1, Grade C.
1. Monster tersimpan sebagai milik pengguna dan otomatis menjadi monster aktif; starter tidak menggunakan telur.
1. Tutorial singkat menambahkan sesi makan dan satu item dari master makanan.
1. Setelah simpan berhasil, beranda menampilkan XP pertama, progres kategori dan tombol Catat.
## 2.2 Alur mencatat

```
Beranda / FAB Catat → pilih waktu/jenis sesi → cari makanan master atau tambah custom
→ isi item (foto, catatan, harga) → tambah item lain (opsional)
→ pilih tempat/pin (opsional) → pratinjau → Simpan
→ transaksi atomik → XP (jika valid) + penemuan FoodDex (jika baru)
→ cek milestone telur dan Grade → popup hasil → kembali Beranda
```

## 2.3 Alur pembukaan monster

```
Kategori mencapai milestone → telur diberikan sekali → masuk antrean telur
→ pengguna memilih telur untuk inkubator (satu aktif)
→ 3 sesi makan berhadiah berikutnya → telur Retak → tombol Tetaskan
→ shake → kilat + fade telur → Baby muncul → MonsterDex terbuka
→ aktifkan monster (opsional)
```

## 2.4 Alur evolusi dan MonsterDex

```
Monster aktif terima XP → Level 10 → animasi transisi Baby→Young
→ Level 25 → transisi Young→Adult → level maksimal 30
MonsterDex awal: 20 siluet hitam / ??? / gembok
Setelah hatch: gambar Baby terbuka; Young/Adult tetap siluet sampai level tercapai
```

# 3. Arsitektur informasi dan navigasi

| Halaman | Isi utama | Aksi |
| --- | --- | --- |
| Beranda | Monster aktif, level/XP, ringkasan makan, telur aktif, CTA | Catat; ganti pet; lihat hasil |
| Catat | Sesi, item, katalog, harga, foto, lokasi, jenis sesi | Simpan draf/sesi |
| FoodDex | Kategori, filter, kartu ditemukan/terkunci | Cari, lihat jenis dan riwayat |
| MonsterDex | 20 slot, siluet, rarity, kategori, filter | Lihat detail, aktifkan, Nursery |
| Peta | Pin tempat, detail lokasi, riwayat & filter harga | Pilih lokasi, lihat riwayat |
| Profil/Pengaturan | Statistik, ekspor/impor, privasi, tema | Backup, reset dan preferensi |

Navigasi utama disarankan: bottom bar Beranda, Catat, FoodDex, MonsterDex, Peta. Nursery diakses dari MonsterDex dan kartu telur pada Beranda. Statistik lanjutan dan Pengaturan melalui avatar di kanan atas.

## 3.1 Empty states

- FoodDex kosong: “Belum ada makanan yang kamu temukan” + CTA Catat Makanan.
- MonsterDex: setiap slot tetap terlihat, disamarkan sebagai siluet dan “???”; starter terbuka.
- Peta kosong: ilustrasi pin + ajakan menambahkan tempat pertama.
- Nursery kosong: “Telur baru muncul setelah kamu menjelajahi makanan dalam kategori.”
- Offline: data tetap dapat disimpan, peta menampilkan daftar tempat dan pemberitahuan tile tidak tersedia.
# 4. FoodDex: kategori, katalog dan keunikan

## 4.1 Dua tingkat identitas makanan

Master Food adalah jenis hidangan yang dikurasi (contoh nasi goreng); Meal Item adalah kejadian makan aktual (contoh nasi goreng dari Warung A seharga Rp18.000). Pemain dapat mencatat jenis master yang sama berkali-kali; hanya penemuan pertama per akun yang dihitung sebagai hidangan unik.

| Contoh | Jenis master | FoodDex | Log & peta |
| --- | --- | --- | --- |
| Nasi goreng, dua kali di rumah | Satu food_id | 1 ditemukan | 2 log, tempat opsional |
| Nasgor vs nasi goreng | Alias → food_id sama | Tidak bertambah | Riwayat bertambah |
| Nasi goreng seafood | food_id varian lain | +1 jika disetujui | Harga independen |
| Makanan custom baru | custom_food_id | Belum dihitung master | Tetap sah untuk log |

## 4.2 Dua belas kategori dan target seed

| Kategori | Contoh |
| --- | --- |
| Nasi & Serealia | nasi goreng, nasi uduk, risotto |
| Mie & Pasta | mie ayam, ramen, spaghetti |
| Roti & Adonan | roti canai, pizza, sandwich |
| Sup & Berkuah | bakso, soto, pho |
| Lauk & Protein | rendang, ayam bakar, telur balado |
| Ikan & Seafood | sushi, ikan bakar, udang |
| Sayur & Nabati | gado-gado, capcay, salad |
| Camilan Asin | cireng, tahu isi, takoyaki |
| Kue & Dessert | puding, es krim, martabak manis |
| Buah & Olahannya | rujak, salad buah, fruit bowl |
| Kopi & Teh | kopi susu, cappuccino, teh tarik |
| Minuman Lain | jus, susu, smoothie |

Target seed v1: minimal 300, ideal 300–500 hidangan yang telah ditinjau, dengan minimal 25 varian valid pada tiap kategori supaya target Grade SS (18 jenis) dan Rare (12 jenis) mungkin tercapai. Sumber eksternal perlu dikurasi, dideduplicasi dan ditinjau lisensinya; jumlah resep tidak sama dengan jumlah jenis hidangan unik.

## 4.3 Aturan normalisasi tanpa AI

- Input dicari menggunakan case-insensitive dan trim, Unicode-normalization, spasi berlebih, serta alias eksplisit.
- Pencarian “nasgor”, “nasi goreng” memetakan ke food_id sama; perbedaan “nasi goreng seafood” dipertahankan jika master varian tersedia.
- Satu hidangan hanya memiliki satu kategori utama; tag banyak-ke-banyak boleh ada untuk pencarian/filter.
- Penambahan custom tidak langsung menambah angka discovery master/grade/telur; pemain masih boleh memilih kategori dan tetap mendapat XP sesi.
- Jika item custom di kemudian hari dikurasi, lakukan mapping custom→master, lalu jalankan rekonsiliasi penemuan dan hadiah sekali saja.
## 4.4 Standar metadata master

foods: id UUID atau kode stabil, canonical_name, locale, category_id, description, origin_region, status (active/inactive), created_at, updated_at. food_aliases: id, food_id, alias, normalized_alias. Tag dan subkategori bersifat opsional di MVP.

# 5. Pencatatan makan: field dan validasi

| Field | Wajib | Aturan |
| --- | --- | --- |
| meal_sessions.id, occurred_at | Ya | Waktu lokal; default sekarang; backdate diperbolehkan untuk riwayat |
| meal_type | Ya | breakfast / lunch / dinner / snack / other |
| meal_items.food_id atau custom_id | Ya | Harus tepat salah satu |
| meal_items.price | Tidak | Integer minor unit, ≥0; Rp tanpa desimal jika mata uang IDR |
| meal_items.description | Tidak | Catatan bebas max 500 karakter |
| meal_items.photo_path | Tidak | File lokal app-private; gambar otomatis dikompresi |
| meal_sessions.place_id | Tidak | Satu sesi satu tempat; opsi Rumah/Tidak diketahui |
| meal_items.quantity | Tidak | Default 1; tidak memengaruhi XP |
| rating | Tidak | 1–5, tidak memengaruhi XP |

Satu sesi dapat berisi banyak item. Harga total sesi dihitung dari jumlah harga masing-masing item (jika tersedia); harga kosong tidak diasumsikan nol. Foto boleh per item. Waktu dan tempat level sesi, tetapi bila dibutuhkan nanti dukung override tempat per item.

## 5.1 Aturan perubahan dan penghapusan

Penyimpanan harus atomik. Jika terjadi edit/hapus, ledger XP dan milestone dihitung ulang secara deterministik dari sesi yang valid agar reward tidak dobel. Perubahan pada tanggal lampau tidak membuat sesi lama mendadak memberi XP baru. Makanan custom yang diubah ke master dapat menambahkan discovery, tetapi reward dicatat satu kali dengan idempotency key.

# 6. XP, level dan pembatasan harian

| Sumber XP | XP | Batas |
| --- | --- | --- |
| Sarapan pertama yang berhak pada hari itu | 10 | 1 / hari |
| Makan siang pertama | 10 | 1 / hari |
| Makan malam pertama | 10 | 1 / hari |
| Camilan pertama | 5 | 1 / hari |
| Food master baru ditemukan | 5 | maksimal 3 jenis / hari |

Maksimum normal adalah 50 XP per hari (35 sesi + 15 discovery). Slot dihitung menurut meal_type dan tanggal lokal pengguna. Tipe “other” tetap tercatat tanpa XP; lebih dari satu sesi jenis sama tetap boleh, tetapi hanya sesi yang pertama valid mendapat XP. Bonus penemuan mengikuti urutan transaksi log valid hari itu dan tidak pernah diberikan untuk food_id yang sudah ditemukan.

## 6.1 Syarat sesi berhadiah

- occurred_at berada pada tanggal lokal saat pencatatan dan bukan tanggal masa depan.
- Minimal satu item makanan valid; harga, foto dan lokasi tidak diwajibkan.
- Satu sesi berhadiah per jenis sarapan/siang/malam/camilan per hari.
- Tidak memberikan XP dengan menambah item atau mengganti jenis sesi berulang-ulang.
- Bila monster aktif belum ada (misal data sedang direstorasi), XP dicatat sebagai pending dan diproses sesudah sistem stabil.
## 6.2 Level

```
xp_to_next_level(L) = 15 + 3 * (L - 1), untuk L = 1..29
XP total dari Level 1 sampai Level N = (N-1)*15 + 3*(N-1)*(N-2)/2
Level cap = 30; kelebihan XP tidak menaikkan level lagi.
```

| Level | XP kumulatif | Fase |
| --- | --- | --- |
| 1 | 0 | Baby |
| 5 | 78 | Baby |
| 10 | 243 | Young |
| 15 | 483 | Young |
| 20 | 798 | Young |
| 25 | 1.188 | Adult |
| 30 | 1.653 | Adult |

XP dari satu sesi diberikan kepada tepat satu monster aktif pada waktu transaksi. Mengganti monster tidak memindahkan XP lampau. Evolusi otomatis pada Lv10 dan Lv25, dengan layar perayaan yang dapat dilewati. Tidak ada degradasi level karena lama tidak membuka game.

# 7. Katalog resmi 20 spesies MamPet

Nama berikut merupakan identitas resmi untuk implementasi MamPet v1 dan setiap slug cocok dengan folder aset ZIP yang sudah ada. Nama elemen berasal dari konsep game, sedangkan rarity merupakan aturan yang ditetapkan untuk pengalaman koleksi (bukan kualitas gambar).

| ID | Nama | Slug aset | Kategori | Elemen | Rarity |
| --- | --- | --- | --- | --- | --- |
| 01 | Embergon | fire
dragon | Lauk & Protein | Api | Rare |
| 02 | Grovongo | leaf
gorilla | Sayur & Nabati | Alam | Uncommon |
| 03 | Zephlet | sky
bird | Mie & Pasta | Angin | Common |
| 04 | Foxili | fox | Lauk & Protein | Api | Common |
| 05 | Bubblu | water
slime | Sup & Berkuah | Air | Uncommon |
| 06 | Sproutle | leaf
spirit | Buah & Olahannya | Alam | Common |
| 07 | Axolumi | pink
axolotl | Sup & Berkuah | Air | Common |
| 08 | Cacopaw | dessert
panda | Kue & Dessert | Misteri | Common |
| 09 | Bellmori | lamb | Nasi & Serealia | Bumi | Uncommon |
| 10 | Crustello | bread
turtle | Roti & Adonan | Bumi | Common |
| 11 | Marinox | sea
dragon | Ikan & Seafood | Air | Rare |
| 12 | Mossolith | moss
golem | Nasi & Serealia | Bumi | Common |
| 13 | Puddinghoul | dessert
ghost | Kue & Dessert | Misteri | Rare |
| 14 | Mellibee | bee
moth | Kopi & Teh | Angin | Common |
| 15 | Frostelle | ice
fox | Minuman Lain | Air | Common |
| 16 | Floradeer | forest
deer | Buah & Olahannya | Alam | Uncommon |
| 17 | Pingochef | chef
penguin | Ikan & Seafood | Air | Common |
| 18 | Stellacat | mage
cat | Kopi & Teh | Misteri | Uncommon |
| 19 | Sporella | mushroom | Camilan Asin | Alam | Common |
| 20 | Bambalu | bamboo
panda | Sayur & Nabati | Alam | Common |

Distribusi rarity: 12 Common, 5 Uncommon, 3 Rare. Tiga starter: Foxili, Sproutle, dan Axolumi. Rare dapat ditemukan lewat eksplorasi kategori—tidak berasal dari pembelian atau peluang acak.

## 7.1 Identitas, cara mendapatkannya, dan karakter

#01 Embergon — Naga api; sayap dan tanduk. Kategori Lauk & Protein; elemen Api; rarity Rare. Buka: 12 hidangan unik + 6 hari kategori.

#02 Grovongo — Gorila penjaga hutan berdaun. Kategori Sayur & Nabati; elemen Alam; rarity Uncommon. Buka: 8 hidangan unik + 4 hari kategori.

#03 Zephlet — Burung langit biru-putih. Kategori Mie & Pasta; elemen Angin; rarity Common. Buka: 3 hidangan unik + 2 hari kategori.

#04 Foxili — Rubah api ekor mengembang. Kategori Lauk & Protein; elemen Api; rarity Common. Buka: Starter atau 3 hidangan unik + 2 hari.

#05 Bubblu — Slime air berbentuk tetes. Kategori Sup & Berkuah; elemen Air; rarity Uncommon. Buka: 8 hidangan unik + 4 hari kategori.

#06 Sproutle — Roh tanaman berdaun. Kategori Buah & Olahannya; elemen Alam; rarity Common. Buka: Starter atau 3 hidangan unik + 2 hari.

#07 Axolumi — Axolotl merah muda. Kategori Sup & Berkuah; elemen Air; rarity Common. Buka: Starter atau 3 hidangan unik + 2 hari.

#08 Cacopaw — Panda dessert cokelat-ceri. Kategori Kue & Dessert; elemen Misteri; rarity Common. Buka: 3 hidangan unik + 2 hari kategori.

#09 Bellmori — Domba berpita dan lonceng gandum. Kategori Nasi & Serealia; elemen Bumi; rarity Uncommon. Buka: 8 hidangan unik + 4 hari kategori.

#10 Crustello — Kura-kura bercangkang roti. Kategori Roti & Adonan; elemen Bumi; rarity Common. Buka: 3 hidangan unik + 2 hari kategori.

#11 Marinox — Naga laut bersirip. Kategori Ikan & Seafood; elemen Air; rarity Rare. Buka: 12 hidangan unik + 6 hari kategori.

#12 Mossolith — Golem batu-lumut. Kategori Nasi & Serealia; elemen Bumi; rarity Common. Buka: 3 hidangan unik + 2 hari kategori.

#13 Puddinghoul — Hantu puding dengan stroberi. Kategori Kue & Dessert; elemen Misteri; rarity Rare. Buka: 12 hidangan unik + 6 hari kategori.

#14 Mellibee — Lebah-moth madu. Kategori Kopi & Teh; elemen Angin; rarity Common. Buka: 3 hidangan unik + 2 hari kategori.

#15 Frostelle — Rubah es berekor awan. Kategori Minuman Lain; elemen Air; rarity Common. Buka: 3 hidangan unik + 2 hari kategori.

#16 Floradeer — Rusa bunga dan dedaunan. Kategori Buah & Olahannya; elemen Alam; rarity Uncommon. Buka: 8 hidangan unik + 4 hari kategori.

#17 Pingochef — Penguin juru masak. Kategori Ikan & Seafood; elemen Air; rarity Common. Buka: 3 hidangan unik + 2 hari kategori.

#18 Stellacat — Kucing penyihir bintang. Kategori Kopi & Teh; elemen Misteri; rarity Uncommon. Buka: 8 hidangan unik + 4 hari kategori.

#19 Sporella — Makhluk jamur berpayung. Kategori Camilan Asin; elemen Alam; rarity Common. Buka: 3 hidangan unik + 2 hari kategori.

#20 Bambalu — Panda pemegang bambu. Kategori Sayur & Nabati; elemen Alam; rarity Common. Buka: 3 hidangan unik + 2 hari kategori.

## 7.2 Data teknis spesies

Setiap monster memiliki species_id, slug, display_name, category_id, element_id, rarity_id, flavor_text, unlock_rule, asset_baby, asset_young, asset_adult. Pemain memiliki instance user_monsters terpisah, dengan species_id, level, total_xp, bond, active_flag, unlocked_at. Per kategori maksimal dua spesies pada rilis awal.

# 8. Visual rarity, Grade, Level, evolusi dan Bond

## 8.1 Rarity: sinyal visual yang jelas

| Rarity | Warna / pola kartu | Treatment UI | Aturan buka |
| --- | --- | --- | --- |
| Common | Slate #94A3B8 • lingkaran | Border 2 px, latar abu hangat, label COMMON | 3 unik + 2 hari kategori atau starter |
| Uncommon | Teal #14B8A6 • heksagon | Border 2 px, latar mint, detail kilau tipis | 8 unik + 4 hari kategori |
| Rare | Violet #8B5CF6 • bintang | Border 3 px, tint ungu + aura ringan | 12 unik + 6 hari kategori |

[Ilustrasi: Contoh kartu rarity dari aset Baby yang telah dibuat: warna + bingkai + label + ikon]

Rarity tidak boleh disampaikan hanya dengan warna. Gunakan label teks, bentuk ikon, ketebalan/pola border, dan dukungan aksesibilitas. Monster terkunci tidak membocorkan rarity asli: semua memakai kartu gelap netral dan label ???.

## 8.2 Grade berdasarkan penguasaan kategori

| Grade | Jumlah jenis unik | Syarat tambahan | Perubahan visual |
| --- | --- | --- | --- |
| C | 0 | Default saat monster didapat | Badge dasar |
| B | 3 | Tidak ada | Badge + dekorasi kecil |
| A | 6 | Tidak ada | Bingkai grade |
| S | 10 | ≥2 tempat berbeda ATAU ≥5 tanggal makan kategori | Efek glow halus |
| SS | 18 | ≥4 tempat berbeda ATAU ≥10 tanggal makan kategori | Aura kosmetik + badge SS |

“Tanggal makan kategori” berarti tanggal kalender unik dengan setidaknya satu sesi makan yang berhak memperoleh XP dan memuat hidangan master dari kategori tersebut. Catatan tanggal lampau (backdate) tidak menambah jumlah hari untuk unlock/Grade. Tempat berbeda menggunakan place_id, bukan perubahan koordinat beberapa meter. Jalur hari sebagai alternatif memastikan pengguna yang memasak di rumah tidak dirugikan.

Grade dihitung dinamis dari per-kategori discovery dan riwayat, bukan lewat item yang dapat dibeli; harga tidak boleh digunakan. Kenaikan Grade tidak menaikkan jumlah XP secara eksponensial.

## 8.3 Tiga fase evolusi

| Fase | Level | Aset | Perubahan |
| --- | --- | --- | --- |
| Baby | 1–9 | baby.png | Siluet kecil dan ekspresi lucu |
| Young | 10–24 | young.png | Ukuran dan identitas elemen berkembang |
| Adult | 25–30 | adult.png | Perubahan bentuk akhir dan detail menonjol |

## 8.4 Bond: kosmetik, bukan tekanan

Bond 0–100 dapat bertambah melalui interaksi sederhana dengan cooldown, misalnya tap pet/interaksi harian; Bond 20/50/80 dapat membuka ekspresi atau animasi dekoratif universal. Tidak ada pengurangan Bond karena pengguna absen, tidak ada kematian monster, dan tidak ada kewajiban memberi makan hewan secara terpisah dari jurnal.

# 9. Telur dan inkubator

## 9.1 Enam elemen, dua visual state

| Elemen | Aset normal | Aset retak |
| --- | --- | --- |
| Api | 01_fire_intact.png | 01_fire_cracked.png |
| Air | 02_water_intact.png | 02_water_cracked.png |
| Alam | 03_nature_intact.png | 03_nature_cracked.png |
| Angin | 04_wind_intact.png | 04_wind_cracked.png |
| Bumi | 05_earth_intact.png | 05_earth_cracked.png |
| Misteri | 06_mystery_intact.png | 06_mystery_cracked.png |

## 9.2 State machine penetasan

```
LOCKED → ELIGIBLE → EGG_GRANTED → QUEUED → INCUBATING_0/3
→ INCUBATING_1/3 → CRACKED_2/3 → READY_3/3
→ HATCH_ANIMATION → MONSTER_UNLOCKED → ARCHIVED
```

Telur diberikan maksimal sekali per spesies. Satu inkubator aktif, antrean telur boleh banyak. Progres hanya bertambah ketika sesi makan berhadiah XP tersimpan setelah waktu inkubasi dimulai; maksimal satu increment per meal_session_id. Tidak ada timer real-time atau monetisasi. Pada progres 2/3 pakai cracked.png; saat 3/3 tombol Tetaskan tersedia.

## 9.3 Animasi penetasan (Flutter biasa)

- Normal: gerak mengambang ±6 px, 2,0–2,8 detik per loop.
- Menuju retak: shake ±3–6°, 2–3 kali pendek, cross-fade ke cracked.png.
- Siap: pulsasi scale 1,00→1,06→1,00 dan glow elemen.
- Ketika “Tetaskan”: shake cepat 0,6 detik → white-flash 0,25 detik → telur fade out → gambar Baby scale 0,7→1,07→1,0 dengan confetti 1 detik.
- Tombol “Lewati” langsung menetapkan state MONSTER_UNLOCKED, tanpa kehilangan hadiah.
Saat rilis, gunakan kombinasi AnimatedBuilder/AnimationController/TweenAnimationBuilder; tidak perlu sprite sheet atau GIF. Efek kilau/partikel diletakkan di layer Flutter dan dimatikan jika pengguna mengaktifkan Reduce Motion.

# 10. MonsterDex: siluet terkunci

[Ilustrasi: Mockup kartu monster terkunci: bentuk Baby disamarkan hitam, nama ??? dan gembok]

## 10.1 Katalog utama

Tampilkan grid dua kolom di ponsel, 20 slot dengan ID tetap (#001–#020). Saat belum ditemukan, gambar Baby disamarkan menjadi siluet gelap penuh dengan alpha dari PNG; detail warna/aset tidak terbuka, nama “???”, ikon gembok, rarity disembunyikan. Identitas hanya bisa dibuka setelah telur ditetaskan; membuka halaman kategori tidak otomatis membuka spesies.

## 10.2 Detail monster terkunci

Halaman detail menampilkan nomor, siluet, progres syarat yang tidak membocorkan nama untuk Rare, dan CTA “Jelajahi makanan kategori”. Contoh: “Sup & Berkuah: 2/3 makanan unik • 1/2 hari”. Untuk misteri Rare gunakan petunjuk kategori dan progres, bukan menampilkan desain atau nama sebelum terbuka.

## 10.3 Detail monster terbuka

Tampilkan nama, gambar sesuai fase, rarity card, elemen, kategori, Level, progress XP, Grade, Bond, timeline evolusi, tombol Jadikan Aktif, statistik penemuan kategori. Fase yang belum dicapai tetap siluet dengan label “Lv 10” dan “Lv 25”, walaupun monster Baby sudah terbuka.

## 10.4 Filter

Filter Semua / Terkunci / Terbuka, Elemen, Rarity (hanya terbuka), Kategori, Fase, dan sort Nomor/Abjad/Level. Progres “x/20 dikoleksi” menghitung spesies hatch, bukan telur yang diperoleh.

# 11. Peta kuliner dan harga

## 11.1 Definisi tempat

place.id, display_name, lat, lng, optional address, source (manual/device/search), privacy (private/public_future). Koordinat rumah tidak dipublikasikan. Dua catatan di tempat yang sama menggunakan place_id sama; tempat baru ditentukan melalui pilihan manual atau hasil pencarian, bukan hanya jarak GPS.

## 11.2 Fitur utama peta

- Marker kumpulan tempat pribadi; klik marker → daftar sesi dan makanan di tempat tersebut.
- Filter kategori, rentang harga, tanggal, serta tempat yang pernah dikunjungi.
- Pilih titik lokasi ketika mencatat; pemain bisa memberi label tempat sendiri.
- Tanpa lokasi, catatan tetap sah, masih bisa dihitung ke FoodDex dan XP.
- Offline: daftar lokasi tersimpan tetap dapat diakses; tile map tidak dijanjikan offline.
## 11.3 Harga dan statistik

Harga disimpan pada meal_items dalam integer minor unit atau model Money(currency, amount_minor); IDR ditampilkan Rp. Gunakan median/riwayat harga per jenis/tempat hanya dari catatan yang memiliki nominal. Jumlah pengeluaran menghitung item yang memiliki harga, dengan label “sebagian catatan tanpa harga” jika tidak lengkap. Harga bukan faktor XP/grade/rarity.

# 12. Spesifikasi layar dan komponen UI

| Screen | Bagian utama | Acceptance UX |
| --- | --- | --- |
| Splash / Onboarding | Logo, intro 3 layar, starter choice | Boleh skip intro; starter harus dipilih |
| Beranda | Hero monster aktif, XP, ringkasan, telur | CTA Catat selalu terlihat |
| Catat sesi | Jenis makan, waktu, list item, tempat | Dapat tambah beberapa item dalam satu sesi |
| Pencarian makanan | Search, alias, kategori, recent | Tampil “tidak ada” + Tambah Custom |
| Reward | XP breakdown, discovery, telur | Bisa tutup; reward tidak hilang |
| FoodDex | Kategori, ditemukan/belum, riwayat | Jumlah unik tidak mengikuti jumlah log |
| MonsterDex | 20 grid, filter, lock silhouettes | Locked = silhouette + ???; unlocked = full art |
| Detail monster | Art fase, level, grade, rarity, bond | Fase berikutnya tertutup sampai level |
| Nursery | Telur queue, 1 inkubator aktif, progress | Sesi valid → progress; hatch dapat dilewati |
| Peta | Marker, detail, filter, list fallback | Tetap berguna bila GPS ditolak |
| Settings | Backup, restore, privasi, reduce motion | Reset memerlukan konfirmasi eksplisit |

## 12.1 Pedoman visual

Tema: hangat, ramah, clean 2D cartoon. Ukuran sentuh minimal 44–48dp; gunakan gambar PNG transparan sebagai overlay kartu, hindari menambahkan bayangan permanen dalam aset. Rarity: base neutral/slate, mint/teal, violet. Grade menggunakan badge kecil terpisah sehingga tidak rancu dengan Rarity. Gunakan label teks dan ikon bentuk untuk aksesibilitas buta warna.

## 12.2 Contoh microcopy

- “Makanan baru ditemukan! +5 XP”
- “Kamu sudah punya catatan makanan ini. Riwayatnya tetap tersimpan!”
- “Telur Air ditemukan. Masukkan ke inkubator untuk mulai menetaskan.”
- “2/3 sesi makan valid menuju penetasan.”
- “??? — Temukan lebih banyak hidangan untuk mengungkap monster ini.”
# 13. Data model, indeks dan transaksi

## 13.1 Skema tabel utama

| Tabel | Kolom penting / unique constraint |
| --- | --- |
| profiles | id; display_name; locale; timezone; currency; starter_selected |
| food_categories | id; slug unique; name; icon; sort_order |
| foods | id; category_id; canonical_name; description; status; unique normalisasi per scope |
| food_aliases | id; food_id; normalized_alias; UNIQUE(normalized_alias,locale) sesuai kebijakan |
| food_tags / food_tag_links | tag_id; food_id; opsional |
| custom_foods | id; local owner; name; category_id; mapped_food_id nullable |
| places | id; name; lat; lng; address; privacy; source |
| meal_sessions | id; profile_id; occurred_at; meal_type; place_id; created_at |
| meal_items | id; session_id; food_id XOR custom_id; price_minor; photo_path; notes |
| food_discoveries | id; profile_id; food_id; first_meal_item_id; UNIQUE(profile_id,food_id) |
| monster_species | id; slug; category_id; element; rarity; asset paths; unlock_json |
| user_monsters | id; profile_id; species_id; level; xp_total; bond; is_active; UNIQUE(profile_id,species_id) |
| monster_eggs | id; profile_id; species_id; status; hatch_progress; incubated_at |
| reward_ledger | id; profile_id; source_event_id; reward_type; value; monster_id; idempotency_key UNIQUE |
| schema_migrations / app_settings | versioned schema / reduced_motion / last_backup |

## 13.2 Diagram relasi konseptual

```
PROFILE 1──N MEAL_SESSIONS 1──N MEAL_ITEMS N──1 FOODS N──1 FOOD_CATEGORIES
                 │                 └── N:1 CUSTOM_FOODS
                 └── N:1 PLACES
PROFILE 1──N FOOD_DISCOVERIES N──1 FOODS
PROFILE 1──N USER_MONSTERS N──1 MONSTER_SPECIES N──1 FOOD_CATEGORIES
PROFILE 1──N MONSTER_EGGS N──1 MONSTER_SPECIES
PROFILE 1──N REWARD_LEDGER
```

Semua status unlock dihasilkan dari transaksi atau dapat dihitung ulang dari sumber event. Source of truth untuk FoodDex adalah kombinasi meal_items valid + relasi master; cache denormalisasi diperbolehkan untuk kecepatan tetapi harus bisa dibangun ulang.

## 13.3 Event dan idempotensi

```
onSaveMealSession(session):
  BEGIN TRANSACTION
  persist(session, items)
  if qualifies_for_today_session_reward(session):
      award_once("session:{id}", xp_for_slot, current_active_monster)
      increment_active_egg_once("incubation:{egg}:{session}")
  for food_id in distinct(master_food_ids_in_session):
      if not previously_discovered(profile, food_id):
          add_discovery(profile, food_id)
          if daily_discovery_bonus_slots_remaining():
              award_once("discovery:{profile}:{food_id}", 5, active_monster)
  reevaluate_monster_grade_and_egg_eligibility(profile)
  COMMIT
```

Implementasi nyata perlu membedakan basis reward sesi dari penemuan, serta memastikan meal_session tidak dapat digunakan berkali-kali untuk inkubator yang sama. Simpan event monotonic dan lakukan re-evaluasi transaksional ketika edit/hapus mengubah status pencapaian.

# 14. Arsitektur Flutter: offline-first

| Lapisan | Usulan teknologi | Alasan |
| --- | --- | --- |
| UI | Flutter Material 3 + tema MamPet | Komponen UI mobile lintas platform |
| State management | Riverpod / BLoC (pilih satu saja) | State terukur dan testable |
| Database lokal | SQLite via Drift | Relasi, migrasi, query dan reactive updates |
| File foto | App documents directory + thumbnail/cache | Gambar lokal, tidak membebani DB |
| Peta | flutter_map + penyedia tile patuh kebijakan | Titik dan marker kustom |
| Animasi | AnimationController, Tween, AnimatedSwitcher | Tanpa GIF/spritesheet |
| Routing | go_router / router sejenis | Navigasi deklaratif |
| Serialisasi | JSON seed katalog + migrasi SQL | Pembaruan master data terkontrol |

## 14.1 Kebijakan offline

Fungsi Catat, FoodDex, MonsterDex, Nursery, XP, Grade, dan daftar tempat harus berjalan offline. Peta online dapat memakai flutter_map; layanan tile disediakan oleh provider sesuai ketentuan dan atribusi yang tepat. Jangan bulk-download tile dari server publik OpenStreetMap. Untuk MVP Android tidak memerlukan backend. Bila nantinya ingin sinkronisasi lintas perangkat, desain table id UUID dan updated_at sudah memudahkan migrasi.

## 14.2 Backup dan restore

Ekspor ZIP berisi snapshot database, foto, manifest, schema_version, checksum; berikan opsi penyimpanan ke lokasi yang dipilih pengguna. Restore membuat backup sementara lebih dulu, memvalidasi integritas dan versi sebelum menimpa data. Data pribadi tidak dikirim otomatis ke server.

## 14.3 Struktur modul kode

```
lib/
  app/ (theme, routes, bootstrap)
  core/ (db, files, clock, localization, errors)
  features/food_catalog/
  features/meal_log/
  features/food_dex/
  features/monster_dex/
  features/eggs/
  features/map/
  features/profile_backup/
assets/monsters/<slug>/{baby,young,adult}.png
assets/eggs/<element>/{intact,cracked}.png
```

# 15. Spesifikasi aset dan animasi

Aset saat ini telah diverifikasi dari arsip sebelumnya: 20 folder spesies berisi masing-masing baby.png, young.png dan adult.png, serta 12 telur utuh/retak. Semua art inti ditujukan untuk gambar satu karakter penuh berlatarkan transparan. Gunakan 1024×1024 master dan buat ukuran turun jika profiling memerlukan penghematan memori.

| Aset | Jumlah | Konvensi |
| --- | --- | --- |
| Monster Baby / Young / Adult | 60 | assets/monsters/<slug>/<phase>.png |
| Telur 6 elemen × 2 state | 12 | assets/eggs/<element>/(intact/cracked).png |
| Ikon elemen / rarity / grade | Tambahan UI | SVG atau ikon Flutter; belum termasuk paket 72 gambar |
| SFX hatch/level-up | Opsional | Singkat, bisa dimatikan |

## 15.1 Transformasi gerak MVP

Idle: floating ±4–8px (2–3 detik), scale napas 0,98–1,02, rotasi ±1–2°. Tap: bounce 1,00→1,07→0,98→1,00. Evolusi: cross-fade/scale antara fase, confetti sederhana. Kedipan mata sejati dan flap sayap artikulatif tidak bisa dibuat akurat dari satu PNG utuh; untuk MVP cukup whole-body motion, sementara layer mata/sayap baru dibuat pada rilis lanjutan jika diperlukan.

## 15.2 Siluet

Siluet memakai alpha PNG baby yang tersedia kemudian diberi fill warna #17202B dengan opasitas tinggi (misal ColorFiltered/BlendMode.srcIn) dan filter gelap; jangan memodifikasi aset asli. Tampilkan lock overlay, “???”, dan border netral. Mask hanya untuk UI—semua aset tetap terbundel di aplikasi secara teknis.

# 16. Privasi, keamanan, aksesibilitas

- Foto dan lokasi adalah data pribadi: penyimpanan lokal, izin kamera/lokasi hanya saat dibutuhkan; fallback manual.
- Hindari menyimpan GPS akurat pada log jika pengguna memilih “Rumah (tanpa pin)” atau “Tidak diketahui”.
- Tidak melakukan tracking lokasi di background atau upload data otomatis.
- Ekspor berisi data pribadi: tampilkan peringatan sebelum membagikan file backup.
- Tampilan rarity tidak hanya warna, wajib label dan ikon; teks skalabel dan kontras yang layak.
- Opsi Reduce Motion meniadakan goyangan berkepanjangan dan memperpendek animasi hatch.
- Tidak memberi bonus berdasar harga, porsi berlebihan, makanan mahal atau kalori.
- Tidak ada hukuman untuk pengguna yang hanya makan dua kali atau tidak mencatat pada suatu hari.
## 16.1 Performa dan kualitas

Target: first meaningful screen ≤3 detik di perangkat Android kelas menengah pada data lokal seed; interaksi simpan ≤500 ms untuk sesi 1–5 item setelah media sudah disiapkan; scroll 20 monster dan FoodDex tetap mulus dengan lazy loading. Angka ini merupakan target produk untuk diuji, bukan hasil benchmark. Cache thumbnail dari art besar dan kompres gambar foto agar memori tetap wajar.

# 17. Edge cases dan aturan anti-eksploitasi

| Kasus | Perilaku yang diharapkan |
| --- | --- |
| Makan nasi goreng 5 kali dalam sehari | 1 penemuan master dan XP berdasarkan slot, bukan 5 hadiah penuh |
| Satu sesi berisi 5 menu baru | Masing-masing FoodDex baru, hanya 3 bonus discovery hari itu |
| Menambah sesi tanggal kemarin | Riwayat diperbarui, tidak mendapat XP sesi hari ini |
| Mengubah nasi goreng jadi alias nasgor | Tidak mengubah food_id; tidak memperoleh penemuan kedua |
| Lokasi ditolak sistem | Simpan tanpa lokasi; peta dapat menampilkan daftar |
| Telur didapat saat inkubator penuh | Masuk antrean, tidak hilang |
| Dapat telur spesies starter | Hadiah kosmetik/poin mastery pengganti, bukan duplikat |
| Monster maksimal Level 30 | XP yang melebihi batas tidak menaikkan level lagi |
| Pengguna mengganti monster aktif saat simpan | Penentuan monster saat commit transaksi; hanya satu penerima |
| Aplikasi mati di tengah hatch | Status reward persisten; hatch dapat ditampilkan ulang bila perlu |
| Impor backup lama | Validasi versi, migrasi, tidak menambahkan hadiah dua kali |
| Jam ponsel diubah | Pencegahan terbatas local-first; terapkan ledger/tanggal terakhir, jangan klaim anti-cheat penuh |

# 18. Acceptance criteria dan QA

| ID | Kondisi uji | Hasil lulus |
| --- | --- | --- |
| AC-01 | Fresh install | Tiga starter tampil; pilih satu dan menjadi aktif |
| AC-02 | Log makanan master baru | Sesi tersimpan; food_discoveries +1; XP sesuai slot |
| AC-03 | Log makanan master sama | Riwayat bertambah; FoodDex tetap satu |
| AC-04 | Log satu sesi 3 item | Hanya 1 XP sesi, bonus discovery ≤3 |
| AC-05 | Buka 20 slot MonsterDex | Slot lengkap; locked = black silhouette + ??? + lock |
| AC-06 | Melengkapi 3/8/12 unik dan hari | Telur Common/Uncommon/Rare tepat satu kali |
| AC-07 | Inkubasi tiga sesi valid | Status 0→1→2(retak)→3(siap)→unlock |
| AC-08 | Level 10 dan 25 | Aset berubah Baby→Young→Adult; XP tetap utuh |
| AC-09 | Grade tercapai | Grade memenuhi alternatif tempat/hari kategori |
| AC-10 | Perangkat tanpa internet | Catat, FoodDex, MonsterDex, telur tetap berfungsi |
| AC-11 | Lokasi tidak diberi | Tidak memblokir catatan atau XP |
| AC-12 | Ekspor lalu restore | Log, foto, monster, XP dan telur identik |
| AC-13 | Delete/edit lalu retry | Tidak ada XP atau telur ganda |
| AC-14 | Reduce Motion aktif | Animasi intens diganti transisi sederhana |

## 18.1 Rencana pengujian

Unit: formula XP, level cap, discovery aliases, threshold rarity/Grade, reward ledger, inkubator. Integration: simpan/edit/hapus dalam database transaction, export/restore, migrasi katalog. Widget: form catat, 20 kartu silhouette, rarity, timer/progres penetasan. Manual: izin kamera/lokasi, offline, font besar, perangkat layar kecil, penggunaan memori.

# 19. Roadmap eksekusi

| Sprint | Ruang lingkup | Definition of done |
| --- | --- | --- |
| S0 • Fondasi | Flutter project, routing, theme, local DB, import 300+ makanan & aset | Build Android + CI unit test |
| S1 • Journal | Sesi, item, custom food, harga, foto, edit/hapus | Log offline & pencarian normalisasi |
| S2 • FoodDex | Penemuan, kategori, alias, progres | Jumlah unik konsisten & duplicate-safe |
| S3 • MonsterDex | 20 katalog, siluet, rarity, detail, 3 fase | Semua 60 aset tampil benar |
| S4 • Gamifikasi | XP, Level, Grade, milestone, ledger | Skenario AC-01..AC-09 lulus |
| S5 • Nursery | 6 telur, 2 state, antrean, hatch anim | 3 sesi memberi progres tepat |
| S6 • Map & backup | Lokasi, marker, filter harga, ZIP backup | Offline fallback & restore lulus |
| S7 • QA rilis | Performansi, a11y, stabilitas, feedback pengguna | UAT dan checklist privasi tuntas |

## 19.1 Risiko dan mitigasi

| Risiko | Mitigasi |
| --- | --- |
| Katalog berisi bahan, bukan hidangan | Kurasi manual; minimal 25 master per kategori |
| Makanan custom dipakai spam hadiah | Custom memberi XP sesi saja, bukan discovery sebelum mapping |
| Terlalu lama membuka Rare | Pantau median pengguna; threshold configurable via seed config |
| Kualitas aset adult tidak selalu seragam | QA art per spesies dan cropping thumbnail |
| Peta online melanggar kebijakan tile | Provider patuh kebijakan; atribusi; jangan bulk prefetch |
| Aplikasi tanpa akun kehilangan data | Ekspor/import backup sejak MVP |
| Foto memenuhi storage | Kompresi dan kontrol hapus cache |
| Pengguna merasa wajib makan banyak | Hadiah dari variasi dan sesi, bukan porsi/kalori |

## 19.2 KPI produk (opsional, lokal)

Tanpa analytics jarak jauh, tampilkan ringkasan pribadi: jumlah sesi makan, jenis unik FoodDex, kategori paling beragam, tempat dikunjungi, monster unlock, tingkat penyelesaian evolusi, dan rata-rata catatan per minggu. Jika suatu hari analytics telemetry ditambahkan, wajib opt-in dengan kebijakan privasi jelas.

# 20. Lampiran, keputusan dan referensi

## 20.1 Keputusan final yang dibekukan untuk pengembangan MVP

- Nama aplikasi: MamPet; nama lama FoodDex Monsters hanya placeholder terdahulu.
- Platform prioritas Android Flutter, local-first, tanpa AI dan tanpa login wajib.
- 20 spesies, 3 fase, Level maksimal 30, 6 elemen, 3 rarity, Grade C sampai SS.
- Starter Foxili, Sproutle, Axolumi; bonus XP tidak bergantung foto/lokasi/harga.
- Satu spesies satu monster; semua unlock deterministik dari master discovery dan hari kategori.
- Satu inkubator aktif dan tiga sesi makan valid untuk menetas.
- Rarity jelas lewat border + background + ikon + label; MonsterDex terkunci menggunakan siluet hitam dan ???.
- 60 aset monster dan 12 aset telur yang sudah dibuat menjadi sumber referensi asset path.
## 20.2 File pendukung

monster_collection_60_complete_flutter.zip — 20 folder spesies, baby.png, young.png, adult.png, monster_manifest.json. egg_assets_flutter.zip — 12 PNG telur, egg_manifest.json. MamPet_game_config_v1.json — roster, unlock threshold, XP, hatching, grade, elemen dan asset path yang diselaraskan dengan PRD ini.

## 20.3 Referensi publik untuk tim engineering

- Flutter Animations: https://docs.flutter.dev/ui/animations
- Flutter AnimationController API: https://api.flutter.dev/flutter/animation/AnimationController-class.html
- Drift (SQLite for Flutter): https://pub.dev/packages/drift
- flutter_map: https://pub.dev/packages/flutter_map
- OpenStreetMap tile usage policy: https://operations.osmfoundation.org/policies/tiles/
- Wikidata: https://www.wikidata.org/ (untuk calon sumber data makanan, tetap perlu kurasi dan cek lisensi)
- Open Food Facts: https://world.openfoodfacts.org/ (lebih cocok pangan kemasan dibanding menu restoran)
Catatan balancing: ambang 3/8/12 makanan unik, hari kategori 2/4/6, Grade SS 18 jenis, dan 50 XP harian adalah hipotesis desain. Validasi dengan 5–10 pengguna sebelum rilis publik.
