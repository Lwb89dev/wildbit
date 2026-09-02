# Budget del renderer interattivo

La mappa è un’interfaccia in movimento: la qualità non può dipendere da un
numero illimitato di sprite o feature OSM.

| Risorsa | Budget corrente | Degrado previsto |
| --- | ---: | --- |
| Alberi pixel | 96 di base, fino a 300 generati più alberi OSM ravvicinati | popolazione adattata a device/scena/frame, identità stabile |
| Poligoni acqua | tutti quelli intersecanti il viewport | rive decorative ridotte, superficie mai omessa |
| Moduli riva | 18 per poligono | nessun modulo sotto zoom 14.5; spaziatura maggiore sopra il budget |
| Sentieri/strade | tutte le linee visibili | vertici semplificati e texture sospesa durante i gesti |
| Corsi d’acqua | tutte le catene visibili | topologia composta una volta e animazione condivisa a 3 fps |
| POI | marker prioritari sempre presenti; secondari con cap LOD | etichette sottoposte a collision layout e LOD |

Regole architetturali:

1. Alberi, sentieri e strade vengono disegnati in Canvas, non come widget
   individuali.
2. Le coordinate sono cullate contro il viewport prima della proiezione.
3. Le polilinee vengono semplificate solo in spazio schermo; la geometria OSM
   originale non viene mai modificata.
4. La topologia costa è costruita al cambio dei dati, non ad ogni pan/zoom;
   a camera invariata anche la sua proiezione Canvas viene riusata durante
   rebuild di GPS, Bit e controlli.
5. Ogni modifica al renderer va verificata in `profile`/`release` su Android:
   obiettivo iniziale 60 fps e frame raster sotto 16,6 ms durante il pan.
6. La topologia dei corsi d'acqua viene composta fuori dal painter animato:
   l'animazione aggiorna solo la fase della texture e non ricostruisce le
   catene OSM a ogni tick.
