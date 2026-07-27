"""CRUD de tareas."""

from fastapi import APIRouter, HTTPException, Query, status

from app.models import Task, TaskCreate, TaskStatus, TaskUpdate
from app.store import store

router = APIRouter(prefix="/api/v1/tasks", tags=["tasks"])


@router.get("", response_model=list[Task])
def list_tasks(status_filter: TaskStatus | None = Query(default=None, alias="status")):
    return store.list(status_filter)


@router.post("", response_model=Task, status_code=status.HTTP_201_CREATED)
def create_task(payload: TaskCreate):
    return store.create(payload)


@router.get("/{task_id}", response_model=Task)
def get_task(task_id: int):
    task = store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")
    return task


@router.patch("/{task_id}", response_model=Task)
def update_task(task_id: int, payload: TaskUpdate):
    task = store.update(task_id, payload)
    if task is None:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")
    return task


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: int):
    if not store.delete(task_id):
        raise HTTPException(status_code=404, detail="Tarea no encontrada")
