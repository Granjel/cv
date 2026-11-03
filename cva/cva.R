# shared Excel data -> validated JSON -> Typst -> CVA PDFs
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
  Perfil = list(
    headers = c(
      "campo",
      "valor",
      "es",
      "en"
    )
  ),
  Experiencia = list(
    headers = c(
      "id",
      "incluir_cva",
      "inicio",
      "fin",
      "puesto_es",
      "puesto_en",
      "institucion",
      "pais_es",
      "pais_en",
      "motivo_es",
      "motivo_en",
      "meses_interrupcion"
    )
  ),
  Formacion = list(
    headers = c(
      "id",
      "incluir_cva",
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
      "id",
      "incluir_cva",
      "fecha",
      "tipo",
      "autores",
      "posicion_autor",
      "correspondencia",
      "titulo",
      "revista_editorial",
      "volumen",
      "paginas",
      "doi",
      "isbn",
      "contribucion_es",
      "contribucion_en"
    )
  ),
  Congresos = list(
    headers = c(
      "id",
      "incluir_cva",
      "fecha",
      "titulo",
      "autores",
      "modalidad_es",
      "modalidad_en",
      "congreso",
      "lugar"
    )
  ),
  Proyectos = list(
    headers = c(
      "id",
      "incluir_cva",
      "inicio",
      "fin",
      "referencia",
      "titulo",
      "financiador",
      "convocatoria",
      "ip",
      "institucion_ip",
      "importe",
      "moneda",
      "rol_es",
      "rol_en",
      "estado_es",
      "estado_en",
      "contribucion_es",
      "contribucion_en"
    )
  ),
  Transferencia = list(
    headers = c(
      "id",
      "incluir_cva",
      "fecha",
      "fin",
      "tipo",
      "autores",
      "referencia",
      "titulo",
      "entidad",
      "ip",
      "institucion_ip",
      "importe",
      "moneda",
      "paises_prioridad",
      "titular",
      "explotacion_es",
      "explotacion_en",
      "empresas",
      "descripcion_es",
      "descripcion_en"
    )
  ),
  Textos = list(
    headers = c(
      "clave",
      "es",
      "en"
    )
  )
)
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
  "puesto",
  "fecha_inicio",
  "institucion",
  "departamento",
  "pais",
  "telefono",
  "palabras_clave",
  "datos_de_ejemplo"
)

cva_error <- function(...) stop(..., call. = FALSE)
cva_dependencies <- function() {
  needed <- c("readxl", "jsonlite", "xml2", "pdftools")
  missing <- needed[
    !vapply(needed, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    cva_error("Instala los paquetes de R: ", paste(missing, collapse = ", "))
  }
}
cva_text <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[[1]])) {
    return("")
  }
  if (inherits(x, c("POSIXt", "Date"))) {
    return(format(x, "%Y-%m-%d", tz = "UTC"))
  }
  value <- trimws(as.character(x[[1]]))
  # ISO date cells produced by some XLSX writers are returned as text by readxl
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00(\\.0+)?Z$", value)) {
    return(substr(value, 1, 10))
  }
  value
}
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
cva_required <- function(row, key, context = row$context) {
  value <- cva_text(row[[key]])
  if (!nzchar(value)) {
    cva_error(context, ": falta ", key, ".")
  }
  value
}
cva_localized <- function(row, key, lang, mandatory = FALSE) {
  value <- cva_text(row[[paste0(key, "_", lang)]])
  other <- cva_text(row[[paste0(key, "_", if (lang == "es") "en" else "es")]])
  if (!nzchar(value) && (mandatory || nzchar(other))) {
    cva_error(row$context, ": falta la traducción ", key, "_", lang, ".")
  }
  value
}
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
  full <- paste0(
    value,
    switch(as.character(nchar(value)), "4" = "-01-01", "7" = "-01", "")
  )
  parsed <- suppressWarnings(as.Date(full, format = "%Y-%m-%d"))
  if (is.na(parsed) || format(parsed, "%Y-%m-%d") != full) {
    cva_error(context, ": fecha no válida: ", value)
  }
  value
}
cva_date_bounds <- function(value) {
  start <- as.Date(paste0(
    value,
    switch(as.character(nchar(value)), "4" = "-01-01", "7" = "-01", "")
  ))
  end <- if (nchar(value) == 4L) {
    as.Date(sprintf("%04d-01-01", as.integer(value) + 1L)) - 1
  } else if (nchar(value) == 7L) {
    seq(start, by = "month", length.out = 2L)[[2]] - 1
  } else {
    start
  }
  list(start = start, end = end)
}
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

