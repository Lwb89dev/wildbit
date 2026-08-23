# WildBit

WildBit è un’app escursionistica sperimentale, privacy-first, costruita con
Flutter. Il suo elemento centrale è una carta geografica in pixel art generata
da dati OpenStreetMap: non una normale mappa raster con un filtro pixelato, ma
un renderer semantico originale che trasforma boschi, prati, acqua, sentieri,
edifici e POI in un piccolo mondo illustrato.

Bit, la mascotte, occupa fisicamente la scena: cammina con il bastone da
trekking, consulta la mappa quando l’utente è fermo e viene ordinato in
profondità rispetto ad alberi e rocce anche quando la carta viene ruotata.

> [!WARNING]
> WildBit è attualmente un prototipo **alpha**. Non è un dispositivo di
> navigazione certificato e non deve essere usato come unica fonte per
> scegliere o seguire un percorso. Dati OSM, GPS, accessibilità, orari,
> potabilità e condizioni dei sentieri possono essere incompleti o non
> aggiornati.

## Obiettivi

- Rendere una carta escursionistica leggibile con un linguaggio pixel-art
  coerente, senza incorporare artwork o codice proprietario di terzi.
- Funzionare senza Google Play Services per il fix della posizione su Android.
- Conservare localmente tracce e aree offline in un database cifrato.
- Usare servizi e protocolli aperti: OpenStreetMap, Overpass e Nostr.
- Mantenere separati dato geografico, rappresentazione visiva e valutazioni di
  sicurezza.

Lo stile prende ispirazione generale dai diorami JRPG e dall’HD-2D, ma WildBit
non è affiliato a Square Enix e non utilizza suoi asset, mappe o codice.

## Stato delle funzionalità

| Area | Stato attuale |
| --- | --- |
| Renderer pixel-art | Attivo sulla mappa principale; FlutterMap gestisce soltanto camera, proiezione e gesture |
| Terreno e biomi | Prato, foresta, roccia, neve, acqua, corsi d’acqua e costa |
| Geometrie | Sentieri, strade, ponti, edifici, rive e scala cartografica |
| Oggetti | Alberi, sottobosco, fiori, rocce, rifugi, cartelli e altri POI |
| Bit | Animazioni idle/cammino, scala legata allo zoom e occlusione rotazionale |
| GPS Android | `LocationManager` forzato, cache nativa e fix GNSS senza API Google |
| Esplora | Ricerca sentieri OSM per nome o entro un raggio configurabile fino a 100 km |
| Traccia | Registrazione, pausa, salvataggio e statistiche della camminata |
| Offline | Selezione area da mappa e cache delle feature geografiche; ancora sperimentale |
| POI | Etichette anticollisione, schede e metadati OSM conservativi |
| Voce di Bit | Sintesi offline Kokoro/ONNX opzionale con fonemizzazione eSpeak NG |
| Nostr | Login facoltativo con Amber o nsec e condivisione esplicita delle tracce |
| Routing automatico | Non disponibile come navigazione affidabile; i segmenti proposti richiedono verifica umana |

Le schermate principali sono `Mappa`, `Esplora`, `Traccia`, `Percorsi`,
`Offline` e `Impostazioni`.

## Il renderer della mappa

La mappa principale non visualizza tile raster OSM. La pipeline è:

```text
OpenStreetMap / Overpass
        ↓
parser e modello semantico WildBit
        ↓
cache geografica versionata
        ↓
proiezione FlutterMap
        ↓
composizione Flutter Canvas + sprite pixel-art
```

Ordine di composizione semplificato:

```text
terreno e acqua
→ rive, geologia e curve di livello
→ biomi ed edifici
→ sentieri, strade e ponti
→ alberi, rocce e Bit con profondità geografica
→ vegetazione di primo piano
→ POI, etichette e interfaccia
```

Principi implementati:

- distribuzione deterministica: lo stesso oggetto mantiene posizione e variante;
- coordinate geografiche stabili durante pan, zoom e rotazione;
- nearest-neighbour per gli asset, senza sfocatura del pixel;
- sentieri e strade non vengono eliminati per alleggerire un livello di zoom;
- dettagli decorativi e dimensioni seguono curve LOD separate;
- oggetti non vengono generati dentro acqua o nel corridoio dei percorsi;
- Bit e gli oggetti alti vengono ordinati usando il punto a terra già
  proiettato e ruotato sullo schermo;
