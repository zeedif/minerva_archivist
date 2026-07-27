# Guía de comandos

Cada bandera, qué hace, y cómo se combinan las piezas.
[English](GUIDE.md) · **Español** — volver al [README](README.ES.md).

Marcadores: `<dat>` un archivo DAT o una carpeta de DATs · `<raiz-roms>` tu
carpeta de ROMs · `<ruta>` cualquier ruta de archivo.

---

## Opciones comunes

Disponibles en todos los comandos.

| Opción | Significado |
|---|---|
| `-d, --dat <dat>` | Archivo DAT **o** carpeta de DATs. Repetible. Tipo autodetectado |
| `-r, --rom-root <dir>` | Raíz de tu colección de ROMs |
| `--cache <dir>` | Caché de metadatos (por defecto `.minerva-cache`) |
| `-v, --verbose` | Registro detallado |
| `-h, --help` | Uso de ese comando |

Pasar varios DATs los fusiona en una sola ejecución — así es como se unifican un
set MAME-Redump CHD y su equivalente Redump:

```sh
minerva_archivist run -d <dat-mame-redump> -d <dat-redump> -r <raiz-roms>
```

Códigos de salida: `0` correcto · `64` uso incorrecto · `70` fallo en ejecución
(por ejemplo, falta `aria2c`).

---

## Opciones de selección

Compartidas por `filter`, `audit`, `download`, `organize`, `m3u`, `prune` y `run`.
Deciden *sobre qué* juegos actúa un comando.

| Opción | Significado |
|---|---|
| `--lang <códigos>` | Prioridad de idiomas, mejor primero. Ordena y restringe. Por defecto `En` |
| `--region <nombres>` | Prioridad de regiones, mejor primero. Ordena y restringe |
| `--priority <ejes>` | Qué desempates deciden un grupo. Por defecto `lang,region,ra` |
| `--wishlist <ruta>` | Array JSON/JSONC de nombres a seleccionar |
| `--wishlist-mode absolute\|subset` | Qué afirma nombrar un título. Por defecto `absolute` |
| `--achievements any\|approved` | Seleccionar solo títulos con logros |
| `--supersets prefer\|ignore` | Cuánto vale un pack frente a su contenido. Por defecto `prefer` |
| `--exclude <clases>` | Descarta estas clases de volcado |

### `--lang` y `--region`

Ambas **ordenan y restringen**: colocan los volcados de un título y descartan el
título que no responde a nada de la lista. Así, nombrar un solo valor te da ese
segmento — `--lang Es` es el conjunto español, `--region Spain` el de ediciones
españolas — y nombrar varios los ordena.

En vez de enumerar cada valor, dos entradas cubren el resto y se ordenan donde las
pongas:

| Entrada | Cubre |
|---|---|
| `Other` | Cualquier valor que la lista no nombre, y los ausentes salvo que esté `Unknown` |
| `Unknown` | Títulos de los que el DAT no dice nada en ese eje |

`Other` es una sola posición, así que los valores que la comparten recurren a un
orden interno completo —región sobre `USA, World, Canada, Europe, UK, …`, idioma
sobre lo que eso implica— en vez de resolverse arbitrariamente.

```sh
# solo español
minerva_archivist filter -d <dat> --lang Es

# español, luego inglés, luego todo lo demás
minerva_archivist filter -d <dat> --lang Es,En,Other

# España y América primero, el resto sigue siendo bienvenido
minerva_archivist filter -d <dat> --region Spain,USA,Europe,Other
```

Las entradas de `--lang` cubren sus subetiquetas: pedir `Es` acepta `Es-MX`. Sin
`--region`, se usa el orden interno completo, que lista todas las regiones y por
tanto no descarta nada; los títulos sin etiqueta cuentan como `Unknown`.

### `--priority`

Idioma, región y logros tiran en direcciones distintas: preferir tu idioma puede
costarte el volcado que lleva los logros, y al revés. `--priority` dice quién gana,
mejor primero.

| Valor | Efecto |
|---|---|
| `lang,region,ra` | Por defecto. Gana tu idioma; los logros solo desempatan |
| `ra,lang` | Gana el volcado con logros, aunque esté en otro idioma |
| `lang,ra` | Idioma primero, luego logros; la región deja de superar a ninguno |

Dejar fuera `lang` o `ra` los saca del orden por completo. **`region` no**:
conserva un puesto fijo por debajo de lo que sí listaste, porque nada más en la
cadena puede decidir entre dos regiones y un empate entre regiones acabaría
resuelto por la ortografía. Omitirla significa que no debe superar a tu idioma ni
a los logros.

