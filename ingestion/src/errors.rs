//! Document error model — the shape stored in `document_error`.
//!
//! One document accumulates many of these (header and/or per-line), from
//! external validation and from BC posting. They live in Postgres, never in BC.

/// Where the error applies.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorScope {
    Header,
    Line,
}

impl ErrorScope {
    pub fn as_str(&self) -> &'static str {
        match self {
            ErrorScope::Header => "header",
            ErrorScope::Line => "line",
        }
    }
}

/// Who produced the error.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorSource {
    /// Caught externally (fields, reference data) before touching BC.
    Validation,
    /// Returned by BC during import/post.
    Bc,
}

impl ErrorSource {
    pub fn as_str(&self) -> &'static str {
        match self {
            ErrorSource::Validation => "validation",
            ErrorSource::Bc => "bc",
        }
    }
}

/// A single error against a document.
#[derive(Debug, Clone)]
pub struct DocError {
    pub scope: ErrorScope,
    /// 1-based line number for line-scope errors; None for header.
    pub line_no: Option<i32>,
    pub field: Option<String>,
    pub code: String,
    pub message: String,
    pub source: ErrorSource,
}

impl DocError {
    /// Header-scope validation error.
    pub fn header(code: &str, field: Option<&str>, message: impl Into<String>) -> Self {
        Self {
            scope: ErrorScope::Header,
            line_no: None,
            field: field.map(str::to_string),
            code: code.to_string(),
            message: message.into(),
            source: ErrorSource::Validation,
        }
    }

    /// Line-scope validation error (1-based line number).
    pub fn line(line_no: i32, code: &str, field: Option<&str>, message: impl Into<String>) -> Self {
        Self {
            scope: ErrorScope::Line,
            line_no: Some(line_no),
            field: field.map(str::to_string),
            code: code.to_string(),
            message: message.into(),
            source: ErrorSource::Validation,
        }
    }

    /// Error returned by BC during import/post (header-scope).
    pub fn bc(message: impl Into<String>) -> Self {
        Self {
            scope: ErrorScope::Header,
            line_no: None,
            field: None,
            code: "BC_ERROR".to_string(),
            message: message.into(),
            source: ErrorSource::Bc,
        }
    }
}
