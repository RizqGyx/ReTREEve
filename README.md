<div align="center">
  <img src="ReTREEve/IconReTREEve.icon/Assets/Image.png" alt="Ikon ReTREEve" width="112" height="112">

  <h1>ReTREEve</h1>

  <p>
    <strong>Simpan passage yang bermakna. Temukan kembali meski hanya sebagian yang diingat.</strong><br>
    Aplikasi iOS untuk menangkap passage dari buku fisik, menyimpannya, dan menemukannya kembali dari partial memory.
  </p>

  <p>
    <img src="https://img.shields.io/badge/Platform-iOS%2026%2B-000000?logo=apple" alt="iOS 26+">
    <img src="https://img.shields.io/badge/Swift-5-orange?logo=swift" alt="Swift 5">
    <img src="https://img.shields.io/badge/UI-SwiftUI-007AFF" alt="SwiftUI">
    <img src="https://img.shields.io/badge/Data-SwiftData-5E5CE6" alt="SwiftData">
    <img src="https://img.shields.io/badge/Search-Hybrid%20Retrieval-2E7D32" alt="Hybrid Retrieval">
  </p>
</div>

---

## Tentang proyek

ReTREEve adalah aplikasi iOS untuk membantu pembaca buku fisik menyimpan passage yang mereka anggap bermakna dan menemukannya kembali ketika dibutuhkan, bahkan ketika mereka hanya mengingat sebagian kata, topik, situasi, atau maknanya.

Passage dapat ditambahkan dengan memindai halaman yang sudah ditandai, mengimpor foto, atau memasukkannya secara manual. Saat mencari kembali, pengguna tidak perlu mengingat kalimat secara persis; ReTREEve menampilkan beberapa possible matches dari koleksi mereka sendiri.

> Proyek ini menargetkan **iOS 26.0** dan memakai framework Apple terbaru, termasuk Foundation Models. Jalankan pada Xcode/SDK yang mendukung iOS 26.

## Fitur utama

### Tangkap insight dari buku

- **Pindai halaman bertanda** — Kamera mengambil halaman, Vision membaca teks, dan model Core ML memberi saran area passage yang ditandai.
- **Pilih cara lain bila perlu** — Impor foto dari pustaka atau tulis passage secara manual; input manual selalu tersedia, termasuk di Simulator.
- **Konfirmasi sebelum menyimpan** — Pengguna memilih dan dapat mengoreksi passage, lalu melengkapi judul buku, penulis, halaman, dan catatan pribadi.

### Temukan kembali dari ingatan samar

- **Pencarian hybrid** — BM25 menjadi sinyal utama, diperluas dengan istilah semantik dan dibantu sentence embedding untuk memecahkan hasil yang setara.
- **Bukti yang dapat dilihat** — Hasil menampilkan *possible matches* beserta kata atau frasa yang menghubungkannya dengan query.
- **Dikte suara** — Ucapkan apa yang masih diingat untuk mengisi kolom pencarian, lalu gunakan mesin pencarian yang sama seperti input ketik.

### Library yang tumbuh bersama pembaca

- **Library per buku** — Jelajahi dan buka kembali insight berdasarkan buku.
- **Pohon ReTREEve** — Pohon di layar utama tumbuh berdasarkan insight yang disimpan dan yang berhasil ditemukan kembali.
- **Penyimpanan lokal** — Insight disimpan melalui SwiftData pada perangkat.

## Teknologi

| Komponen | Teknologi |
| --- | --- |
| Bahasa & UI | Swift 5 dan SwiftUI |
| Persistensi | SwiftData |
| Kamera & media | AVFoundation dan PhotosUI |
| OCR | Vision |
| Deteksi passage bertanda | Core ML (`BookAnnotationDetector.mlpackage`) |
| Pencarian | BM25, NaturalLanguage (`NLEmbedding`), dan ekspansi semantik |
| Dikte | Speech dan AVFoundation |
| Model generatif opsional | Foundation Models / Apple Intelligence |

Tidak ada dependency pihak ketiga atau Swift Package yang perlu diinstal.

## Menjalankan aplikasi

1. Buka [ReTREEve.xcodeproj](ReTREEve.xcodeproj) di Xcode.
2. Pilih scheme **ReTREEve**.
3. Pilih perangkat iOS 26 atau lebih baru, lalu jalankan (`⌘R`).

Simulator cocok untuk meninjau UI dan alur input manual/foto. Pemindaian kamera memerlukan perangkat fisik yang memiliki kamera. Bila Apple Intelligence tidak tersedia, aplikasi tetap berjalan: penyimpanan dan pencarian literal tetap dapat dipakai, tetapi perluasan semantik tidak dijalankan.

