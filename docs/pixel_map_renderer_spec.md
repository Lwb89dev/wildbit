# WildBit Pixel Map — specifica visiva e tecnica v0.1

**Stato:** proposta da validare nel prototipo della valle/bosco.  
**Obiettivo:** una mappa geografica leggibile, costruita da dati vettoriali
OSM ma illustrata come un mondo top-down pixel-art originale. Non è ammesso
usare tile raster OSM come immagine di fondo nello stile finale.

## 1. Decisione di motore

Il prototipo e la prima versione di produzione usano **Dart + Flutter Canvas**:

- `CustomPainter` per il compositore di un chunk;
- `PictureRecorder`/cache immagini per non ridisegnare chunk invariati;
- FlutterMap solo per proiezione, camera, gesture e coordinate;
- nessun FFI, C++, Qt, Skia esterno o codice/artwork di OsmAnd.

Questa decisione non esclude C++ in futuro. Un modulo nativo potrà essere
valutato solo dopo benchmark reali se la composizione di chunk o il clipping
delle geometrie supera stabilmente il budget di frame. Anche in quel caso sarà
un componente WildBit ristretto, non OsmAnd-core.

## 2. Coordinate, pixel grid e chunk

### 2.1 Griglia visiva

La cella di stile è un **pixel logico**. Tutti gli asset e le coordinate di
disegno vengono arrotondati a questa griglia; antialiasing e interpolazione
lineare sono vietati nel renderer del mondo.

| Proprietà | Valore iniziale | Motivo |
|---|---:|---|
| Dimensione asset terreno | 16 × 16 pixel | Sufficiente per trama ricca, facile da comporre |
| Dimensione chunk composito | 256 × 256 pixel | Cache semplice e 16 × 16 tile di terreno |
| Scala di presentazione | 2×, 3× o 4× nearest-neighbour | Nessun blur su schermi diversi |
| Margine chunk | 32 pixel per lato | Vegetazione/rive non devono spezzarsi al bordo |
| Unità geografica | Web Mercator, proiezione esistente | Coerenza con GPS e gesture |

Un pixel non corrisponde a un numero fisso di metri: la conversione dipende
dallo zoom. Il renderer conserva la geometria geografica, poi la quantizza al
pixel logico del livello di dettaglio corrente.

### 2.2 Livelli di dettaglio (LOD)

| Zoom FlutterMap | Modalità | Elementi visibili |
|---|---|---|
| 3–10 | panoramica | acqua, costa, grandi foreste/prati, strade principali, traccia |
| 11–12 | regione | aree naturali, fiumi larghi, piste forestali, rifugi maggiori |
| 13–14 | escursione | sentieri, torrenti, rocce grandi, vegetazione a gruppi, POI |
| 15–16 | avventura | alberi, cespugli, rive, fiori, rocce, ponti, cartelli, Bit |
| 17–18 | ravvicinata | varianti terreno, sassi piccoli, acqua animata, dettagli sentiero |
| 19 | ispezione | consentito solo su cache locale; non aumenta la densità oltre LOD 17–18 |

La camera può avere zoom continuo, ma lo stile cambia solo alle soglie LOD;
fra due soglie il chunk viene scalato nearest-neighbour e non rigenerato a ogni
frame.

## 3. Palette

La palette è limitata per disciplina artistica, non perché il display abbia un
vincolo tecnico. I colori nuovi devono riusare una voce esistente salvo
approvazione esplicita.

### 3.1 Giorno — 30 colori

| Famiglia | Colori |
|---|---|
| Acqua | `#183F5A`, `#28698A`, `#4D97B6`, `#9BD5DE`, `#E4F5E7` |
| Erba/prato | `#253E25`, `#426A31`, `#6F963D`, `#9CBC4A`, `#C7D86B`, `#E5EC9A` |
| Bosco | `#102A28`, `#1C4736`, `#2F6540`, `#4C8148`, `#739D50` |
| Terra/sentiero | `#4A3424`, `#765031`, `#A87945`, `#D2A866`, `#E7C886` |
| Roccia | `#353B3C`, `#59605C`, `#858476`, `#B5AD96`, `#E0D7C1` |
| Accenti | `#F2F0D4`, `#FFFFFF`, `#E8B83E`, `#D3733C`, `#B66AB1` |

