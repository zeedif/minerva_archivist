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

Compartidas por `filter`, `audit`, `download`, `organize`, `m3u`, `prune` y
`run`. Deciden *sobre qué* juegos actúa el comando. Las opciones de varios
valores aceptan comas o repetición.

| Opción | Significado |
|---|---|
| `--lang <códigos>` | Prioridad de idiomas, mejor primero. Por defecto `En` |
| `-l, --filter-languages` | Además **descarta** los títulos que no hablen ninguno de `--lang` |
| `--wishlist <ruta>` | Arreglo JSON/JSONC con los nombres a conservar |
| `-a, --retroachievements` | Conserva los títulos con soporte de RetroAchievements |
| `--combine or\|and` | Cómo se combinan lista de deseos y RA. Por defecto `or` |
| `--exclude-status <lista>` | Descarta estos estados de producción |
| `--exclude-category <lista>` | Descarta estas categorías |

### `--lang` y `-l`

Por sí sola, `--lang` solo **ordena**: si un grupo tiene una edición en español y
otra en inglés, gana la española — pero un juego solo en francés se conserva,
porque no hay nada mejor en ese grupo.

`-l` la convierte además en **filtro**: los títulos que no hablen ninguno de tus
idiomas se eliminan. Los de idioma desconocido se conservan, porque no hay con
qué juzgarlos.

```sh
# se prefiere español, pero se conserva todo
minerva_archivist filter -d <dat> --lang Es,En

# solo español o inglés — francés, alemán, etc. se descartan
minerva_archivist filter -d <dat> -l --lang Es,En
```

Las variantes regionales coinciden con su código base: pedir `Es` acepta `Es-MX`.

### `--exclude-status`

Acepta: `released`, `prototype`, `beta`, `alpha`, `demo`, `sample`, `pirate`,
`unlicensed`, `mia`.

`mia` significa que se sabe que el volcado existe pero nunca se ha preservado;
excluirlo evita que la herramienta persiga archivos que nadie tiene.

```sh
--exclude-status mia,prototype,beta,alpha,demo,sample,unlicensed,pirate
```

### `--exclude-category`

Coincidencia por subcadena sin distinguir mayúsculas, contra las categorías del
juego, que salen del elemento `<category>` del DAT **y** de su grupo en el
clonelist. Esa segunda fuente importa: los DATs de No-Intro no traen categorías,
así que los cartuchos de prueba y las utilidades solo se reconocen por el
clonelist.

Valores habituales: `Applications`, `Audio`, `BIOS`, `Bonus Discs`,
`Coverdiscs`, `Demos`, `Educational`, `Games`, `Manuals`, `Multimedia`,
`Pirate`, `Preproduction`, `Promotional`, `Unlicensed`, `Video`.

```sh
--exclude-category "Applications,Audio,BIOS,Coverdiscs,Educational,Manuals,Multimedia,Promotional,Video"
```

### Lista de deseos

Un arreglo JSON/JSONC con nombres base de juegos:

```jsonc
[
  "Chrono Trigger",
  "Final Fantasy VII",
  "Bomber Boy"   // también arrastra su grupo de clones
]
```

La coincidencia ignora mayúsculas, puntuación, un "The" inicial o final, y las
etiquetas de región y formato. Es exacta tras normalizar, no por subcadena — usa
títulos base completos. Nombrar cualquier título de un grupo de clones selecciona
el grupo entero.

Combínala con RetroAchievements desde la línea de comandos, no desde el archivo:

```sh
--wishlist <ruta> -a --combine or    # en la lista O tiene logros
--wishlist <ruta> -a --combine and   # en la lista Y tiene logros
```

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
minerva_archivist filter -d <dat> -a -l --lang En,Ja
minerva_archivist filter -d <dat> --wishlist <ruta> -a --combine and
```

La salida es un embudo — el total, los supervivientes, y qué quitó cada etapa:

```
<sistema> [noIntro]: 404 -> 309  (status -89, language -6)
```

### `audit`

Compara la selección contra `<raiz-roms>`.

```sh
minerva_archivist audit -d <dat> -r <raiz-roms>
minerva_archivist audit -d <dat> -r <raiz-roms> --no-hash --no-chd
```

| Opción | Significado |
|---|---|
| `--[no-]hash` | Verifica por hash. `--no-hash` hace una pasada rápida por nombre y tamaño. Activo por defecto |
| `--[no-]chd` | Acepta un `.chd` local para una entrada Redump cruda. Activo por defecto |

Los archivos dentro de `.trash` se ignoran — una copia en cuarentena no cuenta
como que la tienes.

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

Protegido significa: cualquier carpeta nombrada en `--protect`, más cualquier
carpeta que ya contenga archivos tuyos (`.ips`, `.bps`, `.sav`, `.state`, …). Un
juego cuyo destino no se pueda escribir se reporta y se omite — no aborta la
ejecución.

### `m3u`

Escribe un `.m3u` por cada juego multidisco o de varias caras, ordenado para que
el disco 1 vaya primero.

```sh
minerva_archivist m3u -d <dat> -r <raiz-roms> --apply
```

### `prune`

Mueve a `.trash` todo lo que haya en `<raiz-roms>` y no forme parte de la
selección, conservando la estructura relativa. Mueve, nunca borra, y jamás toca
`.trash` ni las carpetas protegidas.

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
  -l --lang Es,En,Ja --wishlist <ruta> -a --combine or \
  --exclude-status mia,prototype,beta,demo \
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
[select] 404 in DAT -> 309 wanted  (status -89, language -6)
[audit] 0/309 on disk, 309 missing, 0 unknown
[download] 309 missing -> 303 in torrent, 6 not distributed, 102.5 MB
[audit] 303/309 on disk, 6 missing
[organize] 303 extracted
[prune] 0 orphans
```

- **select** — total del DAT, supervivientes, y una entrada por cada motivo que
  quitó algo. Los motivos son `status`, `category`, `language`, `1g1r` y
  `wishlist/ra`; siempre suman la diferencia.
- **audit** — `en disco / deseados`. `unknown` cuenta los archivos presentes que
  ningún juego seleccionado reclama; son los que `prune` movería.
- **download** — cuántos faltan, cuántos lleva realmente el archivo, y el
  faltante listado por nombre.

## Notas

- El motor 1G1R replica el de Retool, pero su filtro de regiones no está
  implementado. Si tu configuración de Retool restringe regiones, usa `-l` para
  obtener resultados equivalentes; un título de una región excluida y sin
  metadatos de idioma podría colarse.
- La selección funciona sin conexión. Solo `sync` y `download` usan la red.
