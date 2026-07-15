//! Business Central API client.
//!
//! Implements OAuth2 client-credentials auth against Azure AD, a real
//! `salesInvoices` import (header + lines) against the standard v2.0 API, and
//! create/trigger of the custom `batchPostJobs` API exposed by the AL
//! extension. Honors HTTP 429 with a single `Retry-After`-aware retry per call;
//! the orchestrator adds broader backoff.

use std::sync::Arc;

use ingestion::{Invoice, InvoiceLine};
use serde::Deserialize;

use crate::config::Config;
use crate::retry;
use crate::throttle::AdaptiveLimiter;

pub struct BcClient {
    http: reqwest::Client,
    access_token: String,
    /// e.g. https://api.businesscentral.dynamics.com/v2.0/{tenant}/{env}
    env_root: String,
    company_id: String,
    /// Fed 429/success signals so it can tune concurrency (AIMD).
    limiter: Arc<AdaptiveLimiter>,
}

#[derive(Debug, Deserialize)]
struct TokenResponse {
    access_token: String,
}

/// Result of creating a draft invoice in BC.
#[derive(Debug, Clone)]
pub struct CreatedInvoice {
    /// BC systemId (GUID) — parent for lines and posting.
    pub id: String,
    /// BC document number (e.g. from the sales number series).
    pub number: String,
}

impl BcClient {
    /// Authenticate (client credentials) and build a ready-to-use client.
    pub async fn authenticate(cfg: &Config, limiter: Arc<AdaptiveLimiter>) -> anyhow::Result<Self> {
        let http = reqwest::Client::builder().build()?;

        let scope = "https://api.businesscentral.dynamics.com/.default";

        let resp = http
            .post(&cfg.token_url)
            .form(&[
                ("grant_type", "client_credentials"),
                ("client_id", &cfg.client_id),
                ("client_secret", &cfg.client_secret),
                ("scope", scope),
            ])
            .send()
            .await?
            .error_for_status()?
            .json::<TokenResponse>()
            .await?;

        // base already ends at /v2.0 -> append /{tenant}/{env}
        let env_root = format!(
            "{}/{}/{}",
            cfg.api_base_url.trim_end_matches('/'),
            cfg.tenant_id,
            cfg.environment
        );

        Ok(Self {
            http,
            access_token: resp.access_token,
            env_root,
            company_id: cfg.company_id.clone(),
            limiter,
        })
    }

    /// URL under the standard v2.0 automation API.
    fn std_url(&self, entity: &str) -> String {
        format!(
            "{}/api/v2.0/companies({})/{}",
            self.env_root, self.company_id, entity
        )
    }

    /// URL under the extension's custom API (publisher=bif, group=invoiceForge).
    fn bif_url(&self, entity: &str) -> String {
        format!(
            "{}/api/bif/invoiceForge/v1.0/companies({})/{}",
            self.env_root, self.company_id, entity
        )
    }

    /// POST JSON with one 429-aware retry, returning the parsed JSON body.
    async fn post_json(&self, url: &str, body: &serde_json::Value) -> anyhow::Result<serde_json::Value> {
        for attempt in 0..2u32 {
            let resp = self
                .http
                .post(url)
                .bearer_auth(&self.access_token)
                .json(body)
                .send()
                .await?;

            let status = resp.status().as_u16();
            if retry::is_retryable(status) && attempt == 0 {
                self.limiter.report_throttled();
                let wait = resp
                    .headers()
                    .get(reqwest::header::RETRY_AFTER)
                    .and_then(|v| v.to_str().ok())
                    .and_then(|s| s.parse::<u64>().ok())
                    .map(std::time::Duration::from_secs)
                    .unwrap_or_else(|| retry::backoff_delay(attempt));
                tracing::warn!(status, ?wait, "retrying after throttle");
                tokio::time::sleep(wait).await;
                continue;
            }

            let resp = resp.error_for_status()?;
            self.limiter.report_ok();
            // 204 No Content (bound actions) yields an empty body.
            let text = resp.text().await?;
            if text.is_empty() {
                return Ok(serde_json::Value::Null);
            }
            return Ok(serde_json::from_str(&text)?);
        }
        anyhow::bail!("request to {url} failed after retry")
    }

