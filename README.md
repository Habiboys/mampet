# MamPet

**MamPet** adalah aplikasi **jurnal kuliner lokal-first + game koleksi monster interaktif** berbasis Flutter (Android). Catat makanan harianmu, kumpulkan koleksi **FoodDex** (612 menu kurasi + menu kustom), tetaskan telur monster, dan rawat partner monstermu hingga berevolusi!

## Fitur Utama

- **Jurnal Makanan & Galeri Foto** — Catat sesi makan (foto, rating, catatan, pengeluaran, lokasi Google Maps), rekap harian/bulanan/tahunan, galeri foto 3 kolom dengan *pinch-to-zoom*, serta fitur **Share langsung ke WhatsApp** lengkap dengan foto, deskripsi, nama tempat, dan tautan Google Maps.
- **FoodDex & Katalog 612 Menu + Custom Food** — 12 kategori kuliner (51 menu kurasi per kategori) dan dukungan penuh makanan kustom yang masuk FoodDex (`KUSTOM`), menghitung penguasaan kategori (Grade C → SS), XP discovery, dan membuka telur monster.
- **20 Spesies Monster × 3 Fase Evolusi (Baby → Young → Adult)** — Didukung runtime native **OpenBone 0.4.8 Pure-Dart (`Canvas.drawVertices`)** secara 100% offline dengan deformasi mesh berbobot, transisi *cross-fade*, ekspresi mata & mulut v2 (`idle`, `happy`, `pet`, `eat`, `sleep`, `play`, `special`), hitbox wajah (`face_touch`), dan **Animation Preview Lab**.
- **Widget Layar Beranda Android** — Partner aktif tampil langsung di *Home Screen* Android dan bereaksi saat disentuh.
- **Offline-First & Backup ZIP** — Seluruh data tersimpan lokal di SQLite dengan fitur ekspor & pemulihan cadangan ZIP.

## Persiapan Lingkungan Lokal

1. **Prasyarat**
   - Flutter SDK (`^3.14.0` Dart SDK)
   - Android SDK & JDK 17

2. **Konfigurasi Google Maps API Key (Lokal)**
   Salin `android/local.properties.example` menjadi `android/local.properties` (file ini diabaikan oleh `.gitignore`), lalu tambahkan API key Anda:
   ```properties
   flutter.sdk=C:\\flutter\\flutter
   sdk.dir=C:\\Users\\<USER>\\AppData\\Local\\Android\\sdk
   MAPS_API_KEY=YOUR_GOOGLE_MAPS_ANDROID_API_KEY
   ```
   *(Atau set environment variable `MAPS_API_KEY` sebelum build.)*

3. **Install Dependensi & Jalankan Pengujian**
   ```bash
   flutter pub get
   flutter test
   ```

4. **Sinkronisasi Aset OpenBone & Build APK Rilis**
   ```bash
   python tools/sync_pubspec_assets.py
   flutter build apk --release --split-per-abi --target-platform android-arm64,android-arm
   ```

## Dokumentasi Terkait

- [PRD Lengkap MamPet](MamPet_PRD_Lengkap_v1.md)
- [Panduan Integrasi Animasi OpenBone](ANIMATION_INTEGRATION_GUIDE.md)
- [Inventaris Aset Animasi](docs/ANIMATION_ASSET_INVENTORY.md)
