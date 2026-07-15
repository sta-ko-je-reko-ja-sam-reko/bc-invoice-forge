//! Backoff + retry helpers for BC throttling (HTTP 429) and transient errors.

use std::time::Duration;

/// Exponential backoff with a cap. Real impl should also honor a server-sent
/// `Retry-After` header when present.
pub fn backoff_delay(attempt: u32) -> Duration {
    let base_ms = 250u64;
    let max_ms = 30_000u64;
    let ms = base_ms.saturating_mul(1u64 << attempt.min(7)).min(max_ms);
    Duration::from_millis(ms)
}

/// Whether an HTTP status is worth retrying.
pub fn is_retryable(status: u16) -> bool {
    matches!(status, 429 | 500 | 502 | 503 | 504)
}
