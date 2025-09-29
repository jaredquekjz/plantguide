import pandas as pd
import gzip
import csv
from collections import defaultdict, Counter
from pathlib import Path
from unidecode import unidecode
import builtins

print = lambda *args, **kwargs: builtins.print(*args, flush=True, **kwargs)


def normalize(name):
    if not isinstance(name, str):
        return None
    name = name.strip()
    if not name or name.lower() == "nan":
        return None
    return unidecode(name).strip().lower()


def build_name_mapping(stage3_path: Path, classification_path: Path):
    print("Loading Stage 3 species...")
    stage3 = pd.read_csv(stage3_path, usecols=["wfo_accepted_name"]).drop_duplicates()
    stage3["wfo_accepted_name"] = stage3["wfo_accepted_name"].astype(str).str.strip()

    print("Loading WFO classification (this may take a moment)...")
    wfo = pd.read_csv(
        classification_path,
        sep="\t",
        dtype=str,
        encoding_errors="ignore",
    )
    wfo["scientificName"] = wfo["scientificName"].astype(str).str.strip('"').str.strip()
    wfo["binomial"] = (wfo["genus"].fillna("") + " " + wfo["specificEpithet"].fillna("")).str.strip()
    wfo["binomial_norm"] = wfo["binomial"].apply(normalize)
    wfo["scientific_norm"] = wfo["scientificName"].apply(normalize)

    print("Building synonym mapping...")
    name_to_acc = {}

    accepted_mask = wfo["taxonomicStatus"] == "Accepted"
    accepted_lookup = dict(
        zip(
            wfo.loc[accepted_mask, "taxonID"],
            wfo.loc[accepted_mask, "binomial"],
        )
    )

    for _, row in wfo.iterrows():
        accepted_id = row.get("acceptedNameUsageID")
        binom_norm = row["binomial_norm"]
        sci_norm = row["scientific_norm"]
        if not binom_norm:
            continue
        if row["taxonomicStatus"] == "Accepted":
            name_to_acc[binom_norm] = row["binomial"]
        elif accepted_id and accepted_id in accepted_lookup:
            name_to_acc[binom_norm] = accepted_lookup[accepted_id]
        elif row["scientific_norm"]:
            name_to_acc[binom_norm] = row["binomial"]
        if sci_norm and row["binomial"]:
            name_to_acc[sci_norm] = row["binomial"]

    print(f"Synonym map entries: {len(name_to_acc):,}")

    stage3_synonyms = {}
    for name in stage3["wfo_accepted_name"]:
        norm = normalize(name)
        syns = set()
        if norm and norm in name_to_acc:
            accepted = name_to_acc[norm]
            syns.add(normalize(accepted))
        else:
            accepted = name
            syns.add(norm)
        mask = wfo["binomial"] == accepted
        for _, row in wfo.loc[mask].iterrows():
            syns.add(row["binomial_norm"])
            syns.add(row["scientific_norm"])
        stage3_synonyms[name] = {s for s in syns if s}

    name_to_wfo = {}
    for accepted, syns in stage3_synonyms.items():
        for variant in syns:
            name_to_wfo[variant] = accepted

    print(f"Total synonym variants mapped: {len(name_to_wfo):,}")
    return stage3, name_to_wfo


