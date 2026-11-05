# retrieve public publication and activity metadata from the workbook
# save publication affiliations and activity evidence in input/stats.csv
# use Rscript cva/stats.R or source this file and call retrieve_stats()

# resolve the repository from the script when sourced or executed directly
stats_root <- local({
  files <- Filter(
    function(x) is.character(x) && length(x) == 1L,
    lapply(sys.frames(), function(frame) {
      get0("ofile", envir = frame, inherits = FALSE)
    })
  )
  arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  script <- if (length(files)) {
    tail(files, 1L)[[1]]
  } else if (length(arg)) {
    sub("^--file=", "", arg[[1]])
  } else {
    ""
  }
  directory <- if (nzchar(script)) dirname(normalizePath(script)) else getwd()
  candidates <- unique(c(dirname(directory), directory, getwd()))
  found <- Filter(
    function(x) file.exists(file.path(x, "input/datos-cv.xlsx")),
    candidates
  )
  if (!length(found)) {
    stop("Cannot locate input/datos-cv.xlsx", call. = FALSE)
  }
  normalizePath(found[[1]], winslash = "/")
})

# use the same user library and UTF-8 locale as the CVA renderer
if (.Platform$OS.type == "windows") {
  minor <- strsplit(R.version$minor, ".", fixed = TRUE)[[1]][[1]]
  library_path <- file.path(
    Sys.getenv("LOCALAPPDATA"),
    "R",
    "win-library",
    paste(R.version$major, minor, sep = ".")
  )
  if (dir.exists(library_path)) {
    .libPaths(unique(c(.libPaths(), library_path)))
  }
  if (!l10n_info()[["UTF-8"]]) {
    invisible(suppressWarnings(Sys.setlocale(
      "LC_CTYPE",
      "English_United States.utf8"
    )))
  }
}

# preserve missing JSON scalars rather than treating empty objects as names
stats_text <- function(x) {
  if (is.null(x) || !length(x) || is.list(x) || is.na(x[[1]])) {
    return("")
  }
  if (inherits(x, c("POSIXt", "Date"))) {
    return(format(x, "%Y-%m-%d", tz = "UTC"))
  }
  trimws(as.character(x[[1]]))
}
stats_names <- function(x) {
  result <- trimws(strsplit(stats_text(x), ";", fixed = TRUE)[[1]])
  result[nzchar(result)]
}
stats_key <- function(x) {
  x <- iconv(x, to = "ASCII//TRANSLIT", sub = "")
  tolower(gsub("[^a-zA-Z0-9]", "", x))
}
stats_person_name <- function(x) {
  parts <- trimws(strsplit(x, ",", fixed = TRUE)[[1]])
  if (length(parts) == 2L) paste(parts[[2]], parts[[1]]) else x
}
stats_orcid <- function(x) {
  value <- sub("^https?://orcid.org/", "", stats_text(x))
  if (grepl("^[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{3}[0-9X]$", value)) value else ""
}
stats_flag <- function(x) {
  value <- tolower(stats_text(x))
  if (value %in% c("", "true", "si", "sí", "1")) {
    return(TRUE)
  }
  if (value %in% c("false", "no", "0")) {
    return(FALSE)
  }
  stop("Invalid incluir value: ", value, call. = FALSE)
}
stats_time <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
stats_scalar <- function(x, default = NA_real_) {
  value <- stats_text(x)
  if (!nzchar(value)) default else suppressWarnings(as.numeric(value))
}
stats_logical <- function(x) {
  value <- stats_text(x)
  if (!nzchar(value)) NA else tolower(value) == "true"
}

