// define the CVA layout and typography
// header artwork was supplied by the applicant; the ministry logo uses a PNG
// rasterisation
// the applicant's concise labels and content are retained
// workbook strings remain literal data and are never evaluated as Typst code
#let cv = json(sys.inputs.at("data"))
#let es = cv.idioma == "es"
#let tr(a, b) = if es { a } else { b }
#let p = cv.perfil
#set document(
  title: tr("Curriculum vitae abreviado", "Abbreviated curriculum vitae"),
  author: p.nombre + " " + p.apellidos,
)
#set text(font: "Times New Roman", size: 11pt, lang: cv.idioma, fallback: false, hyphenate: false)
#set page(
  paper: "a4",
  margin: (x: 2.5cm, top: 21mm, bottom: 15mm),
  foreground: context {
    place(top + left, dx: 25mm, dy: 2mm, image("/assets/logo-MCIU.png", width: 44.1mm))
    place(top + right, dx: -25mm, dy: 2mm, image("/assets/logo-AEI.svg", height: 14mm))
  },
  footer: context {
    grid(
      columns: (1fr, 1fr, 1fr),
      align: (left, center, right),
      [], if counter(page).get().first() > 1 { counter(page).display() } else { [] }, [],
    )
  },
)
#set par(leading: 0.4em, spacing: 6pt, justify: true)
#set block(spacing: 0pt)
#let part-heading-gap = 9pt
#let subsection-heading-gap = 7pt
#let prose-leading = 0.6em
#let entry-gap = prose-leading
#let narrative-paragraph-gap = 11pt
#let section(body, above: 18pt) = block(above: above, below: part-heading-gap, sticky: true)[#strong(body)]
#let subsection(body, above: 12pt) = block(above: above, below: subsection-heading-gap, sticky: true)[#strong(body)]
#let grid-table(columns, ..cells) = block(above: 0pt, below: 0pt)[
  #set align(left)
  #set par(leading: 0.4em, spacing: 0pt, justify: false)
  #table(columns: columns, align: left + horizon, inset: (
      left: 5pt,
      right: 3pt,
      top: 2.5pt,
      bottom: 2.5pt,
    ), stroke: 0.4pt, ..cells.pos())
]
#let label-fill = rgb("D8D8D8")
#let label(body) = table.cell(fill: label-fill)[#body]
#let column-label(body) = table.cell(align: center + horizon, fill: label-fill)[#body]
#let first-column = 32mm
#let information-columns = (first-column, 59mm, 26mm, 43mm)
#let career-column = 54mm
#let display-date(value) = value.split("-").rev().join("/")
#let hyperlink(target, label: none, accent: true) = {
  let body = if label == none { target } else { label }
  if accent { text(fill: blue)[#underline(link(target, body))] } else { link(target, body) }
}
// style ordinal suffixes consistently while leaving code untouched
#let ordinal-pattern = regex("(?i)\\b([0-9]+)(st|nd|rd|th|\\.?[ºª]|\\.er)\\b")
#let ordinal-text(value) = {
  let offset = 0
  for matched in value.matches(ordinal-pattern) {
    value.slice(offset, matched.start)
    let suffix = matched.captures.at(1)
    let native-suffix = suffix.ends-with("º") or suffix.ends-with("ª")
    matched.captures.at(0)
    if native-suffix {
      suffix
    } else {
      if suffix.starts-with(".") { "." }
      super(size: 0.75em, suffix.trim(".", at: start))
    }
    offset = matched.end
  }
  value.slice(offset)
}
#let code-span(value) = text(font: "Consolas", size: 10.5pt, value)
// backticks mark any number of code spans in workbook text
// ordinary quotation marks remain literal input
#let inline(value, capitals: false) = {
  let plain(value) = ordinal-text(if capitals { upper(value) } else { value })
  let offset = 0
  for matched in value.matches(regex("`[^`]+`")) {
    plain(value.slice(offset, matched.start))
    code-span(matched.text.slice(1, -1))
    offset = matched.end
  }
  plain(value.slice(offset))
}
// render literal Markdown nodes without evaluating their contents as Typst code
#let markdown-inline(nodes) = {
  for node in nodes {
    if node.type == "text" {
      ordinal-text(node.text)
    } else if node.type == "strong" {
      strong(markdown-inline(node.children))
    } else if node.type == "emph" {
      emph(markdown-inline(node.children))
    } else if node.type == "link" {
      hyperlink(node.destination, label: markdown-inline(node.children))
    } else if node.type == "code" {
      code-span(node.text)
    } else if node.type == "linebreak" {
      linebreak()
    }
  }
}

