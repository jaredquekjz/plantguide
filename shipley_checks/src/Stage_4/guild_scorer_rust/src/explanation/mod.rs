pub mod types;
pub mod fragments;
pub mod nitrogen;
pub mod soil_ph;
pub mod pest_analysis;
pub mod fungi_network_analysis;
pub mod pollinator_network_analysis;
pub mod biocontrol_network_analysis;
pub mod pathogen_control_network_analysis;
pub mod csr_strategy_analysis;
pub mod taxonomic_profile_analysis;
pub mod unified_taxonomy;
pub mod generator;
pub mod formatters;
pub mod ecosystem_services;

pub use types::{
    BenefitCard, ClimateExplanation, Explanation, MetricCard, MetricFragment, MetricsDisplay,
    OverallExplanation, RiskCard, Severity, WarningCard,
};

pub use fragments::{
    generate_m1_fragment, generate_m2_fragment, generate_m3_fragment, generate_m4_fragment,
    generate_m5_fragment, generate_m6_fragment, generate_m7_fragment,
};

pub use nitrogen::check_nitrogen_fixation;
pub use soil_ph::check_soil_ph_compatibility;
pub use pest_analysis::{analyze_guild_pests, PestProfile};
pub use fungi_network_analysis::{analyze_fungi_network, FungiNetworkProfile};
pub use pollinator_network_analysis::{analyze_pollinator_network, PollinatorNetworkProfile};
pub use biocontrol_network_analysis::{analyze_biocontrol_network, BiocontrolNetworkProfile};
pub use pathogen_control_network_analysis::{analyze_pathogen_control_network, PathogenControlNetworkProfile};
pub use csr_strategy_analysis::{analyze_csr_strategies, CsrStrategyProfile};
pub use taxonomic_profile_analysis::{analyze_taxonomic_diversity, TaxonomicProfile};

pub use generator::ExplanationGenerator;
pub use formatters::{HtmlFormatter, JsonFormatter, MarkdownFormatter};
