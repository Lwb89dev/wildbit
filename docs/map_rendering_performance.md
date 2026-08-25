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
6. La topologia dei corsi d'acqua viene composta fuori dal painter animato:
   l'animazione aggiorna solo la fase della texture e non ricostruisce le
   catene OSM a ogni tick.
7. Il caricamento OSM ha un budget UI di 10 secondi: oltre quel limite la
   mappa mantiene i dati già disponibili (o l'anteprima debug) mentre la
   richiesta continua in background per alimentare la cache.

## Diagnostica del profilo

In debug, il pannello **Livelli mappa** mostra i tempi medi build/raster,
il picco della finestra più recente e la percentuale di frame oltre 16,7 ms.
Mostra anche gli hit/miss della cache di proiezione condivisa da sentieri ed
etichette. La diagnostica non viene avviata nelle build release.

Per una misura ripetibile su Android usare `flutter run --profile`, eseguire
tre cicli di pan continuo di 20 secondi e tre cicli di pinch tra zoom 12 e 17.
Registrare frame raster, memoria e temperatura dopo ogni ciclo; il primo
obiettivo è mantenere il raster sotto 16,6 ms e non aumentare il lavoro di
rete durante il gesto. I fetch OSM devono partire solo dopo che la camera è
ferma.
