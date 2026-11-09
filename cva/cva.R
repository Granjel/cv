# read and validate input data, prepare one document per language,
# then compile the Typst template and validate the resulting PDFs
# use Rscript cva/cva.R or source this file and call generar_cva()

# locate the shared repository from either the script path or the working
# directory
cva_root <- local({
  source_files <- Filter(
    function(value) is.character(value) && length(value) == 1L,
    lapply(sys.frames(), function(frame) {
      get0("ofile", envir = frame, inherits = FALSE)
    })
  )
  arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  script <- if (length(source_files)) {
    tail(source_files, 1L)[[1]]
  } else if (length(arg)) {
    sub("^--file=", "", arg[[1]])
  } else {
    ""
  }
  cwd <- normalizePath(getwd(), winslash = "/")
  directory <- if (nzchar(script) && file.exists(script)) {
    dirname(normalizePath(script, winslash = "/"))
  } else {
    cwd
  }
  candidates <- unique(c(dirname(directory), directory, cwd, dirname(cwd)))
  valid <- vapply(
    candidates,
    function(directory) {
      all(file.exists(file.path(directory, "cva", c("cva.R", "cva.typ"))))
    },
    logical(1)
  )
  if (!any(valid)) {
    stop("No se encuentra la carpeta cva del repositorio.", call. = FALSE)
  }
  normalizePath(candidates[valid][[1]], winslash = "/")
})

# use the normal user library
# including when Rscript starts with system libraries only
if (.Platform$OS.type == "windows") {
  r_minor <- strsplit(R.version$minor, ".", fixed = TRUE)[[1]][[1]]
  user_library <- file.path(
    Sys.getenv("LOCALAPPDATA"),
    "R",
    "win-library",
    paste(R.version$major, r_minor, sep = ".")
  )
  if (dir.exists(user_library)) {
    .libPaths(unique(c(.libPaths(), user_library)))
  }
  if (!l10n_info()[["UTF-8"]]) {
    invisible(suppressWarnings(Sys.setlocale(
      "LC_CTYPE",
      "English_United States.utf8"
    )))
  }
}

# required workbook columns
# optional columns and auxiliary sheets remain in Excel
cva_schema <- list(
  Perfil = list(headers = c("campo", "valor", "ingles")),
  Experiencia = list(
    headers = c(
      "incluir",
      "inicio",
      "fin",
      "puesto_es",
      "puesto_en",
      "institucion",
      "departamento",
      "direccion",
      "address",
      "pais_es",
      "pais_en",
      "duracion_meses",
      "nota",
      "note",
      "url_es",
      "url_en"
    )
  ),
  Formacion = list(
    headers = c(
      "incluir",
      "fecha",
      "titulo_es",
      "titulo_en",
      "universidad",
      "pais_es",
      "pais_en"
    )
  ),
  Publicaciones = list(
    headers = c(
      "incluir",
      "estado",
      "fecha",
      "tipo",
      "titulo",
      "autores",
      "posicion_autor",
      "correspondencia",
      "revista_editorial",
      "volumen",
      "paginas",
      "doi",
      "isbn",
      "contribucion_es",
      "contribucion_en",
      "datos_codigo"
    )
  ),
  Congresos = list(
    headers = c(
      "incluir",
      "fecha",
      "tipo",
      "modalidad_es",
      "modalidad_en",
      "titulo",
      "autores",
      "congreso_institucion",
      "lugar_es",
      "lugar_en"
    )
  ),
  Proyectos = list(
    headers = c(
      "incluir",
      "inicio",
      "fin",
      "referencia",
      "acronimo",
      "titulo_es",
      "titulo_en",
      "financiador",
      "funding",
      "convocatoria",
      "call",
      "ip",
      "institucion",
      "institution",
      "importe",
      "moneda",
      "tipo_importe",
      "estado",
      "status",
      "detalle_importe_es",
      "detalle_importe_en",
      "contribucion_es",
      "contribucion_en"
    )
  )
)

# list the personal and authorship fields required by the CVA
# appointment information comes from Experiencia
cva_profile_keys <- c(
  "fecha_cva",
  "nombre",
  "apellidos",
  "sexo",
  "fecha_nacimiento",
  "documento",
  "email",
  "web",
  "orcid",
  "telefono",
  "palabras_clave",
  "alias_autoria"
)

# report validation failures without exposing an internal R call stack
cva_error <- function(...) stop(..., call. = FALSE)

# check runtime packages without installing anything during a build
cva_dependencies <- function() {
  needed <- c("readxl", "jsonlite", "xml2", "pdftools", "commonmark")
  missing <- needed[
    !vapply(needed, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    cva_error("Instala los paquetes de R: ", paste(missing, collapse = ", "))
  }
}

# normalise Excel scalars while retaining literal text and date precision
cva_text <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[[1]])) {
    return("")
  }
  if (inherits(x, c("POSIXt", "Date"))) {
    return(format(x, "%Y-%m-%d", tz = "UTC"))
  }
  value <- trimws(as.character(x[[1]]))
  # normalise ISO date cells returned as text by some XLSX writers
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00(\\.0+)?Z$", value)) {
    return(substr(value, 1, 10))
  }
  value
}

# interpret the workbook's inclusion flags and reject ambiguous values
cva_bool <- function(x, context) {
  if (is.logical(x) && length(x) == 1L && !is.na(x)) {
    return(x)
  }
  value <- tolower(cva_text(x))
  if (value %in% c("true", "si", "sí", "1")) {
    return(TRUE)
  }
  if (value %in% c("false", "no", "0")) {
    return(FALSE)
  }
  cva_error(context, ": usa SI/NO o TRUE/FALSE.")
}

# require a non-empty field and keep its worksheet/row context in errors
cva_required <- function(row, key, context = row$context) {
  value <- cva_text(row[[key]])
  if (!nzchar(value)) {
    cva_error(context, ": falta ", key, ".")
  }
  value
}

# read a translation and flag missing counterparts instead of silently falling
# back
cva_localized <- function(row, key, lang, mandatory = FALSE) {
  fields <- switch(
    key,
    financiador = c(es = "financiador", en = "funding"),
    convocatoria = c(es = "convocatoria", en = "call"),
    institucion = c(es = "institucion", en = "institution"),
    direccion = c(es = "direccion", en = "address"),
    nota = c(es = "nota", en = "note"),
    estado = c(es = "estado", en = "status"),
    c(es = paste0(key, "_es"), en = paste0(key, "_en"))
  )
  value <- cva_text(row[[fields[[lang]]]])
  other_lang <- if (lang == "es") "en" else "es"
  other <- cva_text(row[[fields[[other_lang]]]])
  if (!nzchar(value) && (mandatory || nzchar(other))) {
    cva_error(row$context, ": falta la traducción ", fields[[lang]], ".")
  }
  value
}

