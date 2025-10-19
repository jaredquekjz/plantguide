#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key, default = NULL) {
  hit <- grep(paste0('^', key, '='), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0('^', key, '='), '', hit[1])
}

# Safely parse integer-like CLI args, stripping stray backticks/newlines
get_int_arg <- function(key, default = 0L) {
  raw <- get_arg(key, as.character(default))
  if (is.null(raw)) return(as.integer(default))
  raw <- gsub("[\\r\\n`\"']+", '', raw)
  raw <- gsub('[^0-9-]+', '', raw)
  val <- suppressWarnings(as.integer(raw))
  if (is.na(val)) as.integer(default) else val
}

normalize_name <- function(x) {
  x <- ifelse(is.na(x), '', trimws(x))
  # Remove botanical hybrid sign (×) and ASCII 'x' marker between tokens.
  # Avoid using \s; use POSIX classes to prevent R string escape issues.
  x <- gsub('^×[[:space:]]*', '', x, perl = TRUE)
  x <- gsub('[[:space:]]*×[[:space:]]*', ' ', x, perl = TRUE)
  x <- gsub('(^|[[:space:]])x([[:space:]]+)', ' ', x, perl = TRUE)
  x <- iconv(x, to = 'ASCII//TRANSLIT')
  x <- tolower(gsub('[\r\n]+', ' ', x))
  x <- gsub('[[:space:]]+', ' ', x)
  trimws(x)
}

eive_csv <- trimws(gsub('[\r\n`]+','', get_arg('--eive_csv', 'data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv')))
out_csv  <- trimws(gsub('[\r\n`]+','', get_arg('--out', 'data/EIVE/EIVE_TaxonConcept_WFO.csv')))
wfo_csv  <- trimws(gsub('[\r\n`]+','', get_arg('--wfo_csv', '')))
wfo_file <- trimws(gsub('[\r\n`]+','', get_arg('--wfo_file', '')))
fuzzy    <- get_int_arg('--fuzzy', 1L)
batch_size <- get_int_arg('--batch_size', 1000L)
checkpoint_every <- get_int_arg('--checkpoint_every', 0L)  # 0 = only final write

if (!file.exists(eive_csv)) stop(sprintf('Missing EIVE CSV: %s', eive_csv))
dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)

eive <- fread(eive_csv, encoding = 'UTF-8')
if (!'TaxonConcept' %in% names(eive)) stop('EIVE CSV must have a TaxonConcept column')
names_in <- unique(eive$TaxonConcept)

# Phase 1: Fast exact join against WFO backbone CSV (preferred)
WFO.data <- NULL
if (nzchar(wfo_csv) && file.exists(wfo_csv)) {
  message(sprintf('Loading WFO backbone (slim columns) from: %s', wfo_csv))
  # Read header first to detect column names robustly
  hdr <- names(fread(wfo_csv, nrows = 0, encoding = 'UTF-8'))
  has <- function(x) any(tolower(hdr) == tolower(x))
  col_of <- function(x) hdr[tolower(hdr) == tolower(x)][1]
  need <- c('taxonID','scientificName','acceptedNameUsageID','taxonomicStatus')
  sel <- vapply(need, function(x) if (has(x)) col_of(x) else NA_character_, character(1))
  if (any(is.na(sel))) {
    stop(sprintf('WFO CSV missing required columns: %s', paste(need[is.na(sel)], collapse = ', ')))
  }
  WFO.data <- fread(wfo_csv, select = sel, encoding = 'UTF-8')
  setnames(WFO.data, sel, need)
  # Normalize and prepare accepted mapping
  WFO.data[, norm := normalize_name(scientificName)]
  acc_map <- WFO.data[taxonomicStatus == 'Accepted', .(accepted_id = taxonID, accepted_scientificName = scientificName)]
  WFO.data[, accepted_id2 := ifelse(taxonomicStatus == 'Accepted' | is.na(taxonomicStatus), taxonID, acceptedNameUsageID)]
  WFO.data <- merge(WFO.data, acc_map, by.x = 'accepted_id2', by.y = 'accepted_id', all.x = TRUE)
  WFO.data[, wfo_accepted_name := fifelse(!is.na(accepted_scientificName), accepted_scientificName, scientificName)]
  WFO.data[, wfo_id := accepted_id2]
  WFO.data[, rank := ifelse(taxonomicStatus == 'Accepted', 1L, 2L)]
  setorderv(WFO.data, c('norm','rank'))
  # Best row per normalized name
  wfo_best <- WFO.data[nzchar(norm), .SD[1], by = norm, .SDcols = c('wfo_id','wfo_accepted_name')]
} else {
  message('No WFO CSV provided; skipping fast exact join phase.')
}