7. Il caricamento OSM ha un budget UI di 10 secondi: oltre quel limite la
   mappa mantiene i dati già disponibili (o l'anteprima debug) mentre la
   richiesta continua in background per alimentare la cache.
8. Poligoni d'acqua, laghi e biomi mantengono la geometria OSM completa nei
   dati, ma nel painter rimuovono solo vertici consecutivi sotto 0,75 pixel,
   conservando le svolte nette. I fill texture sono limitati al rettangolo
   effettivamente visibile, anche se il poligono proiettato è molto più grande
   dello schermo.
9. Il materiale di una riva (sabbia, fango o roccia) viene calcolato una volta
   per snapshot OSM e riusato durante pan, zoom e rotazione; il path proiettato
   dell'acqua resta riusabile tra i tick dell'animazione.
10. Un campione mobile dei frame è attivo anche in release, ma non espone UI
    diagnostica. Il budget considera anche il p95, non solo la media: quando
    una coda di frame supera 16,7 ms cambia soltanto una fascia di qualità:
    meno moduli decorativi delle rive e highlight d'acqua sospesi; il
    materiale base dell'acqua resta texture anche durante un gesto,
    POI secondari ed edifici ridotti e clock ambientale da 3 fps a 1–1,5 fps.
    Il tier resta attivo anche dopo il gesto finché una finestra sana non ne
    giustifica il recupero. Nel tier grave la quota decorativa scende al 35%,
    mantenendo una canopy rappresentativa ma lasciando sentieri, acqua solida,
    POI e geometrie usate per la sicurezza sempre completi.
11. Le way OSM patologicamente dense vengono pre-campionate prima della
    proiezione: le strade comuni e i corsi d'acqua usano un limite di lavoro
    proporzionato allo zoom, mentre i sentieri con ref o relazione
    escursionistica ricevono un margine più ampio. Endpoint e svolte
    geografiche restano sempre nel working set; nel cap finale le svolte più
    nette hanno priorità sui campioni rettilinei. Il dato originale rimane
    intatto.
12. Un sentiero molto segmentato conserva lo stesso path e la stessa larghezza,
    ma applica la texture in una sola pennellata Canvas invece di una
    trasformazione per segmento. I tratti brevi mantengono il materiale
    orientato localmente; gli overlay di difficoltà/accesso restano invariati.
13. Il culling degli extent usa intervalli longitudinali circolari e non
    confronti numerici lineari: poligoni, way e viewport che attraversano
    l'antimeridiano restano candidati alla proiezione.
14. I marker prioritari (rifugi, punti panoramici, cartelli, cime, guadi,
    acqua e campeggi) non vengono mai scartati dal LOD. Parcheggi e marker
    secondari usano invece un sottoinsieme stabile per zoom, evitando che una
    piazza urbana con centinaia di POI saturi il Canvas.
15. Nel passaggio POI l'offset proiettato viene calcolato una sola volta per
    marker e riusato per ordinamento, sprite e layout dell'etichetta nello
    stesso frame; la semantica viene ricostruita solo quando il painter cambia.
16. Il budget di qualità usa isteresi: la degradazione entra subito quando il
    frame supera le soglie, mentre il recupero da una pressione intermedia
    avviene per fasce. Un campione nettamente sotto budget può ripristinare
    direttamente il dettaglio pieno; questo evita continui rebuild oscillanti
    durante pan, pinch e compilazione iniziale degli shader.
17. La rete dei corsi d'acqua viene composta una volta per snapshot OSM e la
    proiezione viene riusata per la stessa camera. Il painter animato aggiorna
    soltanto fase e dettagli, senza ricostruire endpoint e catene ad ogni
    rebuild del widget.
18. Le linee con lo stesso livello visivo vengono ordinate con un tie-break
    stabile sulla geometria OSM, così l'ordine dei way restituiti da Overpass
    non produce flicker sui raccordi quando le celle vengono unite.
19. Il monitor raccoglie ogni `FrameTiming`, ma notifica il riepilogo a
    intervalli ravvicinati (quattro campioni in release). Il budget adattivo
    resta reattivo, mentre il thread Dart evita un rebuild diagnostico per ogni
    refresh del display.
20. Alberi, rocce e cespugli usano piccoli atlanti GPU: ogni passaggio di
    profondità conserva gli stessi sprite e anchor, ma li invia in batch con
    `drawAtlas` anziché una chiamata `drawImageRect` per oggetto.
21. Laghi e mare separano fill, rive e moduli statici dalle sole increspature
    animate. Un tick ambiente non può più ridisegnare l'intera superficie
    d'acqua; il flusso dei fiumi rimane invece nel relativo layer direzionale.
22. I due passaggi di profondità attorno a Bit condividono culling, proiezione
    e ordinamento di cespugli, POI e impronte urbane. Il secondo passaggio
    cambia solo il range di pittura: non ricampiona né riproietta la stessa
    geografia a ogni aggiornamento dell'attore.
23. Il prato di base viene composto una sola volta in una superficie GPU delle
    dimensioni dello schermo, fuori dalla trasformazione della camera. Il
    renderer non ripete più una texture a ogni frame o movimento della mappa.
24. Dopo quattro secondi senza gesto, il clock delle sole increspature passa
    a 1,5 fps. Al primo pan/pinch torna subito alla cadenza normale; se il
    p95 è sotto pressione, la cadenza più prudente del budget resta sempre
    dominante. Bit, sentieri, acqua statica e GPS non vengono sospesi.
25. Al callback nativo di pressione memoria vengono rilasciate solo le cache
    ricostruibili: proiezioni schermo di linee, POI, vegetazione ed edifici,
    immagini nella cache Flutter e celle OSM decodificate in RAM. La scena
    corrente, la posizione e il database offline cifrato non vengono toccati.
26. La scheda Mappa non resta in un `IndexedStack` quando l'utente è in una
    sezione secondaria: il compositore Canvas viene smontato e libera i suoi
    target GPU. Centro e zoom vengono salvati dal shell e ripristinati al
    rientro; dati OSM e cache offline non vengono riscaricati.
27. Le piccole texture raster del compositore (terreno, acqua, rive, sentieri,
    ponti, POI e vegetazione) condividono un solo decode per asset tra i layer
    e tra i rientri nella scheda Mappa. La cache contiene solo immagini sorgente
    e viene svuotata al segnale Android di memory pressure: shader, atlanti e
    target dipendenti dalla camera restano quindi liberabili.
28. Il warm-up iniziale comprende tutti i materiali di suolo (prato, foresta,
    roccia, neve), acqua/rive e sentieri, non soltanto gli sprite. Così il
    primo ingresso in un nuovo bioma usa già il suo shader: una zona OSM non
    può lampeggiare temporaneamente nel fallback a colore pieno.

## Diagnostica del profilo

In debug, il pannello **Livelli mappa** mostra i tempi medi build/raster, il
95° percentile e il picco della finestra più recente, oltre alla percentuale
di frame oltre 16,7 ms. Il p95 separa una vera instabilita del gesto da un
singolo frame di warm-up degli shader.
Mostra anche gli hit/miss della cache di proiezione condivisa da sentieri ed
etichette. In release lo stesso campionamento resta attivo senza pannello:
serve esclusivamente a selezionare la fascia di qualità più prudente.

Per una misura ripetibile su Android usare `flutter run --profile`, con
priorità agli smartphone (fascia economica, media e top di gamma). Su ogni
telefono eseguire tre cicli di pan continuo di 20 secondi e tre cicli di pinch
tra zoom 12 e 17; il tablet è solo un quarto scenario di stress. Registrare
frame raster, memoria, temperatura e batteria dopo ogni ciclo. Il primo
obiettivo è mantenere il raster sotto 16,6 ms senza aumentare il lavoro di
rete durante il gesto. I fetch OSM devono partire solo dopo che la camera è
ferma.

Il laboratorio locale `renderer_profile_main.dart` include anche un gesto
scriptato di 4,3 secondi su scena standard, replay OSM o stress. Alla fine
congela scena, p95, picco e percentuale di frame lenti: usare quella riga per
confrontare dispositivi e regressioni, senza confondere il risultato con la
finestra mobile del monitor.

Il pulsante del preset nel laboratorio alterna **Tutti i layer**, **Base**,
**Idrologia**, **Terreno**, **Percorsi**, **Vegetazione** e **POI e urbano**.
Ogni preset usa gli stessi dati locali e la stessa camera. Il pulsante di
profilo per layer esegue automaticamente il gesto controllato su tutti i
passaggi, dopo un breve warm-up, e riporta il p95 di ciascuno: così un valore
alto è attribuibile a un gruppo del compositore prima di ridurre qualità o
cambiare codice di produzione.

Misura di riferimento, Pixel 10 in `profile`, scena standard con gesto
scriptato: prima della superficie base precomposta il passaggio **Base** era
circa 23,3 ms p95 e il completo circa 25,3 ms; dopo, **Base** è 10,3 ms e
**Tutti i layer** 16,0 ms p95. È una baseline di confronto, non una garanzia:
ogni telefono reale deve mantenere il proprio margine sotto 16,7 ms.

Sullo stesso Pixel, la scena locale stress (1.380 alberi censiti/generati,
327 aree e 187 linee) superava inizialmente il budget con **18,0 ms p95**.
La fascia di pressione grave riduce gli sprite decorativi al 35% e il batching
delle linee molto segmentate evita una trasformazione Canvas per tratto: il
gesto completo misurato il 1 settembre 2026 misura **15,5 ms p95** (3% frame
lenti). Sentieri, acqua, Bit e POI prioritari restano identici; la misura va
comunque ripetuta sui telefoni meno potenti prima di una release.

La classificazione del renderer resta basata su pixel fisici e complessità
della scena, non sul modello commerciale. Una superficie fisica più grande
parte con una quota decorativa più prudente, non più ricca: questo tutela sia
i telefoni ad alta densità sia i tablet, mentre sentieri, acqua e POI di
sicurezza restano completi a ogni livello.

La modalità di interazione non può ridurre il numero degli sprite già visibili:
farlo produce pop-in al rilascio del gesto e rende incerta la lettura della
mappa. Durante pan, pinch e rotazione il risparmio deriva invece dalla
sospensione dell'orologio ambientale, dalla semplificazione delle polilinee e
dal rinvio di etichette, edifici e fetch. Device factor, complessità della scena
e pressione misurata possono scegliere a monte una popolazione decorativa più
piccola, ma quella popolazione resta deterministica finché i dati non cambiano
o non viene attraversata una banda LOD esplicita.