# read an optional department URL for this row and language
# a blank cell deliberately leaves the institution unlinked
cva_institution_url <- function(row, lang) {
  key <- paste0("url_", lang)
  value <- cva_text(row[[key]])
  if (nzchar(value) && !grepl("^https?://[^[:space:]]+$", value)) {
    cva_error(row$context, ": URL no válida en ", key, ".")
  }
  value
}

# supply first-month/day anchors for calculations
# preserve the precision displayed in the document
cva_expand_date <- function(value) {
  paste0(
    value,
    switch(as.character(nchar(value)), "4" = "-01-01", "7" = "-01", "")
  )
}

# validate complete or partial ISO dates without inventing displayed precision
cva_date <- function(x, context, optional = FALSE, partial = TRUE) {
  value <- cva_text(x)
  if (optional && !nzchar(value)) {
    return("")
  }
  pattern <- if (partial) {
    "^[0-9]{4}(-[0-9]{2})?(-[0-9]{2})?$"
  } else {
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
  }
  if (!grepl(pattern, value) || substr(value, 1, 4) == "0000") {
    cva_error(context, ": fecha no válida: ", value)
  }
  full <- cva_expand_date(value)
  parsed <- suppressWarnings(as.Date(full, format = "%Y-%m-%d"))
  if (is.na(parsed) || format(parsed, "%Y-%m-%d") != full) {
    cva_error(context, ": fecha no válida: ", value)
  }
  value
}

# derive the earliest and latest dates represented by a partial date
cva_date_bounds <- function(value) {
  start <- as.Date(cva_expand_date(value))
  end <- if (nchar(value) == 4L) {
    as.Date(sprintf("%04d-01-01", as.integer(value) + 1L)) - 1
  } else if (nchar(value) == 7L) {
    seq(start, by = "month", length.out = 2L)[[2]] - 1
  } else {
    start
  }
  list(start = start, end = end)
}

# validate finite non-negative numbers and optional integer-only fields
cva_number <- function(x, context, integer = FALSE) {
  n <- suppressWarnings(as.numeric(cva_text(x)))
  if (length(n) != 1L || !is.finite(n) || n < 0 || (integer && n != floor(n))) {
    cva_error(
      context,
      ": se necesita un número no negativo",
      if (integer) " entero" else "",
      "."
    )
  }
  n
}

# format an award using the language's separators and its original currency
cva_amount <- function(row, lang, digits = 2L, symbols = FALSE) {
  n <- cva_number(row$importe, paste0(row$context, ": importe"))
  amount <- formatC(
    n,
    format = "f",
    digits = digits,
    big.mark = if (lang == "es") "." else ",",
    decimal.mark = if (lang == "es") "," else "."
  )
  currency <- cva_required(row, "moneda")
  if (symbols && currency == "EUR") {
    return(if (lang == "en") paste0("€", amount) else paste(amount, "€"))
  }
  if (symbols && currency == "USD") {
    return(paste0("US$", amount))
  }
  paste(amount, currency)
}

# join non-empty fields without duplicating sentence-ending punctuation
cva_sentences <- function(parts) {
  result <- ""
  for (part in parts[nzchar(parts)]) {
    result <- paste0(
      result,
      if (!nzchar(result)) {
        ""
      } else if (grepl("[.!?]$", result)) {
        " "
      } else {
        ". "
      },
      part
    )
  }
  result
}

# identify the date component without boxing matching text elsewhere
cva_project_segments <- function(before, period, after) {
  list(
    list(
      text = paste0(sub("[.]$", "", cva_sentences(before)), "; "),
      style = "plain"
    ),
    list(text = period, style = "nowrap"),
    list(
      text = paste0(". ", sub("[.]$", "", cva_sentences(after)), "."),
      style = "plain"
    )
  )
}

# load the required sheets, retaining optional columns for section formatters
# map the compact workbook headers to the internal document fields
cva_import_row <- function(row, name, index, count) {
  if (name == "Perfil") {
    return(row)
  }
  # row order resolves date ties without exposing technical IDs in Excel
  row$id <- sprintf("fila_%08d", count - index + 1L)
  row$incluir_cva <- if (nzchar(cva_text(row$incluir))) row$incluir else "SI"
  if (
    name == "Experiencia" &&
      tolower(cva_text(row$fin)) %in% c("actualmente", "actualidad", "present")
  ) {
    row$fin <- ""
  }
  row
}

# load and validate the compact workbook without storing intermediate files
cva_read_excel <- function(filename) {
  cva_dependencies()
  schema <- cva_schema
  # reject formulas rather than trusting potentially stale cached values
  entries <- utils::unzip(filename, list = TRUE)$Name
  if (any(grepl("(^[/\\\\])|(^|/)\\.\\.(/|$)", entries))) {
    cva_error("El archivo Excel contiene rutas no válidas.")
  }
  xml_entries <- grep(
    "^xl/worksheets/sheet[0-9]+\\.xml$",
    entries,
    value = TRUE
  )
  temporary <- tempfile("xlsx-")
  dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
  utils::unzip(filename, files = xml_entries, exdir = temporary)
  for (entry in xml_entries) {
    document <- xml2::read_xml(file.path(temporary, entry))
    if (length(xml2::xml_find_all(document, "//*[local-name()='f']"))) {
      cva_error("El Excel contiene fórmulas; usa valores en los datos del CVA.")
    }
  }
  sheets <- readxl::excel_sheets(filename)
  result <- list()
  for (name in names(schema)) {
    required_headers <- schema[[name]]$headers
    if (!name %in% sheets) {
      cva_error("Falta la pestaña ", name, ".")
    }
    frame <- readxl::read_excel(
      filename,
      sheet = name,
      col_types = "list",
      .name_repair = "minimal"
    )
    headers <- names(frame)
    if (anyDuplicated(headers)) {
      cva_error(name, ": encabezados duplicados.")
    }
    missing <- setdiff(required_headers, headers)
    if (length(missing)) {
      cva_error(name, ": faltan columnas ", paste(missing, collapse = ", "))
    }
    rows <- list()
    seen <- character()
    key <- if (name == "Perfil") {
      "campo"
    } else {
      "id"
    }
    for (i in seq_len(nrow(frame))) {
      row <- lapply(frame, function(col) col[[i]])
      if (
        !any(vapply(
          row[required_headers],
          function(x) nzchar(cva_text(x)),
          logical(1)
        ))
      ) {
        next
      }
      row$context <- paste0(name, ", fila ", i + 1L)
      row <- cva_import_row(row, name, i, nrow(frame))
      id <- cva_required(row, key)
      if (id %in% seen) {
        cva_error(row$context, ": ", key, " duplicado: ", id)
      }
      seen <- c(seen, id)
      rows[[length(rows) + 1L]] <- row
    }
    result[[name]] <- rows
  }
  result
}