Conviene saberlo antes de poner `ra` primero: un volcado europeo con español
suele no tener logros —se validan contra la edición USA—, así que `ra,lang` pasará
por alto justo el volcado para el que se hizo tu parche de traducción.

Por debajo de lo que listaste el orden es fijo: supersets, región, prioridad del
clonelist, ediciones modernas (una copia de Virtual Console o de consola pierde
frente al original), ediciones económicas (gana la reedición, suele traer las
correcciones), revisión, `(Alt)`/OEM, y por último las listas de promoción y
degradación.

### Lista de deseos

Un array JSON/JSONC de nombres base:

```jsonc
[
  "Chrono Trigger",
  "Final Fantasy VII",
  "Bomber Boy"   // sirve cualquiera de las grafías regionales del título
]
```

El emparejamiento ignora mayúsculas, puntuación, un "The" inicial o final, y las
etiquetas de región y formato. Tras eso es exacto, no por subcadena: usa títulos
base completos. Nombrar cualquier edición de un juego selecciona el juego, y luego
son los órdenes los que eligen su mejor volcado, así que tu grafía nunca decide
con qué región acabas. Nombrar un pack multijuego pide el pack, no cada título que
lleva dentro.

#### `--wishlist-mode`

Una lista de deseos puede ser dos cosas, y una sola respuesta resuelve las dos
mitades de la pregunta.

**`absolute`** (por defecto) — un conjunto propio, **por encima** de `--lang` y
`--region`. Todo lo que nombraste se selecciona; esos órdenes solo eligen cuál de
sus volcados te llevas. Es lo que hace que un título solo en japonés sobreviva a
`--lang Es,En`, que es justo lo que quieres cuando lo nombras para aplicarle un
parche de traducción. Y como está por encima de los órdenes, sería absurdo
descartarlo luego por no tener logros: `--achievements` **se le suma** en vez de
recortarlo.

```sh
--wishlist <ruta> --achievements any   # mi lista, más todo lo que tenga logros
```

**`subset`** — una condición entre las demás. Un título nombrado sigue teniendo que
hablar un idioma del orden, venir de una región del orden y cumplir
`--achievements`, que por tanto **acota** la lista:

```sh
--wishlist <ruta> --wishlist-mode subset --achievements any   # solo los títulos de la lista que tienen logros
```

### `--achievements`

Omítelo y los logros no restringen nada: `--priority ra` sigue ordenándolos. Si lo
pasas, nombra el conjunto que quieres, a la escala que quieres:

| Valor | Conserva |
|---|---|
| `any` | Títulos con logros en alguno de sus volcados, dejando que `--priority` elija cuál los representa |
| `approved` | Solo los volcados contra los que se creó el set, de modo que el volcado aprobado sea el que gane su grupo |

Un volcado se vincula de dos formas, que no valen igual: por **hash** demuestra que
el set se creó contra exactamente esos bytes, por **nombre** solo dice que hay un
título así cubierto. `approved` solo acepta la primera, y el desempate `ra` la
prefiere. `--explain` marca cuál obtuvo cada volcado:

```
WIN Dragon Quest - The Hand of the Heavenly Bride (Europe)  [...]  ra:name
    Dragon Quest V - Hand of the Heavenly Bride (USA)       [...]
```

Dos advertencias. RetroAchievements no cubre Xbox, Xbox 360, PS3, 3DS ni Vita, así
que ahí `--achievements` no selecciona nada. Y en los sistemas de disco los sets se
calculan contra el ejecutable del disco y no contra la imagen, así que todas las
uniones son por nombre y `approved` no selecciona nada: es una herramienta de la
era del cartucho.

### Packs y `--supersets`

Un clonelist lista un pack multijuego bajo **todos** los grupos que contiene, así
que el pack responde por todos ellos. Compite por la plaza de cada juego que
incluye y, al ganarla, la ocupa: obtienes el pack, no el pack más copias sueltas de
lo que ya viene en él.

| Modo | Efecto |
|---|---|
| `prefer` | Por defecto. El pack responde por su contenido y ocupa sus plazas |
| `ignore` | Cada grupo va a una edición propia; el pack solo cubre los grupos que nada más cubre |

Nombrar uno de los títulos que lleva un pack te da el pack con `prefer`, o esa
edición con `ignore`.

Lo mismo vale para una edición que engloba a otra: una edición deluxe o de torneo
que contiene la original representa a su grupo y gana frente a una edición normal,
frente a una revisión superior de esa, y frente a un volcado de una región que
tengas por encima.

