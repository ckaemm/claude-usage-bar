# Claude Usage Bar

Claude Code kullanımınızı macOS menü çubuğunda gösteren native bir uygulama (Swift + SwiftUI, macOS 13+).
Her şey yerelde çalışır. Varsayılan olarak hiçbir veri dışarı gönderilmez.

- Menü çubuğunda ikon ve kısa bir özet: bugünkü token (`114.5M`), maliyet (`$43`), 5 saatlik pencere yüzdesi (`~56%`) ya da yalnızca ikon.
- Popover'da şunlar var:
  - 5 saatlik pencere ve geri sayım
  - Bugün, bu hafta ve bu ay için token ve tahmini maliyet
  - Model dağılımı (Opus / Sonnet / Haiku / Fable)
  - Son 7 günün grafiği (Swift Charts)
  - Yenile butonu ve son güncelleme zamanı
- Log klasörü FSEvents ile anlık izlenir. Ayrıca ayarlanabilir aralıklarla yenilenir.
- Ayarlar: yenileme aralığı, menü çubuğu gösterimi, eşik bildirimi, login'de başlatma, opsiyonel plan limitleri.

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

Uygulama Dock'ta görünmez (`LSUIElement`); yalnızca menü çubuğunda yaşar. Kapatmak için popover'daki ⏻ butonunu kullanın veya ⌘Q'ya basın.

Geliştirme sırasında:

```bash
swift build && .build/debug/ClaudeUsageBar          # uygulamayı paketlemeden çalıştırır (bildirimler devre dışı)
.build/debug/ClaudeUsageBar --dump                   # UI açmadan tüm logları tarar, özeti yazdırır
./test.sh                                            # birim testleri (Swift Testing)
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

### 2) Plan limitleri (resmi değil, varsayılan KAPALI)

Ayarlar › **Plan limitlerini göster (resmi değil)** seçeneği açıldığında uygulama, Claude Code'un kullandığı belgelenmemiş `https://api.anthropic.com/api/oauth/usage` uç noktasından 5 saatlik ve haftalık kullanım yüzdelerini alır.

- Token yalnızca macOS Keychain'deki `Claude Code-credentials` öğesinden okunur ve macOS bunun için izin sorar.
- Token yalnızca bellekte tutulur. Diske yazılmaz, loglanmaz ve api.anthropic.com dışında hiçbir yere gönderilmez.
- Uç nokta her an değişebilir. Başarısız olursa uygulama yerel verilerle çalışmaya devam eder ve 5 dk sonra yeniden dener.
- Ad-hoc imzalı derlemelerde, her yeniden derlemeden sonra Keychain izni tekrar sorulabilir.

### Arayüzdeki etiketler

| Etiket | Anlamı |
|---|---|
| **maliyetler tahmini** | Token sayıları × `pricing.json`'daki API liste fiyatları. Abonelik (Pro/Max) faturanızı yansıtmaz. |
| **tahmini** (5 sa pencere) | Yerel hesap: pencere ilk mesajın saatinde başlar ve 5 saat sürer. Yüzde, geçmişteki en yüksek maliyetli 5 saatlik bloğa oranlanır. Sunucudaki gerçek pencere ve limitle birebir değildir. |
| **resmi değil** | Belgelenmemiş uç noktadan gelen plan limiti verisi. |

Menü çubuğundaki `~42%` biçimindeki `~` işareti, yüzdenin yerel tahmin olduğunu gösterir.

## Fiyat tablosu

İlk açılışta `~/Library/Application Support/ClaudeUsageBar/pricing.json` dosyası oluşturulur. Fiyatlar 1M token başına USD'dir:

```json
"claude-opus-5-5": { "input": 4, "output": 20, "cacheWrite5m": 5, "cacheWrite1h": 8, "cacheRead": 0.2, "fastMultiplier": 2 }
```

- Model eşleme sırası: tam ad, sonra en uzun önek (tarih ekli kimlikler için), sonra `familyFallback` (ör. bilinmeyen bir Opus sürümü `claude-opus-5-5` fiyatını alır).
- Dosyayı düzenlediğinizde değişiklik bir sonraki yenilemede uygulanır. Dosya bozuksa varsayılan fiyatlar kullanılır ve popover'da uyarı çıkar.
- Varsayılan fiyatlar Anthropic API liste fiyatlarıdır (Ekim 2026). Bir oturumda Claude Code'un kendi hesapladığı maliyetle (`cost-state.costUSD`) birebir doğrulandı.

## Gizlilik

- Varsayılan olarak hiçbir ağ isteği yapılmaz. Tek istisna, açıkça açıldığında plan limiti isteğidir.
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
  SessionBlocks.swift       yerel 5 saatlik pencere tahmini
  Pricing.swift             düzenlenebilir fiyat tablosu
  PlanLimits.swift          resmi olmayan uç nokta yanıt modeli
  UsageEngine.swift         arka plan aktörü + disk önbelleği
Sources/ClaudeUsageBar/     SwiftUI uygulaması (MenuBarExtra, ayarlar, FSEvents, Keychain, bildirimler)
Tests/UsageCoreTests/       Swift Testing; Fixtures/ gerçek bir oturumdan alınmış, içeriği temizlenmiş veri
```

## Bilinen sınırlamalar

- Log biçimi Claude Code sürümleriyle değişebilir. Parser bilinmeyen alanları yok sayar; okunamayan satır sayısı Ayarlar › Veri bölümünde görünür.
- Haiku 5.5'in 100K token üstü istem fiyatlandırması modellenmemiştir.
- Silinen log dosyalarındaki kullanım önbellekte kalır. "Önbelleği sıfırla ve yeniden tara" ile temizlenebilir.