# Build result with exact matches first
res <- data.table(TaxonConcept = names_in)
res[, norm := normalize_name(TaxonConcept)]
# Ensure expected columns exist even if exact phase is skipped
if (!is.null(WFO.data)) {
  res <- merge(res, wfo_best, by = 'norm', all.x = TRUE, sort = FALSE)
  exact_n <- sum(!is.na(res$wfo_id))
  message(sprintf('Exact normalized matches (WFO CSV): %d of %d', exact_n, nrow(res)))
} else {
  res[, `:=`(wfo_id = NA_character_, wfo_accepted_name = NA_character_)]
}

# Write exact matches immediately
if (!is.null(WFO.data)) {
  exact_matched <- res[!is.na(wfo_id)]
  if (nrow(exact_matched) > 0) {
    fwrite(exact_matched[, .(TaxonConcept, wfo_id, wfo_accepted_name)], out_csv)
    message(sprintf('Wrote %d exact matches to: %s', nrow(exact_matched), out_csv))
  }
}

# Phase 2: Fuzzy/advanced matching only for unmatched (optional, via WorldFlora)
has_worldflora <- requireNamespace('WorldFlora', quietly = TRUE)
message(sprintf('Parameters: eive_csv=%s; wfo_csv=%s; out=%s; fuzzy=%d; batch_size=%d; checkpoint_every=%d',
                eive_csv, ifelse(nzchar(wfo_csv), wfo_csv, 'NONE'), out_csv, fuzzy, batch_size, checkpoint_every))