# filter selected entries, validate their periods and sort them newest first
cva_selected <- function(tables, name) {
  rows <- Filter(function(r) cva_bool(r$incluir_cva, r$context), tables[[name]])
  if (
    name %in%
      c("Publicaciones", "Congresos", "Proyectos") &&
      length(rows) > 10L
  ) {
    cva_error(name, ": el máximo es 10 aportaciones.")
  }
  key <- if (name %in% c("Experiencia", "Proyectos")) "inicio" else "fecha"
  rows <- lapply(rows, function(row) {
    row[[key]] <- cva_date(row[[key]], paste0(row$context, ": ", key))
    if ("fin" %in% names(row)) {
      row$fin <- cva_date(
        row$fin,
        paste0(row$context, ": fin"),
        optional = TRUE
      )
      if (
        nzchar(row$fin) &&
          cva_date_bounds(row$fin)$end < cva_date_bounds(row[[key]])$start
      ) {
        cva_error(row$context, ": fin es anterior a ", key)
      }
    }
    row
  })
  if (length(rows)) {
    rows <- rows[order(
      vapply(rows, `[[`, character(1), key),
      vapply(rows, function(r) cva_text(r$id), character(1)),
      decreasing = TRUE
    )]
  }
  unname(rows)
}

# compact given names to initials without changing surname spelling
cva_short_author <- function(name) {
  parts <- strsplit(name, ",", fixed = TRUE)[[1]]
  if (length(parts) != 2L) {
    initials <- regexpr(" [[:upper:]][[:upper:]. -]*$", name)
    if (initials[[1]] < 1L) {
      return(name)
    }
    return(paste0(
      substr(name, 1L, initials[[1]] - 1L),
      " ",
      gsub("[[:space:].-]", "", substring(name, initials[[1]] + 1L))
    ))
  }
  given <- strsplit(trimws(parts[[2]]), "[[:space:].-]+")[[1]]
  given <- given[nzchar(given)]
  initials <- vapply(
    given,
    function(part) {
      if (grepl("^[[:upper:]]+$", part)) part else substr(part, 1, 1)
    },
    character(1)
  )
  paste0(trimws(parts[[1]]), " ", paste0(initials, collapse = ""))
}

# read semicolon-separated names without carrying empty display entries forward
cva_split_names <- function(value) {
  names <- trimws(strsplit(value, ";", fixed = TRUE)[[1]])
  names[nzchar(names)]
}

# validate the applicant's position against the complete ordered author list
cva_author_position <- function(row) {
  names <- cva_split_names(cva_required(row, "autores"))
  total <- length(names)
  position <- cva_number(
    row$posicion_autor,
    paste0(row$context, ": posicion_autor"),
    TRUE
  )
  if (position < 1L || position > total) {
    cva_error(
      row$context,
      ": posicion_autor está fuera de la lista de autores."
    )
  }
  list(position = position, total = total)
}

# abbreviate long lists while retaining required authors and meaningful ellipses
cva_authors <- function(row) {
  names <- cva_split_names(cva_required(row, "autores"))
  position <- cva_author_position(row)$position
  display <- vapply(names, cva_short_author, character(1))
  if (length(names) <= 8L) {
    return(paste(display, collapse = "; "))
  }
  corresponding <- cva_split_names(cva_text(row$correspondencia))
  if (!all(corresponding %in% names)) {
    cva_error(row$context, ": autor de correspondencia ausente de autores.")
  }
  indices <- sort(unique(c(
    1:2,
    position,
    match(corresponding, names),
    length(names)
  )))
  shown <- character()
  previous <- 0L
  for (index in indices) {
    if (index > previous + 1L) {
      shown <- c(shown, "…")
    }
    shown <- c(shown, display[[index]])
    previous <- index
  }
  paste(shown, collapse = "; ")
}

# state corresponding authorship and the applicant's position for the quote
cva_publication_role <- function(
  position,
  total,
  own_author,
  corresponding_authors,
  lang
) {
  is_corresponding <- own_author %in% corresponding_authors
  if (lang == "en") {
    paste0(
      if (is_corresponding) {
        "Corresponding author and position "
      } else {
        "Position "
      },
      position,
      "/",
      total,
      if (total == 1L) " author." else " authors."
    )
  } else {
    paste0(
      if (is_corresponding) {
        "Autor de correspondencia y posición "
      } else {
        "Posición "
      },
      position,
      "/",
      total,
      if (total == 1L) " autor." else " autores."
    )
  }
}

# compare author aliases independently of case, spaces and punctuation
cva_author_key <- function(value) tolower(gsub("[[:space:],.]+", "", value))

# separate literal citation text from the styles applied later by Typst
cva_citation_segments <- function(
  parts,
  own_authors,
  venue_index,
  separators = NULL,
  keep_together = integer()
) {
  # treat titles as literal data
  # format initials and style applicant and venue
  own_authors <- cva_author_key(vapply(
    own_authors,
    cva_short_author,
    character(1)
  ))
  segments <- list()
  add <- function(value, style = "plain") {
    if (nzchar(value)) {
      segments[[length(segments) + 1L]] <<- list(text = value, style = style)
    }
  }
  previous <- ""
  for (index in which(nzchar(parts))) {
    value <- parts[[index]]
    if (nzchar(previous)) {
      add(
        if (as.character(index) %in% names(separators)) {
          separators[[as.character(index)]]
        } else if (grepl("[.!?]$", previous)) {
          " "
        } else {
          ". "
        }
      )
    }
    if (index == venue_index) {
      add(value, "venue")
    } else if (index == 1L) {
      # semicolons delimit workbook data
      # displayed authors use commas
      authors <- strsplit(value, ";", fixed = TRUE)[[1]]
      for (i in seq_along(authors)) {
        if (i > 1L) {
          add(", ")
        }
        author <- cva_short_author(trimws(authors[[i]]))
        add(
          author,
          if (cva_author_key(author) %in% own_authors) "author" else "plain"
        )
      }
    } else {
      add(value, if (index %in% keep_together) "nowrap" else "plain")
    }
    previous <- if (index == 1L) author else value
  }
  segments
}