def stream_interactions(interactions_path: Path, name_to_wfo: dict, raw_path: Path):
    total_records = Counter()
    source_records = Counter()
    target_records = Counter()
    unique_partners = defaultdict(set)
    partner_kingdoms = defaultdict(set)
    interaction_types = defaultdict(set)

    categories = ["pollination", "herbivory", "dispersal", "pathogen"]
    category_records = {cat: Counter() for cat in categories}
    category_partner_sets = {cat: defaultdict(set) for cat in categories}
    category_counters = {cat: defaultdict(Counter) for cat in categories}

    pollination_types = {"pollinates", "visitsflowersof"}
    herbivory_types = {"eats", "preyson", "iseatenby", "ispreyedonby", "ispreyeduponby"}
    dispersal_types = {"disperses", "dispersesseedsof"}
    pathogen_types = {
        "parasiteof",
        "pathogenof",
        "endoparasiteof",
        "ectoparasiteof",
        "parasitoidof",
        "hasparasite",
        "haspathogen",
        "hashost",
    }

    chunk_size = 200_000
    rows_processed = 0
    interactions_written = 0

    print("Streaming GloBI interactions...")
    with gzip.open(interactions_path, "rt") as gz, gzip.open(raw_path, "wt", newline="") as raw_out:
        writer = csv.writer(raw_out)
        writer.writerow(
            [
                "wfo_accepted_name",
                "role",
                "interaction_type",
                "partner_name",
                "partner_kingdom",
                "partner_family",
                "source_taxon_name",
                "target_taxon_name",
                "reference_doi",
                "reference_url",
            ]
        )

        for chunk in pd.read_csv(
            gz,
            chunksize=chunk_size,
            usecols=[
                "sourceTaxonName",
                "sourceTaxonKingdomName",
                "sourceTaxonFamilyName",
                "targetTaxonName",
                "targetTaxonKingdomName",
                "targetTaxonFamilyName",
                "interactionTypeName",
                "referenceDoi",
                "referenceUrl",
            ],
            dtype=str,
            low_memory=False,
        ):
            rows_processed += len(chunk)
            chunk = chunk.fillna("")

            source_norm = chunk["sourceTaxonName"].apply(normalize)
            target_norm = chunk["targetTaxonName"].apply(normalize)

            source_idx = [i for i, name in enumerate(source_norm) if name and name in name_to_wfo]
            target_idx = [i for i, name in enumerate(target_norm) if name and name in name_to_wfo]

            for idx in source_idx:
                plant = name_to_wfo[source_norm.iloc[idx]]
                partner_name = chunk.iloc[idx]["targetTaxonName"].strip()
                if not partner_name:
                    continue
                partner_kingdom = chunk.iloc[idx]["targetTaxonKingdomName"].strip()
                partner_family = chunk.iloc[idx]["targetTaxonFamilyName"].strip()
                interaction_type = chunk.iloc[idx]["interactionTypeName"].strip()
                reference_doi = chunk.iloc[idx]["referenceDoi"].strip()
                reference_url = chunk.iloc[idx]["referenceUrl"].strip()

                writer.writerow(
                    [
                        plant,
                        "source",
                        interaction_type,
                        partner_name,
                        partner_kingdom,
                        partner_family,
                        chunk.iloc[idx]["sourceTaxonName"],
                        chunk.iloc[idx]["targetTaxonName"],
                        reference_doi,
                        reference_url,
                    ]
                )
                interactions_written += 1
                total_records[plant] += 1
                source_records[plant] += 1
                unique_partners[plant].add(partner_name)
                if partner_kingdom:
                    partner_kingdoms[plant].add(partner_kingdom)
                interaction_types[plant].add(interaction_type)

                itype_norm = normalize(interaction_type)
                if itype_norm in pollination_types:
                    category_records["pollination"][plant] += 1
                    category_partner_sets["pollination"][plant].add(partner_name)
                    category_counters["pollination"][plant][partner_name] += 1
                if itype_norm in {"iseatenby", "ispreyedonby", "ispreyeduponby"}:
                    category_records["herbivory"][plant] += 1
                    category_partner_sets["herbivory"][plant].add(partner_name)
                    category_counters["herbivory"][plant][partner_name] += 1
                if itype_norm in dispersal_types:
                    category_records["dispersal"][plant] += 1
                    category_partner_sets["dispersal"][plant].add(partner_name)
                    category_counters["dispersal"][plant][partner_name] += 1
                if (
                    itype_norm in pathogen_types
                    and itype_norm not in {"hasparasite", "haspathogen", "hashost"}
                ):
                    category_records["pathogen"][plant] += 1
                    category_partner_sets["pathogen"][plant].add(partner_name)
                    category_counters["pathogen"][plant][partner_name] += 1

            for idx in target_idx:
                plant = name_to_wfo[target_norm.iloc[idx]]
                partner_name = chunk.iloc[idx]["sourceTaxonName"].strip()
                if not partner_name:
                    continue
                partner_kingdom = chunk.iloc[idx]["sourceTaxonKingdomName"].strip()
                partner_family = chunk.iloc[idx]["sourceTaxonFamilyName"].strip()
                interaction_type = chunk.iloc[idx]["interactionTypeName"].strip()
                reference_doi = chunk.iloc[idx]["referenceDoi"].strip()
                reference_url = chunk.iloc[idx]["referenceUrl"].strip()

                writer.writerow(
                    [
                        plant,
                        "target",
                        interaction_type,
                        partner_name,
                        partner_kingdom,
                        partner_family,
                        chunk.iloc[idx]["sourceTaxonName"],
                        chunk.iloc[idx]["targetTaxonName"],
                        reference_doi,
                        reference_url,
                    ]
                )
                interactions_written += 1
                total_records[plant] += 1
                target_records[plant] += 1
                unique_partners[plant].add(partner_name)
                if partner_kingdom:
                    partner_kingdoms[plant].add(partner_kingdom)
                interaction_types[plant].add(interaction_type)

                itype_norm = normalize(interaction_type)
                if itype_norm in pollination_types:
                    category_records["pollination"][plant] += 1
                    category_partner_sets["pollination"][plant].add(partner_name)
                    category_counters["pollination"][plant][partner_name] += 1
                if itype_norm in {"eats", "preyson"}:
                    category_records["herbivory"][plant] += 1
                    category_partner_sets["herbivory"][plant].add(partner_name)
                    category_counters["herbivory"][plant][partner_name] += 1
                if itype_norm in dispersal_types:
                    category_records["dispersal"][plant] += 1
                    category_partner_sets["dispersal"][plant].add(partner_name)
                    category_counters["dispersal"][plant][partner_name] += 1
                if itype_norm in pathogen_types:
                    category_records["pathogen"][plant] += 1
                    category_partner_sets["pathogen"][plant].add(partner_name)
                    category_counters["pathogen"][plant][partner_name] += 1

            if rows_processed % 1_000_000 == 0:
                print(
                    f"Processed {rows_processed:,} rows, interactions matched: {interactions_written:,}"
                )

    print(f"Completed streaming. Total interactions written: {interactions_written:,}")
    return (
        total_records,
        source_records,
        target_records,
        unique_partners,
        partner_kingdoms,
        interaction_types,
        category_records,
        category_partner_sets,
        category_counters,
    )