Saat peluncuran pertama, aplikasi membuat lima insight contoh agar alur library dan pencarian dapat langsung dicoba. Insight pengguna dan data contoh disimpan secara lokal di penyimpanan SwiftData aplikasi.

## Cara menggunakan

1. Dari layar utama, pilih **New Insight**.
2. Pilih **Scan a Marked Page**, impor foto, atau **Type Manually**.
3. Untuk hasil scan/foto, pilih passage yang ingin disimpan; periksa dan edit bila OCR kurang tepat.
4. Tambahkan informasi buku dan catatan pribadi, lalu simpan insight.
5. Saat ingin menemukannya lagi, buka **Find Again** dan tulis atau ucapkan ide, suasana, atau situasi yang masih diingat.
6. Tinjau *possible matches*, buka hasil yang cocok, lalu konfirmasi **Found It** untuk mencatat penemuan kembali.

## Izin dan privasi

| Izin | Kegunaan |
| --- | --- |
| Kamera | Memotret halaman buku untuk OCR dan pemilihan passage. |
| Mikrofon | Merekam input dikte untuk kolom pencarian. |
| Pengenalan ucapan | Mengubah ucapan menjadi teks pencarian. |

Foto halaman diproses di perangkat. Dikte memakai pengenalan on-device apabila locale mendukungnya; untuk locale yang tidak mendukung, konfigurasi saat ini mengizinkan transkripsi oleh Apple dan UI memberi tahu pengguna. Input ketik tetap lokal.

## Cara kerja pencarian

Setiap insight menyimpan teks kutipan, metadata buku, catatan pribadi, dan—jika model tersedia—frasa alternatif yang dibuat saat insight disimpan. Saat pengguna mencari:

1. Query dapat diperluas menjadi istilah sehari-hari yang berkaitan.
2. BM25 memberi sinyal utama dari teks, judul buku, penulis, catatan, dan frasa alternatif.
3. Sentence embedding hanya membantu mengurutkan hasil dengan bukti leksikal yang setara; embedding tidak dapat mengalahkan hasil tanpa kecocokan kata.
4. Hasil yang terlalu lemah disaring, lalu aplikasi menampilkan maksimal lima *possible matches* beserta kata/frasa pendukungnya.

Perluasan model memiliki batas waktu lima detik untuk query. Jika model belum siap, tidak tersedia, atau melewati batas waktu, pencarian otomatis kembali ke pencarian leksikal tanpa menghambat pengguna.

```text
Ingatan pembaca
      │
      ▼
Ekspansi query opsional ──► BM25 atas passage, metadata, catatan, dan frasa alternatif
                                      │
                                      ▼
                         Embedding sebagai pemecah seri
                                      │
                                      ▼
                    Maks. 5 possible matches + bukti kecocokan
```

## Benchmark retrieval

Eksperimen retrieval berada di [`Benchmarks/`](Benchmarks). Ini adalah skrip Swift mandiri, bukan target aplikasi:

```bash
cd Benchmarks
swift RetrievalBenchmark.swift
```

Benchmark memakai lima insight contoh dan sepuluh query yang diingat sebagian. Hasil eksperimen dan catatan keterbatasannya tersedia di [Benchmarks/README.md](Benchmarks/README.md). Berkas `docexp.json` menyimpan cache perluasan dokumen agar sisi indeks konsisten antarrun.

## Struktur proyek

```text
ReTREEve/
├── Capture/       Kamera, import foto, OCR, deteksi penanda, dan pemilihan passage
├── Design/        Tema, latar, dekorasi, dan komponen visual
├── Model/         Model SwiftData, data contoh, dan pertumbuhan pohon
├── Onboarding/    Alur onboarding
├── Retrieval/     Indeks teks, pencarian hybrid, ekspansi, dan dikte
├── Views/         Layar utama, library, pencarian, detail, dan editor insight
└── Assets.xcassets/
Benchmarks/        Harness dan data eksperimen retrieval
```

## Batasan saat ini

- Kualitas pencarian semantik bergantung pada ketersediaan Apple Intelligence; tanpa itu hasil mengandalkan kecocokan leksikal.
- Benchmark masih memakai korpus kecil, sehingga belum mewakili library besar atau banyak insight yang mirip.
- Pemindaian langsung tidak tersedia di Simulator; jalur input manual selalu tersedia sebagai alternatif.

## Lisensi & Kontak

Dikembangkan oleh **Muhammad Rizki**.
