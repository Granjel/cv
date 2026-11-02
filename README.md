# CV

Shared CV data and assets, with the AEI CVA workflow in `cva/`.

## Files

- `data/datos-cv.xlsx`: the single source of CV data, including both languages and all auxiliary sheets.
- `cva/cva.R`: reads and validates Excel, prepares the content and builds the PDFs.
- `cva/cva.typ`: document layout.
- `assets/`: the two SVG header logos.
- `cva/pdf/`: generated English and Spanish CVAs, included in version control.

## Requirements

Install R, the Typst CLI and Times New Roman. Install these R packages once in your normal user library:

```r
install.packages(c("readxl", "jsonlite", "xml2", "pdftools"))
```

## Update and build

Edit `data/datos-cv.xlsx`, save it, then run from this directory:

```sh
Rscript cva/cva.R --draft
```

This updates `cva/pdf/cva-borrador-en.pdf` and `cva/pdf/cva-borrador-es.pdf`. Use `--idioma en` or `--idioma es` for one language, or `--check` to validate the data without building. When the content is complete, omit `--draft` to produce PDFs without the draft footer.

From an R session in this directory:

```r
source("cva/cva.R", encoding = "UTF-8")
generar_cva(borrador = TRUE)
```

From the `cva/` directory, use `Rscript cva.R --draft` or `source("cva.R", encoding = "UTF-8")`; shared inputs and output paths are resolved automatically.

## Data conventions

- Keep sheet names, headers and record IDs. `incluir_cva` selects entries with `SI` / `NO`; entries are sorted by date automatically.
- Shared values stay in common columns. Translations use `_es` / `_en`; in `Perfil`, use either `valor` or the `es` / `en` cells.
- Dates accept `YYYY`, `YYYY-MM` or `YYYY-MM-DD`. Do not invent missing days or months.
- Keep full author lists in order, separated by semicolons. `posicion_autor` is your position; `correspondencia` uses exact names from that list. R generates the compact author-position text.
- Publication explanations are edited in `contribucion_es` / `contribucion_en` and appear in quote blocks.
- `Proyectos.tipo_importe` distinguishes `financiacion_total` from `valor_acceso_estimado`. Keep the original currency. `participacion_meses` records your participation separately from project dates.
- `Perfil.duracion_meses` overrides the calculated appointment duration. `nota_fecha_inicio` contains the bilingual parental-leave note.
- Part B is edited in `Textos`, row `resumen`, with a limit of 5,000 characters per language. Its current text is a placeholder; C.4 also remains to be completed.

The build validates the A4 format, four-page / 4 MB limits, permitted fonts and minimum 11 pt text. Intermediate JSON, logs and compilation files are created in the operating system's temporary directory and removed automatically. No project snapshots or package caches are stored in this repository.