# retain a plain-text version of the same styled citation segments
cva_citation_text <- function(segments) {
  paste0(
    vapply(
      segments,
      `[[`,
      character(1),
      "text"
    ),
    collapse = ""
  )
}

# display conference dates in the requested language at their known precision
cva_conference_date <- function(value, lang) {
  year <- substr(value, 1, 4)
  if (nchar(value) < 7L) {
    return(year)
  }
  months <- if (lang == "es") {
    c(
      "Enero",
      "Febrero",
      "Marzo",
      "Abril",
      "Mayo",
      "Junio",
      "Julio",
      "Agosto",
      "Septiembre",
      "Octubre",
      "Noviembre",
      "Diciembre"
    )
  } else {
    c(
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December"
    )
  }
  month <- months[[as.integer(substr(value, 6, 7))]]
  if (lang == "es") paste(month, "de", year) else paste(month, year)
}

# display appointment and project dates as year or month/year
cva_period_date <- function(value) {
  if (nchar(value) >= 7L) {
    paste0(substr(value, 6, 7), "/", substr(value, 1, 4))
  } else {
    value
  }
}

# capitalise only the first character of each semicolon-separated keyword
cva_keywords <- function(value) {
  terms <- trimws(strsplit(value, ";", fixed = TRUE)[[1]])
  terms <- terms[nzchar(terms)]
  paste(
    paste0(toupper(substr(terms, 1, 1)), substring(terms, 2)),
    collapse = "; "
  )
}

# calculate covered months, half-month rounding or a supplied duration override
cva_duration <- function(start, end = "", as_of, lang, override = NULL) {
  # durations use the resolved CVA date, automatic or manually fixed
  suffix <- if (lang == "es") "meses" else "months"
  display <- function(value) {
    format(
      value,
      trim = TRUE,
      scientific = FALSE,
      decimal.mark = if (lang == "es") "," else "."
    )
  }
  quantity <- function(value) {
    paste(
      display(value),
      if (value == 1) {
        if (lang == "es") "mes" else "month"
      } else {
        suffix
      }
    )
  }
  if (nzchar(cva_text(override))) {
    return(quantity(cva_number(override, "duracion_meses")))
  }
  ongoing <- !nzchar(end)
  finish <- if (ongoing) as_of else end
  month_index <- function(value) {
    as.integer(substr(value, 1, 4)) * 12L + as.integer(substr(value, 6, 7))
  }
  if (nchar(start) < 7L || nchar(finish) < 7L) {
    lower <- month_index(format(cva_date_bounds(finish)$start, "%Y-%m-%d")) -
      month_index(format(cva_date_bounds(start)$end, "%Y-%m-%d")) +
      1L
    upper <- month_index(format(cva_date_bounds(finish)$end, "%Y-%m-%d")) -
      month_index(format(cva_date_bounds(start)$start, "%Y-%m-%d")) +
      1L
    return(paste0(max(0L, lower), "-", max(0L, upper), " ", suffix))
  }
  if (nchar(start) == 10L && nchar(finish) == 10L) {
    from <- as.Date(start)
    until <- as.Date(finish) + if (ongoing) 0 else 1
    add_months <- function(n) {
      index <- month_index(start) - 1L + n
      first <- as.Date(sprintf(
        "%04d-%02d-01",
        index %/% 12L,
        index %% 12L + 1L
      ))
      last_day <- as.integer(format(
        seq(first, by = "month", length.out = 2)[[2]] - 1,
        "%d"
      ))
      first + min(as.integer(format(from, "%d")), last_day) - 1L
    }
    whole <- month_index(finish) - month_index(start)
    if (add_months(whole) > until) {
      whole <- whole - 1L
    }
    fraction <- as.numeric(until - add_months(whole)) /
      as.numeric(add_months(whole + 1L) - add_months(whole))
    elapsed <- whole + fraction
    value <- round(elapsed * 2) / 2
    return(quantity(value))
  }
  # month-only dates describe covered calendar months. For an ongoing role,
  # exclude the still-incomplete current month
  months <- month_index(finish) - month_index(start) + if (ongoing) 0L else 1L
  quantity(max(0L, months))
}

# resolve today's date in Madrid independently of the machine's time zone
cva_today <- function(now = Sys.time()) {
  format(now, "%Y-%m-%d", tz = "Europe/Madrid")
}

# convert supported inline Markdown nodes to literal, typed JSON data
cva_markdown_inline <- function(nodes, context) {
  lapply(seq_along(nodes), function(i) {
    node <- nodes[[i]]
    type <- xml2::xml_name(node)
    if (type %in% c("text", "code")) {
      return(list(type = type, text = xml2::xml_text(node)))
    }
    if (type == "softbreak") {
      return(list(type = "text", text = " "))
    }
    if (type == "linebreak") {
      return(list(type = "linebreak"))
    }
    if (type %in% c("strong", "emph")) {
      return(list(
        type = type,
        children = cva_markdown_inline(xml2::xml_children(node), context)
      ))
    }
    if (type == "link") {
      return(list(
        type = type,
        destination = xml2::xml_attr(node, "destination"),
        children = cva_markdown_inline(xml2::xml_children(node), context)
      ))
    }
    cva_error(
      context,
      ": unsupported inline Markdown element '",
      type,
      "'; use plain text, bold, italics, links or inline code."
    )
  })
}

# count only visible text, including explicit breaks and paragraph separators
cva_markdown_plain <- function(nodes) {
  paste0(
    vapply(
      nodes,
      function(node) {
        if (node$type %in% c("text", "code")) {
          node$text
        } else if (node$type == "linebreak") {
          "\n"
        } else {
          cva_markdown_plain(node$children)
        }
      },
      character(1)
    ),
    collapse = ""
  )
}

