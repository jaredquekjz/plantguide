// Web handlers for HTML page rendering

#[cfg(feature = "api")]
mod pages;

#[cfg(feature = "api")]
pub use pages::*;
