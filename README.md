# CV

The CVA uses one workbook for structured information and two Markdown files for narrative text.

## CVA review checklist

- [ ] **Part B:** review the overall voice, opening definition and theoretical foundations, personal contributions, balance between scientific achievements and mobility, and the final research direction with Carlos.
- [ ] **ChEMISt and RECODYN notes:** rewrite both contribution notes in the preferred style, keeping each within two rendered lines. The current wording still needs personal review.
- [ ] **C.4 scope:** decide which activities demonstrate knowledge transfer. Present the systematic sharing of documented data and reproducible code in Part B as open science; assess any distinct software-transfer claim separately. Review the 2019 judicial expert assessment as an application of biological expertise. English C.4 currently contains the new open-science paragraph; Spanish still contains the older software paragraph.
- [ ] **Outreach responsibilities:** confirm the scope and years of organising or co-organising the European Researchers' Night, including whether this covered the group contribution or the wider event. Update the current participation wording in Part B where appropriate.
- [ ] **ChEMISt access value:** confirm with Lucille the documentation supporting the estimated EUR 85,000 value and distinguish awarded access and analytical services from cash funding.
- [ ] **Mobility records:** add the French visit dates to the structured inputs so the statistics can use the documented total of 15 visits and 173 inclusive calendar days in 2023–2025. Verify exact MBG-CSIC and German stay durations if precise totals are needed; the current month ranges describe calendar coverage. Keep UNESP, Rio Claro as the main Brazilian host and UFSCar as a brief additional visit.
- [ ] **Ongoing manuscripts:** confirm status and authorship for LUI, the Brazilian collaboration, the two US manuscripts and the postdoctoral papers. Distinguish completed publications from work in progress and avoid counting the same manuscript twice.
- [ ] **Language consistency:** agree on the English content, then synchronise the Spanish text and bilingual spreadsheet notes, especially C.4.
- [ ] **Submission format:** resolve the shortened author lists and code-font styling against the [2026 CVA guidelines](https://www.aei.gob.es/sites/default/files/convocatory_info/assistants/2026-09/4.CVA%202026%20guidelines.pdf). The instructions request the first three authors for lists longer than eight and Times New Roman, Calibri or Arial at a minimum of 11 pt; the current choices retain two opening authors and Consolas 10.5 pt code. After the content review, check the final layout, the 5,000-character limit for Part B and the four-page limit.

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

`alias_autoria` contains your complete author-name variants, separated by semicolons, including any forms with initials. These aliases control bolding in all author lists, independently of which publications are included. Add a new spelling here rather than editing the code. The ORCID number is always linked to its ORCID page.

In the other CVA sheets, `incluir` accepts `TRUE` or `FALSE`, and also `SI` or `NO`; blank means include. Keep dated sheets in chronological order, oldest first, and add new entries at the bottom. Undated entries go last. The CVA displays entries newest first; sheet order resolves ties. `Perfil` keeps its personal-field order.

In `Experiencia`, use `actualmente` in `fin` for the current appointment. Its position, institution, department and country populate A.1; the other appointments populate A.2. `duracion_meses` sets the displayed duration; leave it blank to calculate the duration from the dates, rounded to half months when complete dates are supplied. `direccion` / `address` and `nota` / `note` hold the Spanish and English address and appointment note, including childcare leave.

`url_es` / `url_en` in `Experiencia` hold the department links for each language. Only the exact institution name is hyperlinked in A.1 and A.2, without changing its appearance. A blank URL leaves that name unlinked. Education institutions remain unlinked.

Dates accept Excel dates or text in `YYYY`, `YYYY-MM` or `YYYY-MM-DD` format. Keep the precision you know. `Formacion` has one `fecha` column for each degree's completion date.

Author lists use `Surname, Given names; Surname, Given names`. `posicion_autor` gives your position; `correspondencia` names the corresponding authors exactly as in the list. Lists of up to eight authors are shown in full. Longer lists retain the first two authors, you, all corresponding authors and the final author, in their original order without duplicates; ellipses mark omitted gaps. The total and your position always come from the complete list, regardless of the displayed abbreviation.

Publication quotes are in `contribucion_es` and `contribucion_en`. The same two columns in `Proyectos` contain the complete project contribution, including any participation duration you want to mention.

In `Proyectos`, keep `acronimo` separate from the title. Titles use the stored wording, prefixed by the acronym when present. `financiador` / `funding` and `convocatoria` / `call` hold the Spanish and English funding body and call. `ip` lists the principal investigators, separated by semicolons. `institucion` / `institution` hold the Spanish and English institution names. Each institution follows the investigator names as `PI: name, at institution` in English or `IP: nombre, en institución` in Spanish; multiple investigators use `Co-PIs` or `Co-IP`.

Both languages use the same metadata order: reference, call and funder, investigators and institution; period. The amount and any award description follow, with the status last. Project year ranges use an en dash without spaces, for example `2023–2027`. `tipo_importe` distinguishes `total` funding from an `estimado` value; keep the original currency in `moneda`. Estimated values receive a neutral label rather than an inferred claim about services. Use optional `detalle_importe_es` / `detalle_importe_en` for the complete award description, including any facilities or services; this text is printed directly without generating a separate facilities list or label. `estado` / `status` hold the Spanish and English status. Leave both language cells blank to omit an optional description or status.

In `Congresos`, `congreso_institucion` names the event or host institution. Presentations display their authors; organisational roles such as scientific committees do not. `modalidad_es` / `modalidad_en` supply the displayed contribution type literally, including the full wording you want for posters or talks.

In displayed workbook text, use `*text*` for italics and `**text**` for bold. For example, enter `*Arabidopsis thaliana*` to italicise a scientific name. Surround each code fragment with single backticks. Any number of fragments can appear in one cell. They use Consolas 10.5 pt, as does Markdown inline code; backticks are removed and quotation marks appear only when you type them. Ordinals use consistent superscript styling throughout the CVA, outside code fragments.

`Otros` and auxiliary fields remain available for other CV material even when they are not displayed in this CVA. Update the input fields and render again; new entries follow these shared rules without individual changes to the scripts.

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

Install R, the Typst CLI, Times New Roman and Consolas. Install the R packages once in your normal user library:

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

The build checks dates, translations, authorship, the Part B character limit, A4 size, the four-page and 4 MB limits, and the established font rules. Each numbered contribution stays on one page with its explanatory quote. An entry taller than the usable page area raises an error instead of being split or shrunk. Date fields and short ranges stay together, while locations can wrap normally. Both logos appear in their usual positions on every page in both languages.

Compilation files are created in the operating system's temporary directory and removed after the build. Format R code with `air`.

## Retrieve CVA statistics

`cva/stats.R` reads the workbook, retrieves public metadata and saves everything in `input/stats.csv`. Its `record_type` column distinguishes publication–author–affiliation rows (`publication`) from activity evidence (`activity`). Fields that do not apply to a record are blank. The workbook and CVA PDFs are not modified.

From the repository directory:

```sh
Rscript cva/stats.R --render
```

From Positron's R Console:

```r
source("cva/stats.R", encoding = "UTF-8")
stats <- retrieve_stats()
render_stats()
```

The Quarto source `cva/stats.qmd` reads only `input/stats.csv` and calculates the text, tables and offline map. The rendered page is `cva/stats.html`. Omit `--render` to update only the CSV; `render_stats()` alone rebuilds the report without downloading metadata. It selects the current R installation through a temporary `QUARTO_R` setting.

The BioScience collective appeal is excluded by the explicit `exclude_dois` argument. `reference_country` defaults to Spain (`ES`), and `as_of` defaults to today's date in Europe/Madrid. Statistics use all career records, independently of CVA selection flags.

Count unique `paper_id` values for publications and unique `activity_id` values for activities. Several institutions or countries can produce multiple rows for the same record. Collaboration measures exclude the applicant and use researcher and ROR identifiers. Research mobility uses appointments and research visits; project funding, awarded facility access, supervision partners and online participation retain separate roles. Declared months, covered calendar months and exact days remain separate, and aggregate visit records do not establish a precise trip count. Programme recognition uses the same documented catalogue for all records. Source rows, URLs and retrieval dates remain in the CSV.

The report organises evidence for the [Juan de la Cierva 2026 criteria](https://www.aei.gob.es/sites/default/files/convocatory_info/assistants/2026-09/Convocatoria%20JDC%202026_firmada.pdf#page=41). It flags missing evidence and does not calculate an evaluation score. Affiliation data describe the published records, rather than verified current employment; institution geography may represent the main location. Project budgets and estimated access values are not personal funding totals.

Public responses are cached in the ignored `cva/.stats-cache/` directory for seven days; negative lookups are retried after one day. Use `--refresh` or `retrieve_stats(refresh = TRUE)` to refresh, and `--offline` or `retrieve_stats(offline = TRUE)` to reproduce the CSV from cached responses. Failed retrieval retains the previous CSV. The cache, rendered HTML and Quarto resources are ignored by Git.

Retrieval requires `readxl`, `jsonlite`, `httr2`, `digest`, `countrycode` and `commonmark`; rendering also needs Quarto, `knitr`, `rmarkdown`, `leaflet` and `maps`. A free `OPENALEX_API_KEY` environment variable can provide higher API limits.

Sources: [OpenAlex](https://help.openalex.org/data/authorships/), [Crossref](https://www.crossref.org/documentation/retrieve-metadata/rest-api/) and [ROR](https://ror.readme.io/docs/api-affiliation). Programme classifications retain their official source links in the CSV.
