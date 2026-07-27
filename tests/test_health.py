"""Tests de los endpoints usados por las probes de Kubernetes."""


def test_liveness_ok(client):
    response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json()["status"] == "alive"


def test_readiness_ok(client):
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "ready"


def test_root_expone_metadatos(client):
    body = client.get("/").json()
    assert body["service"] == "task-api"
    assert "version" in body
