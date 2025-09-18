# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This R-based scientific pipeline predicts European plant ecological indicator values (EIVE) from functional traits, then converts predictions to gardening recommendations. The pipeline combines structural equation modeling (SEM), phylogenetic analysis, and copula-based uncertainty quantification.

## Environment Setup

- **XGBoost and ML packages**: Use conda environment `AI` for XGBoost and other ML operations
  - Activate: `conda activate AI` or use `conda run -n AI python ...`
  - Contains: XGBoost 3.0.5, scikit-learn, pandas, numpy
- **R packages**: Use custom R library at `/home/olier/ellenberg/.Rlib`
  - Set: `export R_LIBS_USER=/home/olier/ellenberg/.Rlib`

## Style

- Always plan your work systematically, based on thorough checks of context, before executing. Always propose industry best practices for code - no short cuts.
- Always ULTRA THINK for harder problems. 
- For documentation, aim for concise, formal and technical presentation. Include repro commands, precise descriptions and figures. 
- For user conversation, remain non-technical, systematic and easy to understand. 
- For statistical work - ALWAYS use or search for rigorous best practices. If unsure - confirm with user.
- Do not create new files endlessly - aim to use back the same script - adding flags and/or extending the functionality and modularity of an existing script. Or for documentation, aim to extend, instead of to create new documentation unless explcitly asked for.
- Always test your code appropriately BEFORE promising completion or solutions. Clear up any test scripts after use. 
- Do not clutter repository - always put things into logical folders and sub-folders.
- Execute commands that may take a long while in tmux (15 minutes etc.), and ask user to help monitor. For shorter commands, do not set unrealistic timeouts, then complain things do not work. Set longer timeouts and wait patiently. 

## Git Commit Guidelines

- When creating git commits, DO NOT add Claude Code sign-off or emoji indicators
- Keep commit messages very concise and professional
