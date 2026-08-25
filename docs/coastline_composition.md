# Macro-area: coastline globale

Il renderer non usa tile OSM né filtri su una mappa raster. Per il mare deve
quindi costruire una geometria renderizzabile dalla semantica OSM.

1. Overpass richiede `natural=coastline` insieme a geometria e node ID.
2. La cache conserva i node ID e usa un formato versionato: cache precedenti
   vengono aggiornate prima di essere usate per le coste.
3. Il compositore unisce solo `fine way A == inizio way B`. Non esistono snap
   geografici né deduzioni per vicinanza.
4. Una catena chiusa è un’isola: il renderer compone tutte le isole con
   `evenOdd`, lasciando le terre come fori nel mare.
5. Una catena aperta riempie soltanto il lato destro, conforme alla convenzione
   OSM (terra a sinistra, acqua a destra). La fascia d’acqua viene costruita
   con un offset locale su ogni vertice, non con una sola normale agli estremi:
   baie, promontori e frammenti tagliati dal viewport non possono quindi
   richiudersi accidentalmente verso terra.
6. Rami ambigui, assenza di node ID, mismatch geometria/node ID e ring chiusi
   degeneri vengono registrati e non vengono ricomposti artificialmente.
7. Prima della rotazione della camera, le coordinate proiettate vengono
   riunite nel world-copy più vicino al viewport: un’isola o una costa che
   attraversa l’antimeridiano non genera segmenti attraverso mezzo globo.

Questa geometria è **solo cartografica**. Non è usata per ricerca percorsi,
navigazione o valutazioni di sicurezza.