def build_summary(stage3, totals, sources, targets, partners, kingdoms, types, cat_records, cat_sets, cat_counts, out_path: Path):
    def top_list(counter, n=5):
        if not counter:
            return ""
        return "; ".join([f"{partner} ({count})" for partner, count in counter.most_common(n)])

    categories = ["pollination", "herbivory", "dispersal", "pathogen"]
    summary_data = []
    for name in stage3["wfo_accepted_name"]:
        row = {
            "wfo_accepted_name": name,
            "globi_total_records": int(totals.get(name, 0)),
            "globi_source_records": int(sources.get(name, 0)),
            "globi_target_records": int(targets.get(name, 0)),
            "globi_unique_partners": len(partners.get(name, set())),
            "globi_partner_kingdoms": len(kingdoms.get(name, set())),
            "globi_interaction_types": "; ".join(sorted(types.get(name, set()))),
        }
        for cat in categories:
            row[f"globi_{cat}_records"] = int(cat_records[cat].get(name, 0))
            row[f"globi_{cat}_partners"] = len(cat_sets[cat].get(name, set()))
            row[f"globi_{cat}_top_partners"] = top_list(cat_counts[cat].get(name, Counter()))
        summary_data.append(row)

    summary_df = pd.DataFrame(summary_data)
    summary_df.to_csv(out_path, index=False)
    print(f"Summary saved to {out_path}")
    return summary_df


def join_with_traits(stage3_path: Path, summary_df: pd.DataFrame, out_path: Path):
    print("Joining with Stage 3 trait table...")
    traits = pd.read_csv(stage3_path)
    merged = traits.merge(summary_df, on="wfo_accepted_name", how="left")

    numeric_cols = [
        col
        for col in summary_df.columns
        if col.startswith("globi_")
        and (
            col.endswith("_records")
            or col.endswith("_partners")
            or col.endswith("_kingdoms")
            or col == "globi_unique_partners"
        )
    ]
    for col in numeric_cols:
        # Robust coercion: convert blanks/strings to NaN, then fill and cast
        if col in merged.columns:
            merged[col] = pd.to_numeric(merged[col], errors="coerce").fillna(0).astype(int)

    text_cols = [
        col
        for col in summary_df.columns
        if col.endswith("_top_partners") or col == "globi_interaction_types"
    ]
    for col in text_cols:
        if col in merged.columns:
            merged[col] = merged[col].fillna("").astype(str)

    merged.to_csv(out_path, index=False)
    print(f"Final dataset saved to {out_path}")


def main():
    base_dir = Path('/home/olier/ellenberg')
    pl_base = Path('/home/olier/plantsdatabase')

    stage3_path = base_dir / 'artifacts/model_data_bioclim_subset_enhanced_augmented_tryraw_imputed_cat.csv'
    classification_path = pl_base / 'data/Stage_1/classification.csv'
    interactions_path = pl_base / 'data/sources/globi/globi_cache/interactions.csv.gz'
    artifacts_dir = base_dir / 'artifacts/globi_mapping'
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    raw_path = artifacts_dir / 'globi_interactions_raw.csv.gz'
    summary_path = artifacts_dir / 'stage3_globi_interaction_features.csv'
    final_path = artifacts_dir / 'stage3_traits_with_globi_features.csv'

    stage3, name_to_wfo = build_name_mapping(stage3_path, classification_path)
    (
        totals,
        sources,
        targets,
        partners,
        kingdoms,
        types,
        cat_records,
        cat_sets,
        cat_counts,
    ) = stream_interactions(interactions_path, name_to_wfo, raw_path)
    summary_df = build_summary(
        stage3,
        totals,
        sources,
        targets,
        partners,
        kingdoms,
        types,
        cat_records,
        cat_sets,
        cat_counts,
        summary_path,
    )
    join_with_traits(stage3_path, summary_df, final_path)
    print('All done!')


if __name__ == "__main__":
    main()
