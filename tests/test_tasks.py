"""Tests del CRUD de tareas."""

import pytest


def test_lista_vacia_al_inicio(client):
    assert client.get("/api/v1/tasks").json() == []


def test_crear_tarea(client):
    response = client.post("/api/v1/tasks", json={"title": "Escribir el informe"})
    assert response.status_code == 201
    body = response.json()
    assert body["id"] == 1
    assert body["status"] == "pending"


def test_titulo_vacio_es_rechazado(client):
    assert client.post("/api/v1/tasks", json={"title": ""}).status_code == 422


def test_obtener_tarea_inexistente(client):
    assert client.get("/api/v1/tasks/999").status_code == 404


def test_actualizar_estado(client):
    task_id = client.post("/api/v1/tasks", json={"title": "Deploy"}).json()["id"]
    response = client.patch(f"/api/v1/tasks/{task_id}", json={"status": "done"})
    assert response.status_code == 200
    assert response.json()["status"] == "done"


def test_actualizar_inexistente(client):
    assert client.patch("/api/v1/tasks/999", json={"status": "done"}).status_code == 404


def test_eliminar_tarea(client):
    task_id = client.post("/api/v1/tasks", json={"title": "Temporal"}).json()["id"]
    assert client.delete(f"/api/v1/tasks/{task_id}").status_code == 204
    assert client.get(f"/api/v1/tasks/{task_id}").status_code == 404


def test_eliminar_inexistente(client):
    assert client.delete("/api/v1/tasks/999").status_code == 404


@pytest.mark.parametrize("estado", ["pending", "in_progress", "done"])
def test_filtro_por_estado(client, estado):
    client.post("/api/v1/tasks", json={"title": "A", "status": "pending"})
    client.post("/api/v1/tasks", json={"title": "B", "status": "done"})
    resultado = client.get(f"/api/v1/tasks?status={estado}").json()
    assert all(t["status"] == estado for t in resultado)