### 3.2 Notte — 22 colori

La notte non applica una tinta semitrasparente alla mappa. È una palette
autonoma: acqua blu notte, terreno desaturato, ombre profonde, luce calda di
rifugi/cartelli e contrasto sufficiente per traccia e Bit.

| Famiglia | Colori |
|---|---|
| Acqua | `#10263E`, `#1C4C6B`, `#397A93`, `#80B7BD` |
| Vegetazione | `#0D1E23`, `#18322C`, `#2D4D38`, `#4F6841`, `#71824B` |
| Terra/roccia | `#2B2A2E`, `#51443B`, `#7E654A`, `#A78D68`, `#C9B999` |
| Luce/accenti | `#F7D77D`, `#FFF2BE`, `#D28EE0`, `#B9D9DE` |

## 4. Le sette famiglie iniziali

Queste sono le sole famiglie che il primo mock deve conoscere. Ogni famiglia
ha una grammatica visiva propria: non esiste un generico riempimento verde o
blu. Mare e lago sono varianti distinte della stessa famiglia di acqua ferma,
ma hanno riva, scala e dettaglio diversi.

### 4.1 Prato e terreno aperto

| Campo | Definizione |
|---|---|
| Input OSM | `landuse=meadow`, `natural=grassland`, `landuse=farmland` non coltivato |
| Base | Tile 16×16 d’erba con 3 varianti e transizione verso terra/roccia |
| Dettagli | chiazze, erba alta, fiori 8×8, cespugli sparsi |
| Densità | bassa vicino a sentieri; media negli spazi aperti; mai una griglia regolare |
| LOD | massa colorata a zoom 3–12; fiori/erba da zoom 15 |

### 4.2 Foresta

| Campo | Definizione |
|---|---|
| Input OSM | `landuse=forest`, `natural=wood`, `leaf_type=*`, `leaf_cycle=*` se presenti |
| Base | terreno più scuro e bordo forestale irregolare |
| Dettagli | chiome 32×40, conifere 32×48, sottobosco e tronchi visibili |
| Densità | distribuzione deterministica per poligono; corridoio libero sui sentieri |
| LOD | sagome/scuro di chioma a zoom 11–14; alberi singoli da zoom 15 |

### 4.3 Roccia e ghiaione

| Campo | Definizione |
|---|---|
| Input OSM | `natural=bare_rock`, `natural=scree`, `natural=cliff`, pendenza/DEM in futuro |
| Base | tile roccia con luce dall’alto-sinistra e ombra basso-destra |
| Dettagli | massi 16×16/32×24, crepe e ciuffi d’erba nelle fessure |
| Confini | transizione graduale verso prato; bordo duro solo per falesia/scogliera |
| LOD | massa grigio-bruna da zoom 11; massi individuali da zoom 14 |

### 4.4 Acqua corrente: torrente e fiume

| Campo | Definizione |
|---|---|
| Input OSM | `waterway=stream/river/canal`, poligoni `waterway=riverbank` |
| Base | nastro d’acqua orientato lungo la geometria, non una semplice linea blu |
| Rive | terra umida/erba, sassi radicati al bordo e ombra sotto le sponde |
| Dettagli | rocce, schiuma e increspature solo dove larghezza e pendenza lo giustificano |
| Scala | `stream` stretto e attraversabile; `river` più largo, con variazioni di tono |
| LOD | linea azzurra leggibile da zoom 11; rive e rocce da zoom 14 |

### 4.5 Acqua ferma e aperta: lago e mare

| Campo | Lago | Mare |
|---|---|---|
| Input OSM | `natural=water`, `water=lake/reservoir` | coastline + lato acqua, `natural=bay` |
| Colore | blu-verde più calmo, riflessi brevi | blu più profondo, gradiente verso il largo |
| Riva | canneti/erba, spiaggia o rocce secondo tag | sabbia, dune, scogliera o spiaggia rocciosa |
| Dettagli | piccole onde orizzontali, pietre di riva | onde parallele alla costa, schiuma in battigia/scogli |
| LOD | forma intera già da zoom 3–10 | costa e massa mare già da zoom 3–10 |

