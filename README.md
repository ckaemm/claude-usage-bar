# Claude Usage Bar

Claude planınızın **5 saatlik oturum** ve **haftalık** limit yüzdelerini macOS menü çubuğunda gösteren native bir uygulama (Swift + SwiftUI, macOS 13+).
Her şey yerelde çalışır. Uygulama ağa hiç çıkmaz ve hiçbir veriyi dışarı göndermez.

- **Menü çubuğu:** `5s %46 · 7g %19`. Ayarlardan yalnızca 5 saatlik yüzde ya da yalnızca ikon seçilebilir.
- **Popover:** İki limit için yüzde çubuğu, sıfırlanmaya geri sayım ve son güncelleme zamanı.
- **Eşik bildirimi:** Örneğin %80 geçildiğinde, her pencere için bir kez.
- **Diğer ayarlar:** login'de başlatma, Claude Code status line köprüsünü tek tıkla kurma/kaldırma.

Yüzdeler Claude Code'un kendi status line verisinden gelir; uygulama tahmin yapmaz.

## Gereksinimler

- macOS 13 Ventura veya üstü
- Swift 6 araç zinciri: Xcode **ya da** yalnızca Command Line Tools (`xcode-select --install`)
- Harici bağımlılık yoktur.

## Derleme ve çalıştırma

```bash
./build.sh              # release derler, build/ClaudeUsageBar.app üretir (ad-hoc imzalı)
open build/ClaudeUsageBar.app
```

`/Applications` altına kurmak için:

```bash
./build.sh --install
open /Applications/ClaudeUsageBar.app
```

