# WildBit — macroblocchi e stato reale

Questa è una stima tecnica dello stato dell’alpha, non una promessa di
rilascio. La percentuale misura quanto del lavoro necessario per una versione
utilizzabile è già implementato e verificato; i casi OSM rari e la validazione
su dispositivi reali pesano più delle singole righe di codice.

## Stato sintetico

- Renderer pixel-art/HD-2D: **100% code-complete**.
- App alpha completa (renderer, GPS, tracce, Nostr): **circa 66%
  completato**, quindi **34% ancora da chiudere**.
- Release pubblicabile e affidabile in campo: **non ancora stimabile come
  completata** finché non termina il blocco di test Android/Overpass.

### Harness di profilazione locale

`lib/renderer_profile_main.dart` avvia il compositore reale su una valle locale
deterministica: lago, corso d'acqua, sentieri, ponte, rifugi, vegetazione,
edifici e 180 alberi. Non inizializza GPS, Overpass, cache o persistenza,
perciò il contatore di frame misura soltanto il costo del renderer e degli
asset. Va eseguito in profile mode con
`flutter run --profile -t lib/renderer_profile_main.dart -d <device>`; i
controlli in alto permettono di provare zoom, rotazione e le due animazioni di
Bit, mentre il riquadro in basso mostra build, raster, frame lenti e tier
decorativo adattivo. Il pulsante **Scena stress** usa inoltre una fixture locale
con 1.200 alberi espliciti, 320 footprint e 180 curve di livello: serve a
verificare culling, limiti LOD e recupero del tier su telefoni reali, senza
mascherare un problema con una risposta lenta del server.

Il tier adattivo viene ora valutato anche a camera ferma: se una scena continua
a pesare dopo il pan, conserva il tier decorativo prudente fino a una finestra
di frame realmente sana. Sentieri, acqua, POI e ogni geometria cartografica
restano invariati; cambiano soltanto densità e animazioni decorative.
Il terreno base, che è ancorato allo schermo e non alla camera geografica, è
inoltre isolato in un repaint boundary: animazioni di Bit e aggiornamenti UI
non devono ridisegnare l'intero prato pixel per pixel.
Durante pan, pinch e rotazione viene inoltre usato un fast-path semantico:
prato, biomi, roccia e acqua mantengono anche il proprio materiale texture,
così non flashano in un colore pieno sotto il dito. Si sospendono invece animazioni,
etichette e dettagli ambientali secondari; sentieri, acqua, POI e altri
elementi cartografici non vengono nascosti.
Il clock ambiente condiviso riavvia ora il timer quando il tier cambia: il
divisore di frequenza applicato per pressione grafica è quindi effettivo anche
senza cambiare scheda o mettere l'app in background.
Alberi, rocce e cespugli sono inoltre composti con atlanti GPU, mantenendo
ordine di profondità e silhouette ma evitando una chiamata raster per sprite.
Laghi e mare hanno base/rive statiche in un repaint boundary separato: a ogni
tick si muovono solo le increspature, mentre il flusso dei fiumi resta legato
alla propria direzione geografica. La coastline conserva inoltre la proiezione
Canvas per la camera esatta: aggiornamenti di GPS, Bit e controlli non
riproiettano catene costiere, ma pan/zoom/rotazione invalidano subito la cache.
Il pulsante con il cronometro nel harness esegue inoltre un gesto locale
deterministico di 4,3 secondi (pan, zoom e rotazione), azzera prima la finestra
di frame e restituisce poi il tier grafico pieno. Può essere eseguito su ogni
telefono con la stessa scena standard, replay OSM o stress per confrontare
build/raster senza GPS, rete o variazioni casuali.

Anche fiori e selezione dei pochi footprint urbani hanno ora una cache di
vista esatta. Una variazione di GPS, Bit o interfaccia a camera immobile
riutilizza le proiezioni/ranking già calcolati; cambiare centro, zoom,
rotazione, bounds, dati OSM o tier decorativo invalida la cache subito. I
footprint restano un contesto leggero e non competono con boschi e sentieri.

## Timeline ordinata

