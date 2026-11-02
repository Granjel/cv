// AEI CVA, based on the Spanish and English templates for JdC 2026.
// Data are literal strings: never evaluate workbook text as Typst code.
#let cv = json(sys.inputs.at("data"))
#let es = cv.idioma == "es"
#let tr(a, b) = if es { a } else { b }
#let p = cv.perfil
#set document(title: tr("Curriculum vitae abreviado", "Abbreviated curriculum vitae"), author: p.nombre + " " + p.apellidos)
#set page(paper: "a4", margin: (x: 2.5cm, y: 1.5cm), numbering: "1", number-align: right)
#set text(font: "Arial", size: 11pt, lang: cv.idioma, fallback: false)
#set par(leading: 0.65em, spacing: 0.55em, justify: false)
#set block(spacing: 0.55em)
#let section(body) = block(above: 0.8em, below: 0.4em, sticky: true)[#strong(body)]
#let subsection(body) = block(above: 0.65em, below: 0.35em, sticky: true)[#strong(body)]
#let grid-table(columns, ..cells) = table(columns: columns, inset: (x: 5pt, y: 3pt), stroke: 0.5pt, ..cells.pos())
#let label(body) = table.cell(fill: rgb("eeeeee"))[#body]
#let display-date(value) = value.split("-").rev().join("/")
#let contribution-list(entries) = {
  if entries.len() > 0 {
    enum(..entries.map(entry => [#entry]))
  }
}

#align(center)[*#tr("CURRICULUM VITAE ABREVIADO (CVA)", "ABBREVIATED CURRICULUM VITAE (CVA)")*]
#if cv.demo {
  align(center)[*#tr("EJEMPLO FICTICIO · NO PRESENTAR", "FICTIONAL EXAMPLE · DO NOT SUBMIT")*]
}
#grid-table((4cm, 1fr), label(tr("Fecha del CVA", "Completion date")), display-date(p.fecha_cva))

#section(tr("Parte A. DATOS PERSONALES", "Part A. PERSONAL INFORMATION"))
#grid-table((3.3cm, 4.2cm, 4.2cm, 1fr),
  label(tr("Nombre", "First name")), table.cell(colspan: 3)[#p.nombre],
  label(tr("Apellidos", "Family name")), table.cell(colspan: 3)[#p.apellidos],
  label(tr("Sexo", "Gender")), p.sexo,
  label(tr("Fecha de nacimiento", "Birth date")), display-date(p.fecha_nacimiento),
  label(tr("DNI, NIE, Pasaporte", "Passport or ID number")), table.cell(colspan: 3)[#p.documento],
  label("Email"), p.email,
  label("URL Web"), p.web,
  table.cell(colspan: 2, fill: rgb("eeeeee"))[Open Researcher and Contributor ID (ORCID)], table.cell(colspan: 2)[#p.orcid],
)
#subsection(tr("A.1. Situación profesional actual", "A.1. Current position"))
#grid-table((3.3cm, 4.2cm, 4.2cm, 1fr),
  label(tr("Puesto", "Position")), table.cell(colspan: 3)[#p.puesto],
  label(tr("Fecha inicio", "Start date")), table.cell(colspan: 3)[#display-date(p.fecha_inicio)],
  label(tr("Organismo / Institución", "Institution")), table.cell(colspan: 3)[#p.institucion],
  label(tr("Departamento / Centro", "Department / Center")), table.cell(colspan: 3)[#p.departamento],
  label(tr("País", "Country")), p.pais,
  label(tr("Teléfono", "Phone number")), p.telefono,
  label(tr("Palabras clave", "Keywords")), table.cell(colspan: 3)[#p.palabras_clave],
)
#subsection(tr("A.2. Situación profesional anterior (incluya interrupciones en la carrera investigadora, indicando el número de meses totales)", "A.2. Previous positions (include any research activity interruptions and the total number of months)"))
#grid-table((3.3cm, 1fr),
  table.header(label(tr("Periodo", "Period")), label(tr("Puesto / Institución / País / Motivo interrupción", "Position / Institution / Country / Reason for interruption"))),
  ..cv.experiencia.map(r => (r.periodo, r.detalle)).flatten(),
)
#subsection(tr("A.3. Formación académica", "A.3. Education"))
#grid-table((1fr, 1fr, 1.4cm),
  table.header(label(tr("Grado / Máster / Tesis", "PhD / Master's / Bachelor's")), label(tr("Universidad / País", "University / Country")), label(tr("Año", "Year"))),
  ..cv.formacion.map(r => (r.titulo, r.universidad, r.anio)).flatten(),
)
#section(tr("Parte B. RESUMEN DEL CV (máx. 5.000 caracteres, incluyendo espacios)", "Part B. CV SUMMARY (max. 5000 characters, including spaces)"))
#for paragraph in cv.resumen.split("\n\n") {
  par(paragraph)
}
#section(tr("Parte C. LISTADO DE APORTACIONES MÁS RELEVANTES", "Part C. LIST OF MORE RELEVANT CONTRIBUTIONS"))
#subsection(tr("C.1. Publicaciones más importantes en libros y revistas con ‘peer review’ y en conferencias", "C.1. Most important publications in peer-reviewed journals, books, and conference proceedings"))
#contribution-list(cv.publicaciones)
#subsection(tr("C.2. Congresos", "C.2. Conferences"))
#contribution-list(cv.congresos)
#subsection(tr("C.3. Proyectos o líneas de investigación en los que ha participado", "C.3. Research projects or lines of research in which you have participated"))
#contribution-list(cv.proyectos)
#subsection(tr("C.4. Participación en actividades de transferencia de tecnología/conocimiento y explotación de resultados", "C.4. Participation in technology/knowledge transfer activities and the exploitation of research results"))
#contribution-list(cv.transferencia)