Il mare non deve mai apparire come un prato senza dati: l’assenza di costa o
poligoni acqua è un problema dati da segnalare e non da mascherare.

### 4.6 Sentiero escursionistico

| Campo | Definizione |
|---|---|
| Input OSM | `highway=path/footway/bridleway/steps`, `sac_scale`, `surface`, relazioni hiking |
| Base | fascia di terra 8–16 pixel con contorno scuro e bordo consumato |
| Varianti | terra, ghiaia, roccia, tavolato/gradini; la variante dipende da `surface` |
| Bivi | nessuna sovrapposizione casuale di erba al centro; spazio per cartelli |
| LOD | polilinea con colore distinto da zoom 11; fascia illustrata da zoom 13 |

### 4.7 Strada forestale e pista

| Campo | Definizione |
|---|---|
| Input OSM | `highway=track/service/unclassified`, `tracktype`, `surface`, `access` |
| Base | fascia 16–28 pixel, ombra esterna e doppia carreggiata solo se pertinente |
| Varianti | sterrato, ghiaia, asfalto rurale, strada erbosa |
| Relazione | più larga e meno luminosa del sentiero; Bit non viene disegnato come veicolo |
| LOD | visibile a zoom 10; dettagli di carreggiata da zoom 14 |

### Matrice rapida delle fonti

| Famiglia | Geometria preferita | Cosa fare se manca |
|---|---|---|
| Prato, foresta, roccia | poligono | texture neutra solo dentro area nota |
| Torrente/fiume | linea + larghezza/poligono | linea semplificata, mai finto lago |
| Lago | poligono | nessun riempimento se il poligono non è disponibile |
| Mare | coastline/poligono acqua globale | fallback esplicito di dato mancante |
| Sentiero/strada | linea | disegno lineare con larghezza conservativa |

Quando un tag è assente non si inventa una precisione falsa: si applica una
variante neutra della categoria, registrando la confidenza nel chunk debug.

## 5. Libreria oggetti iniziale

Gli oggetti sono asset semantici, non icone Material appoggiate sul mondo. Ogni
asset ha quattro informazioni obbligatorie: `footprint` (spazio fisico a terra),
`anchor` (punto geografico), `occlusionMask` (quali parti possono coprire Bit e
sentieri) e `variants` (almeno quattro, salvo ponti/rifugi che dipendono dalla
geometria).

### 5.1 Regole comuni

| Regola | Definizione |
|---|---|
| Ancora | il punto geografico coincide sempre con il centro del piede/base, mai con il centro dell’immagine |
| Pixel snapping | ancora, posizione e dimensione sono arrotondate alla griglia del LOD attivo |
| Seed | `hash(chunkId, osmFeatureId o cella, variantSetVersion)`; nessun `Random()` non persistente |
| Collisione | ogni oggetto inserisce il proprio `footprint` in un indice spaziale del chunk |
| Bordi | il chunk crea oggetti nel margine di 32 pixel ma il proprietario è il chunk d’origine, così non vengono duplicati |
| Ombra | ombra a terra nel layer 3; corpo dell’oggetto nel layer 5 o 6 |
| LOD | sotto la soglia un gruppo di oggetti diventa texture/densità, non decine di sprite minuscoli |

Le collisioni seguono questa priorità: **acqua > ponte > strada/sentiero >
rifugio/cartello > roccia strutturale > albero > cespuglio > fiore**. Un oggetto
a priorità inferiore si sposta entro il proprio raggio ammesso o viene omesso;
non può sovrascrivere un elemento di navigazione.

### 5.2 Alberi

| Variante | Pixel base | Uso |
|---|---:|---|
| Latifoglia giovane | 24 × 32 | radure, bordi del bosco |
| Latifoglia matura | 32 × 40 | foresta e prati umidi |
| Conifera | 32 × 48 | quote alte, roccia e boschi misti |
| Albero contorto | 32 × 40 | costa, roccia, bordo acqua |

- Input: poligoni foresta/bosco; `natural=tree` come albero puntuale.
- Il bordo di una foresta deve essere più denso e più scuro dell’interno.
- Un corridoio libero pari a 1.5 volte il footprint è obbligatorio attorno a
  sentieri, strade, edifici e rive attraversabili.
