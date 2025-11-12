pub mod types;
pub mod fragments;
pub mod nitrogen;
pub mod soil_ph;
pub mod generator;
pub mod formatters;

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

pub use generator::ExplanationGenerator;
pub use formatters::{HtmlFormatter, JsonFormatter, MarkdownFormatter};