# parse explicit workbook emphasis with the same safe inline Markdown nodes
# prefix the cell so leading punctuation cannot create a heading or list
cva_workbook_formatting <- function(value) {
  texts <- unique(as.character(unlist(value, use.names = FALSE)))
  texts <- texts[!is.na(texts) & grepl("*", texts, fixed = TRUE)]
  formatted <- list()
  prefix <- "cva-inline "
  for (text in texts) {
    tree <- commonmark::markdown_xml(
      paste0(prefix, gsub("[\r\n]+", " ", text)),
      smart = FALSE,
      normalize = FALSE,
      footnotes = FALSE,
      extensions = FALSE
    )
    document <- xml2::read_xml(tree, options = c("NONET", "NOBLANKS"))
    xml2::xml_ns_strip(document)
    paragraph <- xml2::xml_children(document)[[1L]]
    if (!length(xml2::xml_find_all(paragraph, ".//emph | .//strong"))) {
      next
    }
    nodes <- xml2::xml_children(paragraph)
    xml2::xml_text(nodes[[1L]]) <- substring(
      xml2::xml_text(nodes[[1L]]),
      nchar(prefix) + 1L
    )
    # html-looking input remains literal text, never executable markup
    html <- xml2::xml_find_all(paragraph, ".//html_inline")
    for (i in seq_along(html)) {
      xml2::xml_name(html[[i]]) <- "text"
    }
    formatted[[text]] <- cva_markdown_inline(nodes, "workbook text")
  }
  formatted
}

# read the two editable sections without interpreting HTML or Typst code
cva_read_markdown <- function(filename) {
  if (!file.exists(filename)) {
    cva_error("Missing narrative Markdown file: ", filename)
  }
  context <- basename(filename)
  markdown <- paste(
    readLines(filename, encoding = "UTF-8", warn = FALSE),
    collapse = "\n"
  )
  tree <- commonmark::markdown_xml(
    markdown,
    smart = FALSE,
    normalize = FALSE,
    footnotes = FALSE,
    extensions = FALSE
  )
  document <- xml2::read_xml(tree, options = c("NONET", "NOBLANKS"))
  xml2::xml_ns_strip(document)
  blocks <- xml2::xml_children(document)
  sections <- list(resumen = list(), transferencia = list())
  headings <- c("Part B" = "resumen", "C.4" = "transferencia")
  seen <- character()
  current <- NULL

  # section headings select the destination and are not rendered or counted
  for (i in seq_along(blocks)) {
    block <- blocks[[i]]
    type <- xml2::xml_name(block)
    if (type == "heading") {
      title <- xml2::xml_text(block)
      if (
        xml2::xml_attr(block, "level") != "1" ||
          !title %in% names(headings)
      ) {
        cva_error(
          context,
          ": use only '# Part B' and '# C.4' as section headings; ",
          "use bold text for labels inside a section."
        )
      }
      current <- unname(headings[[title]])
      if (current %in% seen) {
        cva_error(context, ": duplicate section heading '# ", title, "'.")
      }
      seen <- c(seen, current)
      next
    }
    if (is.null(current)) {
      cva_error(context, ": narrative text must follow '# Part B' or '# C.4'.")
    }
    if (type != "paragraph") {
      cva_error(
        context,
        ": unsupported Markdown block '",
        type,
        "'; use paragraphs with bold, italics, links or inline code."
      )
    }
    sections[[current]][[length(sections[[current]]) + 1L]] <-
      cva_markdown_inline(xml2::xml_children(block), context)
  }

  # retain visible text for the character limit and document comparisons
  missing <- setdiff(unname(headings), seen)
  if (length(missing)) {
    cva_error(context, ": include both '# Part B' and '# C.4' headings.")
  }
  result <- lapply(sections, function(paragraphs) {
    list(
      text = paste(
        vapply(
          paragraphs,
          cva_markdown_plain,
          character(1)
        ),
        collapse = "\n\n"
      ),
      paragraphs = paragraphs
    )
  })
  if (!nzchar(result$resumen$text)) {
    cva_error(context, ": Part B cannot be empty.")
  }
  result
}

# collect explicit code from Markdown nodes and backticked workbook text
# the same single-backtick convention is used by the Typst inline renderer
cva_declared_code <- function(value) {
  if (is.list(value)) {
    if (identical(value$type, "code")) {
      return(value$text)
    }
    return(unlist(lapply(value, cva_declared_code), use.names = FALSE))
  }
  if (!is.character(value)) {
    return(character())
  }
  unlist(
    lapply(value, function(text) {
      spans <- regmatches(text, gregexpr("`[^`]+`", text))[[1]]
      substring(spans, 2L, nchar(spans) - 1L)
    }),
    use.names = FALSE
  )
}

# resolve personal data and the current appointment for Part A
# read the editable B/C.4 narrative and enforce the summary limit
cva_prepare_header <- function(tables, current, lang, render_date, root) {
  profile_rows <- setNames(
    tables$Perfil,
    vapply(tables$Perfil, `[[`, character(1), "campo")
  )
  profile <- list()
  for (key in cva_profile_keys) {
    row <- profile_rows[[key]]
    if (is.null(row) && key != "fecha_cva") {
      cva_error("Perfil: falta el campo ", key)
    }
    value <- if (lang == "en" && nzchar(cva_text(row$ingles))) {
      cva_text(row$ingles)
    } else {
      cva_text(row$valor)
    }
    if (key == "fecha_cva" && (!nzchar(value) || tolower(value) == "auto")) {
      value <- render_date
    }
    if (!nzchar(value) && key != "web") {
      cva_error("Perfil: falta ", key, " para el idioma ", lang)
    }
    profile[[key]] <- value
  }
  for (key in c("fecha_cva", "fecha_nacimiento")) {
    profile[[key]] <- cva_date(
      profile[[key]],
      paste0("Perfil: ", key),
      partial = FALSE
    )
  }
  if (!grepl("^[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{3}[0-9X]$", profile$orcid)) {
    cva_error("Perfil: ORCID no válido.")
  }

  # derive the current-position table and its note from one appointment row
  profile$puesto <- cva_localized(current, "puesto", lang, TRUE)
  profile$fecha_inicio <- current$inicio
  profile$institucion <- cva_required(current, "institucion")
  profile$url_institucion <- cva_institution_url(current, lang)
  profile$departamento <- cva_required(current, "departamento")
  profile$pais <- cva_localized(current, "pais", lang, TRUE)
  profile$nota_fecha_inicio <- cva_localized(current, "nota", lang)
  profile$palabras_clave <- cva_keywords(profile$palabras_clave)

  narrative <- cva_read_markdown(file.path(root, "input", paste0(lang, ".md")))
  summary <- narrative$resumen$text
  if (nchar(summary, type = "chars") > 5000L) {
    cva_error(
      "El resumen ",
      lang,
      " tiene ",
      nchar(summary),
      " caracteres; el máximo es 5000."
    )
  }
  list(
    idioma = lang,
    perfil = profile,
    resumen = summary,
    resumen_parrafos = narrative$resumen$paragraphs,
    transferencia_narrativa = narrative$transferencia$text,
    transferencia_parrafos = narrative$transferencia$paragraphs,
    duracion_actual = cva_duration(
      current$inicio,
      as_of = profile$fecha_cva,
      lang = lang,
      override = current$duracion_meses
    )
  )
}

