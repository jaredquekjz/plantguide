#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
  suppressWarnings(try(library(rtry), silent = TRUE))
})

args <- commandArgs(trailingOnly = TRUE)

# Simple CLI parsing
get_arg <- function(key, default = NULL) {
  hit <- grep(paste0('^', key, '='), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0('^', key, '='), '', hit[1])
}

eive_csv <- get_arg('--eive_csv', 'data/EIVE_Paper_1.0_SM_08_csv/mainTable.csv')
sources  <- get_arg('--sources', '')
out_path <- get_arg('--out', 'data/traits_for_eive_taxa_rtry.tsv')
chunk_sz <- as.integer(get_arg('--chunk_lines', '200000'))
no_filter <- tolower(get_arg('--no_filter', 'false')) %in% c('1','true','yes')
eive_wfo_csv <- get_arg('--eive_wfo_csv', '')

# Sanitize key paths in case of wrapped shell input
eive_csv <- trimws(gsub('[\r\n]+', '', eive_csv))
out_path <- trimws(gsub('[\r\n]+', '', out_path))

if (nzchar(sources)) {
  sources <- strsplit(sources, ',')[[1]]
  # Trim spaces and strip accidental newlines/carriage returns from wrapped shells
  sources <- trimws(gsub('[\r\n]+', '', sources))
  sources <- sources[nzchar(sources)]
}
if (length(sources) == 0) {
  stop('Provide --sources=comma,separated,paths to TRY extract .txt files')
}

# Fail fast if any source path is missing
missing <- sources[!file.exists(sources)]
if (length(missing)) {
  stop(sprintf('Missing source file(s): %s', paste(missing, collapse = ', ')))
}

dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)

normalize_name <- function(x) {
  x <- ifelse(is.na(x), '', trimws(x))
  # Remove hybrid cross sign (×) when used as botanical hybrid marker
  # - Leading marker: "×Aegilotriticum" -> "Aegilotriticum"
  # - Between tokens: "Abelia × grandiflora" -> "Abelia grandiflora"
  # Avoid using \s in regex; use POSIX classes to prevent unrecognized escapes.
  x <- gsub('^×[[:space:]]*', '', x, perl = TRUE)       # leading ×
  x <- gsub('[[:space:]]*×[[:space:]]*', ' ', x, perl = TRUE)    # interior ×
  # Also drop standalone ASCII 'x' token used as hybrid marker between tokens: "Abelia x grandiflora"
  x <- gsub('(^|[[:space:]])x([[:space:]]+)', ' ', x, perl = TRUE)
  # strip accents and transliterate
  x <- iconv(x, to = 'ASCII//TRANSLIT')
  # normalize whitespace
  x <- tolower(gsub('[\r\n]+', ' ', x))
  x <- gsub('[[:space:]]+', ' ', x)
  trimws(x)
}

# Load EIVE taxa and normalize (raw TaxonConcepts)
eive <- fread(eive_csv, select = 'TaxonConcept', encoding = 'UTF-8')
taxa_norm <- unique(normalize_name(eive$TaxonConcept))
taxa_norm <- taxa_norm[nzchar(taxa_norm)]

# Optionally, load WFO-normalized mapping and include accepted WFO names
taxa_wfo <- character(0)
if (nzchar(eive_wfo_csv)) {
  eive_wfo_csv <- trimws(gsub('[\r\n]+', '', eive_wfo_csv))
  if (file.exists(eive_wfo_csv)) {
    map <- fread(eive_wfo_csv, encoding = 'UTF-8')
    # Try a few likely column names for accepted WFO scientific name
    cand <- intersect(c('wfo_accepted_name','WFO.accepted','accepted_name','AcceptedName','acceptedName','WFO.best','best_match'), names(map))
    if (length(cand) > 0) {
      taxa_wfo <- unique(normalize_name(map[[cand[1]]]))
      taxa_wfo <- taxa_wfo[nzchar(taxa_wfo)]
      message(sprintf('Loaded %d WFO-accepted names from %s (column: %s)', length(taxa_wfo), eive_wfo_csv, cand[1]))
    } else {
      message(sprintf('No accepted-name column found in %s; using raw TaxonConcepts only', eive_wfo_csv))
    }
  } else {
    message(sprintf('eive_wfo_csv not found: %s; using raw TaxonConcepts only', eive_wfo_csv))
  }
}

