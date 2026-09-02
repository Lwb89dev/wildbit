# WildBit Pixel Map — kit asset e silhouette del mock v0.1

**Dipendenza:** `pixel_map_renderer_spec.md` v0.1.  
**Scopo:** validare composizione, ancoraggi, collisioni, LOD e occlusioni in
una valle reale prima di investire nell’artwork HD‑2D definitivo.

Le silhouette non sono il look finale. Sono forme pixel-snapped a 1–3 colori,
con dimensioni e maschere finali: se il mock funziona con queste, l’artwork
ricco può sostituirle senza cambiare il renderer.

## 1. Convenzioni del kit

### 1.1 File e coordinate

```text
assets/map/mock/
  terrain/     # tile seamless 16×16
  objects/     # silhouette singole con canvas trasparente
  structures/  # moduli ponte e rifugio
  masks/       # footprint e occlusione, non disegnati
```

- Origine dello sprite: alto-sinistra del canvas.
- Ancora geografica: `anchorX, anchorY`, espressa in pixel del canvas.
- Footprint: rettangolo o poligono a terra usato dall’indice collisioni.
- `drawOrder`: gruppo di composizione della specifica principale.
- Ogni sprite mantiene una cornice trasparente di 1 pixel: evita clipping e
  rende immediato individuare gli errori di ancoraggio.

### 1.2 Colori provvisori

| Ruolo | Colore | Uso |
|---|---|---|
| terreno | `#6F963D` | prato/riempimento |
| acqua | `#28698A` | corsi d’acqua e lago/mare |
| sentiero | `#D2A866` | fascia percorribile |
| vegetazione | `#1C4736` | chiome, cespugli |
| roccia | `#59605C` | massi e affioramenti |
| struttura | `#765031` | ponti, cartelli, rifugi |
| ombra | `#102A28` al 45% | ombre a terra |
| debug footprint | `#FF00FF` al 35% | solo modalità debug |

Il renderer non deve dipendere da questi colori: li sostituiremo attraverso
asset e palette, non con condizioni nel codice.

## 2. Terreno minimo

| ID | Canvas | Varianti | Ancora | Livello | Silhouette |
|---|---:|---:|---|---|---|
| `grass_base` | 16×16 | 3 | n/a | 1 | pieno verde, 2–3 pixel di variazione |
| `forest_floor` | 16×16 | 2 | n/a | 1 | verde scuro, macchie rade |
| `rock_base` | 16×16 | 3 | n/a | 1 | grigio irregolare, nessun oggetto alto |
| `sand_base` | 16×16 | 2 | n/a | 1 | sabbia per spiaggia e rive lacustri |
| `water_still` | 16×16 | 3 | n/a | 1 | blu uniforme con 1 onda orizzontale |
| `water_flow` | 16×16 | 4 | n/a | 1 | blu con direzione e schiuma minima |
| `trail_base` | 16×16 | 3 | n/a | 4 | fascia ocra con bordo scuro |
| `track_base` | 16×16 | 2 | n/a | 4 | sterrato più largo/scuro |

Per il mock è sufficiente disegnare `water_flow` in quattro orientazioni
cardinali. Diagonali e curve sono generati dal compositore con segmenti e
cap, non con una texture stirata.

## 3. Oggetti vegetali

### 3.1 Alberi

| ID | Canvas | Anchor | Footprint | Layer corpo | Silhouette mock |
|---|---:|---:|---:|---:|---|
| `tree_deciduous_s` | 24×32 | 12, 30 | 12×8 | 5 | chioma circolare + tronco 3px |
| `tree_deciduous_l` | 32×40 | 16, 38 | 16×10 | 5 | chioma larga irregolare + tronco |
| `tree_conifer` | 32×48 | 16, 46 | 14×8 | 5 | tre triangoli sovrapposti + tronco |
| `tree_coastal` | 32×40 | 16, 38 | 16×9 | 5 | chioma inclinata dal vento + tronco |

Ogni albero richiede due artefatti separati:

1. **ombra** 16×8 nel layer 3, con anchor identico al piede;
2. **corpo** nel layer 5, diviso concettualmente in tronco e chioma.

Il mock usa una `occlusionMask` che copre solo il terzo inferiore della chioma:
Bit può essere davanti alla parte bassa o dietro la chioma, ma la sua testa
non può sparire interamente.

### 3.2 Cespugli e microflora

| ID | Canvas | Anchor | Footprint | Layer | Silhouette mock |
|---|---:|---:|---:|---:|---|
| `shrub_round` | 16×16 | 8, 14 | 12×6 | 5 | cupola bassa |
| `shrub_wide` | 24×16 | 12, 14 | 20×6 | 5 | due cupole sovrapposte |
| `shrub_riverside` | 16×16 | 8, 14 | 12×6 | 5 | cupola con base irregolare |
| `flowers_cluster_a` | 8×8 | 4, 7 | 6×3 | 3 | tre pixel luminosi |
| `flowers_cluster_b` | 8×8 | 4, 7 | 6×3 | 3 | cinque pixel a gruppo |

I fiori non hanno ombra né maschera di occlusione. I cespugli possono coprire
solo gli ultimi 3 pixel verticali di Bit e mai il suo marker/ancora.

## 4. Rocce

