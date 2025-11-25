use crate::explanation::types::Explanation;
use serde_json;

/// JSON formatter for explanations
pub struct JsonFormatter;

impl JsonFormatter {
    /// Format explanation as pretty-printed JSON
    pub fn format(explanation: &Explanation) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(explanation)
    }

    /// Format explanation as compact JSON (no whitespace)
    pub fn format_compact(explanation: &Explanation) -> Result<String, serde_json::Error> {
        serde_json::to_string(explanation)
    }
}
