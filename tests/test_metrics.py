"""Tests del endpoint de métricas consumido por Prometheus."""


def test_metrics_expone_formato_prometheus(client):
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "text/plain" in response.headers["content-type"]


def test_contador_de_requests_se_incrementa(client):
    client.get("/health/live")
    cuerpo = client.get("/metrics").text
    assert "http_requests_total" in cuerpo
    assert 'endpoint="/health/live"' in cuerpo


def test_gauge_de_tareas_refleja_altas(client):
    client.post("/api/v1/tasks", json={"title": "Medir"})
    cuerpo = client.get("/metrics").text
    assert 'tasks_total{status="pending"} 1.0' in cuerpo


def test_metrics_no_se_cuenta_a_si_mismo(client):
    client.get("/metrics")
    assert 'endpoint="/metrics"' not in client.get("/metrics").text