    /// Create a draft sales invoice (header + lines) from a canonical invoice.
    pub async fn create_sales_invoice(&self, inv: &Invoice) -> anyhow::Result<CreatedInvoice> {
        let header = serde_json::json!({
            "externalDocumentNumber": inv.external_document_no,
            "customerNumber": inv.partner_no,
            "invoiceDate": inv.document_date,
            "currencyCode": inv.currency_code,
        });

        let created = self.post_json(&self.std_url("salesInvoices"), &header).await?;

        let id = created
            .get("id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("BC response missing invoice id"))?
            .to_string();
        let number = created
            .get("number")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();

        for line in &inv.lines {
            self.create_sales_line(&id, line).await?;
        }

        Ok(CreatedInvoice { id, number })
    }

    async fn create_sales_line(&self, document_id: &str, line: &InvoiceLine) -> anyhow::Result<()> {
        let body = serde_json::json!({
            "documentId": document_id,
            "lineType": "Item",
            "lineObjectNumber": line.no,
            "quantity": line.quantity,
            "unitPrice": line.unit_price,
        });
        self.post_json(&self.std_url("salesInvoiceLines"), &body).await?;
        Ok(())
    }

    /// Create a draft purchase invoice (header + lines) from a canonical invoice.
    pub async fn create_purchase_invoice(&self, inv: &Invoice) -> anyhow::Result<CreatedInvoice> {
        let header = serde_json::json!({
            "vendorInvoiceNumber": inv.external_document_no,
            "vendorNumber": inv.partner_no,
            "invoiceDate": inv.document_date,
            "currencyCode": inv.currency_code,
        });

        let created = self.post_json(&self.std_url("purchaseInvoices"), &header).await?;

        let id = created
            .get("id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("BC response missing invoice id"))?
            .to_string();
        let number = created
            .get("number")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();

        for line in &inv.lines {
            self.create_purchase_line(&id, line).await?;
        }

        Ok(CreatedInvoice { id, number })
    }

    async fn create_purchase_line(&self, document_id: &str, line: &InvoiceLine) -> anyhow::Result<()> {
        let body = serde_json::json!({
            "documentId": document_id,
            "lineType": "Item",
            "lineObjectNumber": line.no,
            "quantity": line.quantity,
            "directUnitCost": line.unit_price,
        });
        self.post_json(&self.std_url("purchaseInvoiceLines"), &body).await?;
        Ok(())
    }

    /// Stamp the batch code onto an imported purchase invoice (by systemId).
    pub async fn tag_purchase_invoice(&self, id: &str, batch_code: &str) -> anyhow::Result<()> {
        let url = format!("{}({})", self.bif_url("purchaseInvoiceTags"), id);
        self.patch_json(&url, &serde_json::json!({ "batchCode": batch_code }))
            .await
    }

    /// Create a draft service invoice (header + lines) via the custom API.
    /// Service has no standard automation entity, so the batch code is set
    /// directly on the header here (no separate tag call).
    pub async fn create_service_invoice(
        &self,
        inv: &Invoice,
        batch_code: &str,
    ) -> anyhow::Result<CreatedInvoice> {
        let header = serde_json::json!({
            "customerNumber": inv.partner_no,
            "documentDate": inv.document_date,
            "currencyCode": inv.currency_code,
            "externalDocumentNo": inv.external_document_no,
            "batchCode": batch_code,
        });

        let created = self.post_json(&self.bif_url("serviceInvoices"), &header).await?;

        let id = created
            .get("id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("BC response missing invoice id"))?
            .to_string();
        let number = created
            .get("number")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();

        // Service lines link to their header by document number.
        for line in &inv.lines {
            self.create_service_line(&number, line).await?;
        }

        Ok(CreatedInvoice { id, number })
    }

    async fn create_service_line(&self, document_no: &str, line: &InvoiceLine) -> anyhow::Result<()> {
        let body = serde_json::json!({
            "documentNo": document_no,
            "lineType": "Item",
            "number": line.no,
            "quantity": line.quantity,
            "unitPrice": line.unit_price,
        });
        self.post_json(&self.bif_url("serviceInvoiceLines"), &body).await?;
        Ok(())
    }

    // --- Order kinds (custom API pages; batch code set inline on the header) ---
    // NOTE: field sets are templated and need sandbox confirmation. Type-specific
    // data (locations, in-transit, routing) rides in header_fields/line_fields,
    // populated by source-specific parsers; absent fields surface as BC errors.

    fn id_and_number(created: &serde_json::Value) -> anyhow::Result<(String, String)> {
        let id = created
            .get("id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("BC response missing id"))?
            .to_string();
        let number = created
            .get("number")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        Ok((id, number))
    }

    /// Create a purchase order (header + lines).
    pub async fn create_purchase_order(&self, inv: &Invoice, batch_code: &str) -> anyhow::Result<CreatedInvoice> {
        let header = serde_json::json!({
            "vendorNumber": inv.partner_no,
            "orderDate": inv.document_date,
            "currencyCode": inv.currency_code,
            "externalDocumentNo": inv.external_document_no,
            "batchCode": batch_code,
        });
        let created = self.post_json(&self.bif_url("purchaseOrders"), &header).await?;
        let (id, number) = Self::id_and_number(&created)?;
        for line in &inv.lines {
            let body = serde_json::json!({
                "documentNo": number,
                "lineType": "Item",
                "number": line.no,
                "quantity": line.quantity,
                "directUnitCost": line.unit_price,
            });
            self.post_json(&self.bif_url("purchaseOrderLines"), &body).await?;
        }
        Ok(CreatedInvoice { id, number })
    }

    /// Create an assembly order (header item + quantity; BOM explodes in BC).
    pub async fn create_assembly_order(&self, inv: &Invoice, batch_code: &str) -> anyhow::Result<CreatedInvoice> {
        let first = inv.lines.first().ok_or_else(|| anyhow::anyhow!("assembly order has no item line"))?;
        let header = serde_json::json!({
            "itemNo": first.no,
            "quantity": first.quantity,
            "dueDate": inv.document_date,
            "locationCode": inv.header_fields.get("location").cloned().unwrap_or_default(),
            "externalDocumentNo": inv.external_document_no,
            "batchCode": batch_code,
        });
        let created = self.post_json(&self.bif_url("assemblyOrders"), &header).await?;
        let (id, number) = Self::id_and_number(&created)?;
        Ok(CreatedInvoice { id, number })
    }

    /// Create a production order (header source item + quantity; refresh in BC — TODO).
    pub async fn create_production_order(&self, inv: &Invoice, batch_code: &str) -> anyhow::Result<CreatedInvoice> {
        let first = inv.lines.first().ok_or_else(|| anyhow::anyhow!("production order has no item line"))?;
        let header = serde_json::json!({
            "sourceNo": first.no,
            "quantity": first.quantity,
            "dueDate": inv.document_date,
            "locationCode": inv.header_fields.get("location").cloned().unwrap_or_default(),
            "externalDocumentNo": inv.external_document_no,
            "batchCode": batch_code,
        });
        let created = self.post_json(&self.bif_url("productionOrders"), &header).await?;
        let (id, number) = Self::id_and_number(&created)?;
        Ok(CreatedInvoice { id, number })
    }

    /// Create a transfer order (header from/to + lines).
    pub async fn create_transfer_order(&self, inv: &Invoice, batch_code: &str) -> anyhow::Result<CreatedInvoice> {
        let header = serde_json::json!({
            "transferFromCode": inv.header_fields.get("transfer_from").cloned().unwrap_or_default(),
            "transferToCode": inv.header_fields.get("transfer_to").cloned().unwrap_or_default(),
            "inTransitCode": inv.header_fields.get("in_transit").cloned().unwrap_or_default(),
            "postingDate": inv.document_date,
            "externalDocumentNo": inv.external_document_no,
            "batchCode": batch_code,
        });
        let created = self.post_json(&self.bif_url("transferOrders"), &header).await?;
        let (id, number) = Self::id_and_number(&created)?;
        for line in &inv.lines {
            let body = serde_json::json!({
                "documentNo": number,
                "itemNo": line.no,
                "quantity": line.quantity,
            });
            self.post_json(&self.bif_url("transferOrderLines"), &body).await?;
        }
        Ok(CreatedInvoice { id, number })
    }

    /// Create a batch-post job row via the custom API. Returns its systemId.
    pub async fn create_batch_post_job(
        &self,
        batch_code: &str,
        doc_type: &str,
    ) -> anyhow::Result<String> {
        let body = serde_json::json!({ "batchCode": batch_code, "docType": doc_type });
        let created = self.post_json(&self.bif_url("batchPostJobs"), &body).await?;
        created
            .get("id")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .ok_or_else(|| anyhow::anyhow!("batchPostJob response missing id"))
    }

    /// Trigger server-side posting for a job via its bound `run` action.
    /// Returns fast; the AL side posts asynchronously in a background session.
    pub async fn run_batch_post_job(&self, job_id: &str) -> anyhow::Result<()> {
        let url = format!("{}({})/Microsoft.NAV.run", self.bif_url("batchPostJobs"), job_id);
        self.post_json(&url, &serde_json::json!({})).await?;
        Ok(())
    }

    /// Post a single already-created sales invoice via the standard bound
    /// action. Kept for smoke tests; bulk posting uses the batch job above.
    pub async fn post_sales_invoice(&self, id: &str) -> anyhow::Result<()> {
        let url = format!("{}({})/Microsoft.NAV.post", self.std_url("salesInvoices"), id);
        self.post_json(&url, &serde_json::json!({})).await?;
        Ok(())
    }

    /// PATCH JSON with a wildcard If-Match (single 429-aware retry).
    async fn patch_json(&self, url: &str, body: &serde_json::Value) -> anyhow::Result<()> {
        for attempt in 0..2u32 {
            let resp = self
                .http
                .patch(url)
                .bearer_auth(&self.access_token)
                .header(reqwest::header::IF_MATCH, "*")
                .json(body)
                .send()
                .await?;

            let status = resp.status().as_u16();
            if retry::is_retryable(status) && attempt == 0 {
                self.limiter.report_throttled();
                tokio::time::sleep(retry::backoff_delay(attempt)).await;
                continue;
            }
            resp.error_for_status()?;
            self.limiter.report_ok();
            return Ok(());
        }
        anyhow::bail!("PATCH {url} failed after retry")
    }

    /// Stamp the batch code onto an imported sales invoice (by systemId) so the
    /// AL batch-post job can filter it.
    pub async fn tag_sales_invoice(&self, id: &str, batch_code: &str) -> anyhow::Result<()> {
        let url = format!("{}({})", self.bif_url("salesInvoiceTags"), id);
        self.patch_json(&url, &serde_json::json!({ "batchCode": batch_code }))
            .await
    }

    /// GET JSON with one 429-aware retry.
    async fn get_json(&self, url: &str) -> anyhow::Result<serde_json::Value> {
        for attempt in 0..2u32 {
            let resp = self.http.get(url).bearer_auth(&self.access_token).send().await?;
            let status = resp.status().as_u16();
            if retry::is_retryable(status) && attempt == 0 {
                self.limiter.report_throttled();
                tokio::time::sleep(retry::backoff_delay(attempt)).await;
                continue;
            }
            let resp = resp.error_for_status()?;
            self.limiter.report_ok();
            return Ok(resp.json::<serde_json::Value>().await?);
        }
        anyhow::bail!("GET {url} failed after retry")
    }

    /// Read a batch-post job's current state (status + counts).
    pub async fn get_batch_post_job(&self, id: &str) -> anyhow::Result<serde_json::Value> {
        self.get_json(&format!("{}({})", self.bif_url("batchPostJobs"), id))
            .await
    }

    /// List per-document posting results for a batch code (OData collection).
    pub async fn list_post_results(&self, batch_code: &str) -> anyhow::Result<serde_json::Value> {
        let url = format!(
            "{}?$filter=batchCode eq '{}'",
            self.bif_url("postResults"),
            batch_code
        );
        self.get_json(&url).await
    }

    /// List all rows of a standard reference entity (customers/vendors/items),
    /// following OData `@odata.nextLink` pagination. Returns (number, displayName).
    pub async fn list_reference(&self, entity: &str) -> anyhow::Result<Vec<(String, Option<String>)>> {
        let mut url = self.std_url(entity);
        let mut out = Vec::new();

        loop {
            let json = self.get_json(&url).await?;
            if let Some(arr) = json.get("value").and_then(|v| v.as_array()) {
                for item in arr {
                    if let Some(no) = item.get("number").and_then(|v| v.as_str()) {
                        let name = item
                            .get("displayName")
                            .and_then(|v| v.as_str())
                            .map(str::to_string);
                        out.push((no.to_string(), name));
                    }
                }
            }
            match json.get("@odata.nextLink").and_then(|v| v.as_str()) {
                Some(next) => url = next.to_string(),
                None => break,
            }
        }
        Ok(out)
    }
}