if (fuzzy <= 0) {
  message('Fuzzy disabled via --fuzzy=0; skipping fuzzy matching phase.')
  # Still need to write unmatched entries when fuzzy is disabled
  unmatched <- res[is.na(wfo_id)]
  if (nrow(unmatched) > 0) {
    append_mode <- file.exists(out_csv)
    fwrite(unmatched[, .(TaxonConcept, wfo_id = NA_character_, wfo_accepted_name = NA_character_)], 
           out_csv, append = append_mode, col.names = !append_mode)
    message(sprintf('Wrote %d unmatched entries to: %s', nrow(unmatched), out_csv))
  }
} else if (has_worldflora && fuzzy > 0) {
  # Identify unmatched rows so far (guard if column missing)
  if (!"wfo_id" %in% names(res)) res[, wfo_id := NA_character_]
  todo <- res[is.na(wfo_id), unique(TaxonConcept)]
  if (length(todo)) {
    message(sprintf('Running WorldFlora::WFO.match on %d unmatched names (Fuzzy=%s)...', length(todo), as.character(fuzzy)))
    # Determine WFO source once
    wf_source <- 'none'
    wf_env <- environment()
    if (!is.null(WFO.data)) {
      wf_source <- 'data'
      WFO.slim <- as.data.frame(WFO.data[, .(taxonID, scientificName, acceptedNameUsageID, taxonomicStatus)])
    } else if (nzchar(wfo_file) && file.exists(wfo_file)) {
      wf_source <- 'file'
    } else if ('WFO.names' %in% data(package='WorldFlora')$results[, 'Item']) {
      data('WFO.names', package = 'WorldFlora', envir = wf_env)
      wf_source <- 'package'
    }
    if (wf_source == 'none') {
      message('WorldFlora matching could not be performed (no data).')
    } else {
      # Batch over unmatched names with checkpointing
      if (is.na(batch_size) || batch_size <= 0) batch_size <- length(todo)
      total <- length(todo)
      processed <- 0L
      before_matches <- sum(!is.na(res$wfo_id))
      for (start in seq.int(1L, total, by = batch_size)) {
        end_idx <- min(start + batch_size - 1L, total)
        names_batch <- todo[start:end_idx]
        wf_res <- tryCatch({
          if (wf_source == 'data') {
            WorldFlora::WFO.match(names_batch, WFO.data = WFO.slim, Fuzzy = fuzzy)
          } else if (wf_source == 'file') {
            WorldFlora::WFO.match(names_batch, WFO.file = wfo_file, Fuzzy = fuzzy)
          } else {
            WorldFlora::WFO.match(names_batch, WFO.data = get('WFO.names', envir = wf_env), Fuzzy = fuzzy)
          }
        }, error = function(e) {
          message(sprintf('WorldFlora batch %d-%d failed: %s', start, end_idx, conditionMessage(e)))
          NULL
        })
        if (!is.null(wf_res)) {
          matched <- as.data.table(wf_res)
          # Determine input column name robustly
          in_col <- if ('Input' %in% names(matched)) 'Input' else if ('input' %in% names(matched)) 'input' else names(matched)[1]
          matched[, TaxonConcept := get(in_col)]
          matched[, norm := normalize_name(TaxonConcept)]
          # Harmonize WorldFlora output column names across versions
          if ('WFO.accepted' %in% names(matched)) setnames(matched, 'WFO.accepted', 'wfo_accepted_name')
          else if ('scientificName' %in% names(matched) && !'wfo_accepted_name' %in% names(matched)) {
            matched[, wfo_accepted_name := scientificName]
          }
          # Support alternative ID column spellings across versions
          id_col <- if ('WFO.ID' %in% names(matched)) 'WFO.ID' else if ('WFOID' %in% names(matched)) 'WFOID' else if ('taxonID' %in% names(matched)) 'taxonID' else NA_character_
          if (!is.na(id_col)) {
            setnames(matched, id_col, 'wfo_id')
          } else if (!'wfo_id' %in% names(matched)) {
            matched[, wfo_id := NA_character_]
          }
          if ('WFO.match' %in% names(matched)) setnames(matched, 'WFO.match', 'wfo_match_type')
          # Write fuzzy matches immediately (append to file)
          fuzzy_batch <- matched[!is.na(wfo_id), .(TaxonConcept, wfo_id, wfo_accepted_name = if ('wfo_accepted_name' %in% names(matched)) wfo_accepted_name else NA_character_)]
          if (nrow(fuzzy_batch) > 0) {
            fwrite(fuzzy_batch, out_csv, append = TRUE, col.names = FALSE)
            message(sprintf('Appended %d fuzzy matches (batch %d-%d)', nrow(fuzzy_batch), start, end_idx))
          }
          # Update res for tracking
          fill <- matched[!is.na(wfo_id), .(norm, wfo_id, wfo_accepted_name = if ('wfo_accepted_name' %in% names(matched)) wfo_accepted_name else NA_character_, wfo_match_type = if ('wfo_match_type' %in% names(matched)) wfo_match_type else NA)]
          setkey(res, norm)
          setkey(fill, norm)
          res[fill, `:=`(wfo_id = i.wfo_id, wfo_accepted_name = i.wfo_accepted_name, wfo_match_type = i.wfo_match_type)]
        }
        processed <- end_idx
      }
      fuzzy_n <- sum(!is.na(res$wfo_id)) - before_matches
      message(sprintf('Additional matches via WorldFlora: %d', fuzzy_n))
    }
  } else {
    message('No unmatched names left for WorldFlora matching.')
  }
} else if (fuzzy > 0) {
  message('WorldFlora package not available; skipping fuzzy matching phase.')
}

# Write any remaining unmatched entries
unmatched <- res[is.na(wfo_id)]
if (nrow(unmatched) > 0) {
  # Check if file exists to determine if we need headers
  append_mode <- file.exists(out_csv)
  fwrite(unmatched[, .(TaxonConcept, wfo_id = NA_character_, wfo_accepted_name = NA_character_)], 
         out_csv, append = append_mode, col.names = !append_mode)
  message(sprintf('Wrote %d unmatched entries to: %s', nrow(unmatched), out_csv))
}

# Final summary
total_matched <- sum(!is.na(res$wfo_id))
message(sprintf('Final summary: %s (total rows: %d, matched: %d, unmatched: %d)', 
                out_csv, nrow(res), total_matched, nrow(res) - total_matched))