cva_read_excel <- function(filename, root = cva_root) {
  cva_dependencies()
  schema <- cva_schema
  # Reject formulas rather than trusting potentially stale cached values.
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
    missing <- setdiff(unlist(schema[[name]]$headers), headers)
    if (length(missing)) {
      cva_error(name, ": faltan columnas ", paste(missing, collapse = ", "))
    }
    rows <- list()
    seen <- character()
    key <- if (name == "Perfil") {
      "campo"
    } else if (name == "Textos") {
      "clave"
    } else {
      "id"
    }
    for (i in seq_len(nrow(frame))) {
      row <- lapply(frame, function(col) col[[i]])
      if (
        !any(vapply(
          row[unlist(schema[[name]]$headers)],
          function(x) nzchar(cva_text(x)),
          logical(1)
        ))
      ) {
        next
      }
      row$context <- paste0(name, ", fila ", i + 1L)
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

cva_selected <- function(tables, name) {
  rows <- Filter(function(r) cva_bool(r$incluir_cva, r$context), tables[[name]])
  if (
    name %in%
      c("Publicaciones", "Congresos", "Proyectos", "Transferencia") &&
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
cva_author_position <- function(row) {
  names <- trimws(strsplit(cva_required(row, "autores"), ";", fixed = TRUE)[[
    1
  ]])
  names <- names[nzchar(names)]
  total <- if (nzchar(cva_text(row$numero_autores))) {
    cva_number(
      row$numero_autores,
      paste0(row$context, ": numero_autores"),
      TRUE
    )
  } else {
    length(names)
  }
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
  if (length(names) != total) {
    cva_error(
      row$context,
      ": la lista completa de autores no coincide con numero_autores."
    )
  }
  list(position = position, total = total)
}
cva_authors <- function(
  row,
  short = FALSE,
  include_position = TRUE,
  keep_applicant = FALSE
) {
  names <- trimws(strsplit(cva_required(row, "autores"), ";", fixed = TRUE)[[
    1
  ]])
  names <- names[nzchar(names)]
  display <- if (short) vapply(names, cva_short_author, character(1)) else names
  if (length(names) <= 8L) {
    return(paste(display, collapse = "; "))
  }
  leading <- if (nzchar(cva_text(row$autores_iniciales))) {
    cva_number(
      row$autores_iniciales,
      paste0(row$context, ": autores_iniciales"),
      integer = TRUE
    )
  } else {
    3L
  }
  if (leading < 1L || leading > length(names)) {
    cva_error(
      row$context,
      ": autores_iniciales está fuera de la lista de autores."
    )
  }
  position <- cva_number(
    row$posicion_autor,
    paste0(row$context, ": posicion_autor"),
    integer = TRUE
  )
  if (position < 1L || position > length(names)) {
    cva_error(
      row$context,
      ": posicion_autor está fuera de la lista de autores."
    )
  }
  corresponding <- cva_required(row, "correspondencia")
  if (
    !all(trimws(strsplit(corresponding, ";", fixed = TRUE)[[1]]) %in% names)
  ) {
    cva_error(row$context, ": autor de correspondencia ausente de autores.")
  }
  corresponding_indices <- match(
    trimws(strsplit(corresponding, ";", fixed = TRUE)[[1]]),
    names
  )
  indices <- sort(unique(c(
    seq_len(leading),
    if (keep_applicant) position,
    corresponding_indices,
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
  paste0(
    paste(shown, collapse = "; "),
    if (include_position) {
      paste0(". (", position, "/", length(names), ")")
    } else {
      ""
    }
  )
}

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

cva_author_key <- function(value) tolower(gsub("[[:space:],.]+", "", value))
cva_citation_segments <- function(
  parts,
  own_authors,
  venue_index,
  separators = NULL,
  keep_together = integer(),
  inline_code = ""
) {
  # treat titles as literal data
  # format initials and style applicant and venue
  own_authors <- vapply(own_authors, cva_short_author, character(1))
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
        add(author, if (author %in% own_authors) "author" else "plain")
      }
    } else if (index == 2L && nzchar(inline_code)) {
      position <- regexpr(inline_code, value, fixed = TRUE)[[1]]
      add(substr(value, 1L, position - 1L))
      add(inline_code, "code")
      add(substring(value, position + nchar(inline_code)))
    } else {
      add(value, if (index %in% keep_together) "nowrap" else "plain")
    }
    previous <- if (index == 1L) author else value
  }
  segments
}
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
cva_conference_place <- function(value) {
  parts <- trimws(strsplit(value, ",", fixed = TRUE)[[1]])
  if (length(parts) < 2L) {
    return(value)
  }
  paste0(paste(head(parts, -1L), collapse = ", "), " (", tail(parts, 1L), ")")
}

cva_period_date <- function(value) {
  if (nchar(value) >= 7L) {
    paste0(substr(value, 6, 7), "/", substr(value, 1, 4))
  } else {
    value
  }
}
cva_keywords <- function(value) {
  terms <- trimws(strsplit(value, ";", fixed = TRUE)[[1]])
  terms <- terms[nzchar(terms)]
  paste(
    paste0(toupper(substr(terms, 1, 1)), substring(terms, 2)),
    collapse = "; "
  )
}
cva_duration <- function(start, end = "", as_of, lang, override = NULL) {
  # durations are evaluated at the CV date, making a saved CV reproducible
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
  # Month-only dates describe covered calendar months. For an ongoing role,
  # exclude the still-incomplete current month.
  months <- month_index(finish) - month_index(start) + if (ongoing) 0L else 1L
  quantity(max(0L, months))
}

cva_prepare <- function(
  tables,
  lang,
  demo = FALSE,
  draft = FALSE,
  root = cva_root
) {
  profile_rows <- setNames(
    tables$Perfil,
    vapply(tables$Perfil, `[[`, character(1), "campo")
  )
  if (is.null(profile_rows$datos_de_ejemplo)) {
    cva_error("Perfil: falta datos_de_ejemplo.")
  }
  example <- cva_bool(
    profile_rows$datos_de_ejemplo$valor,
    "Perfil: datos_de_ejemplo"
  )
  if (example && !demo) {
    cva_error("El libro contiene ejemplos ficticios. Usa --demo para probarlo.")
  }
  profile <- list()
  missing <- character()
  label <- if (lang == "es") "[Pendiente]" else "[To complete]"
  profile_keys <- cva_profile_keys
  note <- profile_rows$nota_fecha_inicio
  if (
    !is.null(note) &&
      any(vapply(
        c("valor", "es", "en"),
        function(key) nzchar(cva_text(note[[key]])),
        logical(1)
      ))
  ) {
    profile_keys <- c(profile_keys, "nota_fecha_inicio")
  }
  for (key in profile_keys) {
    if (key == "datos_de_ejemplo") {
      next
    }
    row <- profile_rows[[key]]
    if (is.null(row)) {
      cva_error("Perfil: falta el campo ", key)
    }
    common <- cva_text(row$valor)
    if (
      nzchar(common) && (nzchar(cva_text(row$es)) || nzchar(cva_text(row$en)))
    ) {
      cva_error("Perfil: ", key, ": usa valor o es/en sin combinarlos.")
    }
    value <- if (nzchar(common)) common else cva_text(row[[lang]])
    if (!nzchar(value) && key != "web") {
      if (!draft) {
        cva_error("Perfil: falta ", key, " para el idioma ", lang)
      }
      missing <- c(missing, key)
      value <- label
    }
    profile[[key]] <- value
  }
  for (key in c("fecha_cva", "fecha_nacimiento", "fecha_inicio")) {
    if (!key %in% missing) {
      profile[[key]] <- cva_date(
        profile[[key]],
        paste0("Perfil: ", key),
        partial = key == "fecha_inicio"
      )
    }
  }
  if (
    !"orcid" %in% missing &&
      !grepl("^[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{3}[0-9X]$", profile$orcid)
  ) {
    cva_error("Perfil: ORCID no válido.")
  }
  profile$palabras_clave <- cva_keywords(profile$palabras_clave)
  texts <- setNames(
    tables$Textos,
    vapply(tables$Textos, `[[`, character(1), "clave")
  )
  summary <- cva_required(texts$resumen, lang, "Textos: resumen")
  if (nchar(summary, type = "chars") > 5000L) {
    cva_error(
      "El resumen ",
      lang,
      " tiene ",
      nchar(summary),
      " caracteres; el máximo es 5000."
    )
  }
  result <- list(
    idioma = lang,
    demo = demo || example,
    borrador = draft,
    campos_pendientes = as.list(missing),
    perfil = profile,
    resumen = summary,
    publicaciones_detalle = list(),
    congresos_detalle = list(),
    proyectos_detalle = list(),
    duracion_actual = if (any(c("fecha_inicio", "fecha_cva") %in% missing)) {
      label
    } else {
      cva_duration(
        profile$fecha_inicio,
        as_of = profile$fecha_cva,
        lang = lang,
        override = profile_rows$duracion_meses$valor
      )
    }
  )
  es <- lang == "es"
  applicant_authors <- c(
    paste(profile$apellidos, profile$nombre, sep = ", "),
    paste(profile$nombre, profile$apellidos)
  )
  for (name in c(
    "Experiencia",
    "Formacion",
    "Publicaciones",
    "Congresos",
    "Proyectos",
    "Transferencia"
  )) {
    entries <- list()
    for (row in cva_selected(tables, name)) {
      req <- function(k) cva_required(row, k)
      loc <- function(k, mandatory = FALSE) {
        cva_localized(row, k, lang, mandatory)
      }
      current <- if (es) "actualidad" else "present"
      if (name == "Experiencia") {
        kind <- cva_text(row$tipo)
        if (!nzchar(kind)) {
          kind <- "puesto"
        }
        if (!kind %in% c("puesto", "interrupcion")) {
          cva_error(row$context, ": tipo de experiencia desconocido.")
        }
        is_interruption <- kind == "interrupcion"
        position <- loc("puesto", TRUE)
        institution <- if (is_interruption) "" else req("institucion")
        country <- if (is_interruption) "" else loc("pais", TRUE)
        reason <- loc("motivo", is_interruption)
        duration_override <- if (is_interruption) {
          cva_number(
            req("meses_interrupcion"),
            paste0(row$context, ": meses_interrupcion")
          )
        } else {
          row$duracion_meses
        }
        if (
          !is_interruption &&
            (nzchar(reason) || nzchar(cva_text(row$meses_interrupcion)))
        ) {
          reason <- paste0(
            loc("motivo", TRUE),
            " (",
            cva_duration(
              row$inicio,
              row$fin,
              profile$fecha_cva,
              lang,
              cva_number(
                row$meses_interrupcion,
                paste0(row$context, ": meses_interrupcion")
              )
            ),
            ")"
          )
        }
        entry <- list(
          tipo = kind,
          periodo = paste(
            cva_period_date(row$inicio),
            if (nzchar(row$fin)) cva_period_date(row$fin) else current,
            sep = " – "
          ),
          duracion = if (
            !is_interruption && !nzchar(row$fin) && "fecha_cva" %in% missing
          ) {
            label
          } else {
            cva_duration(
              row$inicio,
              row$fin,
              profile$fecha_cva,
              lang,
              duration_override
            )
          },
          puesto = position,
          institucion = institution,
          pais = country,
          interrupcion = reason,
          detalle = cva_sentences(c(
            if (is_interruption) {
              position
            } else {
              paste(position, institution, country, sep = " / ")
            },
            reason
          ))
        )
      } else if (name == "Formacion") {
        entry <- list(
          titulo = loc("titulo", TRUE),
          universidad = paste(
            req("universidad"),
            loc("pais", TRUE),
            sep = " / "
          ),
          anio = substr(row$fecha, 1, 4)
        )
      } else if (name == "Publicaciones") {
        author_position <- cva_author_position(row)
        ordered_authors <- trimws(strsplit(req("autores"), ";", fixed = TRUE)[[
          1
        ]])
        ordered_authors <- ordered_authors[nzchar(ordered_authors)]
        own_author <- ordered_authors[[author_position$position]]
        corresponding_authors <- trimws(strsplit(
          cva_text(row$correspondencia),
          ";",
          fixed = TRUE
        )[[1]])
        corresponding_authors <- corresponding_authors[nzchar(
          corresponding_authors
        )]
        if (!all(corresponding_authors %in% ordered_authors)) {
          cva_error(
            row$context,
            ": autor de correspondencia ausente de autores."
          )
        }
        applicant_authors <- unique(c(
          applicant_authors,
          own_author,
          cva_short_author(own_author)
        ))
        kind <- req("tipo")
        if (
          !kind %in% c("articulo", "libro", "capitulo", "datos", "software")
        ) {
          cva_error(row$context, ": tipo de publicación desconocido.")
        }
        citation <- c(
          cva_authors(
            row,
            short = TRUE,
            include_position = FALSE,
            keep_applicant = TRUE
          ),
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
          own_author,
          4L,
          separators = separators
        )
        citation_text <- cva_citation_text(segments)
        authorship <- cva_publication_role(
          author_position$position,
          author_position$total,
          own_author,
          corresponding_authors,
          lang
        )
        contribution <- loc("contribucion")
        entry <- cva_sentences(c(
          citation_text,
          if (nzchar(doi)) paste0("https://doi.org/", doi)
        ))
        entry <- paste(
          entry,
          cva_sentences(c(authorship, contribution)),
          sep = "\n"
        )
        result$publicaciones_detalle[[
          length(result$publicaciones_detalle) + 1L
        ]] <- list(
          tipo = kind,
          posicion = author_position$position,
          total_autores = author_position$total,
          autoria = authorship,
          contribucion = contribution,
          cita = citation_text,
          segmentos = segments,
          doi = doi
        )
      } else if (name == "Congresos") {
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
        mode <- loc("modalidad", TRUE)
        authors <- if (kind == "presentacion") {
          req("autores")
        } else {
          cva_text(row$autores)
        }
        title <- if (kind == "presentacion") {
          req("titulo")
        } else {
          cva_text(row$titulo)
        }
        code <- cva_text(row$titulo_codigo)
        if (nzchar(code) && !grepl(code, title, fixed = TRUE)) {
          cva_error(row$context, ": titulo_codigo no aparece en el título.")
        }
        mode_key <- tolower(mode)
        prefix <- if (mode_key %in% c("poster", "póster")) {
          if (es) "Presentación de póster" else "Poster presentation"
        } else {
          mode
        }
        conference_authors <- trimws(strsplit(authors, ";", fixed = TRUE)[[1]])
        conference_authors <- conference_authors[nzchar(conference_authors)]
        show_authors <- kind == "presentacion" &&
          !(length(conference_authors) == 1L &&
            grepl(
              "^(invited|seminario invitado|conferencia invitada)",
              mode_key
            ))
        place <- loc("lugar")
        if (!nzchar(place)) {
          place <- req("lugar")
        }
        citation <- c(
          if (show_authors) authors else "",
          title,
          req("congreso"),
          cva_conference_date(row$fecha, lang),
          cva_conference_place(place)
        )
        own_authors <- conference_authors[
          cva_author_key(conference_authors) %in%
            cva_author_key(applicant_authors)
        ]
        segments <- cva_citation_segments(
          citation,
          own_authors,
          3L,
          keep_together = 4:5,
          inline_code = code
        )
        citation_text <- cva_citation_text(segments)
        entry <- cva_sentences(c(prefix, citation_text))
        result$congresos_detalle[[
          length(result$congresos_detalle) + 1L
        ]] <- list(
          tipo = prefix,
          categoria = kind,
          autores_visibles = show_authors,
          cita = citation_text,
          segmentos = segments
        )
      } else if (name == "Proyectos") {
        reference <- cva_text(row$referencia)
        pi_label <- loc("etiqueta_ip")
        if (!nzchar(pi_label)) {
          pi_label <- if (lang == "en") "PI" else "IP"
        }
        pi_names <- trimws(strsplit(req("ip"), ";", fixed = TRUE)[[1]])
        pi_names <- pi_names[nzchar(pi_names)]
        pi_display <- if (length(pi_names) == 1L) {
          pi_names
        } else {
          paste0(
            paste(head(pi_names, -1L), collapse = ", "),
            if (lang == "en") " and " else " y ",
            tail(pi_names, 1L)
          )
        }
        pi_institution <- cva_text(row$institucion_ip)
        host <- cva_text(row$anfitrion)
        amount_type <- cva_text(row$tipo_importe)
        if (!nzchar(amount_type)) {
          amount_type <- "financiacion_total"
        }
        if (
          !amount_type %in% c("financiacion_total", "valor_acceso_estimado")
        ) {
          cva_error(row$context, ": tipo_importe desconocido.")
        }
        amount_label <- if (amount_type == "valor_acceso_estimado") {
          if (lang == "en") {
            "Estimated value of awarded access and analytical services: "
          } else {
            "Valor estimado del acceso y los servicios analíticos concedidos: "
          }
        } else {
          if (lang == "en") "Total funding: " else "Financiación total: "
        }
        amount <- cva_number(row$importe, paste0(row$context, ": importe"))
        participation <- ""
        if (nzchar(cva_text(row$participacion_meses))) {
          months <- cva_number(
            row$participacion_meses,
            paste0(row$context, ": participacion_meses")
          )
          participation <- paste0(
            if (lang == "en") "My participation: " else "Mi participación: ",
            cva_duration("", "", as_of = "", lang = lang, override = months)
          )
        }
        period <- if (identical(row$inicio, row$fin)) {
          cva_period_date(row$inicio)
        } else {
          paste(
            cva_period_date(row$inicio),
            if (nzchar(row$fin)) cva_period_date(row$fin) else current,
            sep = " – "
          )
        }
        entry <- cva_sentences(c(
          req("titulo"),
          if (nzchar(reference)) paste0("Ref. ", reference),
          req("financiador"),
          cva_text(row$convocatoria),
          paste0(
            pi_label,
            ": ",
            pi_display,
            if (nzchar(pi_institution)) {
              paste0(" (", pi_institution, ")")
            } else {
              ""
            }
          ),
          if (nzchar(host)) {
            paste0(if (lang == "en") "Host: " else "Centro de acogida: ", host)
          },
          period,
          paste0(
            amount_label,
            cva_amount(
              row,
              lang,
              digits = if (amount == floor(amount)) 0L else 2L,
              symbols = TRUE
            )
          ),
          paste0(
            if (lang == "en") "My role: " else "Mi papel: ",
            loc("rol", TRUE)
          ),
          participation,
          loc("estado", TRUE),
          loc("contribucion")
        ))
        if (lang == "en") {
          title <- cva_text(row$titulo_cva_en)
          if (!nzchar(title)) {
            title <- req("titulo")
          }
          title <- sub("[.]$", "", title)
          institution <- cva_text(row$institucion_ip_en)
          if (!nzchar(institution)) {
            institution <- pi_institution
          }
          own_lead <- grepl(
            "principal investigator|project lead",
            tolower(loc("rol", TRUE))
          )
          leader <- if (!own_lead) {
            paste0(
              pi_label,
              ": ",
              pi_display,
              if (nzchar(institution)) paste0(" (", institution, ")") else ""
            )
          } else {
            ""
          }
          academic_host <- cva_text(row$investigador_anfitrion)
          host_details <- if (nzchar(host)) {
            paste0(
              "Host: ",
              if (nzchar(academic_host)) {
                paste0(academic_host, " (", host, ")")
              } else {
                host
              }
            )
          } else {
            ""
          }
          facilities <- cva_text(row$infraestructuras)
          compact_period <- gsub(" – ", "–", period, fixed = TRUE)
          if (nzchar(cva_text(row$participacion_meses))) {
            compact_period <- paste0("Participation: ", compact_period)
          }
          programme <- c(cva_text(row$convocatoria), req("financiador"))
          parts <- c(
            if (nzchar(reference)) paste0("Ref. ", reference),
            paste(programme[nzchar(programme)], collapse = ", "),
            leader,
            host_details,
            if (nzchar(facilities)) paste0("Access facilities: ", facilities),
            compact_period,
            paste0(
              amount_label,
              cva_amount(
                row,
                lang,
                digits = if (amount == floor(amount)) 0L else 2L,
                symbols = TRUE
              )
            )
          )
          details <- paste(parts[nzchar(parts)], collapse = "; ")
          role <- cva_text(row$rol_cva_en)
          if (!nzchar(role)) {
            role <- loc("rol", TRUE)
          }
          role <- sub("[.]$", "", role)
          if (nzchar(cva_text(row$participacion_meses))) {
            role <- paste0(
              role,
              ", with ",
              cva_duration(
                "",
                "",
                as_of = "",
                lang = lang,
                override = row$participacion_meses
              ),
              " of participation"
            )
          }
          result$proyectos_detalle[[
            length(result$proyectos_detalle) + 1L
          ]] <- list(
            titulo = paste0(title, "."),
            detalles = details,
            periodo = gsub(" – ", "–", period, fixed = TRUE),
            papel = paste0(role, ".")
          )
          entry <- paste0(title, ". ", details, "; Role: ", role, ".")
        }
      } else {
        kind <- req("tipo")
        if (!kind %in% c("contrato", "patente", "otro")) {
          cva_error(row$context, ": tipo de transferencia desconocido.")
        }
        parts <- c(req("autores"), req("referencia"), req("titulo"), row$fecha)
        if (kind == "patente") {
          parts <- c(
            parts,
            req("paises_prioridad"),
            req("titular"),
            loc("explotacion", TRUE),
            cva_text(row$empresas)
          )
        }
        if (kind == "contrato") {
          parts <- c(
            parts,
            req("entidad"),
            paste0("IP: ", req("ip"), " (", req("institucion_ip"), ")"),
            req("fin"),
            cva_amount(row, lang)
          )
        }
        entry <- cva_sentences(c(parts, loc("descripcion", TRUE)))
      }
      entries[[length(entries) + 1L]] <- entry
    }
    result[[tolower(name)]] <- entries
  }
  result
}

cva_check_pdf <- function(filename) {
  info <- pdftools::pdf_info(filename)
  if (info$pages < 1L || info$pages > 4L) {
    cva_error("El PDF tiene ", info$pages, " páginas; el máximo es 4.")
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
  if (any(!grepl("Arial|Calibri|TimesNewRoman|Times-New-Roman", fonts$name))) {
    cva_error("El PDF contiene una fuente no admitida.")
  }
  boxes <- pdftools::pdf_data(filename, font_info = TRUE)
  for (page in boxes) {
    if (any(page$font_size < 10.99 & nzchar(trimws(page$text)))) {
      cva_error("El PDF contiene texto menor de 11 puntos.")
    }
  }
  list(paginas = info$pages, bytes = bytes)
}

generar_cva <- function(
  excel = file.path(cva_root, "data/datos-cv.xlsx"),
  idioma = "ambos",
  borrador = FALSE,
  comprobar = FALSE,
  ejemplo = FALSE,
  typst = "typst",
  output = file.path(cva_root, "cva", "pdf"),
  root = cva_root
) {
  cva_dependencies()
  languages <- if (identical(idioma, "ambos")) c("es", "en") else idioma
  if (!all(languages %in% c("es", "en"))) {
    cva_error("Idioma no válido.")
  }
  tables <- cva_read_excel(excel, root)
  documents <- setNames(
    lapply(languages, function(lang) {
      cva_prepare(tables, lang, ejemplo, borrador, root)
    }),
    languages
  )
  if (comprobar) {
    return(lapply(documents, function(d) {
      list(
        resumen_caracteres = nchar(d$resumen),
        campos_pendientes = d$campos_pendientes
      )
    }))
  }
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
  if (!"Times New Roman" %in% system2(executable, "fonts", stdout = TRUE)) {
    cva_error("No se encuentra la fuente Times New Roman.")
  }
  temporary <- tempfile("cva-")
  dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
  # Keep all Typst inputs inside its temporary root; retain only the finished PDFs.
  dir.create(file.path(temporary, "assets"))
  logos <- file.path(root, "assets", c("logo-AEI.svg", "logo-MCIU.png"))
  if (
    !all(file.exists(c(file.path(root, "cva", "cva.typ"), logos))) ||
      !file.copy(file.path(root, "cva", "cva.typ"), temporary) ||
      !all(file.copy(logos, file.path(temporary, "assets")))
  ) {
    cva_error("No se han podido preparar la plantilla y los logotipos.")
  }
  results <- list()
  for (lang in languages) {
    json <- file.path(temporary, paste0("cva-", lang, ".json"))
    jsonlite::write_json(
      documents[[lang]],
      json,
      auto_unbox = TRUE,
      pretty = TRUE,
      null = "null"
    )
    pdf <- file.path(
      temporary,
      paste0(
        "cva",
        if (borrador) {
          "-borrador"
        } else if (ejemplo) {
          "-ejemplo"
        } else {
          ""
        },
        "-",
        lang,
        ".pdf"
      )
    )
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
    results[[lang]] <- cva_check_pdf(pdf)
  }
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

cva_main <- function(args = commandArgs(TRUE)) {
  opts <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (key %in% c("--draft", "--check", "--demo")) {
      opts[[switch(
        key,
        "--draft" = "borrador",
        "--check" = "comprobar",
        "--demo" = "ejemplo"
      )]] <- TRUE
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
if (sys.nframe() == 0L) {
  tryCatch(cva_main(), error = function(e) {
    message("Error: ", conditionMessage(e))
    quit(status = 1L)
  })
}