# Final taxa set: union of raw EIVE and WFO-accepted names (both normalized)
taxa_set <- unique(c(taxa_norm, taxa_wfo))

write_header <- TRUE
total_kept <- 0L
kept_by_src <- integer(0)

process_source <- function(path, out_path) {
  # Read header with fread to avoid encoding issues
  hdr <- tryCatch(
    fread(path, sep = '\t', nThread = getDTthreads(), nrows = 0, header = TRUE, fill = TRUE, encoding = 'Latin-1'),
    error = function(e) NULL
  )
  if (is.null(hdr)) stop(sprintf('Failed to read header from %s', path))
  header <- names(hdr)
  
  # Remove any trailing empty columns (from trailing tabs)
  repeat {
    if (length(header) == 0) break
    last <- header[length(header)]
    if (!nzchar(last) || grepl('^V[0-9]+$', last)) {
      header <- header[-length(header)]
    } else break
  }

  idx_species <- match('SpeciesName', header)
  idx_acc     <- match('AccSpeciesName', header)
  if (is.na(idx_species) && is.na(idx_acc)) stop(sprintf('No SpeciesName/AccSpeciesName in %s', path))

  src_label <- basename(dirname(path))
  if (src_label == '' || src_label == '.') src_label <- basename(path)

  # Stream in chunks using fread skip/nrows; assign header as col.names
  offset <- 0L
  kept_count <- 0L
  repeat {
    dt <- tryCatch(
      fread(
        path, sep = '\t', header = FALSE, nrows = chunk_sz,
        skip = 1L + offset, fill = TRUE, quote = '"',
        col.names = header, na.strings = c('', 'NA'),
        encoding = 'Latin-1'
      ),
      error = function(e) NULL
    )
    if (is.null(dt) || nrow(dt) == 0L) break

    # Drop any unnamed columns created by trailing tabs
    if ('' %in% names(dt)) {
      dt[, (names(dt)[names(dt) == '']) := NULL]
    }

    # Normalize names and filter
    sn <- if (!is.na(idx_species)) normalize_name(dt[[idx_species]]) else rep('', nrow(dt))
    an <- if (!is.na(idx_acc))     normalize_name(dt[[idx_acc]])     else rep('', nrow(dt))
    keep <- if (no_filter) rep(TRUE, nrow(dt)) else ((sn %in% taxa_set) | (an %in% taxa_set))
    if (any(keep)) {
      sub <- dt[keep]
      sub[, Source := src_label]
      total_kept <<- total_kept + nrow(sub)
      kept_count <- kept_count + nrow(sub)
      if (write_header) {
        fwrite(sub[0], file = out_path, sep = '\t', quote = TRUE, col.names = TRUE)
        write_header <<- FALSE
      }
      fwrite(sub, file = out_path, sep = '\t', append = TRUE, quote = TRUE, col.names = FALSE)
    }
    offset <- offset + nrow(dt)
  }
  # Record per-source tally and print summary
  kept_by_src[src_label] <<- kept_count
  message(sprintf('Finished %s: kept %d rows', src_label, kept_count))
}

for (p in sources) {
  message(sprintf('Processing %s ...', p))
  process_source(p, out_path)
}

if (total_kept == 0L) {
  message('Done. No matching rows; no file written.')
} else {
  message(sprintf('Done. Wrote: %s', out_path))
  message(sprintf('Total rows kept: %d', total_kept))
  if (length(kept_by_src)) {
    bysrc <- paste(sprintf('%s=%d', names(kept_by_src), unlist(kept_by_src)), collapse = ', ')
    message(sprintf('Rows by source: %s', bysrc))
  }
}