- Ogni albero è diviso in ombra, tronco e chioma: Bit può passare dietro la
  chioma bassa ma non deve sparire sopra le spalle.
- LOD: massa di chiome fino a zoom 14; sprite singoli da zoom 15.

### 5.3 Cespugli

| Pixel base | Varianti minime | Posizione |
|---:|---:|---|
| 16 × 16 | 6 | transizione prato-bosco, rive asciutte, radure |

- Input: distribuzione procedurale dentro prato/bosco, `natural=scrub` quando
  disponibile.
- Devono spezzare il bordo perfetto tra due biomi, non riempire casualmente
  tutto lo spazio libero.
- Non possono coprire il centro di sentieri, ponti, cartelli o ingresso rifugio.
- LOD: texture a zoom 13–14; sprite da zoom 15.

### 5.4 Rocce e massi

| Variante | Pixel base | Uso |
|---|---:|---|
| Sasso | 8 × 8 | sentieri ghiaiosi e rive |
| Masso | 16 × 16 | radure, ghiaione, sponde |
| Blocco | 32 × 24 | roccia, riva fiume, scogliera |
| Affioramento | 48 × 32 | `natural=bare_rock`, falesie semplificate |

- Input: roccia/ghiaione, `natural=stone`, massi presso acqua o pendenza.
- Ombra coerente sempre verso basso-destra; nessuna rotazione libera dello
  sprite: sono ammesse quattro orientazioni disegnate.
- Le rocce strutturali possono stringere il sentiero, ma non interromperlo.
- In acqua, solo le varianti “bagnate” possono ricevere schiuma/onda.

### 5.5 Fiori e microflora

| Pixel base | Varianti minime | Palette |
|---:|---:|---|
| 8 × 8 | 8 | bianco, giallo, arancio, viola: solo accenti della palette |

- Input: prato/grassland; mai dedotti su asfalto, roccia nuda o acqua.
- Appaiono a piccoli gruppi irregolari, non come punti uniformemente sparsi.
- Il centro di sentieri e aree di sosta resta libero; il bordo può contenere
  microflora poco densa.
- LOD: invisibili sotto zoom 15. Sono dettaglio, non informazione geografica.

### 5.6 Ponti e guadi

| Tipo | Input OSM | Geometria | Trattamento |
|---|---|---|---|
| Ponte pedonale | `bridge=yes` + `highway=path/footway` | asse sentiero, perpendicolare acqua | tavole 16 × N, parapetto opzionale |
| Ponte strada | `bridge=yes` + `highway=track/service` | asse strada | impalcato più largo, ombra forte |
| Guado | `ford=yes` / `ford=*` | intersezione acqua-percorso | pietre basse, nessun parapetto |

- Un ponte è composto proceduralmente da estremità, moduli centrali e ombra;
  non viene scalato come una singola immagine.
- Ha priorità sullo strato acqua e sul percorso; le rive vengono raccordate ai
  due estremi.
- Bit e la traccia passano sopra l’impalcato, mai sotto l’acqua.
- Se la topologia OSM non conferma l’incrocio acqua/percorso, non si inventa un
  ponte: il renderer conserva entrambe le geometrie e segnala il caso nel debug.

### 5.7 Cartelli escursionistici

| Pixel base | Input OSM | Regola |
|---:|---|---|
| 16 × 24 | `information=guidepost`, `tourism=information`, nodi su relation hiking | solo bivi o nodi informativi reali |

- Varianti: legno chiaro, legno scuro, segnavia basso, freccia multipla.
- Il cartello è nel layer POI, ma il palo è ancorato al terreno e può essere
  parzialmente davanti al bordo del sentiero.
- L’etichetta testuale non è rasterizzata sul cartello: a zoom alto apre un
  tooltip/label vettoriale separato.
- Distanza minima fra cartelli: 48 pixel logici, salvo nodi OSM distinti e
  realmente sovrapposti.

### 5.8 Rifugi

| Variante | Pixel base | Input OSM |
|---|---:|---|
| Bivacco | 32 × 32 | `tourism=wilderness_hut` |
| Rifugio | 48 × 48 | `tourism=alpine_hut`, `amenity=shelter` |
| Capanna | 32 × 32 | `building=hut`, solo se rilevante al sentiero |

