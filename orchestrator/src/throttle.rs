//! Adaptive concurrency limiter (AIMD, like TCP congestion control).
//!
//! Starts at a configured concurrency and **multiplicatively decreases** on a
//! 429, then **additively increases** back toward the ceiling as calls succeed.
//! Concurrency is enforced by a semaphore; import tasks hold a permit for the
//! duration of one invoice, and the BC client reports throttle/success events.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use tokio::sync::{OwnedSemaphorePermit, Semaphore};

/// Successful calls between additive-increase steps.
const INCREASE_EVERY: usize = 20;

pub struct AdaptiveLimiter {
    sem: Arc<Semaphore>,
    target: AtomicUsize,
    since_change: AtomicUsize,
    min: usize,
    max: usize,
}

impl AdaptiveLimiter {
    /// Build a limiter starting at `initial`, bounded to `[1, initial]`.
    pub fn new(initial: usize) -> Arc<Self> {
        let max = initial.max(1);
        let sem = Arc::new(Semaphore::new(max));
        Arc::new(Self {
            sem,
            target: AtomicUsize::new(max),
            since_change: AtomicUsize::new(0),
            min: 1,
            max,
        })
    }

    /// Upper bound on concurrency (use as the `buffer_unordered` cap).
    pub fn max(&self) -> usize {
        self.max
    }

    /// Acquire a permit; held for the duration of one unit of work.
    pub async fn acquire(self: &Arc<Self>) -> OwnedSemaphorePermit {
        self.sem
            .clone()
            .acquire_owned()
            .await
            .expect("throttle semaphore closed")
    }

    /// Report a successful call — additively increase every `INCREASE_EVERY`.
    pub fn report_ok(&self) {
        let n = self.since_change.fetch_add(1, Ordering::Relaxed) + 1;
        if n < INCREASE_EVERY {
            return;
        }
        self.since_change.store(0, Ordering::Relaxed);

        // CAS so a concurrent increase/decrease can't push target past its bounds.
        let mut t = self.target.load(Ordering::Relaxed);
        loop {
            if t >= self.max {
                return;
            }
            match self.target.compare_exchange_weak(t, t + 1, Ordering::Relaxed, Ordering::Relaxed) {
                Ok(_) => {
                    self.sem.add_permits(1);
                    tracing::debug!(target = t + 1, "throttle: increase");
                    return;
                }
                Err(actual) => t = actual,
            }
        }
    }

    /// Report a 429 — multiplicatively decrease (halve toward `min`).
    pub fn report_throttled(self: &Arc<Self>) {
        self.since_change.store(0, Ordering::Relaxed);

        // CAS the halving so concurrent 429s each commit a distinct decrement
        // and we never remove more permits than we actually reduced target by.
        let mut t = self.target.load(Ordering::Relaxed);
        let new = loop {
            let candidate = (t / 2).max(self.min);
            if candidate >= t {
                return;
            }
            match self.target.compare_exchange_weak(t, candidate, Ordering::Relaxed, Ordering::Relaxed) {
                Ok(_) => break candidate,
                Err(actual) => t = actual,
            }
        };
        let remove = t - new;

        // Removing permits may need to wait for in-flight work to release them,
        // so do it off the caller's path.
        let this = Arc::clone(self);
        tokio::spawn(async move {
            for _ in 0..remove {
                if let Ok(permit) = this.sem.clone().acquire_owned().await {
                    permit.forget();
                }
            }
            tracing::debug!(target = new, "throttle: decrease");
        });
    }
}