| # | Macroblocco | Stato | Lavoro residuo principale |
|---:|---|---:|---|
| 0 | Specifica visiva, palette, griglia, asset minimi e mock | 100% | Solo nuove varianti artistiche |
| 1 | Composizione Canvas e ordine di profondità | 100% | QA reale non blocca altro coding del motore |
| 2 | Terreno, acqua, rive e coastline globale | 100% | QA su estratti OSM resta attività di release |
| 3 | Sentieri, strade, ponti, guadi e fiumi | 100% | QA visivo/confluenze resta attività di release |
| 4 | Foreste, alberi, cespugli, fiori e rocce | 100% | Profilo su altri device resta attività di release |
| 5 | Edifici, rifugi, cartelli e POI | 100% | QA collisioni resta attività di release |
| 6 | Bit, animazioni, pivot, traccia e occlusione | 100% | QA con rotazione continua resta attività di release |
| 7 | Traccia registrata, statistiche, preview e condivisione Nostr | 92% | Test relay reali e QA privacy su dispositivo |
| 8 | GPS degoogled, onboarding e permessi | 90% | Test su più versioni Android e acquisizione GNSS a freddo |
| 9 | Esplora, ricerca sentieri e raggio vicino a me | 82% | Test UI con dati reali e ranking su dataset regionali |
| 10 | Pacchetti offline regionali | Rinviato | Funzione rimossa dall’alpha: richiederà una sorgente dati espressamente autorizzata |
| 11 | Performance, cache, batteria e test su device medi | 94% | Profiling release e stress prima sugli smartphone, poi tablet |
| 12 | Packaging, icone, splash, voce e release GPLv3 | 82% | Keystore reale e checklist store |

## Ordine operativo da seguire

1. Chiudere ring annidati/multipolygon e testare coastline su dati reali.
2. Completare confluenze e raccordi del flusso dei corsi d’acqua.
3. Stabilizzare densità/LOD di vegetazione e rocce senza comparsa/scomparsa.
4. Chiudere edifici, rifugi e POI con footprint e profondità coerenti.
5. Fare un passaggio integrato Bit + traccia + rotazione + camera.
6. Rendere affidabili cache Overpass, Explore e modalità degradata.
7. Misurare il profilo release Android.
8. Solo alla fine rifinire packaging, voce e distribuzione.

