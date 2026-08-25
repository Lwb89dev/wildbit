# WildBit — macroblocchi e stato reale

Questa è una stima tecnica dello stato dell’alpha, non una promessa di
rilascio. La percentuale misura quanto del lavoro necessario per una versione
utilizzabile è già implementato e verificato; i casi OSM rari e la validazione
su dispositivi reali pesano più delle singole righe di codice.

## Stato sintetico

- Renderer pixel-art/HD-2D: **circa 78% completato**.
- App alpha completa (renderer, GPS, offline, tracce, Nostr): **circa 66%
  completato**, quindi **34% ancora da chiudere**.
- Release pubblicabile e affidabile in campo: **non ancora stimabile come
  completata** finché non termina il blocco di test Android/Overpass/offline.

## Timeline ordinata

| # | Macroblocco | Stato | Lavoro residuo principale |
|---:|---|---:|---|
| 0 | Specifica visiva, palette, griglia, asset minimi e mock | 100% | Solo nuove varianti artistiche |
| 1 | Composizione Canvas e ordine di profondità | 90% | Test completi con camera ruotata e casi limite |
| 2 | Terreno, acqua, rive e coastline globale | 82% | Ring annidati, multipolygon e validazione su estratti reali |
| 3 | Sentieri, strade, ponti, guadi e fiumi | 78% | Confluenze, direzione downstream nei dati incompleti, QA visivo |
| 4 | Foreste, alberi, cespugli, fiori e rocce | 78% | Profilo Android e QA su dati OSM reali |
| 5 | Edifici, rifugi, cartelli e POI | 84% | Footprint da relation multipolygon e collisioni inter-oggetto |
| 6 | Bit, animazioni, pivot, traccia e occlusione | 96% | QA su device con rotazione continua e camera in movimento |
| 7 | Traccia registrata, statistiche, preview e condivisione Nostr | 82% | Test relay reali, retry offline e privacy UX |
| 8 | GPS degoogled, onboarding e permessi | 78% | Test su più versioni Android e messaggi di fix/errore |
| 9 | Esplora, ricerca sentieri e raggio vicino a me | 72% | Test UI con dati reali e ranking su dataset regionali |
| 10 | Offline: selezione area, overlay sentieri e download | 90% | QA Android, pacchetti regionali estesi e gestione quote disco |
| 11 | Performance, cache, batteria e test su device medi | 76% | Profiling release e stress su device medi |
| 12 | Packaging, icone, splash, voce e release GPLv3 | 55% | Firma release, asset finali, licenze e checklist store |

## Ordine operativo da seguire

1. Chiudere ring annidati/multipolygon e testare coastline su dati reali.
2. Completare confluenze e raccordi del flusso dei corsi d’acqua.
3. Stabilizzare densità/LOD di vegetazione e rocce senza comparsa/scomparsa.
4. Chiudere edifici, rifugi e POI con footprint e profondità coerenti.
5. Fare un passaggio integrato Bit + traccia + rotazione + camera.
6. Rendere affidabili cache Overpass, Explore e modalità degradata.
7. Completare offline regionale e misurare il profilo release Android.
8. Solo alla fine rifinire packaging, voce e distribuzione.

Gli ultimi macroblocchi completati sono il raccordo della direzione dei fiumi ai
metadati OSM (con versionamento della cache), la classificazione dei ring
costieri annidati, la stabilizzazione della vegetazione procedurale, il
passaggio degli edifici a footprint puliti con profondità rispetto a Bit e
l’overlay della traccia registrata nella camera pixel-art e il payload
versionato per la condivisione Nostr. Il blocco 8 ora apre lo stream GPS solo
dopo il consenso, usa timeout sui canali GNSS opzionali e mantiene il fallback
nativo LocationManager. Nel blocco 9 sono ora persistenti cache, ranking e
fallback offline dei sentieri. Il prossimo è il punto 10: completare la
selezione e il download regionale offline. Nel primo sottoblocco del punto 10
sono ora presenti selezione slippy-tile limitata per zoom, cache atomica dei
tile OSM e Waymarked Trails, ripresa dei file già presenti, provider locale con
fallback online, progressione unica feature+tile, stima dello spazio e
centramento GPS della schermata Offline. È ora presente anche un pacchetto
locale da 1 km centrato sul GPS e il controllo dello spazio libero Android via
StatFs. Restano QA su device, pacchetti regionali estesi e quote/cleanup del
disco. Nel blocco 11 il renderer ora applica un budget ridotto durante pan,
pinch e rotazione, mentre un monitor opzionale in debug raccoglie una finestra
mobile dei tempi build/raster e segnala i frame oltre il budget da 16,7 ms.
Restano profiling release, stress test su dispositivi medi e verifica dei
consumi in background. Durante pan, pinch e rotazione i fetch OSM vengono ora
rinviati fino a camera ferma, evitando lavoro di rete e parsing mentre il
renderer sta già sostenendo il carico del gesto.