#let web-link(value) = if value.starts-with("https://") or value.starts-with("http://") {
  hyperlink(value, accent: false)
} else {
  value
}
// link only the institution name using its explicit workbook URL
#let linked-institution(value, target) = {
  if target == "" { inline(value) } else { link(target, inline(value)) }
}
#let citation(entry, journal: false) = {
  for segment in entry.segmentos {
    if segment.style == "author" { strong(inline(segment.text)) } else if segment.style == "venue" {
      inline(segment.text, capitals: journal)
    } else if segment.style == "nowrap" {
      box(inline(segment.text))
    } else { inline(segment.text) }
  }
}
#let prose(body, above: 0pt, below: 0pt, sticky: false, breakable: true) = block(
  width: 100%,
  above: above,
  below: below,
  sticky: sticky,
  breakable: breakable,
)[
  #set par(leading: prose-leading, justify: true)
  #body
]
// measure each complete contribution at its actual list width
// move it to the next page when needed and reject an oversized entry
#let contribution(body) = block(width: 100%, breakable: false)[#layout(size => {
  let content = prose(breakable: false, body)
  let height = measure(content, width: size.width).height
  let usable-height = page.height - page.margin.top - page.margin.bottom
  assert(
    height <= usable-height,
    message: tr(
      "Una aportación supera la altura útil de una página; acorta su texto.",
      "A contribution exceeds the usable page height; shorten its text.",
    ),
  )
  content
})]
#let publication-context(body) = block(width: 100%, above: prose-leading, below: 0pt)[#layout(size => {
  let content = block(width: size.width, above: 0pt, below: 0pt, inset: (left: 10pt))[#body]
  let height = measure(content).height
  block(width: 100%, height: height, above: 0pt, below: 0pt)[
    #place(top + left, dx: 2pt)[
      #rect(width: 3pt, height: height, radius: 0.5pt, fill: rgb("BDBDBD"), stroke: none)
    ]
    #content
  ]
})]
#let publication(entry) = {
  let types = (
    articulo: tr("Artículo científico:", "Journal article:"),
    libro: tr("Libro:", "Book:"),
    capitulo: tr("Capítulo de libro:", "Book chapter:"),
    datos: tr("Datos:", "Dataset:"),
    software: tr("Software:", "Software:"),
  )
  [
    #emph(types.at(entry.tipo)) #citation(entry, journal: true)
    #if entry.doi != "" {
      hyperlink("https://doi.org/" + entry.doi, label: "doi: " + entry.doi)
    }
    #publication-context[
      #inline(entry.autoria) #inline(entry.contribucion)
    ]
  ]
}

