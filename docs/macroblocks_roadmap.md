# WildBit — macroblocchi e stato reale

Questa è una stima tecnica dello stato dell’alpha, non una promessa di
rilascio. La percentuale misura quanto del lavoro necessario per una versione
utilizzabile è già implementato e verificato; i casi OSM rari e la validazione
su dispositivi reali pesano più delle singole righe di codice.

## Stato sintetico

- Renderer pixel-art/HD-2D: **circa 89% completato**.
- App alpha completa (renderer, GPS, offline, tracce, Nostr): **circa 66%
  completato**, quindi **34% ancora da chiudere**.
- Release pubblicabile e affidabile in campo: **non ancora stimabile come
  completata** finché non termina il blocco di test Android/Overpass/offline.

## Timeline ordinata

| # | Macroblocco | Stato | Lavoro residuo principale |
|---:|---|---:|---|
| 0 | Specifica visiva, palette, griglia, asset minimi e mock | 100% | Solo nuove varianti artistiche |
| 1 | Composizione Canvas e ordine di profondità | 90% | Test completi con camera ruotata e casi limite |
| 2 | Terreno, acqua, rive e coastline globale | 90% | QA su estratti OSM reali e multipolygon complessi |
| 3 | Sentieri, strade, ponti, guadi e fiumi | 88% | Direzione downstream nei dati incompleti, QA visivo |
| 4 | Foreste, alberi, cespugli, fiori e rocce | 86% | Profilo Android e QA su dati OSM reali |
| 5 | Edifici, rifugi, cartelli e POI | 90% | Footprint da relation multipolygon e collisioni inter-oggetto |
| 6 | Bit, animazioni, pivot, traccia e occlusione | 96% | QA su device con rotazione continua e camera in movimento |
| 7 | Traccia registrata, statistiche, preview e condivisione Nostr | 82% | Test relay reali, retry offline e privacy UX |
| 8 | GPS degoogled, onboarding e permessi | 78% | Test su più versioni Android e messaggi di fix/errore |
| 9 | Esplora, ricerca sentieri e raggio vicino a me | 72% | Test UI con dati reali e ranking su dataset regionali |
| 10 | Offline: selezione area, overlay sentieri e download | 90% | QA Android, pacchetti regionali estesi e gestione quote disco |
| 11 | Performance, cache, batteria e test su device medi | 76% | Profiling release e stress su device medi |
| 12 | Packaging, icone, splash, voce e release GPLv3 | 82% | Keystore reale e checklist store |

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
fallback offline dei sentieri. Il punto 10 è ora implementato a livello di
alpha: la selezione e il download regionale offline restano da verificare su
device e con pacchetti estesi. Nel primo sottoblocco del punto 10
sono ora presenti selezione slippy-tile limitata per zoom, cache atomica dei
tile OSM e Waymarked Trails, ripresa dei file già presenti, provider locale con
fallback online, progressione unica feature+tile, stima dello spazio e
centramento GPS della schermata Offline. È ora presente anche un pacchetto
locale da 1 km centrato sul GPS e il controllo dello spazio libero Android via
StatFs. Restano QA su device, pacchetti regionali estesi e quote/cleanup del
disco. Il download della viewport usa inoltre il livello di zoom effettivo
selezionato dall’utente, mentre i pacchetti locali mantengono il range
predefinito. Nel blocco 11 il renderer ora applica un budget ridotto durante pan,
pinch e rotazione, mentre un monitor opzionale in debug raccoglie una finestra
mobile dei tempi build/raster e segnala i frame oltre il budget da 16,7 ms.
Restano profiling release, stress test su dispositivi medi e verifica dei
consumi in background. Durante pan, pinch e rotazione i fetch OSM vengono ora
rinviati fino a camera ferma, evitando lavoro di rete e parsing mentre il
renderer sta già sostenendo il carico del gesto. Il download della viewport
usa inoltre lo zoom selezionato, la cache espone dimensione e pulizia dei file
parziali, e la navigazione sospende i timer quando la scheda Mappa non è
visibile. La diagnostica debug espone
anche hit/miss della cache di proiezione condivisa tra sentieri ed etichette.
Nel blocco 12 è ora presente un preflight senza dipendenze per verificare
versione, GPLv3, icone launcher, splash Bit e compileSdk Android; in modalità
`--strict` blocca la distribuzione finché resta la firma debug.
Nel renderer il parsing ora assembla i multipolygon OSM da way spezzate o
invertite, assegna correttamente i ring interni e conserva i fori nella cache;
acqua, biomi e vegetazione rispettano questi fori anche dopo la proiezione.
Le rive vengono inoltre distribuite tra anello esterno e isole interne, con
normale terra/acqua invertita per non dipingere la sabbia dentro il lago.
Le relazioni incomplete non vengono riempite per supposizione: il parser
mantiene invece i way autonomi con geometria e tag propri come fallback.
I corsi d'acqua privi di direzione esplicita usano ora un orientamento
deterministico basato sugli endpoint OSM, così la fase dell'animazione non
inverte casualmente tra refresh o celle adiacenti; i tag `forward`/`backward`
restano prioritari. Prima del fill Canvas, i ring multipolygon vengono inoltre
controllati contro vertici interni ripetuti e autointersezioni, con fallback
conservativo sui way autonomi quando la topologia non è affidabile.
Le way d'acqua con nodi completi vengono inoltre raccordate in pennellate
continue lungo le catene di grado due; le confluenze restano rami separati e
non vengono trasformate in un unico corso inventato. Questo elimina giunti e
discontinuità della texture senza alterare l'identità dei way nella cache.
I ponti espliciti vengono ora ancorati agli intervalli di intersezione della
reale superficie d'acqua, con esclusione delle isole interne; su poligoni
concavi si seleziona l'intervallo che contiene il centro del way. Se esistono
poligoni d'acqua nella cella ma il bridge way non ne attraversa nessuno, il
ponte viene omesso per evitare sprite sospesi sulla terraferma. I guadi restano
invece disponibili solo quando il tag OSM `ford` è esplicito.
Per gli edifici, i footprint ora rifiutano autointersezioni, supportano i ring
interni e vengono disegnati con fill pari alla topologia reale; la vegetazione
procedurale esclude l'interno e una fascia di rispetto del perimetro, ma lascia
liberi i cortili nei fori validi. La stessa regola viene applicata ad alberi e
rocce censiti o generati, evitando collisioni visive instabili durante pan e
rotazione.
La densità decorativa usa ora bande LOD quantizzate: il conteggio non varia a
ogni frazione di zoom, mentre gli anchor appena fuori viewport restano validi
finché il loro sprite proiettato è visibile. Questo riduce pop-in sui bordi e
mantiene stabile la foresta durante pan, pinch e rotazione senza superare il
budget di sprite.
