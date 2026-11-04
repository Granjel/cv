# CV

The CVA uses one workbook for structured information and two Markdown files for narrative text.

## Edit the inputs

Everything you edit is in `input/`:

- `datos-cv.xlsx`: personal details, appointments, education, publications, conferences, projects and other CV material
- `en.md`: English text for Part B and C.4
- `es.md`: Spanish text for Part B and C.4

The workbook has seven plain sheets. Headers are bold, gridlines are visible, and there are no coloured backgrounds, spacer rows or verification columns.

| Sheet | Content |
| --- | --- |
| Perfil | Personal details and current position |
| Experiencia | Previous appointments |
| Formacion | Degrees |
| Publicaciones | Published work and manuscripts |
| Congresos | Presentations, seminars and committee roles |
| Proyectos | Project details and your contribution |
| Otros | Visits, teaching, supervision, service, grants and other merits |

In `Perfil`, enter the shared or Spanish value in `valor`. Use `ingles` only when the English version differs. Leave `fecha_cva` as `auto` or blank to use the render date in Europe/Madrid; a full date (`YYYY-MM-DD`) overrides it. `duracion_meses` sets the displayed duration of your current position.

In the other CVA sheets, `incluir` accepts `SI` or `NO`; blank means `SI`. Manuscripts are initially excluded. Rows are sorted by date; their sheet order resolves ties.

Dates accept `YYYY`, `YYYY-MM` or `YYYY-MM-DD`. Keep the precision you know. Author lists use `Surname, Given names; Surname, Given names`. `posicion_autor` gives your position; `correspondencia` names the corresponding authors exactly as in the list. The total author count is calculated automatically. `autores_iniciales` optionally changes how many leading authors are shown; blank uses three.

Publication quotes are in `contribucion_es` and `contribucion_en`. The same two columns in `Proyectos` contain the complete project contribution, including any participation duration you want to mention. `direccion_es` and `direccion_en` contain the PI/host wording as it should appear. `tipo_importe` distinguishes `financiacion_total` from `valor_acceso_estimado`; keep the original currency. `acceso` identifies the facilities covered by an access award.

In conference titles, backticks mark the existing `Theory < data` fragment.

## Edit the narrative text

Keep the two section headings in each Markdown file:

```markdown
# Part B

**Scientific profile:** Write the summary here.

Another paragraph, with *italics* or a [link](https://example.org).

# C.4

Write the knowledge-transfer section here.
```

Each paragraph occupies one physical line. Put a blank line between paragraphs; use your editor's visual word wrapping for comfortable reading.

Bold, italics, links and inline code are rendered from Markdown. The section headings select the destination and are not printed. Part B is limited to 5,000 visible characters per language, including spaces and paragraph breaks; Markdown markers and link destinations are excluded from that count.

## Render the CVA

Install R, the Typst CLI and Times New Roman. Install the R packages once in your normal user library:

```r
install.packages(c("readxl", "jsonlite", "xml2", "pdftools", "commonmark"))
```

From the repository directory:

```sh
Rscript cva/cva.R
```

This updates `cva/pdf/cva-en.pdf` and `cva/pdf/cva-es.pdf`. Use `--idioma en` or `--idioma es` for one language, or `--check` to validate the inputs without rendering.

From an R session:

```r
source("cva/cva.R", encoding = "UTF-8")
generar_cva()
```

From the `cva/` directory, use `Rscript cva.R` or `source("cva.R", encoding = "UTF-8")`. Paths to the workbook, Markdown and assets are resolved from the repository automatically.

The build checks dates, translations, authorship, the Part B character limit, A4 size, the four-page and 4 MB limits, and the established font rules. Compilation files are created in the operating system's temporary directory and removed after the build. Format R code with `air`.