Gli ultimi macroblocchi completati sono il raccordo della direzione dei fiumi ai
metadati OSM (con versionamento della cache), la classificazione dei ring
costieri annidati, la stabilizzazione della vegetazione procedurale, il
passaggio degli edifici a footprint puliti con profondità rispetto a Bit e
l’overlay della traccia registrata nella camera pixel-art e il payload
versionato per la condivisione Nostr. Il blocco 8 ora apre lo stream GPS solo
dopo il consenso, usa timeout sui canali GNSS opzionali e mantiene il fallback
nativo LocationManager. Il pacchetto Android usa inoltre il fork vendorizzato
senza Play Services di Roadstr: nessun `FusedLocationClient` o
`play-services-location` entra più nel grafo runtime o nell'APK. Nel blocco 9
sono ora persistenti cache, ranking e
fallback dei sentieri. Il punto 10 è stato rimosso dall’alpha: non vengono
più scaricati né prefetched tile raster pubblici. Un futuro pacchetto regionale
dovrà basarsi su estratti PBF/PMTiles o infrastruttura WildBit con condizioni
di distribuzione esplicitamente compatibili. Nel blocco 11 il renderer ora sospende animazioni e dettagli
secondari durante pan, pinch e rotazione senza cambiare la popolazione degli
sprite; un monitor opzionale in debug raccoglie una finestra mobile dei tempi
build/raster e segnala i frame oltre il budget da 16,7 ms.
Restano profiling release, stress test su dispositivi medi e verifica dei
consumi in background. Durante pan, pinch e rotazione i fetch OSM vengono ora
rinviati fino a camera ferma, evitando lavoro di rete e parsing mentre il
renderer sta già sostenendo il carico del gesto. Il download della viewport
usa inoltre lo zoom selezionato, la cache espone dimensione e pulizia dei file
parziali, e la navigazione sospende i timer quando la scheda Mappa non è
visibile. La diagnostica debug espone
anche hit/miss della cache di proiezione condivisa tra sentieri ed etichette.
Il timeout della UI mappa è ora distinto dall'annullamento reale della rete:
dopo dieci secondi l'interfaccia torna reattiva e mostra lo stato del server,
ma la richiesta attuale può completare in background e pubblicare le celle
ricevute. Solo pan, uscita dalla schermata o una nuova viewport la annullano.
Ogni endpoint Overpass riceve un tentativo breve, così una risposta lenta dà
spazio al fallback; 429, 5xx e timeout entrano in cooldown senza dipendere dal
testo dell'eccezione.
Nel blocco 12 è ora presente un preflight senza dipendenze per verificare
versione, GPLv3, icone launcher, splash Bit e compileSdk Android; in modalità
`--strict` blocca la distribuzione finché resta la firma debug.
Nel renderer il parsing ora assembla i multipolygon OSM da way spezzate o
invertite, assegna correttamente i ring interni e conserva i fori nella cache;
acqua, biomi e vegetazione rispettano questi fori anche dopo la proiezione.
Le rive vengono inoltre distribuite tra anello esterno e isole interne, con
normale terra/acqua invertita per non dipingere la sabbia dentro il lago.
Le relazioni incomplete, con ruoli sconosciuti, segmenti ambigui, ring che si
toccano o geometria mancante non vengono riempite per supposizione: il parser
mantiene invece i way autonomi con geometria e tag propri come fallback. I
calcoli topologici geografici svolgono l'unwrap della longitudine, quindi
isole e multipolygon che attraversano l'antimeridiano conservano area e
contenimento locali.
I corsi d'acqua privi di direzione esplicita usano ora un orientamento
deterministico basato sugli endpoint OSM, così la fase dell'animazione non
inverte casualmente tra refresh o celle adiacenti; i tag `forward`/`backward`
restano prioritari. Prima del fill Canvas, i ring multipolygon vengono inoltre
controllati contro vertici interni ripetuti e autointersezioni, con fallback
conservativo sui way autonomi quando la topologia non è affidabile.
Le way d'acqua con nodi completi e coordinate coincidenti vengono inoltre raccordate in pennellate
continue lungo le catene di grado due; le confluenze restano rami separati e
non vengono trasformate in un unico corso inventato. Questo elimina giunti e
discontinuità della texture senza alterare l'identità dei way nella cache.
I ponti espliciti vengono ora ancorati agli intervalli di intersezione della
reale superficie d'acqua, con esclusione delle isole interne; su poligoni
concavi si seleziona l'intervallo che contiene il centro del way. Se esistono
poligoni d'acqua nella cella ma il bridge way non ne attraversa nessuno, il
ponte viene omesso per evitare sprite sospesi sulla terraferma. I guadi restano
invece disponibili solo quando il tag OSM `ford` è esplicito.
La ricerca del poligono è ora limitata all'estensione finita della way: un lago
più lontano ma allineato sullo stesso asse non può più attrarre lo sprite del
ponte. Se più superfici sono candidate viene scelta quella più vicina al way.
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
Alberi, rocce, cespugli, fiori, POI ed edifici ordinano ora la profondità sulla
Y proiettata dalla camera, non sulla latitudine geografica: il rapporto
fronte/retro resta quindi corretto a qualsiasi rotazione. Gli edifici usano il
bordo inferiore proiettato del footprint come contatto col terreno. Durante
pan e pinch la popolazione degli sprite resta invariata; il renderer recupera
tempo sospendendo animazioni ambientali, etichette e dettaglio urbano, senza
far sparire e ricomparire gli oggetti geografici.
Il compositore divide inoltre POI, rifugi e cartelli nelle due fasce di
profondità rispetto al pivot di Bit: gli elementi dietro alla mascotte vengono
disegnati prima di lui, quelli davanti dopo. Le etichette e i target
interattivi esistono solo nel passaggio frontale, quindi non sono duplicati.
Gli anchor OSM semanticamente importanti sono indicizzati in una piccola griglia
spaziale geografica (con continuità all'antimeridiano): alberi, rocce e
cespugli procedurali mantengono una fascia libera attorno a essi senza scansioni
lineari costose per ogni sprite.
Nel passaggio successivo di robustezza il renderer ha rimosso un costo
proporzionale alla dimensione completa di laghi/coastline: le texture riempiono
solo il rettangolo visibile dopo il clip, i path sono riusati fra i frame
ambientali e i vertici consecutivi sotto la soglia di un pixel vengono omessi
solo nel painter. Le svolte nette restano presenti; la geometria OSM e quella
usata per routing non vengono alterate.
Il budget adattivo ora è effettivo anche nelle build release: il monitor
compatto seleziona una fascia solo quando cambia la pressione media dei frame,
causando al massimo un rebuild della scena. Le fasce riducono moduli di riva,
texture e highlight ambientali e la frequenza del clock; acqua, sentieri,
POI e dati di sicurezza restano sempre disegnati.
Per way OSM molto dense il lavoro viene ridotto prima della proiezione, non
dopo: corsi d'acqua e strade comuni hanno un cap coerente con lo zoom, mentre
le way escursionistiche identificate da ref o relazione conservano un
campionamento più fitto. Il cap finale mantiene prima endpoint e svolte
visivamente più nette, poi campiona i tratti rettilinei rimanenti; la
geometria sorgente non viene mai modificata.
Il pannello debug/profile espone ora una fotografia della scena corrente:
conteggio di aree, vie, POI, vertici, acqua e bosco, oltre a una classificazione
leggera/media/densa. La fotografia misura il carico sorgente prima del Canvas,
così un test su smartphone può correlare direttamente la risposta OSM ai tempi
build/raster del monitor; il tablet resta un controllo aggiuntivo per gli
scenari di massima densità.
Il culling geografico usa inoltre intervalli longitudinali circolari: extent,
viewport retained e predicati di contenimento non perdono più poligoni o way
che attraversano l'antimeridiano. Le operazioni di area, punto-in-poligono e
distanza dal bordo usano la stessa longitudine locale unwrap, mantenendo
coerenti rendering e collisioni procedurali su isole globali.
Il passaggio POI applica ora un LOD deterministico: i marker prioritari per
orientamento e sicurezza restano sempre presenti, mentre quelli secondari
vengono limitati alle viste panoramiche. Il limite è applicato dopo il culling
geografico e prima di proiezione, profondità ed etichette, riducendo il costo
del Canvas senza alterare i dati OSM o i target dei POI prioritari.
Gli offset proiettati dei POI vengono inoltre riusati nel painter per depth
sort, sprite e label layout, eliminando proiezioni duplicate nelle scene dense.
L'adattamento della qualità ai tempi build/raster usa ora isteresi: la
degradazione è immediata oltre soglia, mentre il recupero dalle fasce
intermedie è progressivo. Un campione nettamente sotto budget ripristina il
dettaglio pieno, evitando rebuild oscillanti durante gesti e shader warm-up.
La rete dei corsi d'acqua mantiene inoltre uno snapshot topologico per la
geometria OSM e una proiezione per la camera corrente: i rebuild dovuti a Bit,
overlay o pannelli diagnostici non ricomputano catene e endpoint invariati.
Le linee allo stesso livello vengono anche ordinate con un tie-break
deterministico sulla geometria, evitando flicker quando Overpass restituisce i
way in ordine diverso o le celle vengono unite.
Il monitor dei frame conserva tutti i campioni ma pubblica il riepilogo a
intervalli ravvicinati in release, riducendo rebuild e notifiche Dart senza
perdere la reazione alla pressione prolungata.

Il mock pixel-art applica ora un contratto di bounds al posizionamento degli
sprite: l'anchor viene risolto sul canvas nativo e il rettangolo viene traslato
solo quando uscirebbe dal bordo della scena. Questo evita che il clipping
implicito dello Stack tagli alberi grandi ai bordi e mantiene dimensioni native,
ordine di profondità e filtro nearest. Un test carica inoltre i PNG degli
alberi e verifica che il canvas dichiarato coincida con quello reale.

Gli alberi censiti da OSM restano ora eleggibili anche alle viste panoramiche:
il layer usa lo stesso sottoinsieme LOD deterministico della vegetazione
procedurale, con un budget ridotto ma non nullo. Lo zoom non può più eliminare
in blocco un bosco mappato; il dettaglio cresce per bande stabili quando la
camera si avvicina.

Le rocce procedurali usano ora le stesse bande quantizzate: durante un pinch
non viene più aggiunta o rimossa una roccia a ogni frazione di zoom. I POI
prioritari (rifugi, guadi, punti panoramici e cartelli) restano sempre fuori
dal budget decorativo e continuano a essere disegnati e interattivi.

Il layer degli edifici conserva inoltre un campione stabile durante pan, pinch
e rotazione: massimo 48 footprint semplificati senza inset del tetto durante
il gesto, fino a 120 con dettaglio completo a camera ferma. La profondità resta
calcolata sui vertici proiettati, quindi rifugi, edifici e cartelli mantengono
la relazione corretta con Bit a ogni orientamento.

Anche cespugli e vegetazione bassa sono ora divisi rispetto al pivot proiettato
di Bit: la fascia frontale può coprire soltanto la sua silhouette inferiore,
mentre la fascia posteriore rimane dietro anche a 90° di rotazione. Bit usa
inoltre davvero la dimensione nativa fornita dal chiamante. La traccia
registrata conserva gli endpoint ma, durante un gesto, usa un limite e una
semplificazione temporanei più conservativi per non riproiettare migliaia di
fix GPS a ogni frame.

Fiori e rocce usano bande LOD discrete, quindi non lampeggiano a ogni frazione
di zoom. Le proiezioni dei fiori sono riusate per culling, ordine di profondità
e draw. Le curve di livello ricevono infine un budget separato: il rilievo
resta leggibile, mentre dataset altimetrici molto densi vengono limitati e
semplificati soltanto durante pan, pinch e rotazione.

Il budget della scena considera ora anche il numero di vertici geografici, non
solo il conteggio di aree, linee e POI. Una coastline o una way densissima
riduce quindi esclusivamente l'ornamentazione prima di pesare su CPU e batteria;
acqua, sentieri, geometria mappata e POI di sicurezza restano sempre presenti.

Il profilo locale del renderer include ora anche un replay di risposta in
formato OSM/Overpass, elaborata dal parser di produzione prima del Canvas. La
fixture comprende un multipolygon d'acqua spezzato con isola interna, bosco,
prato, roccia, torrente, sentieri con relazione escursionistica, ponte, rifugio,
cartello, fonte e alberi mappati. Il test verifica parsing, topologia e
round-trip della cache locale delle feature senza richiedere GPS, rete o un server Overpass.
Nel pannello `renderer_profile_main.dart` il pulsante della scena ora alterna
standard, replay OSM e stress, così i controlli di pan, zoom e rotazione usano
le stesse geometrie locali e ripetibili.

Le proiezioni Canvas di biomi e geologia sono ora mantenute per una chiave di
camera esatta e per le identità delle aree OSM. Un rebuild dovuto a GPS, Bit o
interfaccia con camera immobile riusa quindi path e shader già pronti; un vero
pan, pinch, rotazione, cambio bounds o cambio dati invalida immediatamente la
cache. Non viene applicata alcuna quantizzazione geografica che possa spostare
un bordo o nascondere una geometria.

Il layer dei laghi applica lo stesso principio a poligoni, isole e rive: la
proiezione e gli anchor dei moduli di costa restano in cache con chiave di
camera esatta, mentre il clock ambiente ridisegna solo la fase dell'acqua. Le
mappe di immagini e shader sono immutabili fra un caricamento asset e l'altro,
eliminando repaint completi causati da rebuild esterni a parità di camera.

Per riprodurre dati reali senza contattare Overpass, le build debug/profile
espongono nella scheda Livelli il comando `Salva replay locale renderer`. Il
file versionato contiene soltanto il `MapFeatureCollection` già normalizzato e
la camera (centro, zoom, rotazione), resta nei documenti privati dell'app e
non viene condiviso o inviato. `renderer_profile_main.dart` può poi aprirlo
con il selettore file e ricostruire la stessa scena. Il decoder impone una
dimensione massima di 20 MB, controlla versione e camera e usa il codec cache
di produzione; il formato è quindi adatto a catturare una cella reale quando
un dispositivo è collegato, senza rendere i test dipendenti dalla rete.
La lettura, validazione e ricostruzione delle geometrie del bundle, così come
la sua codifica in esportazione, avvengono su un isolate: una scena densa non
può congelare l'interfaccia mentre si apre o salva il replay.

Anche la vegetazione bassa conserva ora il sottoinsieme LOD gia proiettato e
ordinato per una chiave di camera esatta. Un nuovo fix GPS di Bit modifica solo
il pivot che separa cespugli davanti e dietro al personaggio: non rigenera,
non riproietta e non riordina gli sprite. Pan, zoom, rotazione, dati OSM o
budget decorativo continuano invece a invalidare subito la cache, cosi la
posizione visiva non viene mai approssimata.

Alberi, rocce e cespugli usano inoltre una frontiera di profondita sullo
schermo, trovata con ricerca binaria sulla lista gia ordinata. Durante
l'interpolazione di Bit la tela resta invariata finche il personaggio non
supera davvero il piede proiettato di un oggetto; in quel momento cambiano
solo le due slice necessarie. Il confronto usa esclusivamente la Y proiettata,
quindi conserva la stessa regola con qualunque rotazione della mappa.

La cache delle proiezioni di alberi e rocce include anche i bounds effettivi
del viewport e il tier di pressione prestazionale. Un cambio di orientamento,
di dimensione della finestra o di budget non puo quindi riutilizzare una
selezione fuori campo; al tempo stesso una camera invariata conserva il fast
path senza lavoro geometrico aggiuntivo.

POI, rifugi e cartelli riusano ora la stessa lista visibile gia proiettata e
ordinata per camera. Il limite e le priorita restano quelli esistenti (i POI
di sicurezza non vengono declassati); il pivot di Bit seleziona solo il range
di profondita necessario. Anche hit-test, etichette e semantica leggono gli
stessi anchor, eliminando proiezioni ripetute durante la camminata.

I footprint urbani rimangono un contesto visivo secondario e sono ancora
limitati alle viste ravvicinate. Quando presenti, anelli, fori e anchor
proiettati sono pero memorizzati per camera e divisi con la stessa frontiera
di profondita di Bit: un fix GPS non ricostruisce piu poligoni di tetti e muri
gia identici sullo schermo.

Il corso d'acqua lineare ha ora due pass Canvas: rive, fango e riempimento
blu sono statici in una `RepaintBoundary`; il clock ambiente anima soltanto
texture e riflessi del flusso. Durante pan, pinch o pressione alta l'overlay
animato non viene neppure montato, mentre il fiume completo resta leggibile.
Le curve di livello usano una cache di proiezione separata per camera.

La cache condivisa di sentieri e relative etichette usa ora i valori esatti
di centro, zoom, rotazione e bounds, senza arrotondamenti. La cache puo quindi
ridurre solo calcoli identici: non puo mantenere una geometria vecchia per
una frazione di spostamento e alterare la lettura di una biforcazione.

Le texture pixel comuni vengono ora risolte una sola volta dal compositore:
terra, acqua, rive, fiumi, sentieri, ponti, POI, alberi e cespugli riusano il
medesimo decode anche dopo il rientro nella scheda Mappa. Il contenitore è
svuotato con la pressione memoria Android, quindi non trattiene target GPU,
shader dipendenti dalla camera o dati geografici e non contraddice lo
smontaggio della mappa fuori scheda.

Il warm-up avvia lo stesso decode condiviso per ogni materiale base del
renderer (prato, foresta, roccia, neve, acqua, rive e sentieri). Il passaggio
in una nuova zona verde mantiene quindi la propria texture anche al primo
frame disponibile, senza il flash di un fallback verde uniforme.

Sul Pixel 10 la scena stress locale misurava 18,0 ms p95 con il gesto
deterministico. La fascia di pressione grave limita ora soltanto la
vegetazione decorativa al 35% (bosco ancora fitto e stabile) e porta la stessa
misura a 15,9 ms p95; sentieri, acqua, Bit e POI prioritari non cambiano.

Il tracciato GPS registrato conserva ora un cache della sua proiezione per
camera e rileva anche i nuovi fix aggiunti alla lista mutabile del recorder.
Un rebuild esterno riusa il path gia pronto; un nuovo fix aggiorna la sola
geometria di visualizzazione, mantenendo sempre origin e posizione corrente
esatti e lasciando intatti tutti i punti sorgente per salvataggio e condivisione.