### Las reediciones no son juegos distintos

`Mario Kart 64 (USA)` y `Mario Kart 64 (USA) (LodgeNet)` son un solo juego. Las
etiquetas de edición se quitan al construir la clave de clon, así que las dos
compiten por una plaza en vez de conservarse y descargarse ambas: eso cubre
`(LodgeNet)`, `(Wii Virtual Console)`, `(Switch Online)`, `(Greatest Hits)` y
algunos cientos más.

### `--exclude`

Se aplica siempre, también sobre la lista de deseos: nombrar un juego no debe
readmitir en silencio su prototipo ni su manual.

Acepta `add-ons`, `applications`, `audio`, `bad-dumps`, `bios`, `bonus-discs`,
`coverdiscs`, `demos`, `educational`, `manuals`, `mia`, `multimedia`, `pirate`,
`preproduction`, `promotional`, `unlicensed`, `video`.

```sh
--exclude mia,preproduction,demos,unlicensed,pirate,bonus-discs,applications,bios,coverdiscs,educational,manuals,multimedia,promotional,video
```

Cada clase se reconoce por tres vías a la vez —la `<category>` del DAT, la del
clonelist y el nombre—, así que un disco de prueba cuenta como demo se escriba
como se escriba, en japonés o coreano incluidos. Importa porque los DAT de
No-Intro no traen categorías, y el nombre es la única señal. `mia` significa que se
sabe que el volcado existe pero nunca se ha preservado; excluirlo evita que la
herramienta persiga archivos que nadie tiene.
---

## Comandos

### `sync`

Espeja en local los clonelists, metadatos, RetroAchievements y datos MIA.
Repítelo cuando quieras; solo se bajan los archivos cuyo hash cambió.

```sh
minerva_archivist sync
minerva_archivist sync --force
minerva_archivist sync --only clonelists --only retroAchievements
```

`--only` acepta `config`, `cloneLists`, `metadata`, `retroAchievements`, `mias`.

Todo queda bajo `.minerva-cache/`:

```
.minerva-cache/
├── clonelists/  metadata/  mias/  retroachievements/  config/
└── <tus carpetas de DATs>
```

### `filter`

Imprime la selección. Sin conexión, no lee más que los DATs y la caché, y no
escribe nada.

```sh
minerva_archivist filter -d <dat>
minerva_archivist filter -d <dat> --achievements any --lang En,Ja
minerva_archivist filter -d <dat> --wishlist <ruta> --wishlist-mode subset --achievements any
```

La salida es un embudo — el total, los supervivientes, y qué quitó cada etapa:

```
<sistema> [noIntro]: 404 -> 309  (exclude -89, language -6)
```

| Opción | Significado |
|---|---|
| `--list` | Imprime el nombre de cada juego seleccionado |
| `--explain <texto>` | Para cada juego cuyo nombre contenga `<texto>`, imprime su grupo de clones y si ganó |

`--explain` responde a «¿por qué tengo dos de esto, o ninguno?»: muestra qué
compitió por la plaza.

```sh
minerva_archivist filter -d <dat> --explain "Bomberman 64"
```

```
  --- Bomberman 64
          Bomberman 64 (Europe)  [bomberman 64]
      WIN Bomberman 64 (USA)  [bomberman 64]
      WIN Bomberman 64 (Japan)  [bomberman 64 japan]
```

Dos ganadores porque el clonelist separa el lanzamiento japonés en su propio
grupo — es otro juego, no una variante regional.

### `audit`

Compara la selección contra `<raiz-roms>`.

```sh
minerva_archivist audit -d <dat> -r <raiz-roms>
minerva_archivist audit -d <dat> -r <raiz-roms> --no-hash --no-chd
```

| Opción | Significado |
|---|---|
| `--[no-]hash` | Verifica por hash. Activo por defecto. `--no-hash` no lee ningún archivo, así que todo sale como ausente: solo sirve para ver el embudo de selección |
| `--[no-]chd` | Acepta un `.chd` local para una entrada Redump cruda. Activo por defecto |

Los archivos dentro de `.trash` se ignoran — una copia en cuarentena no cuenta
como que la tienes.

