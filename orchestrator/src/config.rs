//! Configuration loaded from environment (see .env.example).

pub struct Config {
    pub tenant_id: String,
    pub client_id: String,
    pub client_secret: String,
    pub environment: String,
    pub company_id: String,
    pub api_base_url: String,
    /// OAuth2 token endpoint. Defaults to Azure AD; override (BC_TOKEN_URL) to
    /// point at a mock/proxy for local end-to-end runs and benchmarking.
    pub token_url: String,
    pub import_chunk_size: usize,
    pub max_concurrent_chunks: usize,
    /// Max invoices imported into BC concurrently (bounded backpressure).
    pub import_concurrency: usize,
    /// If true, an invoice whose party can't be mapped to a BC number fails
    /// instead of passing the source id through unchanged.
    pub require_party_mapping: bool,
    /// Same, for line-item codes.
    pub require_item_mapping: bool,
    /// Validate documents against synced BC reference data (ref_entity) before
    /// import, so unknown customers/vendors/items are caught without hitting BC.
    /// Requires reference data to be synced first.
    pub validate_references: bool,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        fn req(key: &str) -> anyhow::Result<String> {
            std::env::var(key).map_err(|_| anyhow::anyhow!("missing env var {key}"))
        }
        fn opt_usize(key: &str, default: usize) -> usize {
            std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
        }
        fn opt_bool(key: &str, default: bool) -> bool {
            std::env::var(key)
                .ok()
                .map(|v| matches!(v.trim().to_lowercase().as_str(), "1" | "true" | "yes"))
                .unwrap_or(default)
        }

        let tenant_id = req("BC_TENANT_ID")?;
        let token_url = std::env::var("BC_TOKEN_URL").unwrap_or_else(|_| {
            format!("https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token")
        });

        Ok(Self {
            client_id: req("BC_CLIENT_ID")?,
            client_secret: req("BC_CLIENT_SECRET")?,
            environment: req("BC_ENVIRONMENT")?,
            company_id: req("BC_COMPANY_ID")?,
            api_base_url: req("BC_API_BASE_URL")?,
            token_url,
            tenant_id,
            import_chunk_size: opt_usize("IMPORT_CHUNK_SIZE", 200),
            max_concurrent_chunks: opt_usize("MAX_CONCURRENT_CHUNKS", 4),
            import_concurrency: opt_usize("IMPORT_CONCURRENCY", 8),
            require_party_mapping: opt_bool("REQUIRE_PARTY_MAPPING", false),
            require_item_mapping: opt_bool("REQUIRE_ITEM_MAPPING", false),
            validate_references: opt_bool("VALIDATE_REFERENCES", false),
        })
    }
}
