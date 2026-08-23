# Budget del renderer interattivo

La mappa è un’interfaccia in movimento: la qualità non può dipendere da un
numero illimitato di sprite o feature OSM.

| Risorsa | Budget corrente | Degrado previsto |
| --- | ---: | --- |
| Alberi pixel | 180 per viewport | nessun albero sotto zoom 15; densità ridotta oltre il budget |
| Poligoni acqua | 10 per viewport | gli altri restano dati disponibili ma non vengono dipinti nel frame |
| Moduli riva | 18 per poligono | nessun modulo sotto zoom 14.5; spaziatura maggiore sopra il budget |
| Sentieri/strade | 48 linee per viewport | feature oltre il budget non vengono pitturate nel frame |
| Corsi d’acqua | 40 linee per viewport | feature oltre il budget non vengono pitturate nel frame |
| POI | 60 marker per viewport | marker eccedenti non vengono costruiti |

Regole architetturali:

1. Alberi, sentieri e strade vengono disegnati in Canvas, non come widget
   individuali.
2. Le coordinate sono cullate contro il viewport prima della proiezione.
3. Le polilinee vengono semplificate solo in spazio schermo; la geometria OSM
   originale non viene mai modificata.
4. La topologia costa è costruita al cambio dei dati, non ad ogni pan/zoom.
5. Ogni modifica al renderer va verificata in `profile`/`release` su Android:
   obiettivo iniziale 60 fps e frame raster sotto 16,6 ms durante il pan.
