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
   OSM (terra a sinistra, acqua a destra).
6. Rami ambigui, assenza di node ID e mismatch geometria/node ID vengono
   registrati e non vengono ricomposti artificialmente.

Questa geometria è **solo cartografica**. Non è usata per ricerca percorsi,
navigazione o valutazioni di sicurezza.