Ardından status line köprüsünü kurun (bkz. [Veri kaynağı](#veri-kaynağı-claude-code-status-line)):
Menü çubuğu ikonu › ⚙︎ Ayarlar › Claude Code bağlantısı › **Kur**.

Uygulama Dock'ta görünmez (`LSUIElement`); yalnızca menü çubuğunda yaşar. Kapatmak için popover'daki ⏻ butonunu kullanın veya ⌘Q'ya basın.

Geliştirme sırasında:

```bash
swift build && .build/debug/ClaudeUsageBar          # uygulamayı paketlemeden çalıştırır (bildirimler devre dışı)
.build/debug/ClaudeUsageBar --dump                   # terminalde yerel log token özeti (bkz. aşağıda)
./test.sh                                            # gizlilik kontrolü + birim testleri (Swift Testing)
```

> `test.sh`, yalnızca Command Line Tools kurulu makinelerde `swift test` Swift Testing testlerini
> bulamadığı için testleri küçük bir çalıştırıcıyla başlatır. Xcode kuruluysa düz `swift test` kullanılır.

## Login'de otomatik başlatma (Login Items)

**Yöntem 1: uygulama içinden (önerilen)**

1. Uygulamayı `/Applications` altına kurun: `./build.sh --install`.
2. `/Applications/ClaudeUsageBar.app` uygulamasını açın.
3. Menü çubuğu ikonu › ⚙︎ Ayarlar › **Login'de otomatik başlat** seçeneğini açın.
4. macOS onay isterse **Sistem Ayarları › Genel › Giriş Öğeleri**'nden uygulamaya izin verin. Ayarlardaki "Aç" butonu bu sayfaya götürür.

Bu yöntem `SMAppService.mainApp` kullanır. Uygulamayı yeniden derleyip kurduktan sonra seçeneği bir kez kapatıp açmanız gerekebilir.

**Yöntem 2: elle**

1. **Sistem Ayarları › Genel › Giriş Öğeleri** sayfasını açın.
2. "Oturum Açıldığında Aç" listesindeki **+** butonuna basın.
3. `/Applications/ClaudeUsageBar.app` uygulamasını seçin.

## Veri kaynağı: Claude Code status line


5 saatlik oturum ve haftalık limit yüzdeleri, Claude Code'un [status line](https://code.claude.com/docs/en/statusline) mekanizmasından gelir. Claude Code, status line script'ine stdin üzerinden bir JSON gönderir. Bu JSON'daki ilgili alanlar şunlardır (şema resmi dokümandan doğrulandı):

```json
"rate_limits": {
  "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
  "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
}
```

- `used_percentage` 0–100 arası bir sayıdır. `resets_at` Unix epoch saniyesidir.
- `rate_limits` yalnızca **claude.ai Pro/Max** girişinde ve oturumdaki ilk API yanıtından sonra gelir. **API anahtarıyla girişte hiç gelmez.**
- Pencereler ayrı ayrı eksik olabilir. Claude Code, `resets_at` zamanı geçen pencereyi JSON'dan çıkarır.
- Status line API token'ı harcamaz.

**Nasıl çalışır:** Kurulum, `~/.claude-usage-bar/statusline.sh` köprü script'ini `~/.claude/settings.json` içindeki `statusLine` ayarına bağlar.

- Script bağımlılık kullanmaz; saf bash'tir ve çağrı başına yaklaşık 10 ms sürer.
- Girdide `rate_limits` varsa JSON'u **oturum başına ayrı** bir dosyaya, `~/.claude-usage-bar/limits/<session_id>.json`'a, **atomik** yazar: önce geçici dosyaya yazar, sonra `mv` ile taşır. Dosya izni `0600`, klasör izni `0700` olur.
- Neden oturum başına dosya: Her Claude Code oturumu yalnızca kendi son API yanıtındaki yüzdeyi bilir. Tek dosya olsaydı, boşta duran bir oturum eski değeriyle (ör. %34) etkin oturumun güncel değerini (ör. %42) ezebilirdi. Uygulama tüm oturum dosyalarını birleştirir:
  - Daha geç `resets_at` değeri daha yeni pencereyi gösterir ve o tercih edilir.
  - Aynı pencerede kullanım yalnızca artabildiği için en yüksek yüzde alınır.
  - 8 günden eski oturum dosyaları uygulama açılırken silinir.
- `rate_limits` içermeyen girdiler (API anahtarlı oturum, ilk yanıttan önceki çağrılar) mevcut veriyi ezmez.
- Hiçbir hatada çıktıyı bozmaz ve her zaman 0 koduyla çıkar.
- Claude Code'un alt satırında `5s %23 · 7g %41` gösterir.
- Uygulama `~/.claude-usage-bar` klasörünü FSEvents ile izler. Yüzdeler ve geri sayım bu dosyadan hesaplanır.
- Dosya yoksa veya veri 15 dakikadan eskiyse kartta **"Claude Code çalışırken güncellenir"** notu çıkar. Claude Code kapalıyken veri güncellenmez.

**Kurulum ve kaldırma**

- Uygulamada: Ayarlar › Claude Code bağlantısı › **Kur** / **Kaldır**.
- Terminalde:

  ```bash
  build/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar --install-statusline
  build/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar --uninstall-statusline
  ```

Kurulum sırasında:

- `settings.json` içinde **yalnızca** `statusLine` anahtarı değişir. Önce `~/.claude-usage-bar/settings.backup.json` adıyla yedek alınır.
- Dosya geçerli JSON değilse kurulum hiçbir şeye dokunmadan durur.
- Not: Dosya yeniden yazılırken anahtarlar alfabetik sıraya girer ve dosya biçimlenir. İçerik değişmez.

**Zaten bir status line'ınız varsa:**

- Kurulum üzerine yazmaz; önce onay ister. Terminalde onay için `--wrap` bayrağını ekleyin: `--install-statusline --wrap`.
- Onay verirseniz script önce mevcut komutunuzu aynı girdiyle çalıştırır ve onun çıktısını aynen gösterir. Limit verisini de ayrıca kaydeder.
- Eski ayarın `padding`, `refreshInterval` gibi alanları korunur.
- **Kaldır** eski ayarı olduğu gibi geri yükler. Status line'ı sonradan elle değiştirdiyseniz kaldırma `settings.json`'a dokunmaz.

Not: Claude Code, özel bir status line tanımlandığında alt bilgideki bazı ipuçlarını (`esc to interrupt`, `? for shortcuts`) gizler.

**"Claude Code çalışırken güncellenir"** notu: Limit verisi yok ya da 15 dakikadan eski. Yüzdeler yalnızca Claude Code çalışırken yenilenir. Veri yoksa menü çubuğunda `—` görünür.

## Terminalde token özeti (`--dump`)

Uygulama arayüzde token veya maliyet göstermez. İsterseniz yerel Claude Code loglarından bir özeti terminalde alabilirsiniz:

```bash
build/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar --dump
```

Bu komut `~/.claude/projects/**/*.jsonl` dosyalarını bir kez tarar, bugün/hafta/ay toplamlarını ve API liste fiyatlarıyla hesaplanmış tahmini maliyeti yazdırır.

- Claude Code bir yanıtın her içerik bloğunu ayrı satıra yazar ve aynı usage'ı tekrar eder. Bu yüzden kayıtlar `message.id:requestId` ile tekilleştirilir; ccusage da aynı yaklaşımı kullanır.
- Fiyatlar `PricingTable.defaultJSON` içindedir (USD / 1M token). `~/Library/Application Support/ClaudeUsageBar/pricing.json` varsa o kullanılır.

## Gizlilik

- Uygulama ağa hiç çıkmaz. Hiçbir veri, token veya log dışarı gönderilmez. Keychain'e erişilmez.
- Uygulamanın okuduğu dosyalar: yalnızca `~/.claude-usage-bar/limits/*.json`. Loglar yalnızca `--dump` komutunda okunur.
- Yazılan dosyalar:
  - `~/.claude-usage-bar/` (köprü script'i ve limit verisi)
  - Kurulum sırasında `~/.claude/settings.json` içindeki `statusLine` anahtarı
- `./test.sh`, kaynak kodda `URLSession`, `URLRequest`, `Network`, `Security` veya `SecItem` kullanımı bulursa başarısız olur.
- Telemetri, analitik ve üçüncü taraf bağımlılık yoktur.

## Proje yapısı

```
Package.swift
build.sh, test.sh
Resources/Info.plist
Sources/UsageCore/          UI'sız çekirdek (test edilebilir)
  StatusLineLimits.swift    status line rate_limits modeli, oturumların birleştirilmesi
  StatusLineInstaller.swift köprü script'i + settings.json kurulum/kaldırma
  --- yalnızca --dump için ---
  LogParser.swift           JSONL satırı → UsageEntry / SessionCostState
  IncrementalScanner.swift  dosya başına ofset ile artımlı okuma
  UsageStore.swift          tekilleştirme + cost-state ekleri
  Aggregation.swift         bugün/hafta/ay, 7 gün, model ailesi
  Pricing.swift             fiyat tablosu
  UsageEngine.swift         tarama motoru
Sources/ClaudeUsageBar/     SwiftUI uygulaması (MenuBarExtra, ayarlar, FSEvents, bildirimler)
Tests/UsageCoreTests/       Swift Testing; Fixtures/ gerçek bir oturumdan alınmış, içeriği temizlenmiş veri
```

## Bilinen sınırlamalar

- Plan limiti yüzdeleri yalnızca Claude Code çalışırken güncellenir; Claude Code kapalıyken son bilinen değer "x dk önce" notuyla gösterilir.
- `rate_limits` alanı API anahtarıyla girişte gelmez; bu durumda uygulama yüzde gösteremez.
