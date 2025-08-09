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

in_path  <- get_arg('--in')
out_path <- get_arg('--out', 'docs/traits_analysis.md')

# Trim stray newlines/CR and whitespace from paths (resist wrapped shell input)
if (!is.null(in_path))  in_path  <- trimws(gsub('[\r\n]+', '', in_path))
if (!is.null(out_path)) out_path <- trimws(gsub('[\r\n]+', '', out_path))

if (is.null(in_path) || !file.exists(in_path)) {
  stop(sprintf('Input file not found. Pass --in=path (got %s)', in_path))
}

dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)

cat(sprintf('Reading: %s\n', in_path))
dt <- fread(in_path, sep = '\t', quote = '"', encoding = 'UTF-8', na.strings = c('', 'NA'))

if (!'TraitName' %in% names(dt)) stop('TraitName column not found in input file')

total_rows <- nrow(dt)
nonempty   <- sum(!is.na(dt$TraitName) & nzchar(dt$TraitName))
empty      <- total_rows - nonempty

# Frequency table
freq <- dt[!is.na(TraitName) & nzchar(TraitName), .N, by = .(TraitName)][order(-N, TraitName)]
freq[, pct := N / sum(N)]

# Optional: per-source distribution if Source present
has_source <- 'Source' %in% names(dt)
per_src <- NULL
if (has_source) {
  per_src <- dt[, .N, by = .(Source)][order(-N, Source)]
}

# Write Markdown
con <- file(out_path, open = 'wt', encoding = 'UTF-8')
on.exit(close(con))

write_md <- function(...) writeLines(paste0(...), con)

write_md('# Trait Frequency Analysis\n')
write_md(sprintf('- Input file: `%s`', in_path), '\n')
write_md(sprintf('- Total rows: %d', total_rows))
write_md(sprintf('- Non-empty TraitName rows: %d', nonempty))
write_md(sprintf('- Empty TraitName rows: %d', empty))
write_md(sprintf('- Unique traits: %d', nrow(freq)), '\n')

if (has_source) {
  write_md('## Rows by Source\n')
  write_md('| Source | Rows |')
  write_md('|---|---:|')
  for (i in seq_len(nrow(per_src))) {
    write_md(sprintf('| %s | %d |', per_src$Source[i], per_src$N[i]))
  }
  write_md('\n')
}

write_md('## Traits Ranked by Frequency\n')
write_md('| Rank | TraitName | Rows | Percent |')
write_md('|---:|---|---:|---:|')
for (i in seq_len(nrow(freq))) {
  write_md(sprintf('| %d | %s | %d | %.2f%% |', i, freq$TraitName[i], freq$N[i], 100 * freq$pct[i]))
}

cat(sprintf('Wrote: %s\n', out_path))
