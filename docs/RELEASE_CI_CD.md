# CI/CD Rilis ke Google Play (GitHub Actions)

Workflow: [`.github/workflows/android-play-release.yml`](../.github/workflows/android-play-release.yml)

Setiap `push` ke `main` akan otomatis:

1. Checkout repo + setup JDK 17 + Flutter 3.50.1
2. Menulis ulang keystore & `android/key.properties` dari GitHub Secrets (tidak pernah di-commit)
3. `flutter build appbundle --release` dengan `versionCode = nomor run GitHub Actions`
4. Mengunggah `app-release.aab` ke Play Console track **internal**

Selain push, bisa dijalankan manual: **Actions → Android Play Release → Run workflow** (pilih track `internal` / `alpha` / `beta` / `production`).

---

## 1. Secrets yang harus diisi

Buka **GitHub repo → Settings → Secrets and variables → Actions → New repository secret**.

| Nama secret | Isi | Nilai untuk MamPet |
| --- | --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Isi file `android/upload-keystore.jks` yang di-encode base64 | lihat perintah di bawah |
| `ANDROID_KEYSTORE_PASSWORD` | Password keystore | password keystore Anda |
| `ANDROID_KEY_PASSWORD` | Password key (biasanya sama) | sama dengan di atas |
| `ANDROID_KEY_ALIAS` | Alias key di keystore | `mampet` |
| `PLAY_SERVICE_ACCOUNT_JSON` | Seluruh isi file JSON service account Google Play | dari langkah 3 |
| `MAPS_API_KEY` | Google Maps Android API Key | `AIzaSy...` (key yang dipakai di `android/local.properties`) |

> `MAPS_API_KEY` sebenarnya selalu bisa dibaca dari APK/AAB, jadi ini bukan rahasia ketat — tapi tetap disimpan sebagai secret supaya tidak di-hardcode di repo.

### Membuat `ANDROID_KEYSTORE_BASE64`

Jalankan di root project (Git Bash / Linux / macOS):

```bash
base64 -w0 android/upload-keystore.jks > /tmp/keystore.b64
# Windows Git Bash: kalau `-w0` tidak dikenal, pakai
#   base64 android/upload-keystore.jks | tr -d '\n' > /tmp/keystore.b64
cat /tmp/keystore.b64   # salin seluruh isi (satu baris panjang) ke secret
rm /tmp/keystore.b64
```

Atau lewat GitHub CLI, tanpa menyalin manual:

```bash
gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 -w0 android/upload-keystore.jks)
gh secret set ANDROID_KEYSTORE_PASSWORD --body "PASSWORD_ANDA"
gh secret set ANDROID_KEY_PASSWORD     --body "PASSWORD_ANDA"
gh secret set ANDROID_KEY_ALIAS        --body "mampet"
gh secret set PLAY_SERVICE_ACCOUNT_JSON < play-service-account.json
gh secret set MAPS_API_KEY             --body "AIzaSy..."
```

**Jangan pernah commit / upload `upload-keystore.jks` dan `key.properties`** — sudah di-ignore oleh `.gitignore` dan `android/.gitignore`. Simpan backup keystore + password di tempat aman: kalau hilang, aplikasi tidak bisa di-update lagi di Play (kecuali pakai Play App Signing key rotation).

---

## 2. Hal yang harus disiapkan sekali di Play Console

1. **App harus sudah ada** di Play Console dengan package name `com.habiboys.mampet` dan minimal **satu AAB ter-upload manual** (mis. `build/app/outputs/bundle/release/app-release.aab`). Google Play API tidak bisa membuat app baru.
2. Aktifkan **Play App Signing** (disarankan) supaya upload key bisa di-reset bila bocor.
3. Selesaikan **App content** wajib (privacy policy, data safety, rating, target audience) — kalau belum, rilis ke track apa pun akan ditolak.

---

## 3. Membuat service account Google Play

1. Buka [Google Cloud Console](https://console.cloud.google.com/) → buat/pilih project.
2. **APIs & Services → Library → Google Play Android Developer API → Enable**.
3. **IAM & Admin → Service Accounts → Create service account** (nama bebas, tidak perlu role GCP).
4. Buka service account → **Keys → Add key → Create new key → JSON** → file JSON ter-download. Isi file inilah nilai `PLAY_SERVICE_ACCOUNT_JSON`.
5. Salin email service account (`xxx@xxx.iam.gserviceaccount.com`).
6. Buka **Play Console → Users and permissions → Invite new users** → tempel email itu → beri izin:
   - **App permissions**: pilih app MamPet, centang *Releases* (minimal: Release to testing tracks / Manage testing tracks; untuk production: *Release to production, exclude devices, and use Play App Signing*).
   - **Account permissions**: *View app information and download bulk reports* sudah cukup.
7. Kirim undangan, lalu **terima** undangan tersebut dari akun service account? Tidak perlu — akses aktif setelah undangan dikirim untuk service account.

---

## 4. Soal `versionCode`

Workflow memakai `--build-number="$((GITHUB_RUN_NUMBER + 100))"`, jadi versionCode naik otomatis setiap run dan Play tidak menolak dengan error *"Version code X has already been used"*.

Pembagian nomor: build manual/lokal memakai versionCode **1–99**, CI mulai dari **101** dan naik satu setiap run. Jadi AAB pertama yang di-upload manual (versionCode 1) tidak akan bentrok dengan run CI pertama.

`versionName` tetap diambil dari `pubspec.yaml` (`version: 1.0.0+1` → `1.0.0`). Naikkan manual saat rilis fitur:

```yaml
version: 1.1.0+1
```

Kalau suatu saat nomor CI ketinggalan di bawah build manual (mis. setelah upload manual berulang), cukup naikkan offset di langkah build, mis. `+ 1000`.

---

## 5. Sebelum push pertama

```bash
flutter analyze
flutter test
```

Workflow ini **tidak** menjalankan test — tujuannya build & deploy. Kalau ingin test jadi gerbang, tambahkan step `flutter test` sebelum langkah build.

---

## 6. Troubleshooting

| Gejala | Penyebab / solusi |
| --- | --- |
| `Secret ANDROID_KEYSTORE_BASE64 belum diisi` | Secret belum dibuat atau nama salah. |
| `Keystore gagal didekode` | Base64 terpotong/terbungkus newline. Pastikan satu baris penuh. |
| `APK or Bundle signed with the wrong key` | AAB ditandatangani keystore berbeda dari yang terdaftar. Pakai `android/upload-keystore.jks` yang sama. |
| `Version code ... has already been used` | Lihat bagian 4 (offset build number). |
| `The caller does not have permission` | Service account belum di-invite di Play Console atau izin release belum dicentang. |
| `Package not found` | App `com.habiboys.mampet` belum ada di Play Console (upload AAB manual sekali). |
| Upload sukses tapi tidak muncul | Rilis `completed` di track internal tetap butuh waktu propagasi; cek tab *Internal testing*. |
