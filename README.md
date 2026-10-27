# Claude Usage Bar

Claude Code kullanımınızı macOS menü çubuğunda gösteren native bir uygulama (Swift + SwiftUI, macOS 13+).
Her şey yerelde çalışır. Uygulama ağa hiç çıkmaz ve hiçbir veriyi dışarı göndermez.

- Menü çubuğunda ikon ve kısa bir özet: bugünkü token (`114.5M`), maliyet (`$43`), 5 saatlik limit yüzdesi (`23%`) ya da yalnızca ikon.
- Popover'da şunlar var:
  - 5 saatlik ve haftalık plan limiti yüzdeleri, sıfırlanmaya geri sayım (Claude Code status line'ından)
  - Bugün, bu hafta ve bu ay için token ve tahmini maliyet
  - Model dağılımı (Opus / Sonnet / Haiku / Fable)
  - Son 7 günün grafiği (Swift Charts)
  - Yenile butonu ve son güncelleme zamanı
- Log klasörü FSEvents ile anlık izlenir. Ayrıca ayarlanabilir aralıklarla yenilenir.
- Ayarlar: yenileme aralığı, menü çubuğu gösterimi, eşik bildirimi, login'de başlatma, Claude Code status line köprüsünü tek tıkla kurma/kaldırma.

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

Plan limiti yüzdeleri için status line köprüsünü kurun (bkz. [Plan limitleri](#2-plan-limitleri-claude-code-status-line)):
Menü çubuğu ikonu › ⚙︎ Ayarlar › Claude Code bağlantısı › **Kur**.

Uygulama Dock'ta görünmez (`LSUIElement`); yalnızca menü çubuğunda yaşar. Kapatmak için popover'daki ⏻ butonunu kullanın veya ⌘Q'ya basın.

Geliştirme sırasında:

```bash
swift build && .build/debug/ClaudeUsageBar          # uygulamayı paketlemeden çalıştırır (bildirimler devre dışı)
.build/debug/ClaudeUsageBar --dump                   # UI açmadan tüm logları tarar, özeti yazdırır
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

## Veri kaynakları

### 1) Yerel Claude Code logları (birincil)

`~/.claude/projects/**/*.jsonl` (varsa `~/.config/claude/projects`). Şema gerçek dosyalardan doğrulandı:

- `type: "assistant"` satırları `message.model`, `message.id`, `requestId`, `timestamp` ve şu alanları içeren `message.usage` taşır:
  - `input_tokens`, `output_tokens`, `cache_read_input_tokens`
  - `cache_creation_input_tokens` ve 5 dk / 1 sa TTL dökümü (`cache_creation.ephemeral_5m/1h_input_tokens`)
  - `speed`
- Claude Code, bir yanıtın her içerik bloğunu (thinking, text, tool_use) **ayrı satır** olarak yazar ve her satıra aynı usage'ı kopyalar. Bu yüzden kayıtlar `message.id:requestId` ile tekilleştirilir; [ccusage](https://github.com/ryoppippi/ccusage) da aynı yaklaşımı kullanır. Örnek: 5458 satır, 2423 tekil yanıt.
- `type: "cost-state"` satırları oturumun kümülatif model kullanımını tutar. Assistant satırlarında hiç görünmeyen iç çağrılar (ör. Haiku) buradan eklenir. Zamanları oturumun son etkinliğine göre yaklaşıktır.
- `<synthetic>` model satırları ve bozuk satırlar atlanır.

Tarama artımlıdır: dosya başına okunan bayt ofseti tutulur, yalnızca yeni eklenen satırlar okunur ve yazılmakta olan yarım satır bekletilir. Sonuçlar `~/Library/Application Support/ClaudeUsageBar/cache.json` dosyasında saklanır. Bu dosyada yalnızca sayılar, kimlikler ve dosya yolları bulunur, mesaj içeriği yoktur. 300 MB log ilk açılışta yaklaşık 2 sn'de taranır, sonraki taramalar milisaniyeler sürer.

### 2) Plan limitleri (Claude Code status line)

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
- Girdide `rate_limits` varsa JSON'u `~/.claude-usage-bar/limits.json` dosyasına **atomik** yazar: önce geçici dosyaya yazar, sonra `mv` ile taşır. Dosya izni `0600` olur.
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

### Arayüzdeki etiketler

| Etiket | Anlamı |
|---|---|
| **maliyetler tahmini** | Token sayıları × `pricing.json`'daki API liste fiyatları. Abonelik (Pro/Max) faturanızı yansıtmaz. |
| **Claude Code çalışırken güncellenir** | Limit verisi yok ya da 15 dakikadan eski. Yüzdeler, Claude Code'un status line'a verdiği değerlerdir; yalnızca Claude Code çalışırken yenilenir. |

Limit verisi yoksa menü çubuğundaki yüzde modu `—` gösterir. Uygulama kendi yüzde tahminini üretmez.

## Fiyat tablosu

İlk açılışta `~/Library/Application Support/ClaudeUsageBar/pricing.json` dosyası oluşturulur. Fiyatlar 1M token başına USD'dir:

```json
"claude-opus-5-5": { "input": 4, "output": 20, "cacheWrite5m": 5, "cacheWrite1h": 8, "cacheRead": 0.2, "fastMultiplier": 2 }
```

- Model eşleme sırası: tam ad, sonra en uzun önek (tarih ekli kimlikler için), sonra `familyFallback` (ör. bilinmeyen bir Opus sürümü `claude-opus-5-5` fiyatını alır).
- Dosyayı düzenlediğinizde değişiklik bir sonraki yenilemede uygulanır. Dosya bozuksa varsayılan fiyatlar kullanılır ve popover'da uyarı çıkar.
- Varsayılan fiyatlar Anthropic API liste fiyatlarıdır (Ekim 2026). Bir oturumda Claude Code'un kendi hesapladığı maliyetle (`cost-state.costUSD`) birebir doğrulandı.

## Gizlilik

- Uygulama ağa hiç çıkmaz. Hiçbir veri, token veya log dışarı gönderilmez. Keychain'e erişilmez.
- Okunan dosyalar: `~/.claude/projects/**/*.jsonl` ve `~/.claude-usage-bar/limits.json`.
- Yazılan dosyalar:
  - `~/Library/Application Support/ClaudeUsageBar/` (önbellek ve fiyat tablosu)
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
  LogParser.swift           JSONL satırı → UsageEntry / SessionCostState
  IncrementalScanner.swift  dosya başına ofset ile artımlı okuma
  UsageStore.swift          tekilleştirme + cost-state ekleri
  Aggregation.swift         bugün/hafta/ay, 7 gün, model ailesi
  Pricing.swift             düzenlenebilir fiyat tablosu
  StatusLineLimits.swift    status line rate_limits modeli (limits.json)
  StatusLineInstaller.swift köprü script'i + settings.json kurulum/kaldırma
  UsageEngine.swift         arka plan aktörü + disk önbelleği
Sources/ClaudeUsageBar/     SwiftUI uygulaması (MenuBarExtra, ayarlar, FSEvents, bildirimler)
Tests/UsageCoreTests/       Swift Testing; Fixtures/ gerçek bir oturumdan alınmış, içeriği temizlenmiş veri
```

## Bilinen sınırlamalar

- Plan limiti yüzdeleri yalnızca Claude Code çalışırken güncellenir; Claude Code kapalıyken son bilinen değer "x dk önce" notuyla gösterilir.
- Log biçimi Claude Code sürümleriyle değişebilir. Parser bilinmeyen alanları yok sayar; okunamayan satır sayısı Ayarlar › Veri bölümünde görünür.
- Haiku 5.5'in 100K token üstü istem fiyatlandırması modellenmemiştir.
- Silinen log dosyalarındaki kullanım önbellekte kalır. "Önbelleği sıfırla ve yeniden tara" ile temizlenebilir.