# cache public responses without putting API keys in filenames or source URLs
# fresh data last seven days; negative lookups are retried after one day
stats_get <- function(url, context, query = list()) {
  request <- do.call(httr2::req_url_query, c(list(httr2::request(url)), query))
  public_url <- request$url
  filename <- file.path(
    context$cache,
    paste0(digest::digest(public_url, algo = "sha256"), ".json")
  )
  old <- if (file.exists(filename)) {
    tryCatch(
      jsonlite::read_json(filename, simplifyVector = FALSE),
      error = function(e) NULL
    )
  } else {
    NULL
  }
  if (!is.null(old)) {
    age <- as.numeric(difftime(
      Sys.time(),
      as.POSIXct(old$retrieved_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      units = "days"
    ))
    lifetime <- if (old$status == 200L) 7 else 1
    if (
      context$offline || (!context$refresh && !is.na(age) && age < lifetime)
    ) {
      return(old)
    }
  }
  if (context$offline) {
    stop("No cached response for ", public_url, call. = FALSE)
  }
  key <- Sys.getenv("OPENALEX_API_KEY")
  if (startsWith(url, "https://api.openalex.org/") && nzchar(key)) {
    request <- httr2::req_headers(request, Authorization = paste("Bearer", key))
  }
  request <- request |>
    httr2::req_user_agent("cv-publication-stats/1.0") |>
    httr2::req_timeout(45) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_error(is_error = function(resp) FALSE)
  Sys.sleep(0.15)
  response <- tryCatch(httr2::req_perform(request), error = function(e) NULL)
  if (is.null(response) || !httr2::resp_status(response) %in% c(200L, 404L)) {
    if (!is.null(old)) {
      warning("Using older cached metadata for ", public_url, call. = FALSE)
      return(old)
    }
    context$failures <- unique(c(context$failures, public_url))
    warning("Metadata request failed: ", public_url, call. = FALSE)
    return(list(
      status = 599L,
      data = NULL,
      url = public_url,
      retrieved_at = NA_character_
    ))
  }
  status <- httr2::resp_status(response)
  data <- if (status == 200L) {
    httr2::resp_body_json(response, simplifyVector = FALSE)
  } else {
    NULL
  }
  result <- list(
    status = status,
    data = data,
    url = public_url,
    retrieved_at = stats_time()
  )
  temporary <- tempfile(tmpdir = context$cache)
  on.exit(unlink(temporary), add = TRUE)
  jsonlite::write_json(
    result,
    temporary,
    auto_unbox = TRUE,
    digits = NA,
    null = "null",
    na = "null"
  )
  if (!file.copy(temporary, filename, overwrite = TRUE)) {
    stop("Cannot save metadata cache", call. = FALSE)
  }
  result
}

# keep workbook authorship authoritative for role counts
# retain all publication rows
# the CVA inclusion flag is retained but does not filter career statistics
stats_read <- function(workbook) {
  frame <- readxl::read_excel(
    workbook,
    sheet = "Publicaciones",
    col_types = "list"
  )
  required <- c(
    "incluir",
    "fecha",
    "tipo",
    "titulo",
    "autores",
    "posicion_autor",
    "correspondencia",
    "revista_editorial",
    "doi"
  )
  if (!all(required %in% names(frame)) || anyDuplicated(names(frame))) {
    stop("Invalid Publicaciones headers", call. = FALSE)
  }
  profile <- readxl::read_excel(workbook, sheet = "Perfil", col_types = "list")
  value <- function(field) {
    index <- which(vapply(profile$campo, stats_text, character(1)) == field)
    if (length(index) != 1L) {
      stop("Missing Perfil field: ", field, call. = FALSE)
    }
    stats_text(profile$valor[[index]])
  }
  aliases <- unique(c(
    stats_names(value("alias_autoria")),
    paste(value("nombre"), value("apellidos"))
  ))
  publications <- lapply(seq_len(nrow(frame)), function(i) {
    row <- lapply(frame, function(column) column[[i]])
    title <- stats_text(row$titulo)
    if (!nzchar(title)) {
      stop("Empty publication title in row ", i + 1L, call. = FALSE)
    }
    authors <- stats_names(row$autores)
    position <- stats_scalar(row$posicion_autor)
    if (
      is.na(position) ||
        position != floor(position) ||
        position < 1 ||
        position > length(authors)
    ) {
      stop("Invalid author position in row ", i + 1L, call. = FALSE)
    }
    doi <- sub(
      "^(https?://(dx[.])?doi[.]org/|doi:[[:space:]]*)",
      "",
      stats_text(row$doi),
      ignore.case = TRUE
    )
    if (nzchar(doi) && !grepl("^10[.][0-9]{4,9}/[^[:space:]]+$", doi)) {
      stop("Invalid DOI in row ", i + 1L, call. = FALSE)
    }
    year <- as.integer(substr(stats_text(row$fecha), 1L, 4L))
    if (is.na(year)) {
      stop("Invalid publication year in row ", i + 1L, call. = FALSE)
    }
    own <- authors[[position]]
    list(
      paper_id = if (nzchar(doi)) {
        paste0("doi:", tolower(doi))
      } else {
        paste0("local:", digest::digest(paste(year, title), algo = "sha256"))
      },
      doi = doi,
      title = title,
      year = year,
      publication_type = stats_text(row$tipo),
      journal = stats_text(row$revista_editorial),
      cva_selected = stats_flag(row$incluir),
      first_author = position == 1L,
      corresponding_author = stats_key(own) %in%
        stats_key(stats_names(row$correspondencia)),
      author_position = position,
      author_count = length(authors),
      authors = authors,
      aliases = unique(c(aliases, own)),
      own_orcid = stats_orcid(value("orcid"))
    )
  })
  ids <- vapply(publications, `[[`, character(1), "paper_id")
  if (anyDuplicated(ids)) {
    stop("Duplicate publication DOI or title/year", call. = FALSE)
  }
  publications
}

# use exact DOI lookups and fetch full works individually
# avoid author-list truncation in search responses
# records without a DOI need an exact normalised title and year match
stats_work <- function(paper, context) {
  failures_before <- length(context$failures)
  doi <- paper$doi
  oa <- NULL
  cr <- NULL
  if (nzchar(doi)) {
    oa <- stats_get(
      paste0(
        "https://api.openalex.org/works/doi:",
        utils::URLencode(doi, reserved = TRUE)
      ),
      context
    )
    cr <- stats_get(
      paste0(
        "https://api.crossref.org/works/",
        utils::URLencode(doi, reserved = TRUE)
      ),
      context
    )
  } else {
    search <- stats_get(
      "https://api.openalex.org/works",
      context,
      list(
        search = paper$title,
        per_page = 5,
        select = "id,display_name,publication_year"
      )
    )
    matches <- Filter(
      function(x) {
        stats_key(stats_text(x$display_name)) == stats_key(paper$title) &&
          identical(stats_scalar(x$publication_year), as.numeric(paper$year))
      },
      search$data$results
    )
    if (length(matches) == 1L) {
      oa <- stats_get(
        sub(
          "https://openalex.org/",
          "https://api.openalex.org/works/",
          matches[[1]]$id
        ),
        context
      )
    }
    if (is.null(oa) || oa$status != 200L) {
      search <- stats_get(
        "https://api.crossref.org/works",
        context,
        list(
          "query.title" = paper$title,
          rows = 5,
          filter = paste0(
            "from-pub-date:",
            paper$year,
            "-01-01,until-pub-date:",
            paper$year,
            "-12-31"
          )
        )
      )
      matches <- Filter(
        function(x) {
          stats_key(stats_text(x$title[[1]])) == stats_key(paper$title)
        },
        search$data$message$items
      )
      if (length(matches) == 1L) {
        doi <- stats_text(matches[[1]]$DOI)
        cr <- stats_get(
          paste0(
            "https://api.crossref.org/works/",
            utils::URLencode(doi, reserved = TRUE)
          ),
          context
        )
        oa <- stats_get(
          paste0(
            "https://api.openalex.org/works/doi:",
            utils::URLencode(doi, reserved = TRUE)
          ),
          context
        )
      }
    }
  }
  if (!is.null(oa) && oa$status == 200L) {
    list(
      source = "openalex",
      response = oa,
      work = oa$data,
      crossref = if (!is.null(cr) && cr$status == 200L) cr else NULL
    )
  } else if (!is.null(cr) && cr$status == 200L) {
    list(
      source = "crossref",
      response = cr,
      work = cr$data$message,
      crossref = cr
    )
  } else {
    failed <- length(context$failures) > failures_before
    list(
      source = "workbook",
      response = NULL,
      work = NULL,
      crossref = NULL,
      status = if (failed) {
        "lookup_failed"
      } else if (nzchar(paper$doi)) {
        "unindexed"
      } else {
        "no_doi_match"
      }
    )
  }
}

# distinguish numeric aggregate labels from named people
# apply the same rule to every paper
stats_aggregate <- function(name, id, orcid) {
  !nzchar(id) &&
    !nzchar(orcid) &&
    grepl(
      "^[[:space:]]*[0-9]+[[:space:]]+(additional|other|more)[[:space:]]+(co[ -]?)?authors?[[:space:]]*$",
      name,
      ignore.case = TRUE
    )
}

# match an applicant or fallback author only by ORCID or a unique complete name
# never apply the workbook position to a differently ordered online author list
stats_match <- function(name, orcid, authors) {
  if (!length(authors)) {
    return(integer())
  }
  if (nzchar(orcid)) {
    matches <- which(vapply(
      authors,
      function(x) identical(x$orcid, orcid),
      logical(1)
    ))
    if (length(matches) == 1L) return(matches)
  }
  key <- stats_key(stats_person_name(name))
  matches <- which(vapply(
    authors,
    function(x) stats_key(x$name) == key,
    logical(1)
  ))
  if (length(matches) == 1L) matches else integer()
}

# decode authors without losing missing identities or raw affiliation strings
stats_authors <- function(paper, source) {
  if (source$source == "openalex") {
    return(lapply(source$work$authorships, function(x) {
      name <- stats_text(x$raw_author_name)
      if (!nzchar(name)) {
        name <- stats_text(x$author$display_name)
      }
      list(
        name = name,
        id = stats_text(x$author$id),
        orcid = stats_orcid(x$author$orcid),
        institutions = x$institutions,
        countries = unlist(x$countries, use.names = FALSE),
        raw = paste(
          unlist(x$raw_affiliation_strings, use.names = FALSE),
          collapse = " | "
        ),
        crossref_affiliations = list()
      )
    }))
  }
  if (source$source == "crossref") {
    return(lapply(source$work$author, function(x) {
      list(
        name = trimws(paste(stats_text(x$given), stats_text(x$family))),
        id = "",
        orcid = stats_orcid(x$ORCID),
        institutions = list(),
        countries = character(),
        raw = "",
        crossref_affiliations = x$affiliation
      )
    }))
  }
  lapply(paper$authors, function(x) {
    list(
      name = stats_person_name(x),
      id = "",
      orcid = "",
      institutions = list(),
      countries = character(),
      raw = "",
      crossref_affiliations = list()
    )
  })
}

# resolve a missing affiliation using ROR's chosen match only
# keep unrecognised strings as unknown rather than choosing a weak candidate
stats_ror <- function(affiliation, context) {
  raw <- stats_text(affiliation$name)
  if (!nzchar(raw)) {
    return(list(raw = raw))
  }
  response <- stats_get(
    "https://api.ror.org/v2/organizations",
    context,
    list(affiliation = raw)
  )
  chosen <- Filter(function(x) isTRUE(x$chosen), response$data$items)
  if (length(chosen) != 1L) {
    return(list(raw = raw))
  }
  org <- chosen[[1]]$organization
  names <- Filter(function(x) "ror_display" %in% unlist(x$types), org$names)
  name <- if (length(names)) {
    stats_text(names[[1]]$value)
  } else {
    stats_text(org$names[[1]]$value)
  }
  location <- if (length(org$locations)) {
    org$locations[[1]]$geonames_details
  } else {
    NULL
  }
  list(
    raw = raw,
    ror_id = stats_text(org$id),
    institution_name = name,
    institution_type = paste(unlist(org$types), collapse = "; "),
    country_code = stats_text(location$country_code),
    country = stats_text(location$country_name),
    city = stats_text(location$name),
    latitude = stats_scalar(location$lat),
    longitude = stats_scalar(location$lng),
    institution_retrieved_at = response$retrieved_at
  )
}

# retain author-level provenance and one row per known affiliation
stats_rows <- function(paper, source, context) {
  authors <- stats_authors(paper, source)
  author_source <- source$source
  if (!length(authors) && !is.null(source$crossref)) {
    authors <- stats_authors(
      paper,
      list(source = "crossref", work = source$crossref$data$message)
    )
    author_source <- "crossref"
  }
  if (!length(authors)) {
    authors <- stats_authors(paper, list(source = "workbook"))
    author_source <- "workbook"
  }
  aggregate <- vapply(
    authors,
    function(x) stats_aggregate(x$name, x$id, x$orcid),
    logical(1)
  )
  own <- which(
    vapply(
      authors,
      function(x) nzchar(paper$own_orcid) && x$orcid == paper$own_orcid,
      logical(1)
    ) &
      !aggregate
  )
  method <- "orcid"
  if (!length(own)) {
    keys <- stats_key(vapply(paper$aliases, stats_person_name, character(1)))
    own <- which(
      vapply(authors, function(x) stats_key(x$name) %in% keys, logical(1)) &
        !aggregate
    )
    method <- "name"
  }
  if (author_source == "workbook") {
    own <- paper$author_position
    method <- "workbook_position"
  } else if (length(own) != 1L) {
    own <- integer()
    method <- "none"
  }
  extra <- if (!is.null(source$crossref)) {
    stats_authors(
      paper,
      list(source = "crossref", work = source$crossref$data$message)
    )
  } else {
    list()
  }
  person_index <- cumsum(!aggregate)
  base <- paper[setdiff(names(paper), c("authors", "aliases", "own_orcid"))]
  base$metadata_author_count <- if (author_source == "workbook") {
    NA_integer_
  } else {
    sum(!aggregate)
  }
  base$metadata_authorship_count <- if (author_source == "workbook") {
    NA_integer_
  } else {
    length(authors)
  }
  base$aggregate_records <- sum(aggregate)
  base$metadata_author_count_matches <- if (author_source == "workbook") {
    NA
  } else {
    sum(!aggregate) == paper$author_count
  }
  base$metadata_source <- source$source
  base$author_source <- author_source
  base$metadata_url <- if (is.null(source$response)) {
    NA_character_
  } else {
    source$response$url
  }
  base$metadata_status <- if (source$source == "workbook") {
    source$status
  } else {
    "matched"
  }
  base$metadata_retrieved_at <- if (is.null(source$response)) {
    NA_character_
  } else {
    source$response$retrieved_at
  }
  base$citation_count <- if (source$source == "openalex") {
    stats_scalar(source$work$cited_by_count)
  } else {
    NA_real_
  }
  base$is_open_access <- if (source$source == "openalex") {
    stats_logical(source$work$open_access$is_oa)
  } else {
    NA
  }
  base$oa_status <- if (source$source == "openalex") {
    stats_text(source$work$open_access$oa_status)
  } else {
    NA_character_
  }
  result <- list()
  for (i in seq_along(authors)) {
    author <- authors[[i]]
    if (i %in% own && !nzchar(author$orcid)) {
      author$orcid <- paper$own_orcid
    }
    record <- c(
      base,
      list(
        author_index = if (aggregate[[i]]) NA_integer_ else person_index[[i]],
        source_author_index = i,
        author_record_type = if (aggregate[[i]]) "aggregate" else "person",
        author_id = author$id,
        author_orcid = author$orcid,
        author_name = author$name,
        is_self = i %in% own,
        self_match_method = if (i %in% own) method else "",
        author_identity_status = if (
          nzchar(author$id) || nzchar(author$orcid)
        ) {
          "resolved"
        } else {
          "unresolved"
        },
        coauthor_key = paste0(paper$paper_id, ":author:", i),
        institution_id = "",
        ror_id = "",
        institution_name = "",
        institution_type = "",
        country_code = "",
        country = "",
        city = "",
        latitude = NA_real_,
        longitude = NA_real_,
        raw_affiliation = author$raw,
        affiliation_status = "unresolved",
        affiliation_source = source$source,
        institution_retrieved_at = NA_character_
      )
    )
    add <- function(fields) {
      item <- record
      for (key in names(fields)) {
        item[[key]] <- fields[[key]]
      }
      result[[length(result) + 1L]] <<- as.data.frame(
        item,
        stringsAsFactors = FALSE
      )
    }
    if (aggregate[[i]]) {
      add(list(affiliation_status = "aggregate"))
      next
    }
    covered <- character()
    if (length(author$institutions)) {
      for (institution in author$institutions) {
        country <- stats_text(institution$country_code)
        covered <- c(covered, country)
        add(list(
          institution_id = stats_text(institution$id),
          ror_id = stats_text(institution$ror),
          institution_name = stats_text(institution$display_name),
          institution_type = stats_text(institution$type),
          country_code = country,
          affiliation_status = "institution_resolved"
        ))
      }
    } else {
      affiliations <- author$crossref_affiliations
      if (!length(affiliations) && length(extra)) {
        matched <- stats_match(author$name, author$orcid, extra)
        if (length(matched)) {
          affiliations <- extra[[matched]]$crossref_affiliations
        }
      }
      for (affiliation in affiliations) {
        institution <- stats_ror(affiliation, context)
        country <- stats_text(institution$country_code)
        covered <- c(covered, country)
        institution$raw_affiliation <- institution$raw
        institution$raw <- NULL
        institution$affiliation_source <- "crossref_ror"
        institution$affiliation_status <- if (
          nzchar(stats_text(institution$ror_id))
        ) {
          "institution_resolved"
        } else {
          "unresolved"
        }
        add(institution)
      }
    }
    countries <- setdiff(author$countries, covered)
    for (country in countries[nzchar(countries)]) {
      add(list(country_code = country, affiliation_status = "country_only"))
    }
    if (
      !length(author$institutions) && !length(covered) && !length(countries)
    ) {
      add(list())
    }
  }
  do.call(rbind, result)
}

# enrich unique institution IDs in batches instead of requesting each row
stats_institutions <- function(data, context) {
  ids <- unique(data$institution_id[nzchar(data$institution_id)])
  if (length(ids)) {
    batches <- split(ids, ceiling(seq_along(ids) / 50L))
    for (batch in batches) {
      response <- stats_get(
        "https://api.openalex.org/institutions",
        context,
        list(
          filter = paste0(
            "ids.openalex:",
            paste(sub("https://openalex.org/", "", batch), collapse = "|")
          ),
          per_page = 100,
          select = "id,display_name,ror,geo"
        )
      )
      for (institution in response$data$results) {
        index <- which(data$institution_id == stats_text(institution$id))
        geo <- institution$geo
        same_country <- !nzchar(data$country_code[index]) |
          data$country_code[index] == stats_text(geo$country_code)
        fill <- index[same_country]
        data$country_code[fill] <- stats_text(geo$country_code)
        data$country[fill] <- stats_text(geo$country)
        data$city[fill] <- stats_text(geo$city)
        data$latitude[fill] <- stats_scalar(geo$latitude)
        data$longitude[fill] <- stats_scalar(geo$longitude)
        data$institution_retrieved_at[index] <- response$retrieved_at
      }
    }
  }
  missing <- !nzchar(data$country) & nzchar(data$country_code)
  data$country[missing] <- countrycode::countrycode(
    data$country_code[missing],
    "iso2c",
    "country.name",
    warn = FALSE
  )
  data
}

# consolidate known identities while keeping unresolved names separate
# an identifier with conflicting ORCIDs is not silently treated as one person
stats_identities <- function(data) {
  mapping <- unique(data[
    nzchar(data$author_id) & nzchar(data$author_orcid),
    c("author_id", "author_orcid")
  ])
  for (id in unique(data$author_id[nzchar(data$author_id)])) {
    index <- which(data$author_id == id)
    orcids <- unique(mapping$author_orcid[mapping$author_id == id])
    if (length(orcids) > 1L) {
      data$author_identity_status[index] <- "conflicting"
    } else {
      data$coauthor_key[index] <- if (length(orcids)) {
        paste0("orcid:", orcids)
      } else {
        id
      }
    }
  }
  orcid_only <- !nzchar(data$author_id) & nzchar(data$author_orcid)
  data$coauthor_key[orcid_only] <- paste0(
    "orcid:",
    data$author_orcid[orcid_only]
  )
  data
}

# recognise country names in recorded locations without inferring nationality
stats_activity_countries <- function(value) {
  value <- stats_text(value)
  if (!nzchar(value)) {
    return(character())
  }
  codes <- countrycode::codelist$iso2c
  if (toupper(value) %in% codes) {
    return(toupper(value))
  }
  dictionary <- countrycode::codelist
  english <- vapply(
    dictionary$country.name.en.regex,
    function(pattern) {
      !is.na(pattern) &&
        nzchar(pattern) &&
        grepl(pattern, value, ignore.case = TRUE, perl = TRUE)
    },
    logical(1)
  )
  normal <- tolower(iconv(value, to = "ASCII//TRANSLIT", sub = ""))
  normal <- paste0(" ", gsub("[^a-z0-9]+", " ", normal), " ")
  spanish <- vapply(
    dictionary$cldr.name.es,
    function(name) {
      if (is.na(name) || !nzchar(name)) {
        return(FALSE)
      }
      name <- tolower(iconv(name, to = "ASCII//TRANSLIT", sub = ""))
      name <- paste0(" ", gsub("[^a-z0-9]+", " ", name), " ")
      grepl(name, normal, fixed = TRUE)
    },
    logical(1)
  )
  unique(codes[(english | spanish) & !is.na(codes)])
}

# recognise documented programme scope with one catalogue for all activities
# programme participation is not evidence of physical travel
stats_activity_programme <- function(value) {
  catalogue <- list(
    list(
      id = "erc",
      pattern = "European Research Council|Consejo Europeo de Investigaci[oó]n|\\bERC\\b",
      scope = "european",
      url = "https://research-and-innovation.ec.europa.eu/funding/funding-opportunities/funding-programmes-and-open-calls/horizon-europe/european-research-council_en"
    ),
    list(
      id = "horizon-europe",
      pattern = "Horizon Europe|Horizonte Europa",
      scope = "european",
      url = "https://research-and-innovation.ec.europa.eu/funding/funding-opportunities/funding-programmes-and-open-calls/horizon-europe_en"
    ),
    list(
      id = "fulbright",
      pattern = "\\bFulbright\\b",
      scope = "bilateral",
      url = "https://fulbright.es/informacion/investigacion-predoctoral-2/investigacion-predoctoral/"
    ),
    list(
      id = "erasmus-plus",
      pattern = "Erasmus[[:space:]]*[+]",
      scope = "european",
      url = "https://erasmus-plus.ec.europa.eu/about-erasmus"
    ),
    list(
      id = "rise-worldwide",
      pattern = "RISE[[:space:]]+Worldwide",
      scope = "international_training",
      url = "https://www.daad.de/rise/en/rise-worldwide/offer-an-internship/what-providers-need-to-know/"
    ),
    list(
      id = "researchers-night",
      pattern = "European Researchers.? Night|Noche Europea de los Investigadores",
      scope = "european_outreach",
      url = "https://marie-sklodowska-curie-actions.ec.europa.eu/actions/msca-and-citizens"
    )
  )
  found <- Filter(
    function(x) grepl(x$pattern, value, ignore.case = TRUE, perl = TRUE),
    catalogue
  )
  list(
    programme_id = paste(
      vapply(found, `[[`, character(1), "id"),
      collapse = "; "
    ),
    programme_scope = paste(
      unique(vapply(found, `[[`, character(1), "scope")),
      collapse = "; "
    ),
    programme_source = paste(
      vapply(found, `[[`, character(1), "url"),
      collapse = "; "
    ),
    international_programme = length(found) > 0L
  )
}

# split joint organisations only at slashes outside parentheses
stats_activity_entities <- function(value) {
  chars <- strsplit(value, "", fixed = TRUE)[[1]]
  depth <- 0L
  start <- 1L
  pieces <- character()
  for (i in seq_along(chars)) {
    if (chars[[i]] == "(") {
      depth <- depth + 1L
    }
    if (chars[[i]] == ")") {
      depth <- max(0L, depth - 1L)
    }
    if (chars[[i]] == "/" && depth == 0L) {
      if (i > start) {
        pieces <- c(
          pieces,
          paste0(chars[seq.int(start, i - 1L)], collapse = "")
        )
      }
      start <- i + 1L
    }
  }
  if (length(chars) && start <= length(chars)) {
    pieces <- c(pieces, paste0(chars[start:length(chars)], collapse = ""))
  }
  pieces <- trimws(pieces)
  unique(pieces[nzchar(pieces)])
}

# derive abbreviation aliases only from explicit organisation names in Excel
stats_activity_aliases <- function(values) {
  aliases <- list()
  for (value in unique(values[nzchar(values)])) {
    prefix <- regmatches(
      value,
      regexec(
        "^([A-Za-z][A-Za-z0-9+-]{1,20})[[:space:]]+[–-][[:space:]]+(.+)$",
        value
      )
    )[[1]]
    suffix <- regmatches(
      value,
      regexec(
        "^(.+?)[[:space:]]*\\(([A-Z][A-Z0-9-]{1,20})\\)[[:space:]]*$",
        value
      )
    )[[1]]
    if (length(prefix)) {
      aliases[[stats_key(prefix[[2]])]] <- prefix[[3]]
    }
    if (length(suffix)) aliases[[stats_key(suffix[[3]])]] <- suffix[[2]]
  }
  aliases
}

# represent date uncertainty without inventing a precise activity date
stats_activity_bound <- function(value, latest = FALSE) {
  if (!nzchar(value)) {
    return(as.Date(NA))
  }
  if (!grepl("^[0-9]{4}(-[0-9]{2})?(-[0-9]{2})?$", value)) {
    stop("Invalid activity date: ", value, call. = FALSE)
  }
  full <- paste0(
    value,
    if (nchar(value) == 4L) {
      "-01-01"
    } else if (nchar(value) == 7L) {
      "-01"
    } else {
      ""
    }
  )
  date <- suppressWarnings(as.Date(full))
  if (is.na(date) || format(date, "%Y-%m-%d") != full) {
    stop("Invalid calendar date: ", value, call. = FALSE)
  }
  if (latest && nchar(value) == 4L) {
    return(as.Date(sprintf("%04d-01-01", as.integer(value) + 1L)) - 1)
  }
  if (latest && nchar(value) == 7L) {
    return(seq(date, by = "month", length.out = 2L)[[2]] - 1)
  }
  date
}

# keep date precision and reported durations separate
# only complete start and end dates support an exact day count
stats_activity_dates <- function(start, end, detail, declared, as_of) {
  start <- stats_text(start)
  end <- stats_text(end)
  current <- tolower(end) %in%
    c("actualmente", "actualidad", "present", "ongoing")
  if (current) {
    end <- ""
  }
  lower <- stats_activity_bound(start)
  upper <- if (nzchar(end)) {
    stats_activity_bound(end, latest = TRUE)
  } else if (current) {
    as.Date(as_of)
  } else {
    as.Date(NA)
  }
  if (!is.na(lower) && !is.na(upper) && upper < lower) {
    stop("Activity end precedes start", call. = FALSE)
  }
  declared <- stats_scalar(declared)
  stated <- regmatches(
    detail,
    regexec(
      "(?:[Tt]otal[[:space:]]+duration|[Dd]uraci[oó]n[[:space:]]+total)[[:space:]]*:[[:space:]]*([0-9]+(?:[.,][0-9]+)?)[[:space:]]*(?:months?|mes(?:es)?)",
      detail,
      perl = TRUE
    )
  )[[1]]
  if (is.na(declared) && length(stated)) {
    declared <- as.numeric(sub(",", ".", stated[[2]], fixed = TRUE))
  }
  exact <- if (nchar(start) == 10L && (nchar(end) == 10L || current)) {
    as.numeric(upper - lower) + 1
  } else {
    NA_real_
  }
  calendar <- if (nchar(start) == 7L && nchar(end) == 7L) {
    (as.integer(substr(end, 1L, 4L)) - as.integer(substr(start, 1L, 4L))) *
      12 +
      as.integer(substr(end, 6L, 7L)) -
      as.integer(substr(start, 6L, 7L)) +
      1
  } else {
    NA_real_
  }
  aggregate <- grepl(
    "\\b(several|multiple|varias|varios)\\b|totalling|en total",
    detail,
    ignore.case = TRUE,
    perl = TRUE
  ) &&
    !nzchar(start)
  periods <- regmatches(
    detail,
    regexec(
      "[Pp]eriod[so]?[[:space:]]*:[[:space:]]*((?:[12][0-9]{3}[[:space:];,]*)+)",
      detail,
      perl = TRUE
    )
  )[[1]]
  period_years <- if (length(periods)) {
    paste(
      unique(regmatches(periods[[2]], gregexpr("[12][0-9]{3}", periods[[2]]))[[
        1
      ]]),
      collapse = "; "
    )
  } else {
    ""
  }
  precision <- unique(c(
    if (nzchar(start)) nchar(start),
    if (nzchar(end)) nchar(end)
  ))
  precision <- if (!length(precision)) {
    "unknown"
  } else if (length(precision) > 1L) {
    "mixed"
  } else {
    switch(as.character(precision), "4" = "year", "7" = "month", "10" = "day")
  }
  status <- if (!nzchar(start)) {
    "undated"
  } else if (lower > as.Date(as_of)) {
    "planned"
  } else if (current) {
    "ongoing"
  } else if (!nzchar(end)) {
    "start_only"
  } else if (upper > as.Date(as_of)) {
    if (nchar(end) < 10L) "possibly_ongoing" else "ongoing"
  } else {
    "dated_period"
  }
  basis <- if (!is.na(declared)) {
    "declared_months"
  } else if (!is.na(exact)) {
    "exact_dates"
  } else if (!is.na(calendar)) {
    "calendar_months_covered"
  } else {
    "not_quantified"
  }
  list(
    start_date = start,
    end_date = end,
    date_precision = precision,
    year = if (nzchar(start)) {
      as.integer(substr(start, 1L, 4L))
    } else if (nzchar(period_years)) {
      as.integer(substr(period_years, 1L, 4L))
    } else {
      NA_integer_
    },
    duration_months_declared = declared,
    duration_months_calendar = calendar,
    duration_days_exact = exact,
    duration_basis = basis,
    aggregate_record = aggregate,
    date_status = status,
    date_duration_discrepancy = !is.na(declared) &&
      !is.na(exact) &&
      abs(declared - exact / (365.25 / 12)) > 0.5,
    period_years = period_years
  )
}

# match institutions automatically and validate against recorded countries
# institution geography describes the registry location, not a campus visit
stats_activity_institution <- function(entity, expected, aliases, context) {
  if (!length(expected)) {
    expected <- stats_activity_countries(entity)
  }
  query <- entity
  alias <- aliases[[stats_key(query)]]
  if (!is.null(alias)) {
    query <- alias
  }
  countries <- countrycode::codelist
  country_names <- c(
    countries$country.name.en,
    countries$cldr.name.es,
    countries$iso2c,
    countries$iso3c
  )
  if (
    !nzchar(query) ||
      stats_key(query) %in% stats_key(country_names[!is.na(country_names)])
  ) {
    return(list())
  }
  candidates <- query
  comma <- trimws(strsplit(query, ",", fixed = TRUE)[[1]])
  academic <- comma[grepl(
    "univer|institut|college|csic|hospital|school|centre|center",
    comma,
    ignore.case = TRUE
  )]
  candidates <- unique(c(candidates, academic))
  for (candidate in candidates) {
    value <- stats_ror(list(name = candidate), context)
    if (!nzchar(stats_text(value$ror_id))) {
      next
    }
    if (length(expected) && !stats_text(value$country_code) %in% expected) {
      next
    }
    return(list(
      ror_id = stats_text(value$ror_id),
      institution_name = stats_text(value$institution_name),
      institution_type = stats_text(value$institution_type),
      country_code = stats_text(value$country_code),
      country = stats_text(value$country),
      city = stats_text(value$city),
      latitude = stats_scalar(value$latitude),
      longitude = stats_scalar(value$longitude),
      metadata_url = stats_text(value$ror_id),
      metadata_retrieved_at = stats_text(value$institution_retrieved_at)
    ))
  }
  list()
}

# extract all non-publication records as an evidence inventory
# activity relations preserve facilities and partner institutions without travel
stats_activities <- function(
  workbook,
  context,
  reference_country = "ES",
  as_of = Sys.Date()
) {
  sheets <- c("Experiencia", "Formacion", "Congresos", "Proyectos", "Otros")
  frames <- setNames(
    lapply(sheets, function(sheet) {
      readxl::read_excel(workbook, sheet = sheet, col_types = "list")
    }),
    sheets
  )
  values <- unlist(
    lapply(frames, function(frame) {
      fields <- intersect(
        c(
          "institucion",
          "institution",
          "universidad",
          "entidad",
          "congreso_institucion"
        ),
        names(frame)
      )
      unlist(lapply(frame[fields], function(column) {
        vapply(column, stats_text, character(1))
      }))
    }),
    use.names = FALSE
  )
  aliases <- stats_activity_aliases(values)
  profile <- readxl::read_excel(workbook, sheet = "Perfil", col_types = "list")
  alias_row <- which(
    vapply(profile$campo, stats_text, character(1)) == "alias_autoria"
  )
  own_aliases <- if (length(alias_row) == 1L) {
    stats_names(profile$valor[[alias_row]])
  } else {
    character()
  }
  own_aliases <- stats_key(vapply(own_aliases, stats_person_name, character(1)))
  doctoral <- frames$Formacion[
    vapply(
      frames$Formacion$titulo_en,
      function(x) grepl("Ph[.]?D|Doctor", stats_text(x), ignore.case = TRUE),
      logical(1)
    ),
  ]
  phd_date <- if (nrow(doctoral)) stats_text(doctoral$fecha[[1]]) else ""
  categories <- c(
    estancia = "research_stay",
    docencia = "teaching",
    supervision = "supervision",
    formacioncomplementaria = "training",
    ayudasybecas = "scholarship",
    revision = "review",
    edicion = "editorial",
    evaluacion = "evaluation",
    asociaciones = "membership",
    idiomas = "language",
    competencias = "skill",
    divulgacion = "outreach",
    otraformacion = "other_training",
    otrosdatos = "other"
  )
  result <- list()
  for (sheet in sheets) {
    frame <- frames[[sheet]]
    for (i in seq_len(nrow(frame))) {
      row <- lapply(frame, function(column) column[[i]])
      text <- function(key) stats_text(row[[key]])
      bilingual <- function(key) {
        en <- text(paste0(key, "_en"))
        if (nzchar(en)) en else text(paste0(key, "_es"))
      }
      type <- switch(
        sheet,
        Experiencia = "appointment",
        Formacion = "degree",
        Congresos = if (text("tipo") == "organizacion") {
          "conference_organisation"
        } else {
          "presentation"
        },
        Proyectos = "project",
        Otros = {
          key <- stats_key(text("tipo"))
          if (key %in% names(categories)) unname(categories[[key]]) else "other"
        }
      )
      title <- if (sheet == "Experiencia") {
        bilingual("puesto")
      } else {
        bilingual("titulo")
      }
      if (sheet == "Proyectos" && nzchar(text("acronimo"))) {
        title <- paste(text("acronimo"), title, sep = ": ")
      }
      entity <- switch(
        sheet,
        Experiencia = text("institucion"),
        Formacion = text("universidad"),
        Congresos = text("congreso_institucion"),
        Proyectos = if (nzchar(text("institution"))) {
          text("institution")
        } else {
          text("institucion")
        },
        Otros = text("entidad")
      )
      detail <- if (sheet == "Experiencia") {
        if (nzchar(text("note"))) text("note") else text("nota")
      } else if (sheet == "Proyectos") {
        bilingual("contribucion")
      } else {
        bilingual("detalle")
      }
      location <- switch(
        sheet,
        Experiencia = bilingual("pais"),
        Formacion = bilingual("pais"),
        Congresos = bilingual("lugar"),
        Proyectos = "",
        Otros = {
          if (type %in% c("research_stay", "training", "other_training")) {
            strsplit(detail, ".", fixed = TRUE)[[1]][1]
          } else {
            ""
          }
        }
      )
      if (is.na(location)) {
        location <- ""
      }
      attendance <- if (
        grepl("online|en l[ií]nea|virtual|remote", location, ignore.case = TRUE)
      ) {
        "online"
      } else if (
        type %in%
          c(
            "appointment",
            "research_stay",
            "presentation",
            "conference_organisation",
            "training"
          ) &&
          nzchar(location)
      ) {
        "in_person_recorded"
      } else {
        "not_specified"
      }
      role <- switch(
        type,
        project = bilingual("contribucion"),
        presentation = bilingual("modalidad"),
        conference_organisation = bilingual("modalidad"),
        appointment = title,
        title
      )
      start <- if (sheet %in% c("Formacion", "Congresos")) {
        text("fecha")
      } else {
        text("inicio")
      }
      end <- if (sheet %in% c("Formacion", "Congresos")) "" else text("fin")
      dates <- stats_activity_dates(
        start,
        end,
        detail,
        row$duracion_meses,
        as_of
      )
      programme <- stats_activity_programme(paste(
        title,
        entity,
        detail,
        text("funding"),
        text("financiador"),
        text("call"),
        text("convocatoria")
      ))
      units <- regmatches(
        detail,
        regexec(
          "^[[:space:]]*([0-9]+)[[:space:]]+(?:review|revisi)",
          detail,
          ignore.case = TRUE,
          perl = TRUE
        )
      )[[1]]
      declared_units <- if (type == "review" && length(units)) {
        as.numeric(units[[2]])
      } else {
        NA_real_
      }
      career <- "not_determined"
      if (nzchar(phd_date) && nchar(phd_date) == 10L) {
        last <- if (nzchar(dates$end_date)) {
          dates$end_date
        } else if (nzchar(dates$period_years)) {
          tail(stats_names(dates$period_years), 1L)
        } else if (
          type %in% c("degree", "presentation", "conference_organisation")
        ) {
          start
        } else {
          ""
        }
        last_bound <- stats_activity_bound(last, latest = TRUE)
        first_bound <- stats_activity_bound(start)
        if (!is.na(last_bound) && last_bound < as.Date(phd_date)) {
          career <- "pre_PhD"
        }
        if (!is.na(first_bound) && first_bound >= as.Date(phd_date)) {
          career <- "post_PhD"
        }
      }
      base <- c(
        list(
          activity_id = paste(sheet, i + 1L, sep = ":"),
          source_sheet = sheet,
          source_row = i + 1L,
          activity_type = type,
          subtype = if (sheet == "Congresos") {
            bilingual("modalidad")
          } else if (sheet == "Otros") {
            text("tipo")
          } else {
            ""
          },
          title = title,
          entity = entity,
          detail = detail,
          cva_selected = if ("incluir" %in% names(row)) {
            stats_flag(row$incluir)
          } else {
            NA
          },
          attendance_mode = attendance,
          country_role = "unspecified",
          country_code = "",
          country = "",
          is_foreign = NA,
          reference_country = reference_country,
          institution_id = "",
          ror_id = "",
          institution_name = "",
          institution_type = "",
          city = "",
          latitude = NA_real_,
          longitude = NA_real_,
          country_source = "not_recorded",
          metadata_url = "",
          metadata_retrieved_at = "",
          role = role,
          principal_investigators = text("ip"),
          is_pi = if (sheet == "Proyectos") {
            any(
              stats_key(vapply(
                stats_names(text("ip")),
                stats_person_name,
                character(1)
              )) %in%
                own_aliases
            )
          } else {
            NA
          },
          reference = text("referencia"),
          amount = stats_scalar(row$importe),
          currency = text("moneda"),
          amount_type = text("tipo_importe"),
          hours = stats_scalar(row$horas),
          declared_units = declared_units,
          coverage_note = "",
          location = location,
          funding = if (nzchar(text("funding"))) {
            text("funding")
          } else {
            text("financiador")
          },
          call = if (nzchar(text("call"))) {
            text("call")
          } else {
            text("convocatoria")
          },
          career_stage = career
        ),
        dates,
        programme
      )
      add <- function(fields = list()) {
        value <- base
        for (key in names(fields)) {
          value[[key]] <- fields[[key]]
        }
        value$is_foreign <- if (nzchar(stats_text(value$country_code))) {
          value$country_code != reference_country
        } else {
          NA
        }
        if (value$date_duration_discrepancy) {
          value$coverage_note <- paste(
            value$coverage_note,
            "Declared duration differs from exact date span"
          )
        }
        result[[length(result) + 1L]] <<- as.data.frame(
          value,
          stringsAsFactors = FALSE
        )
      }
      relation <- if (
        type %in% c("appointment", "degree", "research_stay", "teaching")
      ) {
        "host_institution"
      } else if (
        type %in%
          c(
            "presentation",
            "conference_organisation",
            "training",
            "other_training"
          )
      ) {
        "activity_location"
      } else if (type == "project") {
        "project_host"
      } else if (type == "supervision") {
        "partner_institution"
      } else {
        "entity_country"
      }
      if (attendance == "online") {
        add(list(
          country_role = "activity_location",
          country_source = "online_no_travel",
          coverage_note = "Online contribution; no physical host country inferred"
        ))
      } else {
        countries <- stats_activity_countries(location)
        entities <- stats_activity_entities(entity)
        resolve <- type %in%
          c(
            "appointment",
            "degree",
            "research_stay",
            "teaching",
            "project",
            "supervision",
            "training",
            "other_training",
            "scholarship"
          ) ||
          (type == "presentation" &&
            grepl(
              "seminar|seminario|keynote",
              bilingual("modalidad"),
              ignore.case = TRUE
            ))
        added <- FALSE
        institution_keys <- character()
        if (resolve && length(entities)) {
          for (part in entities) {
            institution <- stats_activity_institution(
              part,
              countries,
              aliases,
              context
            )
            if (length(institution)) {
              key <- stats_text(institution$ror_id)
              if (key %in% institution_keys) {
                next
              }
              institution_keys <- c(institution_keys, key)
              institution$country_role <- relation
              institution$country_source <- if (length(countries)) {
                "workbook_location_and_ror"
              } else {
                "ror_institution"
              }
              add(institution)
              added <- TRUE
            } else if (length(entities) > 1L) {
              part_countries <- if (length(countries)) {
                countries
              } else if (relation == "entity_country") {
                stats_activity_countries(part)
              } else {
                character()
              }
              for (country in if (length(part_countries)) {
                part_countries
              } else {
                ""
              }) {
                add(list(
                  country_role = relation,
                  country_code = country,
                  country = if (nzchar(country)) {
                    countrycode::countrycode(
                      country,
                      "iso2c",
                      "country.name",
                      warn = FALSE
                    )
                  } else {
                    ""
                  },
                  institution_name = part,
                  country_source = if (nzchar(country)) {
                    "workbook_location"
                  } else {
                    "not_recorded"
                  },
                  coverage_note = "Joint institution not resolved"
                ))
              }
              added <- TRUE
            }
          }
        }
        if (!added) {
          if (!length(countries) && relation == "entity_country") {
            countries <- stats_activity_countries(entity)
          }
          if (!length(countries)) {
            add(list(
              country_role = relation,
              institution_name = entity,
              coverage_note = if (nzchar(entity)) {
                "Country or institution not resolved"
              } else {
                "Location not recorded"
              }
            ))
          } else {
            for (country in countries) {
              add(list(
                country_role = relation,
                country_code = country,
                institution_name = entity,
                country = countrycode::countrycode(
                  country,
                  "iso2c",
                  "country.name",
                  warn = FALSE
                ),
                country_source = "workbook_location"
              ))
            }
          }
        }
      }
      if (sheet == "Proyectos") {
        award <- bilingual("detalle_importe")
        if (nzchar(award)) {
          facility <- grepl("access|acceso", award, ignore.case = TRUE) &&
            grepl(
              "facilit|instalaci|services|servicios|analytic|anal[ií]t",
              award,
              ignore.case = TRUE
            )
          for (country in stats_activity_countries(award)) {
            add(list(
              country_role = if (facility) {
                "facility_access"
              } else {
                "award_description"
              },
              country_code = country,
              country = countrycode::countrycode(
                country,
                "iso2c",
                "country.name",
                warn = FALSE
              ),
              country_source = "workbook_award_description",
              detail = award,
              attendance_mode = if (facility) {
                "access_awarded"
              } else {
                "not_specified"
              },
              coverage_note = if (facility) {
                "Awarded facility access; no visit inferred"
              } else {
                "Country mentioned in award description; no travel inferred"
              }
            ))
          }
        }
      }
    }
  }
  data <- do.call(rbind, result)
  data <- data[
    order(
      data$source_sheet,
      data$source_row,
      data$country_role,
      data$country_code,
      data$ror_id
    ),
  ]
  rownames(data) <- NULL
  data
}

# validate the complete CSV before replacing its previous version
stats_save <- function(data, output) {
  if (dir.exists(output)) {
    stop("The CSV output must be a file", call. = FALSE)
  }
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(tmpdir = dirname(output), fileext = ".csv")
  backup <- tempfile(tmpdir = dirname(output), fileext = ".csv")
  complete <- FALSE
  on.exit(
    {
      if (file.exists(backup)) {
        if (complete) {
          unlink(backup)
        } else {
          if (file.exists(output)) {
            unlink(output)
          }
          if (!file.rename(backup, output)) {
            warning("Previous CSV retained at ", backup, call. = FALSE)
          }
        }
      }
      unlink(temporary)
    },
    add = TRUE
  )
  utils::write.csv(
    data,
    temporary,
    row.names = FALSE,
    na = "",
    fileEncoding = "UTF-8"
  )
  check <- utils::read.csv(
    temporary,
    colClasses = "character",
    na.strings = "",
    fileEncoding = "UTF-8"
  )
  if (nrow(check) != nrow(data) || !identical(names(check), names(data))) {
    stop("CSV round-trip validation failed", call. = FALSE)
  }
  if (file.exists(output) && !file.rename(output, backup)) {
    stop(
      "Cannot replace the existing CSV; close it and try again",
      call. = FALSE
    )
  }
  if (!file.rename(temporary, output)) {
    stop("Cannot save the statistics CSV", call. = FALSE)
  }
  complete <- TRUE
  invisible(output)
}

# combine the record types without discarding their source-specific fields
stats_combine <- function(publications, activities) {
  publications$record_type <- "publication"
  activities$record_type <- "activity"
  columns <- unique(c("record_type", names(publications), names(activities)))
  align <- function(data) {
    for (field in setdiff(columns, names(data))) {
      data[[field]] <- NA
    }
    data[columns]
  }
  data <- rbind(align(publications), align(activities))
  rownames(data) <- NULL
  data
}

# retrieve all evidence and save it in one CSV
retrieve_stats <- function(
  workbook = file.path(stats_root, "input/datos-cv.xlsx"),
  output = file.path(stats_root, "input/stats.csv"),
  cache = file.path(stats_root, "cva/.stats-cache"),
  refresh = FALSE,
  offline = FALSE,
  exclude_dois = "10.1093/biosci/biae043",
  reference_country = "ES",
  as_of = as.Date(format(Sys.time(), "%Y-%m-%d", tz = "Europe/Madrid"))
) {
  packages <- c("readxl", "jsonlite", "httr2", "digest", "countrycode")
  missing <- packages[
    !vapply(packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    stop("Install R packages: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (refresh && offline) {
    stop("Use either refresh or offline", call. = FALSE)
  }
  if (length(as_of) != 1L || is.na(as.Date(as_of))) {
    stop("Invalid as_of date", call. = FALSE)
  }
  as_of <- as.Date(as_of)
  reference_country <- toupper(stats_text(reference_country))
  if (
    !grepl("^[A-Z]{2}$", reference_country) ||
      is.na(countrycode::countrycode(
        reference_country,
        "iso2c",
        "country.name",
        warn = FALSE
      ))
  ) {
    stop("reference_country must be an ISO country code", call. = FALSE)
  }
  workbook_hash <- unname(tools::md5sum(workbook))
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  context <- list2env(list(
    cache = cache,
    refresh = refresh,
    offline = offline,
    failures = character()
  ))
  # keep the requested exclusions explicit and independent of CVA selection
  if (!is.character(exclude_dois) || anyNA(exclude_dois)) {
    stop("exclude_dois must contain DOI strings", call. = FALSE)
  }
  exclude_dois <- unique(tolower(trimws(exclude_dois)))
  exclude_dois <- exclude_dois[nzchar(exclude_dois)]
  if (any(!grepl("^10[.][0-9]{4,9}/[^[:space:]]+$", exclude_dois))) {
    stop("Invalid DOI in exclude_dois", call. = FALSE)
  }
  all_publications <- stats_read(workbook)
  publications <- Filter(
    function(x) !tolower(x$doi) %in% exclude_dois,
    all_publications
  )
  excluded_count <- length(all_publications) - length(publications)
  if (!length(publications)) {
    stop("No publication rows", call. = FALSE)
  }
  result <- lapply(seq_along(publications), function(i) {
    paper <- publications[[i]]
    message(
      "Retrieving publication ",
      i,
      "/",
      length(publications),
      ": ",
      paper$title
    )
    source <- stats_work(paper, context)
    stats_rows(paper, source, context)
  })
  data <- do.call(rbind, result)
  data$excluded_dois <- paste(exclude_dois, collapse = "; ")
  data$excluded_publication_count <- excluded_count
  if (any(data$metadata_status == "lookup_failed")) {
    stop(
      "A publication lookup failed; the previous CSV has been retained",
      call. = FALSE
    )
  }
  data <- stats_institutions(data, context)
  message(
    "Retrieving activity evidence from appointments, education, conferences, projects and other CV records"
  )
  activities <- stats_activities(workbook, context, reference_country, as_of)
  if (length(context$failures)) {
    stop(
      "Metadata retrieval was incomplete; the previous CSV has been retained. Retry later or use cached data.",
      call. = FALSE
    )
  }
  data <- stats_identities(data)
  clean <- function(table) {
    text_columns <- vapply(table, is.character, logical(1))
    table[text_columns] <- lapply(table[text_columns], function(x) {
      x <- gsub("[\r\n\t]+", " ", x)
      x[!nzchar(x)] <- NA_character_
      x
    })
    rownames(table) <- NULL
    table
  }
  data <- clean(data)
  activities <- clean(activities)
  data <- data[
    order(
      data$year,
      data$paper_id,
      data$source_author_index,
      data$institution_id,
      data$country_code,
      na.last = TRUE
    ),
  ]
  if (!identical(workbook_hash, unname(tools::md5sum(workbook)))) {
    stop(
      "The workbook changed during retrieval; save your edits and run again",
      call. = FALSE
    )
  }
  data <- stats_combine(data, activities)
  data$as_of_date <- as.character(as_of)
  data$reference_country <- reference_country
  stats_save(data, output)
  message(
    "Saved ",
    nrow(data),
    " rows (",
    length(publications),
    " publications and ",
    length(unique(activities$activity_id)),
    " activity records) to ",
    output
  )
  invisible(data)
}

# render the CSV-only report with the same R installation as this session
render_stats <- function(report = file.path(stats_root, "cva/stats.qmd")) {
  quarto <- unname(Sys.which("quarto"))
  if (!nzchar(quarto)) {
    stop("Install Quarto to render the report", call. = FALSE)
  }
  previous <- Sys.getenv("QUARTO_R", unset = NA_character_)
  on.exit(
    {
      if (is.na(previous)) {
        Sys.unsetenv("QUARTO_R")
      } else {
        Sys.setenv(QUARTO_R = previous)
      }
    },
    add = TRUE
  )
  Sys.setenv(QUARTO_R = file.path(R.home(), "bin"))
  status <- system2(
    quarto,
    c("render", shQuote(normalizePath(report, winslash = "/")))
  )
  if (status != 0L) {
    stop("Quarto rendering failed", call. = FALSE)
  }
  invisible(sub("[.]qmd$", ".html", report))
}

# accept simple CLI switches without running retrieval when the file is sourced
if (sys.nframe() == 0L) {
  args <- commandArgs(TRUE)
  if (any(!args %in% c("--refresh", "--offline", "--render"))) {
    stop("Supported options: --refresh, --offline, --render", call. = FALSE)
  }
  retrieve_stats(
    refresh = "--refresh" %in% args,
    offline = "--offline" %in% args
  )
  if ("--render" %in% args) render_stats()
}