- marker POI sempre presenti, mentre soltanto le etichette secondarie possono
  essere omesse quando non c’è spazio;
- un tag mancante rimane sconosciuto: per esempio una sorgente naturale non
  viene considerata potabile senza un’indicazione OSM esplicita.

La schermata di selezione offline è un’eccezione intenzionale: usa una mappa
OSM standard e l’overlay escursionistico Waymarked Trails per rendere evidente
l’area da scaricare. Questo raster non è il renderer della mappa principale.

## Stack tecnico

- Flutter e Dart
- `flutter_map` e `latlong2`
- OpenStreetMap e API Overpass pubbliche
- Drift + SQLite3MultipleCiphers per il database locale cifrato
- Android `LocationManager` tramite `geolocator` e canale nativo
- Kokoro-82M tramite ONNX Runtime, con eSpeak NG
- Nostr, NIP-44 e firma esterna NIP-55 tramite Amber
- Provider per il grafo delle dipendenze

## Struttura del repository

```text
android/                   integrazione e build Android
assets/
  icons/                   icona launcher e mascotte
  map/mock/                tile e sprite del renderer
  sprites/bit/             frame delle animazioni di Bit
docs/                      specifiche visive, tecniche e prestazionali
lib/
  app/                     bootstrap, provider e tema
  data/                    parser OSM, cache e repository
  domain/                  entità e regole indipendenti dalla UI
  location/                sorgenti GNSS reali e simulate
  map_rendering/           compositori, layer Canvas, Bit e budget
  offline/                 download e ripresa delle aree
  presentation/            schermate Flutter
  services/                voce, Nostr, registrazione e sicurezza
  storage/                 database Drift
linux/                     runner desktop
test/                      test unitari, geometrici e widget
third_party/               fork locali necessari alla build
```

## Requisiti di sviluppo

- Flutter con Dart `>= 3.12.2 < 4.0.0`
- Java 17
- Android SDK Platform 37 per la build Android
- toolchain Linux desktop configurata, se si usa il runner Linux
- un dispositivo Android o un emulatore per verificare permessi e GNSS reali

Controllare l’ambiente:

```bash
flutter doctor -v
flutter pub get
```

## Avvio

### Linux con posizione simulata

Il runner desktop usa automaticamente un percorso simulato, così Bit può
essere verificato senza hardware GNSS:

```bash
flutter run -d linux
```

### Preview offline completa

Questa modalità non interroga Overpass e carica immediatamente una valle mock
con biomi, edifici, sentieri, alberi, acqua e POI:

```bash
flutter run -d linux \
  --dart-define=WILDBIT_OFFLINE_PREVIEW=true \
  --dart-define=WILDBIT_MIXED_PREVIEW=true
```

### Laboratorio isolato del renderer

Per lavorare soltanto sulla scena grafica statica:

```bash
flutter run -d linux -t lib/mock_preview_main.dart
```

### Android

Con un dispositivo visibile da ADB:

```bash
flutter devices
flutter run -d <device-id>
```

Al primo avvio l’onboarding richiede esplicitamente il permesso di posizione.
L’identità Nostr è facoltativa.

> [!IMPORTANT]
> La configurazione `release` Android usa ancora la chiave di debug. Prima di
> distribuire APK/AAB occorre configurare firma, application ID definitivo,
> versioning e pipeline di rilascio.

## Test e controlli

Eseguire l’intera suite:

```bash
flutter test
```

Controlli mirati utili durante lo sviluppo del renderer:

```bash
dart analyze lib/map_rendering
flutter test test/map_geometry_rules_test.dart
flutter test test/projected_depth_order_test.dart
flutter test test/poi_label_layout_test.dart
```

La suite copre, tra le altre cose, parsing e cache OSM, topologia dei percorsi,
coste, rive, persistenza degli oggetti allo zoom, ordinamento Bit/alberi,
collisione delle etichette e trattamento conservativo dei metadati POI.

## Dati e servizi esterni