#v(3mm)
#block(below: part-heading-gap, sticky: true)[
  #grid(
    columns: (91mm, 69mm),
    align: left + horizon,
    strong(tr("Parte A. DATOS PERSONALES", "Part A. PERSONAL INFORMATION")),
    grid-table((26mm, 43mm), label(strong(tr("Fecha CVA", "CVA date"))), table.cell(
      align: center + horizon,
    )[#display-date(
      p.fecha_cva,
    )]),
  )
]
#grid-table(
  information-columns,
  label(tr("Nombre", "First name")),
  table.cell(colspan: 3)[#inline(p.nombre)],
  label(tr("Apellidos", "Family name")),
  table.cell(colspan: 3)[#inline(p.apellidos)],
  label(tr("Sexo", "Gender")),
  inline(p.sexo),
  label(tr("Fecha nac.", "Birth date")),
  display-date(p.fecha_nacimiento),
  label(tr("DNI", "ID number")),
  table.cell(colspan: 3)[#inline(p.documento)],
  label("Email"),
  if p.email.contains("@") {
    hyperlink("mailto:" + p.email, label: p.email, accent: false)
  } else { p.email },
  label("URL Web"),
  web-link(p.web),
  table.cell(colspan: 2, fill: label-fill)[Open Researcher and Contributor ID (ORCID)],
  table.cell(colspan: 2)[#hyperlink(
    "https://orcid.org/" + p.orcid,
    label: p.orcid,
    accent: false,
  )],
)
#subsection(tr("A.1. Situación profesional actual", "A.1. Current position"))
#grid-table(
  information-columns,
  label(tr("Puesto", "Position")),
  table.cell(colspan: 3)[#inline(p.puesto)],
  label(tr("Fecha inicio", "Start date")),
  table.cell(colspan: 3)[#{
    let note = p.at("nota_fecha_inicio", default: "")
    display-date(p.fecha_inicio) + " (" + cv.duracion_actual + (if note != "" { "*" } else { "" }) + ")"
  }],
  label(tr("Institución", "Institution")),
  table.cell(colspan: 3)[#linked-institution(p.institucion, p.url_institucion)],
  label(tr("Departamento", "Department")),
  table.cell(colspan: 3)[#inline(p.departamento)],
  label(tr("País", "Country")),
  inline(p.pais),
  label(tr("Teléfono", "Phone number")),
  p.telefono,
  label(tr("Palabras clave", "Keywords")),
  table.cell(colspan: 3)[#inline(p.palabras_clave)],
)
#let leave-note = p.at("nota_fecha_inicio", default: "")
#if leave-note != "" {
  block(above: 4pt, below: 0pt)[
    #set par(leading: 0.4em, spacing: 0pt, justify: false)
    #inline("*" + leave-note)
  ]
}
#subsection(tr("A.2. Situación profesional anterior", "A.2. Previous positions"))
#grid-table(
  (career-column, 1fr),
  table.header(column-label(tr("Periodo", "Period")), column-label(tr(
    "Puesto / Institución / País",
    "Position / Institution / Country",
  ))),
  ..cv
    .experiencia
    .map(r => (
      table.cell(align: left + horizon)[#box(r.periodo) (#r.duracion)],
      table.cell(align: left + horizon)[
        #inline(r.puesto)#" / "#linked-institution(
          r.institucion,
          r.url_institucion,
        )#inline(" / " + r.pais)
      ],
    ))
    .flatten(),
)
#subsection(tr("A.3. Formación académica", "A.3. Education"))
#grid-table(
  (career-column, 92mm, 14mm),
  table.header(
    column-label(tr("Licenciatura/Grado/Doctorado", "Degree / Master's / PhD")),
    column-label(tr("Universidad / País", "University / Country")),
    column-label(tr("Año", "Year")),
  ),
  ..cv.formacion.map(r => (
    inline(r.titulo),
    inline(r.universidad),
    table.cell(align: center + horizon)[#r.anio],
  )).flatten(),
)
#section(tr("Parte B. RESUMEN DEL CV", "Part B. CV SUMMARY"))
#for paragraph in cv.resumen_parrafos {
  prose(below: narrative-paragraph-gap)[#markdown-inline(paragraph)]
}
#section(tr("Parte C. MÉRITOS RELEVANTES", "Part C. RELEVANT MERITS"))
#set par(leading: prose-leading, spacing: prose-leading, justify: true)
#subsection(
  tr(
    "C.1. Publicaciones",
    "C.1. Publications",
  ),
  above: 0pt,
)
#if cv.publicaciones_detalle.len() > 0 {
  set par(justify: true)
  enum(
    numbering: "1.",
    indent: 0pt,
    body-indent: 19pt,
    tight: false,
    spacing: entry-gap,
    ..cv.publicaciones_detalle.map(entry => contribution[#publication(entry)]),
  )
}
#subsection(tr("C.2. Congresos", "C.2. Conferences"))
#if cv.congresos_detalle.len() > 0 {
  set par(justify: true)
  enum(
    numbering: "1.",
    indent: 0pt,
    body-indent: 19pt,
    tight: false,
    spacing: entry-gap,
    ..cv.congresos_detalle.map(entry => contribution[
      #emph(inline(entry.tipo + ":")) #citation(entry)
    ]),
  )
}
#subsection(tr(
  "C.3. Proyectos de investigación",
  "C.3. Research projects",
))
#if cv.proyectos_detalle.len() > 0 {
  enum(
    numbering: "1.",
    indent: 0pt,
    body-indent: 19pt,
    tight: false,
    spacing: entry-gap,
    ..cv.proyectos_detalle.map(entry => contribution[
      #inline(entry.titulo) #citation(entry)
      #publication-context[#inline(entry.papel)]
    ]),
  )
}
#subsection(tr(
  "C.4. Transferencia de conocimiento y tecnología",
  "C.4. Knowledge and technology transfer",
))
#for paragraph in cv.transferencia_parrafos {
  prose(below: narrative-paragraph-gap)[#markdown-inline(paragraph)]
}