La auditoría identifica los archivos contra el DAT **completo**, no solo contra la
selección, así que un volcado que perdió su plaza 1G1R se sigue reconociendo. Eso
es lo que hace legible una [carpeta curada](#carpetas-curadas) que guarda a un
finalista, en vez de parecer un montón de basura. Informa de qué carpetas
encontró, y por tanto de qué juegos no va a descargar:

```
  18 curated of 18 folder(s), 9 game(s) settled there
  curated: 007 - The World Is Not Enough (Europe)  (1 rom(s), 2 of your own)
  settled elsewhere, will not be fetched: 007 - The World Is Not Enough (USA)
```

### `download`

Resuelve el torrent de la plataforma y baja solo lo que te falta. Con
`--rom-root` baja los huecos; sin él, la selección completa.

```sh
minerva_archivist download -d <dat> --dry-run
minerva_archivist download -d <dat> -r <raiz-roms> --aria2 <ruta> --seed
minerva_archivist download --torrent <ruta> -r <raiz-roms> --aria2 <ruta>
minerva_archivist download --collection No-Intro --platform "<plataforma>" --aria2 <ruta>
```

| Opción | Significado |
|---|---|
| `--collection <nombre>` | Colección de MiNERVA. Se deduce del DAT si se omite |
| `--platform <nombre>` | Nombre de la plataforma. Se deduce del DAT si se omite |
| `--torrent <ruta>` | Usa un `.torrent` local en vez de resolver uno |
| `--aria2 <ruta>` | Ruta al binario `aria2c`. Por defecto `aria2c` |
| `--seed` | Sigue compartiendo al terminar |
| `--dry-run` | Muestra el plan sin transferir nada |

Los juegos que el archivo no distribuye se listan uno por uno, así que un faltante
nunca pasa desapercibido:

```
[download] 309 missing -> 303 in torrent, 6 not distributed, 102.5 MB
           ? not in torrent: <nombre>.zip
```

Al completarse la descarga, los archivos se aplanan desde las carpetas anidadas
del torrent hasta la raíz de ROMs, se borran los archivos de control `.aria2` y
se elimina el árbol vacío. Esto evita los problemas de `MAX_PATH` en Windows y
deja una disposición plana para las etapas siguientes.

### `organize`

Dos banderas eligen una de cuatro disposiciones: `--folder-as-file` (carpeta o
plano) × `--extract` (descomprimir o conservar el archivo).

| Banderas | Disposición | Resultado |
|---|---|---|
| *(ninguna)* | Comprimido plano | `<raiz>/Juego.zip` |
| `--extract` | Plano inteligente | `Juego.nes`, o `Juego/` para discos multipista |
| `--folder-as-file` | Comprimido en carpeta | `Juego/Juego.zip` |
| `--folder-as-file --extract` | Carpeta como archivo | `Juego.nes/Juego.nes` |

```sh
minerva_archivist organize -d <dat> -r <raiz-roms> --extract --apply
minerva_archivist organize -d <dat> -r <raiz-roms> --folder-as-file --extract \
  --protect Hacks --protect Mods --apply
```

| Opción | Significado |
|---|---|
| `--folder-as-file` | Cada juego en su propia carpeta |
| `--extract` | Descomprime. Sin ella conserva el `.zip` |
| `--protect <nombre>` | Carpetas que nunca se tocan. Repetible |
| `--apply` | Mueve de verdad. Por defecto es simulacro |

Un juego cuyo destino no se pueda escribir se reporta y se omite — no aborta la
ejecución.

#### Carpetas curadas

Una carpeta está **curada** cuando guarda un volcado *y* archivos tuyos: parches,
traducciones, manuales, escaneos de carátula, una subcarpeta `translations/`. Las
partidas guardadas, los estados y los `.m3u` no cuentan — esos los escribió la
propia herramienta.

```
Body Harvest (USA)/
├── Body Harvest (USA).z64          <- el volcado
└── translations/
    ├── ... (v0.98) (T-Es).z64      <- tuyo
    └── ... (v0.98) (T-Es).txt      <- tuyo
```

Las carpetas curadas se detectan por contenido, en cada ejecución, además de lo
que nombres en `--protect`. De una carpeta curada no se saca nada, y nada de lo
que hay dentro se manda a `.trash` — esos parches solo tienen sentido junto al
volcado para el que se hicieron.

Dos cosas sí ocurren, porque ninguna puede estropear lo que montaste:

* una carpeta con exactamente un juego completo se renombra al nombre del juego;
* una ROM de dentro se renombra a su nombre del DAT, sin salir de la carpeta.

Una carpeta **sin** contenido extra no está curada: si guarda un volcado que la
selección no quiere, se manda a `.trash` como cualquier archivo suelto, y la
carpeta se elimina al quedar vacía.

#### Copias duplicadas del mismo volcado

La curación protege una carpeta, no los bytes que hay dentro. Si pones una
segunda copia de un volcado curado suelta en la raíz, es redundante — 1G1R
quiere una de cada — así que se poda y la copia curada se queda con el sitio,
con sus parches y todo:

```
Sagaia (Japan) (En)/
├── Sagaia (Japan) (En).gb          <- se conserva
└── translations/sagaia (T-Es).ips
Sagaia (Japan) (En).gb              <- se poda, mismos bytes
```

Cuál se queda con el sitio lo decide el contenido, no el orden de lectura del
disco: gana la carpeta curada; si no la hay, el archivo que ya se llama como lo
nombra el DAT; y luego el más cercano a la raíz. Volcados **distintos** de un
mismo juego en carpetas separadas — tres Ocarinas regionales, cada una con su
traducción — no son duplicados y no se toca nada.

El único caso que se deja en paz son los mismos bytes bajo **dos** carpetas
curadas. Qué juego de parches conservar es un criterio sobre tu contenido, así
que la ejecución solo lo informa:

```
[prune] 1 duplicate(s) left alone inside curated folders — merge them by hand
        = Ocarina FR/Legend of Zelda (USA).z64
```

### `m3u`

Escribe un `.m3u` por cada juego multidisco o de varias caras, ordenado para que
el disco 1 vaya primero.

```sh
minerva_archivist m3u -d <dat> -r <raiz-roms> --apply
```

### `prune`

Mueve a `.trash` todo lo que haya en `<raiz-roms>` y no forme parte de la
selección, conservando la estructura relativa. Mueve, nunca borra, y jamás toca
`.trash`, las carpetas protegidas ni las [carpetas curadas](#carpetas-curadas).
Una carpeta que se quede vacía tras la limpieza se elimina.

```sh
minerva_archivist prune -d <dat> -r <raiz-roms>
minerva_archivist prune -d <dat> -r <raiz-roms> --protect Hacks --apply
```

### `run`

El pipeline completo: **sync → select → audit → [download] → organize → m3u → prune**.

Las etapas que modifican archivos son simulacro salvo con `--apply`; la descarga
está apagada salvo con `--with-download`.

```sh
# vista previa segura
minerva_archivist run -d <dat> -r <raiz-roms>

# todo
minerva_archivist run -d <dat> -r <raiz-roms> \
  --lang Es,En,Ja --wishlist <ruta> --achievements any \
  --exclude mia,preproduction,demos \
  --with-download --aria2 <ruta> \
  --extract --protect Hacks --apply

# elegir etapas
minerva_archivist run -d <dat> -r <raiz-roms> --only select --only audit
minerva_archivist run -d <dat> -r <raiz-roms> --skip prune --skip m3u
```

| Opción | Significado |
|---|---|
| `--only <etapa>` | Ejecuta solo estas etapas. Repetible |
| `--skip <etapa>` | Omite estas etapas. Repetible |
| `--with-download` | Habilita la descarga |
| `--folder-as-file`, `--extract`, `--protect` | Se pasan a `organize` |
| `--aria2 <ruta>`, `--seed` | Se pasan a `download` |
| `--apply` | Aplica descarga / organize / prune |

Etapas: `sync`, `select`, `audit`, `download`, `organize`, `m3u`, `prune`.

Tras una descarga el pipeline vuelve a auditar, así que `organize`/`m3u`/`prune`
actúan sobre los archivos recién llegados.

---

## Leer la salida

```
[select] 404 in DAT -> 309 wanted  (exclude -89, language -6)
[audit] 0/309 on disk, 309 missing, 0 unknown
[download] 309 missing -> 303 in torrent, 6 not distributed, 102.5 MB
[audit] 303/309 on disk, 6 missing
[organize] 303 extracted
[prune] 0 orphans
```

- **select** — total del DAT, supervivientes, y una entrada por cada motivo que
  quitó algo. Los motivos son `exclude`, `language`, `region`, `1g1r`, `superset`
  y `wishlist/ra`; siempre suman la diferencia.
- **audit** — `en disco / deseados`. `unknown` cuenta los archivos presentes que
  ningún juego seleccionado reclama; son los que `prune` movería.
- **download** — cuántos faltan, cuántos lleva realmente el archivo, y el
  faltante listado por nombre.

## Notas

- Los clonelists, metadatos, logros y datos MIA se replican del proyecto original
  al que apunta `sync`. El motor 1G1R reimplementa su agrupación y puntuación, con
  el orden de los desempates a tu elección mediante `--priority`.
- La selección funciona sin conexión. Solo `sync` y `download` usan la red.
