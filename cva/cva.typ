// CVA layout adapted from Carlos Perez Carmona's JdC CVA, supplied 2 November 2026.
// Header artwork was supplied by the applicant; the ministry logo uses a PNG rasterisation.
// The applicant's concise labels and content are retained.
// Workbook strings remain literal data and are never evaluated as Typst code.
#let cv = json(sys.inputs.at("data"))
#let es = cv.idioma == "es"
#let tr(a, b) = if es { a } else { b }
#let p = cv.perfil
#let draft = cv.at("borrador", default: false)
#set document(
  title: tr("Curriculum vitae abreviado", "Abbreviated curriculum vitae"),
  author: p.nombre + " " + p.apellidos,
)
#set text(font: "Times New Roman", size: 11pt, lang: cv.idioma, fallback: false, hyphenate: false)
#set page(
  paper: "a4",
  margin: (x: 2.5cm, top: 21mm, bottom: 15mm),
  foreground: context {
    let page-number = counter(page).get().first()
    if page-number == 1 or not es {
      place(top + left, dx: 25mm, dy: 2mm, image("/assets/logo-MCIU.png", width: 44.1mm))
    }
    place(top + right, dx: -25mm, dy: 2mm, image("/assets/logo-AEI.svg", height: 14mm))
  },
  footer: context {
    grid(
      columns: (1fr, 1fr, 1fr),
      align: (left, center, right),
      [],
      if counter(page).get().first() > 1 { counter(page).display() } else { [] },
      if draft { text(fill: rgb("666666"))[#tr("BORRADOR", "DRAFT")] } else { [] },
    )
  },
)
#set par(leading: 0.4em, spacing: 6pt, justify: true)
#set block(spacing: 0pt)
#let part-heading-gap = 9pt
#let subsection-heading-gap = 7pt
#let prose-leading = 0.6em
#let entry-gap = prose-leading
#let section(body, above: 18pt) = block(above: above, below: part-heading-gap, sticky: true)[#strong(body)]
#let subsection(body, above: 12pt) = block(above: above, below: subsection-heading-gap, sticky: true)[#strong(body)]
#let grid-table(columns, ..cells) = block(above: 0pt, below: 0pt)[
  #set align(left)
  #set par(leading: 0.4em, spacing: 0pt, justify: false)
  #table(columns: columns, inset: (x: 3pt, y: 2.5pt), stroke: 0.4pt, ..cells.pos())
]
#let label(body) = body
#let column-label(body) = table.cell(align: center)[#body]
#let first-column = 42mm
#let display-date(value) = value.split("-").rev().join("/")
#let hyperlink(target, label: none, accent: true) = {
  let body = if label == none { target } else { label }
  if accent { text(fill: blue)[#underline(link(target, body))] } else { link(target, body) }
}
#let web-link(value) = if value.starts-with("https://") or value.starts-with("http://") {
  hyperlink(value, accent: false)
} else {
  value
}
#let citation(entry, journal: false) = {
  for segment in entry.segmentos {
    if segment.style == "author" { strong(segment.text) } else if segment.style == "venue" {
      if journal { upper(segment.text) } else { segment.text }
    } else if segment.style == "nowrap" {
      box(segment.text)
    } else if segment.style == "code" {
      let comparison = segment.text.split("<")
      if comparison.len() == 2 {
        box[#comparison.at(0).trim()#h(0.25em)#sym.lt#h(0.25em)#comparison.at(1).trim()]
      } else {
        box(segment.text)
      }
    } else { segment.text }
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
#let contribution-list(entries) = {
  if entries.len() > 0 {
    enum(
      numbering: "1.",
      indent: 0pt,
      body-indent: 19pt,
      tight: false,
      spacing: entry-gap,
      ..entries.map(entry => prose(entry, breakable: entry.len() > 1500)),
    )
  } else if draft {
    prose(tr("Pendiente de completar y seleccionar aportaciones.", "Contributions to be completed and selected."))
  }
}
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
    articulo: tr("Artículo científico.", "Journal article."),
    libro: tr("Libro.", "Book."),
    capitulo: tr("Capítulo de libro.", "Book chapter."),
    datos: tr("Datos.", "Dataset."),
    software: tr("Software.", "Software."),
  )
  [
    #emph(types.at(entry.tipo)) #citation(entry, journal: true)
    #if entry.doi != "" {
      hyperlink("https://doi.org/" + entry.doi)
    }
    #publication-context[
      #entry.autoria #entry.contribucion
    ]
  ]
}

