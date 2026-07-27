import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.store import store


@pytest.fixture
def client():
    store.reset()
    with TestClient(app) as test_client:
        yield test_client
