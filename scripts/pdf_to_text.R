#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(methods)
})

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key, default = NULL) {
  hit <- grep(paste0('^', key, '='), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0('^', key, '='), '', hit[1])
}

in_pdf  <- get_arg('--in')
out_txt <- get_arg('--out', sub('\n*$', '', sub('\n*$', '', 'docs/WorldFlora.txt')))
if (is.null(in_pdf)) stop('Provide --in=path/to.pdf')
in_pdf  <- trimws(gsub('[\r\n]+', '', in_pdf))
out_txt <- trimws(gsub('[\r\n]+', '', out_txt))
dir.create(dirname(out_txt), showWarnings = FALSE, recursive = TRUE)

ok <- FALSE

# Try pdftools first
if (!ok) {
  suppressWarnings(suppressPackageStartupMessages({
    ok_pdftools <- requireNamespace('pdftools', quietly = TRUE)
  }))
  if (ok_pdftools) {
    txt <- pdftools::pdf_text(in_pdf)
    cat(paste(txt, collapse='\n'), file = out_txt, sep = '')
    ok <- TRUE
    message(sprintf('Wrote text via pdftools: %s', out_txt))
  }
}

# Fallback to system pdftotext if available
if (!ok) {
  status <- try(system2('pdftotext', c('-layout', shQuote(in_pdf), shQuote(out_txt)), stdout = TRUE, stderr = TRUE), silent = TRUE)
  if (!inherits(status, 'try-error') && file.exists(out_txt)) {
    ok <- TRUE
    message(sprintf('Wrote text via pdftotext: %s', out_txt))
  }
}

if (!ok) {
  stop('Could not extract PDF text. Install R package pdftools or the pdftotext (poppler-utils) binary.')
}