#if cv.demo {
  align(center)[*#tr("EJEMPLO FICTICIO · NO PRESENTAR", "FICTIONAL EXAMPLE · DO NOT SUBMIT")*]
}
#v(3mm)
#block(below: part-heading-gap, sticky: true)[
  #grid(
    columns: (1fr, 71mm),
    align: left + horizon,
    strong(tr("Parte A. DATOS PERSONALES", "Part A. PERSONAL INFORMATION")),
    grid-table((46mm, 25mm), strong(tr("Fecha del CVA", "CVA date")), table.cell(align: center)[#display-date(
      p.fecha_cva,
    )]),
  )
]
#grid-table(
  (first-column, 39mm, 48mm, 31mm),
  label(tr("Nombre", "First name")),
  table.cell(colspan: 3)[#p.nombre],
  label(tr("Apellidos", "Family name")),
  table.cell(colspan: 3)[#p.apellidos],
  label(tr("Sexo", "Gender")),
  p.sexo,
  label(tr("Fecha de Nacimiento", "Birth date")),
  display-date(p.fecha_nacimiento),
  label(tr("DNI", "ID number")),
  table.cell(colspan: 3)[#p.documento],
  label("URL Web"),
  table.cell(colspan: 3)[#web-link(p.web)],
  label(tr("Dirección Email", "Email")),
  table.cell(colspan: 3)[#if p.email.contains("@") {
    hyperlink("mailto:" + p.email, label: p.email, accent: false)
  } else { p.email }],
  table.cell(colspan: 2)[ORCID (Open Researcher and Contributor ID)],
  table.cell(colspan: 2)[#if p.orcid.starts-with("000") {
    hyperlink("https://orcid.org/" + p.orcid, label: p.orcid, accent: false)
  } else { p.orcid }],
)
#subsection(tr("A.1. Situación profesional actual", "A.1. Current position"))
#grid-table(
  (first-column, 48mm, 30mm, 40mm),
  label(tr("Puesto", "Position")),
  table.cell(colspan: 3)[#p.puesto],
  label(tr("Fecha inicio", "Start date")),
  table.cell(colspan: 3)[#{
    let note = p.at("nota_fecha_inicio", default: "")
    display-date(p.fecha_inicio) + " (" + cv.duracion_actual + (if note != "" { "*" } else { "" }) + ")"
    if note != "" {
      linebreak()
      "*" + note
    }
  }],
  label(tr("Organismo / Institución", "Institution")),
  table.cell(colspan: 3)[#p.institucion],
  label(tr("Departamento", "Department")),
  table.cell(colspan: 3)[#p.departamento],
  label(tr("País", "Country")),
  p.pais,
  label(tr("Teléfono", "Phone number")),
  p.telefono,
  label(tr("Palabras clave", "Keywords")),
  table.cell(colspan: 3)[#p.palabras_clave],
)
#subsection(tr("A.2. Situación profesional anterior", "A.2. Previous positions"))
#grid-table(
  (first-column, 1fr),
  table.header(column-label(tr("Periodo", "Period")), column-label(tr(
    "Puesto / Institución / País",
    "Position / Institution / Country",
  ))),
  ..cv
    .experiencia
    .map(r => (
      table.cell(align: left + horizon)[#r.periodo #linebreak() (#r.duracion)],
      table.cell(align: left + horizon)[#r.puesto#if r.tipo == "puesto" { " / " + r.institucion + " / " + r.pais }#if (
          r.interrupcion != ""
        ) {
          [. #r.interrupcion]
        }],
    ))
    .flatten(),
)
#subsection(tr("A.3. Formación académica", "A.3. Education"))
#grid-table(
  (64mm, 82mm, 14mm),
  table.header(
    column-label(tr("Licenciatura/Grado/Doctorado", "Degree / Master's / PhD")),
    column-label(tr("Universidad / País", "University / Country")),
    column-label(tr("Año", "Year")),
  ),
  ..cv.formacion.map(r => (r.titulo, r.universidad, table.cell(align: center)[#r.anio])).flatten(),
)
#section(tr("Parte B. RESUMEN DEL CV", "Part B. CV SUMMARY"))
#for paragraph in cv.resumen.split("\n\n") {
  prose(paragraph, below: 11pt)
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
#let publication-details = cv.at("publicaciones_detalle", default: ())
#if publication-details.len() > 0 {
  set par(justify: true)
  enum(
    numbering: "1.",
    indent: 0pt,
    body-indent: 19pt,
    tight: false,
    spacing: entry-gap,
    ..publication-details.map(entry => prose(
      breakable: entry.cita.len() + entry.autoria.len() + entry.contribucion.len() > 1500,
    )[#publication(
      entry,
    )]),
  )
} else {
  contribution-list(cv.publicaciones)
}
#subsection(tr("C.2. Congresos", "C.2. Conferences"))
#let conferences = cv.at("congresos_detalle", default: ())
#if conferences.len() > 0 {
  set par(justify: true)
  enum(
    numbering: "1.",
    indent: 0pt,
    body-indent: 19pt,
    tight: false,
    spacing: entry-gap,
    ..conferences.map(entry => prose(breakable: entry.cita.len() > 1500)[#emph(
        entry.tipo + ".",
      ) #citation(entry)]),
  )
} else {
  contribution-list(cv.congresos)
}
#subsection(tr(
  "C.3. Proyectos de investigación",
  "C.3. Research projects",
))
#let projects = cv.at("proyectos_detalle", default: ())
#let project-metadata(entry) = {
  for (i, part) in entry.detalles.split(entry.periodo).enumerate() {
    if i > 0 { box(entry.periodo) }
    part
  }
}
#if not es and projects.len() > 0 {
  enum(
    numbering: "1.",
    indent: 0pt,
    body-indent: 19pt,
    tight: false,
    spacing: entry-gap,
    ..projects.map(entry => prose(breakable: false)[
      #strong(entry.titulo) #project-metadata(entry)#text("; ")#strong("Role:") #entry.papel
    ]),
  )
} else {
  contribution-list(cv.proyectos)
}
#subsection(tr(
  "C.4. Transferencia de conocimiento y tecnología",
  "C.4. Knowledge and technology transfer",
))
#contribution-list(cv.transferencia)