- Il footprint è riservato: niente alberi, cespugli o massi sull’ingresso.
- Ogni rifugio ha sentiero/strada di accesso visibile se la geometria esiste.
- È un POI prioritario: resta visibile come sagoma da zoom 13 e sprite completo
  da zoom 15; nome e servizi vengono disegnati in un pass successivo.
- Di notte può emettere una piccola luce calda, soltanto per rifugi verificati.

### 5.9 Asset minimi per il primo mock

| Famiglia | Asset necessari |
|---|---:|
| Alberi | 4 specie × 4 varianti + 4 ombre |
| Cespugli | 6 varianti |
| Rocce | 4 classi × 4 varianti, incluse 2 bagnate |
| Fiori | 8 gruppi |
| Ponti/guadi | 3 estremità, 3 moduli centrali, 3 ombre |
| Cartelli | 4 varianti |
| Rifugi | 3 varianti + 3 ombre |

Prima di generare asset definitivi, il mock può usare silhouette temporanee
monocromatiche **solo** per validare ancore, collisioni e ordine dei layer.

## 6. Livelli obbligatori di composizione

Il compositore usa questi livelli, nell’ordine fisso seguente. Ogni oggetto
riceve un `zIndex` interno e un punto di ancoraggio; non è permesso saltare
arbitrariamente fra livelli.

1. **Acqua e terreno base** — oceano, laghi, prato, foresta e roccia di fondo.
2. **Rive, scogli e rocce strutturali** — edge acqua, massi costieri, creste.
3. **Vegetazione di fondo** — masse forestali, erba alta e ombre al suolo.
4. **Sentieri e strade** — ombra, bordo, carreggiata, attraversamenti.
5. **Vegetazione in primo piano** — alberi/cespugli che possono coprire il
   bordo di sentieri e parte di Bit.
6. **POI e segnaletica** — rifugi, sorgenti, cartelli, ponti e icone geografiche.
7. **Dati dinamici** — percorso registrato, direzione utente, Bit e selezioni.
8. **Interfaccia** — scala, stato GPS, controlli; non appartiene al canvas mondo.

## 7. Regole di leggibilità

- Il sentiero attivo deve distinguersi da qualunque terreno con contrasto di
  luminanza e bordo scuro.
- Acqua e costa devono restare riconoscibili già al LOD panoramica.
- Bit non può essere coperto sopra la testa; solo la parte bassa può passare
  dietro vegetazione in primo piano.
- Nessuna etichetta OSM rasterizzata. I nomi verranno aggiunti in un passaggio
  vettoriale separato, con collision detection.
- Un chunk privo di dati non può fingere di essere bosco: mostra una texture
  neutra e uno stato di caricamento/assenza dati diagnosticabile.

## 8. Budget tecnico iniziale

- rendering camera: nessuna rete sul frame critico;
- cache: massimo 9 chunk LOD attivi (viewport + margine);
- rigenerazione: solo su cambio dati, soglia LOD o invalidazione asset;
- GPS: aggiorna Bit/traccia, non rigenera terreno;
- dettagli: massimo 300 sprite individuali per chunk LOD 15–16, poi batching o
  semplificazione;
- obiettivo iniziale: 60 fps su dispositivo Android medio durante pan senza
  rigenerazione; 30 fps minimo durante composizione di nuovi chunk.

## 9. Criterio di uscita della fase

Un mock statico, in una valle/bosco reale, soddisfa tutti i punti:

1. acqua/torrente, bosco, prato, rocce e almeno un sentiero sono riconoscibili;
2. nessuna tile raster OSM è visibile nello screenshot finale;
3. il risultato è composto da asset WildBit originali e palette sopra definita;
4. le geometrie reali mantengono posizione e connettività;
5. Bit, un cartello e un rifugio rispettano i livelli di occlusione;
6. il confronto con il riferimento mostra una scena illustrata e non una mappa
   convenzionale filtrata.

## 10. Decisioni rimandate

- dati altimetrici e ombreggiatura dei versanti;
- etichette e localizzazione;
- generazione/pacchettizzazione offline nazionale;
- biomi neve, palude, costa marina e aree urbane;
- necessità di un acceleratore nativo C++.

Queste decisioni non bloccano il primo prototipo della valle/bosco.