# prepare the previous appointments using their explicit duration when supplied
cva_prepare_experience <- function(row, lang, as_of) {
  list(
    periodo = paste(
      cva_period_date(row$inicio),
      cva_period_date(row$fin),
      sep = " – "
    ),
    duracion = cva_duration(
      row$inicio,
      row$fin,
      as_of,
      lang,
      row$duracion_meses
    ),
    puesto = cva_localized(row, "puesto", lang, TRUE),
    institucion = cva_required(row, "institucion"),
    url_institucion = cva_institution_url(row, lang),
    pais = cva_localized(row, "pais", lang, TRUE)
  )
}

# prepare A.3 degree, university/country and year cells
cva_prepare_education <- function(row, lang) {
  req <- function(key) cva_required(row, key)
  loc <- function(key, mandatory = FALSE) {
    cva_localized(row, key, lang, mandatory)
  }

  entry <- list(
    titulo = loc("titulo", TRUE),
    universidad = paste(
      req("universidad"),
      loc("pais", TRUE),
      sep = " / "
    ),
    anio = substr(row$fecha, 1, 4)
  )
  entry
}

# prepare C.1 citations and contribution quotes from the complete author list
cva_prepare_publication <- function(row, lang, applicant_authors) {
  req <- function(key) cva_required(row, key)
  loc <- function(key, mandatory = FALSE) {
    cva_localized(row, key, lang, mandatory)
  }

  # validate the full list before constructing the shortened citation
  author_position <- cva_author_position(row)
  ordered_authors <- cva_split_names(req("autores"))
  own_author <- ordered_authors[[author_position$position]]
  corresponding_authors <- cva_split_names(cva_text(row$correspondencia))
  if (!all(corresponding_authors %in% ordered_authors)) {
    cva_error(
      row$context,
      ": autor de correspondencia ausente de autores."
    )
  }
  kind <- req("tipo")
  if (!kind %in% c("articulo", "libro", "capitulo", "datos", "software")) {
    cva_error(row$context, ": tipo de publicación desconocido.")
  }
  # assemble literal citation fields and preserve the established separators
  citation <- c(
    cva_authors(row),
    substr(row$fecha, 1, 4),
    req("titulo"),
    req("revista_editorial"),
    cva_text(row$volumen),
    gsub(
      "([0-9])[[:space:]]*[-–][[:space:]]*([0-9])",
      "\\1–\\2",
      cva_text(row$paginas)
    )
  )
  if (kind %in% c("libro", "capitulo")) {
    citation <- c(citation, paste0("ISBN: ", req("isbn")))
  }
  # normalise DOI input; the template supplies its visible label and styling
  doi <- ""
  if (nzchar(cva_text(row$doi))) {
    doi <- sub("^(https://doi.org/|doi:)", "", cva_text(row$doi))
    if (!grepl("^10\\.[0-9]{4,9}/[^[:space:]]+$", doi)) {
      cva_error(row$context, ": DOI no válido.")
    }
  }
  separators <- c("5" = " ", "6" = ", ")
  segments <- cva_citation_segments(
    citation,
    applicant_authors,
    4L,
    separators = separators
  )
  citation_text <- cva_citation_text(segments)
  # keep the role prefix separate from the editable contribution explanation
  authorship <- cva_publication_role(
    author_position$position,
    author_position$total,
    own_author,
    corresponding_authors,
    lang
  )
  contribution <- loc("contribucion")
  detail <- list(
    tipo = kind,
    posicion = author_position$position,
    total_autores = author_position$total,
    autoria = authorship,
    contribucion = contribution,
    cita = citation_text,
    segmentos = segments,
    doi = doi
  )
  list(detail = detail)
}

# prepare C.2 presentation or committee entries, including author and code-font
# segments
cva_prepare_conference <- function(row, lang, applicant_authors) {
  req <- function(key) cva_required(row, key)
  loc <- function(key, mandatory = FALSE) {
    cva_localized(row, key, lang, mandatory)
  }
  kind <- cva_text(row$tipo)
  if (!nzchar(kind)) {
    kind <- "presentacion"
  }
  if (!kind %in% c("presentacion", "organizacion")) {
    cva_error(
      row$context,
      ": tipo de contribución a congresos desconocido."
    )
  }
  # show authors for presentations; organisational roles have no author list
  mode <- loc("modalidad", TRUE)
  authors <- if (kind == "presentacion") {
    req("autores")
  } else {
    ""
  }
  title <- if (kind == "presentacion") {
    req("titulo")
  } else {
    cva_text(row$titulo)
  }
  show_authors <- kind == "presentacion"
  place <- loc("lugar", TRUE)
  citation <- c(
    if (show_authors) authors else "",
    title,
    req("congreso_institucion"),
    place,
    cva_conference_date(row$fecha, lang)
  )
  # use configured aliases for emphasis and keep only the date field unbroken
  segments <- cva_citation_segments(
    citation,
    applicant_authors,
    3L,
    separators = c("2" = ". ", "4" = " (", "5" = "; "),
    keep_together = 5L
  )
  segments <- c(segments, list(list(text = ").", style = "plain")))
  citation_text <- cva_citation_text(segments)
  detail <- list(
    tipo = mode,
    categoria = kind,
    autores_visibles = show_authors,
    cita = citation_text,
    segmentos = segments
  )
  list(detail = detail)
}