| ID | Canvas | Anchor | Footprint | Layer | Silhouette mock |
|---|---:|---:|---:|---:|---|
| `pebble` | 8×8 | 4, 6 | 6×3 | 2 | rombo basso |
| `boulder` | 16×16 | 8, 14 | 12×7 | 2/5 | trapezio con faccia luce/ombra |
| `rock_block` | 32×24 | 16, 22 | 28×9 | 2/5 | blocco spezzato, tre facce |
| `rock_wet` | 16×16 | 8, 14 | 12×7 | 2 | masso con base acqua |
| `outcrop` | 48×32 | 24, 30 | 44×12 | 2 | cresta frastagliata |

Rocce nel layer 2 sono strutturali e rimangono dietro sentieri; rocce nel
layer 5 sono piccoli massi di primo piano. Il mock deve verificare entrambe le
posizioni: questa distinzione evita che un masso interrompa visivamente un
sentiero già disegnato.

## 5. Acqua, rive e spiaggia

| ID | Canvas/modulo | Ancora | Layer | Silhouette mock |
|---|---:|---|---:|---|
| `shore_grass` | 16×16 | n/a | 2 | bordo verde scuro di 2–4px |
| `shore_sand` | 16×16 | n/a | 2 | bordo sabbia ocra chiara |
| `shore_rock` | 16×16 | n/a | 2 | bordo grigio dentellato |
| `foam_stream` | 8×8 | n/a | 2 | due trattini chiari |
| `foam_coast` | 16×8 | n/a | 2 | linea spezzata bianca/blu |
| `reeds` | 16×24 | 8, 22 | 12×5 | 3 | tre steli verticali |

Le rive sono moduli di bordo, non sprites casuali sopra acqua. Il compositore
riceve il confine del poligono acqua, ne calcola normale/verso e sceglie la
variante adatta: sabbia per spiaggia, roccia per costa/fiume veloce, erba o
canneti per sponda lacustre.

## 6. Ponti e guadi modulari

| ID | Canvas | Anchor | Footprint | Layer | Silhouette mock |
|---|---:|---:|---:|---:|---|
| `bridge_foot_start/end` | 16×16 | 8, 14 | 16×8 | 6 | tavole + due pali |
| `bridge_foot_mid` | 16×16 | 8, 14 | 16×8 | 6 | tavole ripetibili |
| `bridge_track_start/end` | 16×24 | 8, 22 | 16×16 | 6 | impalcato largo |
| `bridge_track_mid` | 16×24 | 8, 22 | 16×16 | 6 | impalcato ripetibile |
| `ford_stones` | 16×16 | 8, 14 | 16×8 | 6 | 3–4 pietre basse |

Il mock deve sostenere moduli orizzontali e verticali. Le diagonali sono fuori
scope del primo asset kit, ma il modello di dati deve conservare l’angolo per
non bloccare il lavoro futuro.

## 7. Cartelli e rifugi

| ID | Canvas | Anchor | Footprint | Layer | Silhouette mock |
|---|---:|---:|---:|---:|---|
| `guidepost_single` | 16×24 | 8, 22 | 8×5 | 6 | palo + una freccia |
| `guidepost_multi` | 16×24 | 8, 22 | 8×5 | 6 | palo + due frecce |
| `trail_marker_low` | 8×12 | 4, 10 | 6×3 | 6 | paletto basso |
| `hut_bivouac` | 32×32 | 16, 30 | 28×12 | 6 | tetto triangolare + porta |
| `hut_alpine` | 48×48 | 24, 46 | 44×16 | 6 | tetto largo + porta |
| `hut_shed` | 32×32 | 16, 30 | 28×12 | 6 | capanna rettangolare |

Per i rifugi il footprint deve esporre una **entrance zone**: rettangolo di
12×8 pixel davanti alla porta, proibito a vegetazione, rocce e cartelli. Un
cartello deve mantenere 8 pixel liberi dal bordo centrale del sentiero.

## 8. Pass di test obbligatori

Il renderer del mock non è accettato finché non supera tutti questi test
visuali con overlay debug attivabile:

1. **Ancora:** un albero, un masso, un cartello e Bit poggiano sullo stesso
   piano terreno, senza galleggiare.
2. **Sentiero:** nessun albero/cespuglio/fiore copre la fascia centrale
   percorribile; un masso in primo piano può solo sfiorarne il bordo.
3. **Acqua:** riva, canneto, masso bagnato e ponte rispettano il bordo acqua.
4. **Ponte:** il percorso e Bit passano sopra l’impalcato; acqua e schiuma
   restano sotto.
5. **Rifugio:** ingresso libero, sentiero di arrivo non nascosto.
6. **Bit:** testa sempre visibile dietro un albero; gambe possono essere
   parzialmente coperte da cespuglio/erba.
7. **Determinismo:** riaprire lo stesso chunk produce identiche varianti e
   posizioni di tutti gli oggetti.
8. **Bordo chunk:** nessun doppione/taglio di un albero, ponte o rifugio sul
   confine fra chunk adiacenti.

## 9. Sequenza di realizzazione

1. Definire in codice le strutture `MockAssetSpec`, `Footprint`, `Anchor` e
   `OcclusionMask`, senza dipendenza da artwork finale.
2. Disegnare automaticamente silhouette primitive con gli ID di questa lista.
3. Comporre una scena test statica che eserciti tutti gli otto test visuali.
4. Correggere coordinate, collisioni e draw order.
5. Solo allora sostituire una famiglia alla volta con sprite pixel-art finali.

Il catalogo mantiene inoltre il contratto nativo degli sprite arborei (percorso,
dimensioni PNG e ancora). I test Flutter decodificano i quattro asset reali,
così una modifica grafica che cambia canvas o allineamento viene rilevata prima
del rendering sul dispositivo.