| Servizio | Utilizzo | Nota |
| --- | --- | --- |
| OpenStreetMap | geometrie e tag della carta | dati © OpenStreetMap contributors, ODbL |
| Overpass | viewport e ricerca sentieri | istanze pubbliche soggette a timeout, rate limit e indisponibilità |
| tile.openstreetmap.org | sola selezione area offline | non usato come fondo della mappa pixel-art principale |
| Waymarked Trails | overlay escursionistico nella selezione offline | servizio esterno, non incluso nella cache grafica principale |
| relay Nostr | pubblicazione volontaria di tracce | la traccia GPS diventa pubblica solo dopo conferma esplicita |
| Hugging Face | download opzionale del modello Kokoro | file verificati per dimensione e SHA-256 prima dell’uso |

Overpass non è adatto al download massivo di regioni. L’attuale cache a celle è
una soluzione da prototipo; estratti regionali PBF o vector tile aperte sono
la direzione prevista per aree più grandi e affidabilità offline reale.

## Privacy e sicurezza

- WildBit non richiede un account per usare mappa, GPS e registrazione.
- Su Android la posizione usa `LocationManager` con
  `forceLocationManager: true`; non viene richiesto il fused provider di
  Google Play Services.
- Il database è cifrato con una chiave casuale conservata nel secure storage
  della piattaforma.
- Amber è il metodo Nostr consigliato: la chiave privata non entra nel processo
  di WildBit.
- L’inserimento diretto di un nsec è supportato, ma lo conserva nel secure
  storage del dispositivo ed è quindi un’opzione più sensibile.
- La pubblicazione Nostr include i punti GPS esatti della traccia. La UI deve
  ottenere una conferma esplicita prima dell’invio.
- Il modello vocale è opzionale e, dopo il download, l’inferenza avviene
  localmente.

## Limiti noti

- Le istanze Overpass pubbliche possono rispondere con `429`, `500`, `502` o
  timeout; la cache locale e i mirror riducono ma non eliminano il problema.
- Rifugi e altri POI mappati come aree/edifici devono ancora essere trattati
  con la stessa completezza dei POI nodo.
- La coastline globale e le isole complesse richiedono ulteriore validazione
  su dataset reali estesi.
- La selezione offline è funzionante ma la pipeline non è ancora equivalente
  a un pacchetto cartografico regionale completo.
- Orari, accesso, potabilità e difficoltà sono osservazioni OSM, non garanzie
  sullo stato corrente del luogo.
- Autonomia, memoria e frame time devono continuare a essere misurati su
  dispositivi Android di fascia diversa.
- La voce Kokoro richiede un download iniziale relativamente grande.

## Documentazione tecnica

- [`docs/pixel_map_renderer_spec.md`](docs/pixel_map_renderer_spec.md) —
  linguaggio visivo e livelli del renderer
- [`docs/pixel_map_mock_assets.md`](docs/pixel_map_mock_assets.md) — asset,
  ancoraggi, footprint e occlusioni
- [`docs/coastline_composition.md`](docs/coastline_composition.md) — regole per
  costa, catene e isole
- [`docs/map_rendering_performance.md`](docs/map_rendering_performance.md) —
  budget e principi prestazionali
- [`roadmap.txt`](roadmap.txt) — roadmap storica del renderer

Alcuni documenti descrivono anche obiettivi e budget precedenti: il codice e i
test restano la fonte di verità sul comportamento attualmente implementato.

## Licenze e pubblicazione del repository

Al momento il repository **non contiene una licenza principale**. In assenza
di un file `LICENSE`, il codice e gli asset non sono automaticamente
riutilizzabili o redistribuibili da terzi. Per un semplice backup cloud è
consigliato mantenere il repository privato finché non sono stati definiti:

1. licenza del codice WildBit;
2. licenza e provenienza definitiva di ogni artwork;
3. compatibilità delle licenze delle dipendenze e dei componenti in
   `third_party/`;
4. attribuzioni complete per modello vocale, eSpeak NG, OSM e servizi tile.

I componenti inclusi in `third_party/` conservano i rispettivi file `LICENSE`.
OpenStreetMap è attribuito ai suoi contributori secondo ODbL. Marchi e nomi di
terzi appartengono ai rispettivi proprietari.
