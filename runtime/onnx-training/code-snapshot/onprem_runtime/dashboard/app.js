const jobsEl = document.getElementById("jobs");
const bundleInput = document.getElementById("bundleInput");
const publicDatasetsEl = document.getElementById("publicDatasets");
const localFingerprintsEl = document.getElementById("localFingerprints");
const authTokenEl = document.getElementById("authToken");
const authStatusEl = document.getElementById("authStatus");
const runtimeNoticeEl = document.getElementById("runtimeNotice");
const AUTH_STORAGE_KEY = "neuraleseAuthToken";

authTokenEl.value = localStorage.getItem(AUTH_STORAGE_KEY) || "";
authTokenEl.addEventListener("input", () => {
  const token = authTokenEl.value.trim();
  if (token) {
    localStorage.setItem(AUTH_STORAGE_KEY, token);
  } else {
    localStorage.removeItem(AUTH_STORAGE_KEY);
  }
  refresh();
});

bundleInput.addEventListener("change", async () => {
  const file = bundleInput.files[0];
  if (!file) return;
  const form = new FormData();
  form.append("bundle", file);
  const response = await apiFetch("/api/jobs", { method: "POST", body: form });
  bundleInput.value = "";
  if (response.status === 401) {
    authStatusEl.textContent = "Invalid or missing API token.";
    showNotice("Upload failed: enter the API token configured for this runtime.");
    return;
  }
  if (!response.ok) {
    showNotice(`Upload failed: ${await readApiError(response, "Upload failed.")}`);
    return;
  }
  await refresh();
});

async function refresh() {
  const [statsRes, jobsRes, healthRes, capacityRes] = await Promise.all([
    apiFetch("/api/stats"),
    apiFetch("/api/jobs"),
    apiFetch("/api/health"),
    apiFetch("/api/capacity")
  ]);
  if ([statsRes, jobsRes, capacityRes].some(response => response.status === 401)) {
    authStatusEl.textContent = "API token required for runtime data.";
    showNotice("Runtime data is locked. Enter the API token configured for this runtime.");
    return;
  }
  if (![statsRes, jobsRes, healthRes, capacityRes].every(response => response.ok)) {
    const failed = [statsRes, jobsRes, healthRes, capacityRes].find(response => !response.ok);
    showNotice(`Refresh failed: ${await readApiError(failed, "Runtime data could not be loaded.")}`);
    return;
  }
  authStatusEl.textContent = authTokenEl.value.trim()
    ? "Token active for this browser."
    : "Token is stored only in this browser.";
  hideNotice();
  const stats = await statsRes.json();
  const jobs = await jobsRes.json();
  const health = await healthRes.json();
  const capacity = await capacityRes.json();
  document.getElementById("cpu").textContent = `${Math.round(stats.cpu_percent)}%`;
  document.getElementById("memory").textContent = `${Math.round(stats.memory_percent)}%`;
  document.getElementById("activeJobs").textContent = stats.active_jobs;
  document.getElementById("totalJobs").textContent = stats.total_jobs;
  document.getElementById("runtimeMode").textContent = formatMode(health.mode);
  document.getElementById("capacitySlots").textContent = `${capacity.available_slots}/${capacity.max_parallel_jobs}`;
  renderPublicDatasets(capacity.cached_public_datasets || []);
  renderLocalFingerprints(capacity.cached_local_fingerprints || []);
  jobsEl.innerHTML = jobs.map(renderJob).join("");
}

function renderJob(job) {
  const metric = job.latest || {};
  const loss = metric.train_loss === undefined ? "-" : Number(metric.train_loss).toFixed(4);
  const acc = metric.val_acc === undefined ? "-" : `${Math.round(Number(metric.val_acc) * 100)}%`;
  const stop = job.state === "running" ? `<button class="stop" onclick="stopJob('${job.job_id}')">Stop</button>` : "";
  const download = job.snapshot_ready ? `<button class="download" onclick="downloadSnapshot('${job.job_id}')">Download</button>` : "";
  const snapshot = job.snapshot_ready ? "Snapshot ready" : "Snapshot pending";
  const error = metric.error
    ? `<div class="error-message">${escapeHtml(metric.error)}</div>`
    : "";
  return `
    <article class="job">
      <div><strong>${escapeHtml(job.name)}</strong><code>${job.job_id}</code></div>
      <div class="state ${job.state}">${job.state}</div>
      <div class="metric">loss ${loss} · val acc ${acc}</div>
      <div class="snapshot-status ${job.snapshot_ready ? "ready" : "pending"}">${snapshot}</div>
      <div class="job-actions">${stop}${download}</div>
      ${error}
    </article>
  `;
}

async function stopJob(jobId) {
  const response = await apiFetch(`/api/jobs/${jobId}/stop`, { method: "POST" });
  if (!response.ok) {
    showNotice(`Stop failed: ${await readApiError(response, "Job could not be stopped.")}`);
    return;
  }
  await refresh();
}

async function downloadSnapshot(jobId) {
  const response = await apiFetch(`/api/jobs/${jobId}/snapshot`);
  if (response.status === 401) {
    authStatusEl.textContent = "Invalid or missing API token.";
    showNotice("Download failed: enter the API token configured for this runtime.");
    return;
  }
  if (!response.ok) {
    showNotice(`Download failed: ${await readApiError(response, "Snapshot is not ready.")}`);
    return;
  }
  const blob = await response.blob();
  const href = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = href;
  link.download = `${jobId}_snapshot.zip`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(href);
}

async function readApiError(response, fallback) {
  try {
    const payload = await response.json();
    if (payload.error) {
      const message = payload.error.message || fallback;
      const action = payload.error.action ? ` ${payload.error.action}` : "";
      return `${message}${action}`;
    }
    if (payload.detail) {
      return String(payload.detail);
    }
  } catch (error) {
    return fallback;
  }
  return fallback;
}

function showNotice(message, level = "error") {
  runtimeNoticeEl.textContent = message;
  runtimeNoticeEl.dataset.level = level;
  runtimeNoticeEl.hidden = false;
}

function hideNotice() {
  runtimeNoticeEl.textContent = "";
  runtimeNoticeEl.hidden = true;
}

function apiFetch(url, options = {}) {
  return fetch(url, {
    ...options,
    headers: {
      ...authHeaders(),
      ...(options.headers || {})
    }
  });
}

function authHeaders() {
  const token = authTokenEl.value.trim();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

function withAuthQuery(url) {
  const token = authTokenEl.value.trim();
  if (!token) return url;
  const separator = url.includes("?") ? "&" : "?";
  return `${url}${separator}token=${encodeURIComponent(token)}`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, ch => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#039;"
  }[ch]));
}

function renderPublicDatasets(items) {
  publicDatasetsEl.innerHTML = items.length
    ? items.map(item => `<span>${escapeHtml(item)}</span>`).join("")
    : `<em>No public datasets cached</em>`;
}

function renderLocalFingerprints(items) {
  localFingerprintsEl.innerHTML = items.length
    ? items.map(item => `<code>${escapeHtml(shortFingerprint(item))}</code>`).join("")
    : `<em>No local datasets synced</em>`;
}

function shortFingerprint(value) {
  const text = String(value);
  return text.length > 24 ? `${text.slice(0, 18)}...${text.slice(-6)}` : text;
}

function formatMode(mode) {
  return String(mode || "unknown").replace("_", " ");
}

setInterval(refresh, 1500);
refresh();
