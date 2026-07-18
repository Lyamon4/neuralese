from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_dashboard_static_files_exist():
    dashboard = ROOT / "onprem_runtime" / "dashboard"

    assert (dashboard / "index.html").exists()
    assert (dashboard / "styles.css").exists()
    assert (dashboard / "app.js").exists()
    assert "jobs" in (dashboard / "index.html").read_text(encoding="utf-8")


def test_dashboard_exposes_runtime_capacity_and_dataset_targets():
    dashboard = ROOT / "onprem_runtime" / "dashboard"
    html = (dashboard / "index.html").read_text(encoding="utf-8")
    js = (dashboard / "app.js").read_text(encoding="utf-8")

    for target in (
        'id="authToken"',
        'id="runtimeNotice"',
        'id="runtimeMode"',
        'id="capacitySlots"',
        'id="publicDatasets"',
        'id="localFingerprints"',
    ):
        assert target in html

    assert "localStorage" in js
    assert "authHeaders()" in js
    assert 'apiFetch("/api/health")' in js
    assert 'apiFetch("/api/capacity")' in js
    assert "withAuthQuery" in js
    assert "showNotice" in js
    assert "readApiError" in js
    assert "Upload failed" in js
    assert "Snapshot ready" in js
    assert "metric.error" in js
    assert "error-message" in js
