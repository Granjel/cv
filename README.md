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
| Perfil | Personal details |
| Experiencia | Current and previous appointments |
| Formacion | Degrees |
| Publicaciones | Publications |
| Congresos | Presentations, seminars and committee roles |
| Proyectos | Project details and your contribution |
| Otros | Visits, teaching, supervision, service, grants and other merits |

In `Perfil`, enter the shared or Spanish value in `valor`. Use `ingles` only when the English version differs. Leave `fecha_cva` as `auto` or blank to use the render date in Europe/Madrid; a full date (`YYYY-MM-DD`) overrides it.

In the other CVA sheets, `incluir` accepts `TRUE` or `FALSE`, and also `SI` or `NO`; blank means include. Keep dated sheets in chronological order, oldest first, and add new entries at the bottom. Undated entries go last. The CVA displays entries newest first; sheet order resolves ties. `Perfil` keeps its personal-field order.

In `Experiencia`, use `actualmente` in `fin` for the current appointment. Its position, institution, department and country populate A.1; the other appointments populate A.2. `duracion_meses` sets the displayed duration of each appointment. `direccion` / `address` and `nota` / `note` hold the Spanish and English address and appointment note, including childcare leave.

Dates accept Excel dates or text in `YYYY`, `YYYY-MM` or `YYYY-MM-DD` format. Keep the precision you know. `Formacion` has one `fecha` column for each degree's completion date.

Author lists use `Surname, Given names; Surname, Given names`. `posicion_autor` gives your position; `correspondencia` names the corresponding authors exactly as in the list. The total author count and the abbreviation of long lists are calculated automatically.

Publication quotes are in `contribucion_es` and `contribucion_en`. The same two columns in `Proyectos` contain the complete project contribution, including any participation duration you want to mention.

In `Proyectos`, keep `acronimo` separate from the title. Titles use the stored wording, prefixed by the acronym when present. `financiador` / `funding` and `convocatoria` / `call` hold the Spanish and English funding body and call. `ip` lists the principal investigators, separated by semicolons. `institucion` / `institution` hold the Spanish and English institution names. Each institution follows the investigator names as `PI: name, at institution` in English or `IP: nombre, en institución` in Spanish; multiple investigators use `Co-PIs` or `Co-IP`. Project year ranges use an en dash without spaces, for example `2023–2027`. `tipo_importe` distinguishes `total` funding from an `estimado` access value; keep the original currency. `instalaciones` lists the facilities covered by an access award, separated by semicolons.

In `Congresos`, `congreso_institucion` names the event or host institution. Presentations display their authors; organisational roles such as scientific committees do not. In titles, backticks mark the existing `Theory < data` fragment.

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

From an R session, including Positron's Console:

```r
source("cva/cva.R", encoding = "UTF-8")
generar_cva()
```

After sourcing the script once in that R session, save your Excel or Markdown edits and run `generar_cva()` again. Use `generar_cva(idioma = "en")` or `generar_cva(idioma = "es")` for one language. Source the script again after changing its code.

From the `cva/` directory, use `Rscript cva.R` or `source("cva.R", encoding = "UTF-8")`. Paths to the workbook, Markdown and assets are resolved from the repository automatically.

The build checks dates, translations, authorship, the Part B character limit, A4 size, the four-page and 4 MB limits, and the established font rules. Compilation files are created in the operating system's temporary directory and removed after the build. Format R code with `air`.
