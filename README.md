# sicilik

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Pelan Makanan Anak dan AI

Pelan doktor dalam `users/{uid}/growth_children/{childId}.nutritionPlans`
diutamakan. Apabila tiada pelan doktor, menu ilustrasi mengikut umur kekal
tersedia. Fungsi AI memilih daripada katalog yang disemak dan menyimpan hasil
dalam dokumen `nutrition_days/{YYYY-MM-DD}` milik anak. Pemilihan model hanya
melibatkan ID resipi yang dibenarkan. Katalog menentukan sukatan, cara penyediaan
dan nilai nutrien. Tarikh lahir, nama anak, ID pengguna dan ukuran tumbesaran
kekal dalam siCILIK.

### Sediakan katalog

Tambahkan map `mealPlanning` pada resipi Firestore selepas kandungannya disemak.
Gunakan medan berikut.

| Medan | Maksud |
| --- | --- |
| `reviewed` | Boolean yang ditetapkan oleh penyemak katalog |
| `minAgeMonths`, `maxAgeMonths` | Julat umur inklusif dalam bulan |
| `texture` | Tekstur yang sepadan dengan `functions/kkm.json` |
| `slots` | Kod waktu makan yang dibenarkan dalam `functions/kkm.json` |
| `allergens` | Senarai alergen daripada bahan, termasuk senarai kosong yang disahkan |
| `ingredients` | Senarai map dengan `name`, `group`, `quantity` dan `unit` |
| `serving`, `benefits`, `imageUrl` | Sukatan, penerangan yang disemak, dan URL foto pilihan |
| `nutrientSource` | Rujukan komposisi yang disahkan, termasuk pautan/jadual dan asas sukatan |
| `verifiedNutritionPerServing` | Nilai bagi satu hidangan. `energy` dalam kcal, `protein` dalam g, `calcium` dan `iron` dalam mg |

Medan `name` dan senarai `steps` resipi sedia ada turut digunakan. Kumpulan
bahan ialah Karbohidrat, Protein, Sayur-sayuran, Buah-buahan, Produk Tenusu dan
Bahan Masakan. Tinggalkan medan nutrien yang tiada sumber. Semak nilai dengan
sumber komposisi yang berwibawa sebelum memasukkannya. Julat tenaga dalam
`functions/kkm.json` berasal daripada ilustrasi A hingga K dalam folder
rujukan dan merupakan contoh menu harian.

### Sediakan Firebase

1. Pasang kebergantungan dengan `npm install` dalam folder `functions`.
2. Tetapkan `GEMINI_API_KEY` sebagai secret Functions dengan
   `firebase functions:secrets:set GEMINI_API_KEY --project si-cilik`.
3. Tetapkan parameter `GEMINI_MODEL` semasa deploy. Pilih model Gemini yang
   menyokong output JSON berstruktur. Fungsi menggunakan rantau
   `asia-southeast1` dan ID projek daripada Firebase Auth.
4. Semak peraturan Firestore yang sedang aktif. Pemilik akaun memerlukan akses
   baca ke dokumen `nutrition_days` anaknya, dan akses menulis hanya medan
   `intake`, `intakeUpdatedAt` serta `drinks` di situ. Pemilik juga perlu
   boleh mengemas kini `foodAllergies`, `foodPreferences` dan
   `availableIngredients` pada profil anaknya. Simpan kuasa menulis
   `generatedPlan`, `nutritionAnalysis`, `nutrition_controls` serta menanda
   resipi sebagai disemak pada pelayan atau peranan pentadbir yang sesuai.
   Semak juga peraturan lebih umum yang boleh memberi akses tambahan.
5. Deploy fungsi dengan
   `firebase deploy --only functions:generateNutritionPlan --project si-cilik`.

Contoh penambahan untuk laluan hari pemakanan dalam peraturan sedia ada:

```text
match /users/{uid}/growth_children/{childId}/nutrition_days/{day} {
  function owner() { return request.auth != null && request.auth.uid == uid; }
  allow read: if owner();
  allow create: if owner() &&
    request.resource.data.keys().hasOnly(['intake', 'intakeUpdatedAt', 'drinks']);
  allow update: if owner() &&
    request.resource.data.diff(resource.data).affectedKeys()
      .hasOnly(['intake', 'intakeUpdatedAt', 'drinks']);
}
```

Dokumen sedia ada digunakan semula dan tiada pemindahan destruktif. Mesej
“Rekod pengambilan tidak dapat dimuatkan” muncul jika bacaan Firestore gagal.
Jika mesej menyatakan akses disekat, semak peraturan bagi laluan
`nutrition_days`. “Tiada sasaran” bermaksud pelan doktor belum mempunyai
nilai sasaran. Padanan resipi memerlukan umur dan nilai nutrien yang boleh
dibaca. Penjanaan AI memerlukan cukup resipi disemak untuk semua waktu makan.

Ujian tempatan boleh dijalankan dengan `flutter test test/nutrition_test.dart`
dan `npm test` dari folder `functions`.