# prepare project titles, bilingual metadata and contribution quotes
cva_prepare_project <- function(row, lang) {
  req <- function(key) cva_required(row, key)
  loc <- function(key) cva_localized(row, key, lang, TRUE)
  es <- lang == "es"
  reference <- cva_text(row$referencia)
  call <- loc("convocatoria")
  title <- sub("[.]$", "", loc("titulo"))

  acronym <- cva_text(row$acronimo)
  if (nzchar(acronym)) {
    title <- paste0(acronym, ": ", title)
  }

  # build PI and institution wording from the structured fields
  investigators <- cva_split_names(req("ip"))
  people <- if (length(investigators) == 1L) {
    investigators
  } else {
    paste0(
      paste(head(investigators, -1L), collapse = ", "),
      if (es) " y " else " and ",
      tail(investigators, 1L)
    )
  }
  institution <- loc("institucion")
  direction <- paste0(
    if (length(investigators) > 1L) {
      if (es) "Co-IP: " else "Co-PIs: "
    } else if (es) {
      "IP: "
    } else {
      "PI: "
    },
    people,
    if (es) ", en " else ", at ",
    institution
  )
  period <- if (identical(row$inicio, row$fin)) {
    cva_period_date(row$inicio)
  } else {
    paste(
      cva_period_date(row$inicio),
      if (nzchar(row$fin)) {
        cva_period_date(row$fin)
      } else if (es) {
        "actualidad"
      } else {
        "present"
      },
      sep = "–"
    )
  }
  amount_type <- req("tipo_importe")
  if (!amount_type %in% c("total", "estimado")) {
    cva_error(row$context, ": tipo_importe debe ser total o estimado.")
  }
  amount <- cva_number(row$importe, paste0(row$context, ": importe"))
  value <- cva_amount(
    row,
    lang,
    digits = if (amount == floor(amount)) 0L else 2L,
    symbols = TRUE
  )
  # describe the numeric award neutrally and print only explicit extra details
  award <- paste0(
    if (amount_type == "estimado") {
      if (es) "Valor estimado: " else "Estimated value: "
    } else if (es) {
      "Financiación total: "
    } else {
      "Total funding: "
    },
    value
  )
  programme <- paste(call, loc("financiador"), sep = ", ")
  segments <- cva_project_segments(
    c(if (nzchar(reference)) paste0("Ref. ", reference), programme, direction),
    period,
    c(
      award,
      cva_localized(row, "detalle_importe", lang),
      cva_localized(row, "estado", lang)
    )
  )
  list(
    titulo = paste0(title, "."),
    detalles = paste0(sub("[.]$", "", cva_citation_text(segments)), "."),
    segmentos = segments,
    periodo = period,
    papel = paste0(sub("[.]$", "", loc("contribucion")), ".")
  )
}

# assemble the current and previous appointments and the prepared contribution
# lists in the order used by the template
cva_prepare <- function(
  tables,
  lang,
  root = cva_root,
  render_date = cva_today()
) {
  appointments <- cva_selected(tables, "Experiencia")
  current <- Filter(function(row) !nzchar(row$fin), appointments)
  if (length(current) != 1L) {
    cva_error(
      "Experiencia: debe haber un único puesto actual con fin actualmente o vacío."
    )
  }
  result <- cva_prepare_header(
    tables,
    current[[1]],
    lang,
    render_date,
    root
  )
  profile <- result$perfil
  previous <- Filter(function(row) nzchar(row$fin), appointments)
  result$experiencia <- lapply(
    previous,
    cva_prepare_experience,
    lang = lang,
    as_of = profile$fecha_cva
  )
  result$formacion <- lapply(
    cva_selected(tables, "Formacion"),
    cva_prepare_education,
    lang = lang
  )
  applicant_authors <- cva_split_names(profile$alias_autoria)
  for (name in c("Publicaciones", "Congresos", "Proyectos")) {
    details <- list()
    for (row in cva_selected(tables, name)) {
      prepared <- switch(
        name,
        Publicaciones = cva_prepare_publication(row, lang, applicant_authors),
        Congresos = cva_prepare_conference(row, lang, applicant_authors),
        Proyectos = list(detail = cva_prepare_project(row, lang))
      )
      details[[length(details) + 1L]] <- prepared$detail
    }
    result[[paste0(tolower(name), "_detalle")]] <- details
  }
  result$formato_en_linea <- cva_workbook_formatting(result)
  result$codigo_declarado <- cva_declared_code(result)
  result
}

# check page limits, A4 size, file size and the existing font/size rules
cva_check_pdf <- function(
  filename,
  max_pages = 4L,
  code_fragments = character()
) {
  info <- pdftools::pdf_info(filename)
  if (info$pages < 1L || info$pages > max_pages) {
    cva_error(
      "El PDF tiene ",
      info$pages,
      " páginas; el máximo es ",
      max_pages,
      "."
    )
  }
  bytes <- file.info(filename)$size
  if (bytes > 4000000) {
    cva_error("El PDF supera los 4 MB.")
  }
  size <- pdftools::pdf_pagesize(filename)
  if (any(abs(size$width - 595.28) > 1 | abs(size$height - 841.89) > 1)) {
    cva_error("El PDF no es A4.")
  }
  fonts <- pdftools::pdf_fonts(filename)
  if (
    any(
      !grepl("Arial|Calibri|TimesNewRoman|Times-New-Roman|Consolas", fonts$name)
    )
  ) {
    cva_error("El PDF contiene una fuente no admitida.")
  }
  # validate code against declared input, with one font size in every section
  # pdf words may join adjacent spans or split a span across wrapped lines
  # compare literal substrings of the ordered, whitespace-free declarations
  declared <- gsub("[[:space:]]+", "", paste(code_fragments, collapse = ""))
  boxes <- pdftools::pdf_data(filename, font_info = TRUE)
  for (page in boxes) {
    visible <- nzchar(trimws(page$text))
    code <- grepl("Consolas", page$font_name)
    known_code <- vapply(
      page$text,
      function(text) {
        value <- gsub("[[:space:]]+", "", text)
        nzchar(value) && grepl(value, declared, fixed = TRUE)
      },
      logical(1)
    )
    if (any(code & !known_code)) {
      cva_error("Consolas solo se permite en fragmentos de código declarados.")
    }
    if (any(code & abs(page$font_size - 10.5) > 0.01)) {
      cva_error("Los fragmentos de código deben usar Consolas de 10,5 pt.")
    }
    # accept a reduced ordinal suffix only beside a full-size numeral
    # require the raised position, matching face and the shared 75% size
    ordinal <- rep(FALSE, nrow(page))
    candidates <- which(
      !code &
        grepl("^(st|nd|rd|th|er)$", page$text, ignore.case = TRUE) &
        abs(page$font_size - 8.25) <= 0.01
    )
    for (index in candidates) {
      numeral <- grepl("[0-9][.]?$", page$text) &
        abs(page$font_size - 11) <= 0.01 &
        page$font_name == page$font_name[[index]] &
        abs(page$x + page$width - page$x[[index]]) <= 3 &
        page$y > page$y[[index]] &
        page$y - page$y[[index]] <= 6
      ordinal[[index]] <- any(numeral)
    }
    if (any(visible & !code & !ordinal & page$font_size < 10.99)) {
      cva_error("El PDF contiene texto menor del tamaño mínimo establecido.")
    }
  }
  list(paginas = info$pages, bytes = bytes)
}

# locate Typst and verify the document font before creating compilation inputs
cva_find_typst <- function(typst) {
  executable <- unname(Sys.which(typst))
  if (!nzchar(executable) && file.exists(typst)) {
    executable <- normalizePath(typst, winslash = "/")
  }
  if (!nzchar(executable) && .Platform$OS.type == "windows") {
    candidate <- file.path(
      Sys.getenv("ProgramFiles", "C:/Program Files"),
      "Typst/typst.exe"
    )
    if (file.exists(candidate)) executable <- candidate
  }
  if (!nzchar(executable)) {
    cva_error("No se encuentra Typst. Indica su ruta con --typst.")
  }
  fonts <- system2(executable, "fonts", stdout = TRUE)
  missing <- setdiff(c("Times New Roman", "Consolas"), fonts)
  if (length(missing)) {
    cva_error("No se encuentran las fuentes: ", paste(missing, collapse = ", "))
  }
  executable
}

# stage the unchanged template and logos inside Typst's temporary root
cva_stage_inputs <- function(root, temporary) {
  dir.create(file.path(temporary, "assets"))
  logos <- file.path(root, "assets", c("logo-AEI.svg", "logo-MCIU.png"))
  if (
    !all(file.exists(c(file.path(root, "cva", "cva.typ"), logos))) ||
      !file.copy(file.path(root, "cva", "cva.typ"), temporary) ||
      !all(file.copy(logos, file.path(temporary, "assets")))
  ) {
    cva_error("No se han podido preparar la plantilla y los logotipos.")
  }
  invisible(NULL)
}

# write one language's JSON and compile it with the existing filename
# and Typst options
cva_compile_pdf <- function(
  document,
  lang,
  executable,
  temporary
) {
  json <- file.path(temporary, paste0("cva-", lang, ".json"))
  jsonlite::write_json(
    document,
    json,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
  pdf <- file.path(temporary, paste0("cva-", lang, ".pdf"))
  relative <- basename(json)
  log <- file.path(temporary, paste0(lang, ".log"))
  status <- system2(
    executable,
    c(
      "compile",
      "--root",
      shQuote(normalizePath(temporary, winslash = "/")),
      "--input",
      shQuote(paste0("data=", relative)),
      shQuote(file.path(temporary, "cva.typ")),
      shQuote(pdf)
    ),
    stdout = log,
    stderr = log
  )
  diagnostics <- readLines(log, warn = FALSE, encoding = "UTF-8")
  if (status != 0L || any(nzchar(diagnostics))) {
    cva_error("Typst: ", paste(diagnostics, collapse = "\n"))
  }
  pdf
}

# coordinate validation, temporary compilation and copying of finished PDFs
generar_cva <- function(
  excel = file.path(cva_root, "input/datos-cv.xlsx"),
  idioma = "ambos",
  comprobar = FALSE,
  typst = "typst",
  output = file.path(cva_root, "cva", "pdf"),
  root = cva_root
) {
  cva_dependencies()
  languages <- if (identical(idioma, "ambos")) c("es", "en") else idioma
  if (!all(languages %in% c("es", "en"))) {
    cva_error("Idioma no válido.")
  }
  # prepare every requested language before starting any PDF compilation
  tables <- cva_read_excel(excel)
  render_date <- cva_today()
  documents <- setNames(
    lapply(languages, function(lang) {
      cva_prepare(tables, lang, root, render_date)
    }),
    languages
  )
  # data-only checks stop here and do not require a Typst installation
  if (comprobar) {
    return(lapply(documents, function(d) {
      list(
        resumen_caracteres = nchar(d$resumen),
        publicaciones = length(d$publicaciones_detalle),
        congresos = length(d$congresos_detalle),
        proyectos = length(d$proyectos_detalle)
      )
    }))
  }
  # keep all intermediate JSON, artwork, logs and PDFs in a disposable directory
  executable <- cva_find_typst(typst)
  temporary <- tempfile("cva-")
  dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
  cva_stage_inputs(root, temporary)
  # validate each compiled PDF before copying any requested language to the
  # output
  results <- list()
  for (lang in languages) {
    pdf <- cva_compile_pdf(
      documents[[lang]],
      lang,
      executable,
      temporary
    )
    results[[lang]] <- cva_check_pdf(
      pdf,
      code_fragments = documents[[lang]]$codigo_declarado
    )
  }
  # publish only the finished, validated PDFs and report their size and page
  # count
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  pdfs <- list.files(temporary, pattern = "\\.pdf$", full.names = TRUE)
  if (!all(file.copy(pdfs, output, overwrite = TRUE))) {
    cva_error("No se han podido guardar todos los PDF.")
  }
  for (lang in languages) {
    message(
      lang,
      ": ",
      results[[lang]]$paginas,
      " páginas; ",
      results[[lang]]$bytes,
      " bytes"
    )
  }
  invisible(results)
}

# translate command-line arguments into the public generar_cva() interface
cva_main <- function(args = commandArgs(TRUE)) {
  opts <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (key == "--check") {
      opts$comprobar <- TRUE
    } else {
      name <- switch(
        key,
        "--excel" = "excel",
        "--idioma" = "idioma",
        "--typst" = "typst",
        "--output" = "output",
        NULL
      )
      if (is.null(name) || i == length(args)) {
        cva_error("Opción no válida o sin valor: ", key)
      }
      i <- i + 1L
      opts[[name]] <- args[[i]]
    }
    i <- i + 1L
  }
  result <- do.call(generar_cva, opts)
  if (isTRUE(opts$comprobar)) {
    print(result)
  }
  invisible(result)
}

# run the CLI only when this file is executed directly, not when sourced
if (sys.nframe() == 0L) {
  tryCatch(cva_main(), error = function(e) {
    message("Error: ", conditionMessage(e))
    quit(status = 1L)
  })
}
